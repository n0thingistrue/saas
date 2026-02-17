#!/usr/bin/env bash
# =============================================================================
# Installation K3s Agent (Node 2 - Worker)
# =============================================================================
# Installe K3s en mode agent sur Node 2 pour rejoindre le cluster.
#
# L'agent se connecte au control plane de Node 1 via le réseau privé Hetzner.
# Les pods sont schedulés sur ce node selon les rules d'affinité définies
# dans les manifests Kubernetes.
#
# Usage:
#   ./02-install-k3s-agent.sh --server-ip <ip> --token <token> --node-ip <ip>
#   ./02-install-k3s-agent.sh --help
#
# Prérequis:
#   - 00-prereqs.sh exécuté sur Node 2
#   - 01-install-k3s-server.sh exécuté sur Node 1
#   - Token K3s récupéré depuis Node 1
# =============================================================================
set -euo pipefail

# --- Configuration par défaut ------------------------------------------------
SERVER_IP="${SERVER_IP:-10.10.0.2}"
NODE_IP="${NODE_IP:-10.10.0.3}"
K3S_TOKEN="${K3S_TOKEN:-}"
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
Usage: ./02-install-k3s-agent.sh [OPTIONS]

Installe K3s en mode agent (worker) sur Node 2.

Options:
  --server-ip <ip>     IP privée du K3s server/Node 1 (défaut: 10.10.0.2)
  --node-ip <ip>       IP privée de ce node (défaut: 10.10.0.3)
  --token <token>      Token K3s (depuis Node 1: /var/lib/rancher/k3s/server/node-token)
  --k3s-version <ver>  Version K3s (défaut: v1.29.2+k3s1)
  --help               Afficher cette aide

Exemple:
  ./02-install-k3s-agent.sh \
    --server-ip 10.10.0.2 \
    --node-ip 10.10.0.3 \
    --token "K10xxxxxxxxxxxxxxxxxxxx::server:xxxxxxxxxxxxxxxx"
EOF
    exit 0
}

# --- Parse arguments ---------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --server-ip) SERVER_IP="$2"; shift 2 ;;
        --node-ip) NODE_IP="$2"; shift 2 ;;
        --token) K3S_TOKEN="$2"; shift 2 ;;
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

if [[ -z "$K3S_TOKEN" ]]; then
    log_error "Le token K3s est requis (--token)"
    log_error "Récupérez-le depuis Node 1: cat /var/lib/rancher/k3s/server/node-token"
    exit 1
fi

if systemctl is-active --quiet k3s-agent 2>/dev/null; then
    log_warn "K3s agent est déjà installé et actif"
    log_warn "Pour réinstaller: /usr/local/bin/k3s-agent-uninstall.sh"
    exit 0
fi

# Vérifier la connectivité vers le server
log_info "Vérification de la connectivité vers le server (${SERVER_IP})..."
if ! ping -c 1 -W 3 "$SERVER_IP" &>/dev/null; then
    log_error "Impossible de joindre le server K3s sur ${SERVER_IP}"
    log_error "Vérifiez le réseau privé Hetzner et le firewall"
    exit 1
fi

# Vérifier que le port 6443 est accessible
if ! timeout 5 bash -c "echo > /dev/tcp/${SERVER_IP}/6443" 2>/dev/null; then
    log_error "Port 6443 non accessible sur ${SERVER_IP}"
    log_error "Vérifiez que K3s server est démarré et le firewall autorise le port 6443"
    exit 1
fi

log_info "=== Installation K3s Agent (Worker) ==="
log_info "Server IP:    $SERVER_IP"
log_info "Node IP:      $NODE_IP"
log_info "K3s Version:  $K3S_VERSION"

# --- 1. Préparer les répertoires --------------------------------------------
log_info "[1/3] Préparation..."
mkdir -p "$INSTALL_DIR"

# --- 2. Configuration K3s Agent ----------------------------------------------
log_info "[2/3] Création de la configuration K3s agent..."

cat > "${INSTALL_DIR}/config.yaml" << EOF
# ==========================================================================
# Configuration K3s Agent - Node 2 (Worker)
# ==========================================================================

# IP du server K3s (control plane sur Node 1)
server: "https://${SERVER_IP}:6443"

# Token d'authentification
token: "${K3S_TOKEN}"

# IP de ce node (réseau privé Hetzner)
node-ip: "${NODE_IP}"

# Labels du node pour l'affinité
# Les pods utilisent ces labels pour être schedulés sur le bon node
node-label:
  - "node-role=worker"
  - "node-size=small"
  - "topology.kubernetes.io/zone=fsn1"

# Kubelet configuration
# Limites ajustées pour Node 2 (16GB RAM)
kubelet-arg:
  - "max-pods=60"
  - "eviction-hard=memory.available<500Mi,nodefs.available<10%"
  - "eviction-soft=memory.available<1Gi,nodefs.available<15%"
  - "eviction-soft-grace-period=memory.available=2m,nodefs.available=2m"
  - "system-reserved=cpu=250m,memory=512Mi"
  - "kube-reserved=cpu=250m,memory=512Mi"
EOF

# --- 3. Installation K3s Agent -----------------------------------------------
log_info "[3/3] Installation de K3s agent ${K3S_VERSION}..."

curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION="${K3S_VERSION}" \
    INSTALL_K3S_EXEC="agent" \
    K3S_URL="https://${SERVER_IP}:6443" \
    K3S_TOKEN="${K3S_TOKEN}" \
    sh -

# Attendre que l'agent soit prêt
log_info "Attente de l'enregistrement de l'agent..."
sleep 15

# Vérifier le statut du service
if systemctl is-active --quiet k3s-agent; then
    log_info ""
    log_info "=== K3s Agent installé avec succès ==="
    log_info ""
    log_info "Service k3s-agent: $(systemctl is-active k3s-agent)"
    log_info ""
    log_info "Vérifiez depuis Node 1 que le node est visible :"
    log_info "  kubectl get nodes -o wide"
    log_info ""
    log_info "Prochaine étape:"
    log_info "  ./03-post-install.sh (vérifications complètes)"
else
    log_error "K3s agent n'a pas démarré correctement"
    log_error "Vérifiez les logs: journalctl -u k3s-agent -f"
    exit 1
fi
