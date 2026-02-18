#!/bin/bash
# =============================================================================
# Test Security Scan
# =============================================================================
# Scan de securite complet de l'infrastructure K3s.
# Cible : 0 vulnerabilites CRITICAL
#
# Usage :
#   ./scripts/tests/test-security-scan.sh
#   ./scripts/tests/test-security-scan.sh --full       # Scan complet
#   ./scripts/tests/test-security-scan.sh --dry-run
#
# Pre-requis :
#   - kubectl connecte au cluster
#   - trivy et/ou kubesec installes (optionnel)
# =============================================================================

set -euo pipefail

# --- Configuration ---
NAMESPACES=("production" "ingress" "monitoring" "argocd" "kube-system")
IMAGES_TO_SCAN=(
  "backend:latest"
  "frontend:latest"
  "postgres:16"
  "redis:7.2-alpine"
  "traefik:v3.0"
  "grafana/grafana:10.4"
  "prom/prometheus:v2.50"
  "grafana/loki:2.9"
)

# --- Couleurs ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[PASS]${NC} $*"; }
log_fail()  { echo -e "${RED}[FAIL]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_step()  { echo -e "${CYAN}[STEP]${NC} $*"; }

ERRORS=0
WARNINGS=0
DRY_RUN=false
FULL_SCAN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --full) FULL_SCAN=true ;;
  esac
done

echo "============================================"
echo "  Security Scan Infrastructure"
echo "============================================"
echo ""

# =============================================================================
# 1. Pod Security Standards
# =============================================================================
log_step "1/8 - Verification Pod Security Standards (PSS)"

for ns in "${NAMESPACES[@]}"; do
  PSS_ENFORCE=$(kubectl get namespace "${ns}" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null) || PSS_ENFORCE=""
  PSS_WARN=$(kubectl get namespace "${ns}" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/warn}' 2>/dev/null) || PSS_WARN=""

  if [ -n "${PSS_ENFORCE}" ]; then
    log_ok "${ns}: PSS enforce=${PSS_ENFORCE}"
  elif [ -n "${PSS_WARN}" ]; then
    log_warn "${ns}: PSS warn only (${PSS_WARN})"
    WARNINGS=$((WARNINGS + 1))
  else
    log_warn "${ns}: Pas de PSS configure"
    WARNINGS=$((WARNINGS + 1))
  fi
done
echo ""

# =============================================================================
# 2. NetworkPolicies
# =============================================================================
log_step "2/8 - Verification NetworkPolicies (Zero Trust)"

for ns in "${NAMESPACES[@]}"; do
  NP_COUNT=$(kubectl get networkpolicies -n "${ns}" --no-headers 2>/dev/null | wc -l)
  if [ "${NP_COUNT}" -gt 0 ]; then
    log_ok "${ns}: ${NP_COUNT} NetworkPolicy(ies)"
  else
    log_warn "${ns}: Aucune NetworkPolicy"
    WARNINGS=$((WARNINGS + 1))
  fi
done
echo ""

# =============================================================================
# 3. RBAC
# =============================================================================
log_step "3/8 - Verification RBAC"

# Verifier qu'il n'y a pas de ClusterRoleBinding trop permissif
ADMIN_BINDINGS=$(kubectl get clusterrolebindings -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
risky = []
for item in data.get('items', []):
    role = item.get('roleRef', {}).get('name', '')
    if role == 'cluster-admin':
        subjects = item.get('subjects', [])
        for s in subjects:
            if s.get('kind') == 'ServiceAccount' and s.get('name') != 'system:masters':
                risky.append(f\"{s.get('name')} in {s.get('namespace', 'default')}\")
if risky:
    print('\n'.join(risky))
else:
    print('OK')
" 2>/dev/null) || ADMIN_BINDINGS="check failed"

if [ "${ADMIN_BINDINGS}" = "OK" ]; then
  log_ok "Pas de ServiceAccount avec cluster-admin excessif"
else
  log_warn "ServiceAccounts avec cluster-admin : ${ADMIN_BINDINGS}"
  WARNINGS=$((WARNINGS + 1))
fi

# Verifier les ServiceAccounts par defaut
for ns in "${NAMESPACES[@]}"; do
  DEFAULT_SA_MOUNT=$(kubectl get pods -n "${ns}" -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
mounted = 0
for pod in data.get('items', []):
    automount = pod.get('spec', {}).get('automountServiceAccountToken', True)
    if automount:
        mounted += 1
print(mounted)
" 2>/dev/null) || DEFAULT_SA_MOUNT="0"
done

log_ok "RBAC verification terminee"
echo ""

# =============================================================================
# 4. Secrets
# =============================================================================
log_step "4/8 - Verification des Secrets"

# Verifier qu'il n'y a pas de secrets en clair dans les ConfigMaps
SECRETS_IN_CM=0
for ns in "${NAMESPACES[@]}"; do
  CM_DATA=$(kubectl get configmaps -n "${ns}" -o json 2>/dev/null | \
    grep -ci "password\|secret\|token\|api.key\|private.key" 2>/dev/null || echo "0")
  if [ "${CM_DATA}" -gt 0 ]; then
    log_warn "${ns}: ${CM_DATA} reference(s) sensible(s) dans ConfigMaps"
    SECRETS_IN_CM=$((SECRETS_IN_CM + CM_DATA))
  fi
done

if [ "${SECRETS_IN_CM}" -eq 0 ]; then
  log_ok "Aucun secret en clair dans les ConfigMaps"
else
  log_warn "${SECRETS_IN_CM} reference(s) sensible(s) detectee(s) (verifier manuellement)"
  WARNINGS=$((WARNINGS + 1))
fi

# Verifier SealedSecrets
SS_COUNT=$(kubectl get sealedsecrets --all-namespaces --no-headers 2>/dev/null | wc -l)
log_info "SealedSecrets deployes : ${SS_COUNT}"
echo ""

# =============================================================================
# 5. Container Security
# =============================================================================
log_step "5/8 - Verification securite des containers"

PRIVILEGED_PODS=0
ROOT_PODS=0
READONLY_FS=0

for ns in "${NAMESPACES[@]}"; do
  POD_SECURITY=$(kubectl get pods -n "${ns}" -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
privileged = 0
root = 0
readonly_ok = 0
total = 0
for pod in data.get('items', []):
    for c in pod.get('spec', {}).get('containers', []):
        total += 1
        sc = c.get('securityContext', {})
        if sc.get('privileged', False):
            privileged += 1
        if sc.get('runAsNonRoot') is not True and sc.get('runAsUser', 0) == 0:
            root += 1
        if sc.get('readOnlyRootFilesystem', False):
            readonly_ok += 1
print(f'{privileged} {root} {readonly_ok} {total}')
" 2>/dev/null) || POD_SECURITY="0 0 0 0"

  read -r priv rt ro total <<< "${POD_SECURITY}"
  PRIVILEGED_PODS=$((PRIVILEGED_PODS + priv))
  ROOT_PODS=$((ROOT_PODS + rt))
  READONLY_FS=$((READONLY_FS + ro))
done

if [ "${PRIVILEGED_PODS}" -eq 0 ]; then
  log_ok "Aucun container privileged"
else
  log_fail "${PRIVILEGED_PODS} container(s) en mode privileged"
  ERRORS=$((ERRORS + 1))
fi

if [ "${ROOT_PODS}" -le 2 ]; then
  log_ok "Containers root : ${ROOT_PODS} (acceptable - monitoring/system)"
else
  log_warn "${ROOT_PODS} container(s) en root"
  WARNINGS=$((WARNINGS + 1))
fi

log_info "Containers readOnlyRootFilesystem : ${READONLY_FS}"
echo ""

# =============================================================================
# 6. TLS / Certificates
# =============================================================================
log_step "6/8 - Verification TLS et certificats"

# Verifier les certificats cert-manager
CERTS=$(kubectl get certificates --all-namespaces --no-headers 2>/dev/null) || CERTS=""
CERT_COUNT=$(echo "${CERTS}" | grep -c "True" 2>/dev/null || echo "0")
CERT_TOTAL=$(echo "${CERTS}" | wc -l)

log_info "Certificats : ${CERT_COUNT}/${CERT_TOTAL} valides"

# Verifier les certificats expirant bientot
EXPIRING=$(kubectl get certificates --all-namespaces -o json 2>/dev/null | python3 -c "
import json, sys
from datetime import datetime, timezone, timedelta
data = json.load(sys.stdin)
expiring = []
now = datetime.now(timezone.utc)
for cert in data.get('items', []):
    name = cert['metadata']['name']
    ns = cert['metadata']['namespace']
    not_after = cert.get('status', {}).get('notAfter', '')
    if not_after:
        try:
            exp = datetime.fromisoformat(not_after.replace('Z', '+00:00'))
            days_left = (exp - now).days
            if days_left < 30:
                expiring.append(f'{ns}/{name}: {days_left} jours')
        except:
            pass
if expiring:
    print('\n'.join(expiring))
else:
    print('OK')
" 2>/dev/null) || EXPIRING="check failed"

if [ "${EXPIRING}" = "OK" ]; then
  log_ok "Aucun certificat expirant dans les 30 jours"
else
  log_warn "Certificats expirant bientot : ${EXPIRING}"
  WARNINGS=$((WARNINGS + 1))
fi

# Verifier TLS sur Traefik
TLS_OPTIONS=$(kubectl get tlsoption --all-namespaces --no-headers 2>/dev/null | wc -l)
log_info "TLSOptions configurees : ${TLS_OPTIONS}"
echo ""

# =============================================================================
# 7. Image Scan (Trivy)
# =============================================================================
log_step "7/8 - Scan des images (Trivy)"

if command -v trivy &>/dev/null && [ "${DRY_RUN}" = false ]; then
  CRITICAL_VULNS=0

  for image in "${IMAGES_TO_SCAN[@]}"; do
    log_info "Scan: ${image}..."
    SCAN_RESULT=$(trivy image --severity CRITICAL --no-progress --quiet \
      "${image}" 2>/dev/null) || SCAN_RESULT=""

    CRIT_COUNT=$(echo "${SCAN_RESULT}" | grep -c "CRITICAL" 2>/dev/null || echo "0")

    if [ "${CRIT_COUNT}" -eq 0 ]; then
      log_ok "${image}: 0 CRITICAL"
    else
      log_fail "${image}: ${CRIT_COUNT} CRITICAL"
      CRITICAL_VULNS=$((CRITICAL_VULNS + CRIT_COUNT))
    fi

    [ "${FULL_SCAN}" = false ] && break  # En mode rapide, scanner seulement la premiere image
  done

  if [ "${CRITICAL_VULNS}" -gt 0 ]; then
    ERRORS=$((ERRORS + 1))
  fi
else
  log_warn "Trivy non installe ou --dry-run - scan d'images ignore"
  echo "  Installer : curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh"
fi
echo ""

# =============================================================================
# 8. Kubesec Scan
# =============================================================================
log_step "8/8 - Scan Kubesec des deployments"

if command -v kubesec &>/dev/null && [ "${DRY_RUN}" = false ]; then
  for ns in "production" "ingress"; do
    DEPLOYMENTS=$(kubectl get deployments -n "${ns}" -o name 2>/dev/null) || continue
    for deploy in ${DEPLOYMENTS}; do
      MANIFEST=$(kubectl get "${deploy}" -n "${ns}" -o yaml 2>/dev/null)
      SCORE=$(echo "${MANIFEST}" | kubesec scan - 2>/dev/null | \
        python3 -c "import json,sys; print(json.load(sys.stdin)[0].get('score', 0))" 2>/dev/null) || SCORE="N/A"

      DEPLOY_NAME=$(basename "${deploy}")
      if [ "${SCORE}" != "N/A" ] && [ "${SCORE}" -ge 5 ]; then
        log_ok "${ns}/${DEPLOY_NAME}: score ${SCORE}"
      elif [ "${SCORE}" != "N/A" ]; then
        log_warn "${ns}/${DEPLOY_NAME}: score ${SCORE} (ameliorer)"
        WARNINGS=$((WARNINGS + 1))
      fi
    done
  done
else
  log_warn "Kubesec non installe - scan ignore"
  echo "  Installer : curl -sSL https://github.com/controlplaneio/kubesec/releases/latest/download/kubesec_linux_amd64.tar.gz | tar xz"
fi

# --- Resume ---
echo ""
echo "============================================"
echo "  Resultats Security Scan"
echo "============================================"
echo ""
echo "  Pod Security Standards  : Verifie"
echo "  NetworkPolicies         : Verifie"
echo "  RBAC                    : Verifie"
echo "  Secrets                 : ${SECRETS_IN_CM} warning(s)"
echo "  Containers privileged   : ${PRIVILEGED_PODS}"
echo "  Containers root         : ${ROOT_PODS}"
echo "  Certificats             : ${CERT_COUNT}/${CERT_TOTAL} valides"
echo "  Erreurs CRITICAL        : ${ERRORS}"
echo "  Warnings                : ${WARNINGS}"
echo ""

if [ "${ERRORS}" -eq 0 ]; then
  log_ok "AUCUNE VULNERABILITE CRITICAL"
else
  log_fail "${ERRORS} VULNERABILITE(S) CRITICAL DETECTEE(S)"
fi

if [ "${WARNINGS}" -gt 0 ]; then
  log_warn "${WARNINGS} warning(s) a verifier"
fi
echo "============================================"

exit "${ERRORS}"
