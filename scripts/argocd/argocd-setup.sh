#!/bin/bash
# =============================================================================
# ArgoCD Setup Script
# =============================================================================
# Installation et configuration complete d'ArgoCD sur le cluster K3s.
#
# Usage :
#   ./scripts/argocd/argocd-setup.sh
#
# Pre-requis :
#   - kubectl configure et connecte au cluster
#   - kubeseal installe (pour les secrets)
#   - curl installe
#
# Ce script :
#   1. Installe ArgoCD depuis le manifest officiel
#   2. Attend que les pods soient ready
#   3. Applique les ConfigMaps personnalises
#   4. Deploie l'IngressRoute
#   5. Affiche le mot de passe initial
#   6. Optionnel : ajoute le repository Git et deploie l'App of Apps
# =============================================================================

set -euo pipefail

# --- Configuration ---
ARGOCD_NAMESPACE="argocd"
ARGOCD_MANIFEST_URL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARGOCD_DIR="${PROJECT_ROOT}/kubernetes/argocd"

# --- Couleurs ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# =============================================================================
# Step 1 : Creer le namespace
# =============================================================================
log_info "Step 1/6 : Creating ArgoCD namespace..."
kubectl apply -f "${ARGOCD_DIR}/argocd-namespace.yaml"
log_ok "Namespace ${ARGOCD_NAMESPACE} created"

# =============================================================================
# Step 2 : Installer ArgoCD
# =============================================================================
log_info "Step 2/6 : Installing ArgoCD from official manifest..."
kubectl apply -n "${ARGOCD_NAMESPACE}" -f "${ARGOCD_MANIFEST_URL}"
log_ok "ArgoCD manifest applied"

# =============================================================================
# Step 3 : Attendre les pods
# =============================================================================
log_info "Step 3/6 : Waiting for ArgoCD pods to be ready (timeout 5min)..."
kubectl wait --for=condition=Ready pods \
  --all -n "${ARGOCD_NAMESPACE}" \
  --timeout=300s
log_ok "All ArgoCD pods are ready"

# Afficher les pods
kubectl get pods -n "${ARGOCD_NAMESPACE}"

# =============================================================================
# Step 4 : Appliquer les ConfigMaps
# =============================================================================
log_info "Step 4/6 : Applying custom ConfigMaps..."
kubectl apply -f "${ARGOCD_DIR}/argocd-configmap.yaml"
kubectl apply -f "${ARGOCD_DIR}/argocd-rbac-configmap.yaml"
kubectl apply -f "${ARGOCD_DIR}/argocd-notifications-configmap.yaml"
log_ok "ConfigMaps applied"

# =============================================================================
# Step 5 : Deployer l'IngressRoute
# =============================================================================
log_info "Step 5/6 : Deploying ArgoCD IngressRoute..."
kubectl apply -f "${ARGOCD_DIR}/argocd-ingress.yaml"
log_ok "IngressRoute deployed (argocd.saas.local)"

# =============================================================================
# Step 6 : Recuperer le mot de passe
# =============================================================================
log_info "Step 6/6 : Retrieving initial admin password..."
ADMIN_PASSWORD=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)

echo ""
echo "============================================"
echo "  ArgoCD Installation Complete"
echo "============================================"
echo ""
echo "  URL      : https://argocd.saas.local"
echo "  Username : admin"
echo "  Password : ${ADMIN_PASSWORD}"
echo ""
echo "  IMPORTANT : Changez le mot de passe admin !"
echo "  argocd account update-password"
echo ""
echo "============================================"
echo ""

# =============================================================================
# Optional : Ajouter repo et deployer App of Apps
# =============================================================================
echo ""
log_warn "Etapes optionnelles (a executer manuellement) :"
echo ""
echo "  # 1. Installer le CLI ArgoCD"
echo "  curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64"
echo "  chmod +x argocd && sudo mv argocd /usr/local/bin/"
echo ""
echo "  # 2. Se connecter"
echo "  argocd login argocd.saas.local --grpc-web"
echo ""
echo "  # 3. Ajouter le repository Git"
echo "  argocd repo add https://github.com/your-username/infrastructure-rncp.git"
echo ""
echo "  # 4. Deployer l'App of Apps"
echo "  kubectl apply -f ${ARGOCD_DIR}/applications/app-of-apps.yaml"
echo ""
