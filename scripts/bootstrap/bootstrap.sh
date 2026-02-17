#!/usr/bin/env bash
# =============================================================================
# Bootstrap complet - Déploiement orchestré de la stack
# =============================================================================
# Déploie tous les composants Kubernetes dans le bon ordre.
# Chaque étape attend que le composant précédent soit prêt avant de continuer.
#
# Ordre de déploiement (dépendances respectées) :
#   1. Namespaces + RBAC + Pod Security
#   2. Sealed Secrets controller
#   3. Cert-manager + ClusterIssuer Let's Encrypt
#   4. Traefik + WAF ModSecurity
#   5. PostgreSQL Patroni (primary + standby)
#   6. Redis Sentinel (master + replica)
#   7. Samba-AD (authentification)
#   8. Backend NestJS (dépend de PG + Redis + Samba)
#   9. Frontend Next.js (dépend du Backend)
#  10. Monitoring (Prometheus + Grafana + Loki + AlertManager)
#  11. Security (Wazuh agent)
#  12. ArgoCD (GitOps - déployé en dernier)
#
# Usage:
#   ./bootstrap.sh --env production [--skip-monitoring] [--dry-run]
#   ./bootstrap.sh --help
#
# Prérequis:
#   - Cluster K3s opérationnel (2 nodes Ready)
#   - kubectl configuré
#   - Helm 3 installé
# =============================================================================
set -euo pipefail

# --- Configuration -----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV="${ENV:-production}"
DRY_RUN=false
SKIP_MONITORING=false
SKIP_SECURITY=false
SKIP_ARGOCD=false

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()    { echo -e "\n${BLUE}========== [$1/12] $2 ==========${NC}"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }

# --- Help --------------------------------------------------------------------
show_help() {
    cat << 'EOF'
Usage: ./bootstrap.sh [OPTIONS]

Déploie la stack SaaS complète sur le cluster K3s.

Options:
  --env <env>           Environnement: production ou staging (défaut: production)
  --skip-monitoring     Ne pas déployer le monitoring
  --skip-security       Ne pas déployer Wazuh
  --skip-argocd         Ne pas déployer ArgoCD
  --dry-run             Afficher les commandes sans exécuter
  --help                Afficher cette aide

Exemples:
  ./bootstrap.sh --env production
  ./bootstrap.sh --env staging --skip-monitoring
  ./bootstrap.sh --dry-run
EOF
    exit 0
}

# --- Parse arguments ---------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --env) ENV="$2"; shift 2 ;;
        --skip-monitoring) SKIP_MONITORING=true; shift ;;
        --skip-security) SKIP_SECURITY=true; shift ;;
        --skip-argocd) SKIP_ARGOCD=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help) show_help ;;
        *) log_error "Option inconnue: $1"; show_help ;;
    esac
done

# --- Fonctions utilitaires ---------------------------------------------------

# Exécuter une commande (ou l'afficher en dry-run)
run() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}

# Attendre qu'un déploiement soit prêt
wait_for_deployment() {
    local namespace="$1"
    local deployment="$2"
    local timeout="${3:-300}"

    log_info "Attente de ${deployment} dans ${namespace}..."
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] kubectl rollout status deployment/${deployment} -n ${namespace} --timeout=${timeout}s"
        return 0
    fi

    kubectl rollout status "deployment/${deployment}" -n "${namespace}" --timeout="${timeout}s" || {
        log_error "Timeout: ${deployment} n'est pas prêt après ${timeout}s"
        kubectl get pods -n "${namespace}" -l app="${deployment}"
        return 1
    }
    log_success "${deployment} est prêt"
}

# Attendre qu'un StatefulSet soit prêt
wait_for_statefulset() {
    local namespace="$1"
    local statefulset="$2"
    local timeout="${3:-300}"

    log_info "Attente de ${statefulset} dans ${namespace}..."
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] kubectl rollout status statefulset/${statefulset} -n ${namespace} --timeout=${timeout}s"
        return 0
    fi

    kubectl rollout status "statefulset/${statefulset}" -n "${namespace}" --timeout="${timeout}s" || {
        log_error "Timeout: ${statefulset} n'est pas prêt après ${timeout}s"
        kubectl get pods -n "${namespace}" -l app="${statefulset}"
        return 1
    }
    log_success "${statefulset} est prêt"
}

# Attendre qu'un namespace ait tous ses pods Running
wait_for_namespace_ready() {
    local namespace="$1"
    local timeout="${2:-120}"
    local start_time=$(date +%s)

    log_info "Attente que tous les pods de ${namespace} soient Running..."
    if [[ "$DRY_RUN" == true ]]; then return 0; fi

    while true; do
        local pending=$(kubectl get pods -n "${namespace}" --no-headers 2>/dev/null | \
            grep -v "Running\|Completed\|Succeeded" | wc -l)
        if [[ "$pending" -eq 0 ]]; then
            log_success "Tous les pods de ${namespace} sont Running"
            return 0
        fi

        local elapsed=$(( $(date +%s) - start_time ))
        if [[ "$elapsed" -ge "$timeout" ]]; then
            log_error "Timeout: pods non ready dans ${namespace} après ${timeout}s"
            kubectl get pods -n "${namespace}" | grep -v "Running\|Completed"
            return 1
        fi

        sleep 5
    done
}

# --- Vérifications préalables ------------------------------------------------
log_info "=== Bootstrap SaaS Infrastructure ==="
log_info "Environnement: $ENV"
log_info "Dry-run: $DRY_RUN"
log_info ""

# Vérifier kubectl
if ! command -v kubectl &>/dev/null; then
    log_error "kubectl non trouvé. Installez kubectl avant de continuer."
    exit 1
fi

# Vérifier helm
if ! command -v helm &>/dev/null; then
    log_error "helm non trouvé. Installez Helm 3 avant de continuer."
    exit 1
fi

# Vérifier le cluster
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo 0)
if [[ "$NODE_COUNT" -lt 1 ]]; then
    log_error "Aucun node Ready dans le cluster. Vérifiez K3s."
    exit 1
fi
log_info "Nodes Ready: $NODE_COUNT"

# =============================================================================
# DÉPLOIEMENT
# =============================================================================

# --- Étape 1 : Namespaces + RBAC --------------------------------------------
log_step 1 "Namespaces + RBAC + Pod Security"
run kubectl apply -f "${PROJECT_ROOT}/kubernetes/base/namespaces/"
run kubectl apply -f "${PROJECT_ROOT}/kubernetes/base/rbac/"
run kubectl apply -f "${PROJECT_ROOT}/kubernetes/base/pod-security/"
run kubectl apply -f "${PROJECT_ROOT}/kubernetes/base/network-policies/"
log_success "Namespaces et RBAC configurés"

# --- Étape 2 : Sealed Secrets ------------------------------------------------
log_step 2 "Sealed Secrets Controller"
run helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets 2>/dev/null || true
run helm repo update
run helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
    --namespace security \
    --set resources.requests.cpu=50m \
    --set resources.requests.memory=64Mi \
    --set resources.limits.cpu=100m \
    --set resources.limits.memory=128Mi \
    --wait --timeout 120s
log_success "Sealed Secrets controller installé"

# --- Étape 3 : Cert-manager --------------------------------------------------
log_step 3 "Cert-manager + Let's Encrypt"
run helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
run helm repo update
run helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace ingress \
    --set installCRDs=true \
    --set resources.requests.cpu=50m \
    --set resources.requests.memory=64Mi \
    --set resources.limits.cpu=200m \
    --set resources.limits.memory=256Mi \
    --wait --timeout 180s

# Attendre que cert-manager soit prêt avant d'appliquer les ClusterIssuers
sleep 10
run kubectl apply -f "${PROJECT_ROOT}/kubernetes/ingress/cert-manager/"
log_success "Cert-manager installé avec ClusterIssuer Let's Encrypt"

# --- Étape 4 : Traefik + WAF ------------------------------------------------
log_step 4 "Traefik Ingress + WAF ModSecurity"
run kubectl apply -f "${PROJECT_ROOT}/kubernetes/ingress/traefik/"
run kubectl apply -f "${PROJECT_ROOT}/kubernetes/ingress/waf/"
wait_for_deployment "ingress" "traefik" 180
log_success "Traefik + WAF déployés"

# --- Étape 5 : PostgreSQL Patroni -------------------------------------------
log_step 5 "PostgreSQL Patroni (HA)"
run kubectl apply -f "${PROJECT_ROOT}/kubernetes/apps/postgresql/"
wait_for_statefulset "production" "postgresql" 300
log_success "PostgreSQL Patroni déployé (primary + standby)"

# --- Étape 6 : Redis Sentinel ------------------------------------------------
log_step 6 "Redis Sentinel (HA)"
run kubectl apply -f "${PROJECT_ROOT}/kubernetes/apps/redis/"
wait_for_statefulset "production" "redis" 180
log_success "Redis Sentinel déployé (master + replica)"

# --- Étape 7 : Samba-AD ------------------------------------------------------
log_step 7 "Samba Active Directory"
run kubectl apply -f "${PROJECT_ROOT}/kubernetes/apps/samba-ad/"
wait_for_statefulset "production" "samba-ad" 180
log_success "Samba-AD déployé"

# --- Étape 8 : Backend NestJS ------------------------------------------------
log_step 8 "Backend NestJS"
run kubectl apply -f "${PROJECT_ROOT}/kubernetes/apps/backend/"
wait_for_deployment "production" "backend" 180
log_success "Backend NestJS déployé (3 replicas)"

# --- Étape 9 : Frontend Next.js ----------------------------------------------
log_step 9 "Frontend Next.js"
run kubectl apply -f "${PROJECT_ROOT}/kubernetes/apps/frontend/"
wait_for_deployment "production" "frontend" 180
log_success "Frontend Next.js déployé (2 replicas)"

# --- Étape 10 : Monitoring ---------------------------------------------------
if [[ "$SKIP_MONITORING" == false ]]; then
    log_step 10 "Monitoring (Prometheus + Grafana + Loki)"
    run kubectl apply -f "${PROJECT_ROOT}/monitoring/prometheus/"
    run kubectl apply -f "${PROJECT_ROOT}/monitoring/loki/"
    run kubectl apply -f "${PROJECT_ROOT}/monitoring/promtail/"
    run kubectl apply -f "${PROJECT_ROOT}/monitoring/alertmanager/"
    run kubectl apply -f "${PROJECT_ROOT}/monitoring/grafana/"
    wait_for_namespace_ready "monitoring" 300
    log_success "Stack monitoring déployée"
else
    log_step 10 "Monitoring (IGNORÉ - --skip-monitoring)"
fi

# --- Étape 11 : Security -----------------------------------------------------
if [[ "$SKIP_SECURITY" == false ]]; then
    log_step 11 "Security (Wazuh agent)"
    run kubectl apply -f "${PROJECT_ROOT}/monitoring/wazuh/"
    log_success "Wazuh agent déployé"
else
    log_step 11 "Security (IGNORÉ - --skip-security)"
fi

# --- Étape 12 : ArgoCD -------------------------------------------------------
if [[ "$SKIP_ARGOCD" == false ]]; then
    log_step 12 "ArgoCD (GitOps)"
    run kubectl create namespace argocd 2>/dev/null || true
    run kubectl apply -n argocd \
        -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    wait_for_deployment "argocd" "argocd-server" 180
    run kubectl apply -f "${PROJECT_ROOT}/argocd/projects/"
    run kubectl apply -f "${PROJECT_ROOT}/argocd/applications/"
    log_success "ArgoCD déployé"
else
    log_step 12 "ArgoCD (IGNORÉ - --skip-argocd)"
fi

# --- Étape 13 : Backup CronJobs ---------------------------------------------
log_info ""
log_info "Déploiement des CronJobs de backup..."
run kubectl apply -f "${PROJECT_ROOT}/backup/cronjobs/"
log_success "CronJobs de backup configurés"

# =============================================================================
# RÉSUMÉ
# =============================================================================
echo ""
echo "============================================"
echo "  Bootstrap terminé avec succès !"
echo "============================================"
echo ""
echo "Services déployés:"
kubectl get pods --all-namespaces --no-headers | \
    awk '{print $1}' | sort | uniq -c | sort -rn | \
    while read count ns; do
        echo "  $ns: $count pods"
    done
echo ""
echo "Accès:"
echo "  Application: https://${DOMAIN:-votre-domaine.com}"
echo "  Grafana:     https://grafana.${DOMAIN:-votre-domaine.com}"
echo "  ArgoCD:      https://argocd.${DOMAIN:-votre-domaine.com}"
echo ""
echo "Mots de passe:"
echo "  Grafana:  kubectl get secret -n monitoring grafana -o jsonpath='{.data.admin-password}' | base64 -d"
echo "  ArgoCD:   kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "Vérifications recommandées:"
echo "  kubectl get nodes -o wide"
echo "  kubectl get pods --all-namespaces"
echo "  kubectl top nodes"
echo ""
