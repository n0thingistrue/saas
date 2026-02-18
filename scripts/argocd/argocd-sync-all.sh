#!/bin/bash
# =============================================================================
# ArgoCD Sync All Applications
# =============================================================================
# Force la synchronisation de toutes les applications ArgoCD.
# Respecte l'ordre des sync-waves.
#
# Usage :
#   ./scripts/argocd/argocd-sync-all.sh
#   ./scripts/argocd/argocd-sync-all.sh --prune    # avec suppression des orphelins
#   ./scripts/argocd/argocd-sync-all.sh --dry-run  # simulation
# =============================================================================

set -euo pipefail

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

# --- Options ---
PRUNE_FLAG=""
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --prune) PRUNE_FLAG="--prune" ;;
    --dry-run) DRY_RUN=true ;;
  esac
done

# --- Verifier que ArgoCD CLI est installe ---
if ! command -v argocd &>/dev/null; then
  log_error "ArgoCD CLI not found. Install: curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64"
  exit 1
fi

# --- Applications dans l'ordre des sync-waves ---
APPS=(
  "databases"     # Wave 0
  "samba-ad"      # Wave 1 (manual)
  "backend"       # Wave 2
  "frontend"      # Wave 3
  "monitoring"    # Wave 4
  "ingress"       # Wave 5
)

echo "============================================"
echo "  ArgoCD - Sync All Applications"
echo "============================================"
echo ""

# --- Lister l'etat actuel ---
log_info "Current application status:"
argocd app list --output wide 2>/dev/null || {
  log_error "Cannot connect to ArgoCD. Login first: argocd login <server>"
  exit 1
}
echo ""

# --- Sync chaque application ---
FAILED=0
for app in "${APPS[@]}"; do
  log_info "Syncing: ${app}..."

  # Verifier si l'app existe
  if ! argocd app get "${app}" &>/dev/null; then
    log_warn "Application '${app}' not found, skipping"
    continue
  fi

  if [ "${DRY_RUN}" = true ]; then
    log_info "[DRY-RUN] Would sync: ${app}"
    argocd app diff "${app}" 2>/dev/null || true
    continue
  fi

  # Sync avec ou sans prune
  if argocd app sync "${app}" ${PRUNE_FLAG} --force 2>/dev/null; then
    log_ok "${app} synced successfully"
  else
    log_error "${app} sync FAILED"
    FAILED=$((FAILED + 1))
  fi

  echo ""
done

# --- Attendre que toutes les apps soient healthy ---
if [ "${DRY_RUN}" = false ]; then
  log_info "Waiting for all applications to be healthy..."
  for app in "${APPS[@]}"; do
    if argocd app get "${app}" &>/dev/null; then
      argocd app wait "${app}" --health --timeout 120 2>/dev/null || {
        log_warn "${app} not healthy after 120s"
      }
    fi
  done
fi

# --- Resume ---
echo ""
echo "============================================"
if [ "${FAILED}" -eq 0 ]; then
  log_ok "All applications synced successfully"
else
  log_error "${FAILED} application(s) failed to sync"
fi
echo "============================================"
echo ""

# Afficher l'etat final
argocd app list --output wide 2>/dev/null || true

exit ${FAILED}
