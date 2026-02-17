#!/usr/bin/env bash
# =============================================================================
# Fonctions utilitaires communes
# =============================================================================
# Source ce fichier dans les scripts : source "$(dirname "$0")/../utils/common.sh"
# =============================================================================

# Couleurs
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }

# Vérifier qu'une commande existe
require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Commande requise non trouvée: $cmd"
        exit 1
    fi
}

# Vérifier l'accès root
require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Ce script doit être exécuté en tant que root"
        exit 1
    fi
}

# Vérifier l'accès kubectl au cluster
require_cluster() {
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Impossible de se connecter au cluster Kubernetes"
        log_error "Vérifiez votre kubeconfig"
        exit 1
    fi
}

# Attendre qu'une condition soit vraie
wait_for() {
    local description="$1"
    local check_cmd="$2"
    local timeout="${3:-120}"
    local interval="${4:-5}"
    local start_time=$(date +%s)

    log_info "Attente: $description (timeout: ${timeout}s)..."
    while true; do
        if eval "$check_cmd" &>/dev/null; then
            log_success "$description"
            return 0
        fi

        local elapsed=$(( $(date +%s) - start_time ))
        if [[ "$elapsed" -ge "$timeout" ]]; then
            log_error "Timeout après ${timeout}s: $description"
            return 1
        fi

        sleep "$interval"
    done
}

# Charger les variables d'environnement depuis un fichier
load_env() {
    local env_file="$1"
    if [[ -f "$env_file" ]]; then
        set -a
        source "$env_file"
        set +a
    else
        log_warn "Fichier env non trouvé: $env_file"
    fi
}

# Obtenir le répertoire racine du projet
project_root() {
    local dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
    echo "$dir"
}
