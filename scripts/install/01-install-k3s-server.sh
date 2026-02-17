#!/usr/bin/env bash
# =============================================================================
# Installation K3s Server (Node 1 - Control Plane)
# =============================================================================
# Installe K3s en mode server sur Node 1 (control plane).
#
# K3s est configuré avec :
#   - Traefik désactivé (on installe notre propre version avec WAF)
#   - ServiceLB désactivé (on utilise le LB Hetzner)
#   - Flannel VXLAN pour le réseau pod (traverse le VPN WireGuard)
#   - etcd embarqué pour la persistance du state
#   - TLS-SAN avec la Floating IP et le domaine
#   - Audit logging activé
#
# Usage:
#   ./01-install-k3s-server.sh --node-ip <private-ip> --floating-ip <fip> --domain <domain>
#   ./01-install-k3s-server.sh --help
#
# Prérequis:
#   - 00-prereqs.sh exécuté
#   - Exécuter sur Node 1 uniquement
# =============================================================================
set -euo pipefail

# --- Configuration par défaut ------------------------------------------------
NODE_IP="${NODE_IP:-10.10.0.2}"
FLOATING_IP="${FLOATING_IP:-}"
DOMAIN="${DOMAIN:-}"
K3S_VERSION="${K3S_VERSION:-v1.29.2+k3s1}"
INSTALL_DIR="/etc/rancher/k3s"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# --- Help --------------------------------------------------------------------
show_help() {
    cat << 'EOF'
Usage: ./01-install-k3s-server.sh [OPTIONS]

Installe K3s en mode server (control plane) sur Node 1.

Options:
  --node-ip <ip>        IP privée du node (défaut: 10.10.0.2)
  --floating-ip <ip>    Floating IP Hetzner (ajoutée au TLS-SAN)
  --domain <domain>     Domaine principal (ajouté au TLS-SAN)
  --k3s-version <ver>   Version K3s (défaut: v1.29.2+k3s1)
  --help                Afficher cette aide

Exemple:
  ./01-install-k3s-server.sh \
    --node-ip 10.10.0.2 \
    --floating-ip 78.46.x.x \
    --domain saas.example.com
EOF
    exit 0
}

# --- Parse arguments ---------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --node-ip) NODE_IP="$2"; shift 2 ;;
        --floating-ip) FLOATING_IP="$2"; shift 2 ;;
        --domain) DOMAIN="$2"; shift 2 ;;
        --k3s-version) K3S_VERSION="$2"; shift 2 ;;
        --help) show_help ;;
        *) log_error "Option inconnue: $1"; show_help ;;
    esac
done

# --- Vérifications -----------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    log_error "Ce script doit être exécuté en tant que root"
    exit 1
fi

if systemctl is-active --quiet k3s 2>/dev/null; then
    log_warn "K3s est déjà installé et actif"
    log_warn "Pour réinstaller, exécutez d'abord: /usr/local/bin/k3s-uninstall.sh"
    exit 0
fi

log_info "=== Installation K3s Server (Control Plane) ==="
log_info "Node IP:      $NODE_IP"
log_info "Floating IP:  ${FLOATING_IP:-non configurée}"
log_info "Domain:       ${DOMAIN:-non configuré}"
log_info "K3s Version:  $K3S_VERSION"

# --- 1. Préparer les répertoires --------------------------------------------
log_info "[1/5] Préparation des répertoires..."
mkdir -p "$INSTALL_DIR"
mkdir -p /var/lib/rancher/k3s/server/manifests
mkdir -p /var/log/kubernetes/audit

# --- 2. Configuration K3s ---------------------------------------------------
log_info "[2/5] Création de la configuration K3s..."

# Construire la liste TLS-SAN
TLS_SAN="--tls-san ${NODE_IP}"
if [[ -n "$FLOATING_IP" ]]; then
    TLS_SAN="${TLS_SAN} --tls-san ${FLOATING_IP}"
fi
if [[ -n "$DOMAIN" ]]; then
    TLS_SAN="${TLS_SAN} --tls-san ${DOMAIN}"
fi

# Fichier de configuration K3s
cat > "${INSTALL_DIR}/config.yaml" << EOF
# ==========================================================================
# Configuration K3s Server - Node 1 (Control Plane)
# ==========================================================================
# Documentation: https://docs.k3s.io/installation/configuration

# --- Réseau ---
# IP d'écoute du node (réseau privé Hetzner)
node-ip: "${NODE_IP}"
# IP pour l'API server (accessible depuis le réseau privé)
bind-address: "0.0.0.0"
# Flannel VXLAN comme backend réseau (compatible WireGuard)
flannel-backend: "vxlan"
# CIDR des pods (réseau overlay)
cluster-cidr: "10.42.0.0/16"
# CIDR des services
service-cidr: "10.43.0.0/16"
# DNS du cluster
cluster-dns: "10.43.0.10"

# --- Composants désactivés ---
# On installe nos propres versions de Traefik et ServiceLB
disable:
  - traefik
  - servicelb

# --- Sécurité ---
# Protection du token d'inscription
# Les agents doivent fournir ce token pour rejoindre le cluster
# Le token est généré automatiquement dans /var/lib/rancher/k3s/server/node-token

# Audit logging
kube-apiserver-arg:
  - "audit-log-path=/var/log/kubernetes/audit/audit.log"
  - "audit-log-maxage=30"
  - "audit-log-maxbackup=10"
  - "audit-log-maxsize=100"
  - "enable-admission-plugins=NodeRestriction,PodSecurity"
  - "admission-control-config-file=/etc/rancher/k3s/admission-control.yaml"

# Labels du node (pour l'affinité des pods)
node-label:
  - "node-role=control-plane"
  - "node-size=large"
  - "topology.kubernetes.io/zone=fsn1"

# Taints : aucun sur Node 1 car il exécute aussi des workloads
# (dans un cluster plus grand, le control plane serait tainté)

# --- Stockage ---
# StorageClass local-path par défaut (inclus dans K3s)
default-local-storage-path: "/var/lib/rancher/k3s/storage"

# --- etcd ---
# Snapshots automatiques etcd
etcd-snapshot-schedule-cron: "0 */12 * * *"
etcd-snapshot-retention: 10

# --- Kubelet ---
kubelet-arg:
  - "max-pods=110"
  - "eviction-hard=memory.available<500Mi,nodefs.available<10%"
  - "eviction-soft=memory.available<1Gi,nodefs.available<15%"
  - "eviction-soft-grace-period=memory.available=2m,nodefs.available=2m"
  - "system-reserved=cpu=500m,memory=1Gi"
  - "kube-reserved=cpu=500m,memory=1Gi"

# --- Écriture kubeconfig ---
write-kubeconfig-mode: "0644"
EOF

# --- 3. Audit Policy ---------------------------------------------------------
log_info "[3/5] Configuration de l'audit policy..."

cat > "${INSTALL_DIR}/audit-policy.yaml" << 'EOF'
# Politique d'audit Kubernetes
# Enregistre les actions sensibles pour la conformité ISO 27001
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # Ne pas logger les checks de santé
  - level: None
    resources:
      - group: ""
        resources: ["endpoints", "services", "services/status"]
    verbs: ["get", "list", "watch"]

  # Ne pas logger les events système
  - level: None
    resources:
      - group: ""
        resources: ["events"]

  # Logger les modifications de secrets (metadata uniquement, pas le contenu)
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets", "configmaps"]

  # Logger toutes les modifications de RBAC
  - level: RequestResponse
    resources:
      - group: "rbac.authorization.k8s.io"
        resources: ["clusterroles", "clusterrolebindings", "roles", "rolebindings"]

  # Logger les créations/suppressions de pods
  - level: Request
    resources:
      - group: ""
        resources: ["pods", "deployments", "statefulsets", "daemonsets"]
    verbs: ["create", "update", "patch", "delete"]

  # Logger les accès à l'API par défaut (metadata)
  - level: Metadata
    omitStages:
      - RequestReceived
EOF

# --- Admission control config ---
cat > "${INSTALL_DIR}/admission-control.yaml" << 'EOF'
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
  - name: PodSecurity
    configuration:
      apiVersion: pod-security.admission.config.k8s.io/v1
      kind: PodSecurityConfiguration
      defaults:
        enforce: "baseline"
        enforce-version: "latest"
        audit: "restricted"
        audit-version: "latest"
        warn: "restricted"
        warn-version: "latest"
      exemptions:
        usernames: []
        runtimeClasses: []
        namespaces:
          - kube-system
          - ingress
          - monitoring
          - security
EOF

# --- 4. Installation K3s -----------------------------------------------------
log_info "[4/5] Installation de K3s ${K3S_VERSION}..."

curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION="${K3S_VERSION}" \
    INSTALL_K3S_EXEC="server" \
    sh -

# Attendre que K3s soit prêt
log_info "Attente du démarrage de K3s..."
sleep 10

# Vérifier que K3s fonctionne
RETRIES=30
until kubectl get nodes &>/dev/null || [[ $RETRIES -eq 0 ]]; do
    sleep 2
    ((RETRIES--))
done

if [[ $RETRIES -eq 0 ]]; then
    log_error "K3s n'a pas démarré dans le temps imparti"
    log_error "Vérifiez les logs: journalctl -u k3s -f"
    exit 1
fi

# --- 5. Post-installation ----------------------------------------------------
log_info "[5/5] Configuration post-installation..."

# Copier kubeconfig pour l'utilisateur courant
mkdir -p ~/.kube
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
chmod 600 ~/.kube/config

# Si Floating IP configurée, remplacer 127.0.0.1 par la Floating IP
# dans le kubeconfig pour l'accès distant
if [[ -n "$FLOATING_IP" ]]; then
    KUBECONFIG_REMOTE="/etc/rancher/k3s/k3s-remote.yaml"
    cp /etc/rancher/k3s/k3s.yaml "$KUBECONFIG_REMOTE"
    sed -i "s/127.0.0.1/${FLOATING_IP}/g" "$KUBECONFIG_REMOTE"
    chmod 600 "$KUBECONFIG_REMOTE"
    log_info "Kubeconfig distant généré: $KUBECONFIG_REMOTE"
fi

# Configurer la Floating IP sur l'interface réseau
# Nécessaire pour que le serveur accepte le trafic sur la Floating IP
if [[ -n "$FLOATING_IP" ]]; then
    if ! ip addr show | grep -q "$FLOATING_IP"; then
        ip addr add "${FLOATING_IP}/32" dev eth0
        # Rendre persistant
        cat > /etc/network/interfaces.d/60-floating-ip.cfg << FIPEOF
auto eth0:1
iface eth0:1 inet static
    address ${FLOATING_IP}
    netmask 255.255.255.255
FIPEOF
        log_info "Floating IP ${FLOATING_IP} configurée sur eth0:1"
    fi
fi

# Récupérer le token pour Node 2
NODE_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)

# --- Résumé ------------------------------------------------------------------
log_info ""
log_info "=== K3s Server installé avec succès ==="
log_info ""
log_info "Node:"
kubectl get nodes -o wide
log_info ""
log_info "Token pour Node 2 (à conserver de manière sécurisée) :"
log_info "  $NODE_TOKEN"
log_info ""
log_info "Kubeconfig local:  /etc/rancher/k3s/k3s.yaml"
if [[ -n "$FLOATING_IP" ]]; then
    log_info "Kubeconfig remote: /etc/rancher/k3s/k3s-remote.yaml"
fi
log_info ""
log_info "Prochaine étape:"
log_info "  Sur Node 2: ./02-install-k3s-agent.sh --server-ip ${NODE_IP} --token <token>"
