#!/bin/bash
# =============================================================================
# Setup Secrets - Generation et configuration securisee des secrets
# =============================================================================
# Genere des passwords forts aleatoires pour tous les services,
# cree les Kubernetes Secrets et les SealedSecrets pour GitOps.
#
# Usage :
#   ./scripts/setup-secrets.sh              # Generer tout
#   ./scripts/setup-secrets.sh --regenerate # Regenerer (avec confirmation)
#   ./scripts/setup-secrets.sh --list       # Lister les secrets (sans valeurs)
#   ./scripts/setup-secrets.sh --apply      # Apply les SealedSecrets dans K8s
#
# Pre-requis :
#   - openssl (generation mots de passe)
#   - kubectl (connecte au cluster)
#   - kubeseal (chiffrement SealedSecrets)
# =============================================================================

set -euo pipefail

# --- Configuration ---
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_DIR="${PROJECT_ROOT}/kubernetes/secrets"
SEALED_DIR="${PROJECT_ROOT}/kubernetes/secrets/sealed"
ENV_FILE="${PROJECT_ROOT}/.secrets.env"
BACKUP_DIR="${PROJECT_ROOT}/.secrets-backup"

# Longueurs de mots de passe
PW_LENGTH=32
PW_LENGTH_SHORT=24
JWT_LENGTH=64

# --- Couleurs ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "${CYAN}[STEP]${NC} $*"; }

# --- Options ---
ACTION="generate"
for arg in "$@"; do
  case "$arg" in
    --regenerate) ACTION="regenerate" ;;
    --list)       ACTION="list" ;;
    --apply)      ACTION="apply" ;;
    --help|-h)    ACTION="help" ;;
  esac
done

# =============================================================================
# Fonctions utilitaires
# =============================================================================

generate_password() {
  local length="${1:-${PW_LENGTH}}"
  openssl rand -base64 "${length}" 2>/dev/null | tr -d '/+=' | head -c "${length}"
}

generate_hex() {
  local length="${1:-${JWT_LENGTH}}"
  openssl rand -hex "$((length / 2))" 2>/dev/null | head -c "${length}"
}

generate_bcrypt_hash() {
  local password="$1"
  # htpasswd format pour Traefik BasicAuth
  if command -v htpasswd &>/dev/null; then
    htpasswd -nbB admin "${password}" 2>/dev/null
  else
    # Fallback: format simple (non bcrypt)
    echo "admin:$(openssl passwd -apr1 "${password}" 2>/dev/null)"
  fi
}

check_prerequisites() {
  local missing=()

  if ! command -v openssl &>/dev/null; then
    missing+=("openssl")
  fi

  if [ "${ACTION}" = "apply" ] || [ "${ACTION}" = "generate" ]; then
    if ! command -v kubectl &>/dev/null; then
      missing+=("kubectl")
    fi
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    log_error "Pre-requis manquants : ${missing[*]}"
    echo "  Installer les outils necessaires avant de continuer."
    exit 1
  fi

  # kubeseal est optionnel mais recommande
  if ! command -v kubeseal &>/dev/null; then
    log_warn "kubeseal non installe - SealedSecrets ne seront pas crees"
    log_warn "Installer : https://github.com/bitnami-labs/sealed-secrets/releases"
    HAS_KUBESEAL=false
  else
    HAS_KUBESEAL=true
  fi
}

create_k8s_secret_yaml() {
  local name="$1"
  local namespace="$2"
  shift 2
  # Remaining args are key=value pairs

  local file="${SECRETS_DIR}/${namespace}-${name}.yaml"

  cat > "${file}" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${name}
  namespace: ${namespace}
type: Opaque
stringData:
EOF

  while [ $# -gt 0 ]; do
    local key="${1%%=*}"
    local value="${1#*=}"
    echo "  ${key}: \"${value}\"" >> "${file}"
    shift
  done

  echo "${file}"
}

seal_secret() {
  local input_file="$1"
  local output_file="${SEALED_DIR}/$(basename "${input_file}" .yaml)-sealed.yaml"

  if [ "${HAS_KUBESEAL}" = true ]; then
    kubeseal --format yaml < "${input_file}" > "${output_file}" 2>/dev/null && {
      return 0
    }
    log_warn "kubeseal echoue (controller non accessible?) - secret YAML conserve"
    return 1
  fi
  return 1
}

append_env() {
  local key="$1"
  local value="$2"
  echo "${key}=\"${value}\"" >> "${ENV_FILE}"
}

# =============================================================================
# Action : help
# =============================================================================
show_help() {
  echo ""
  echo -e "${BOLD}Setup Secrets - Generation securisee des secrets${NC}"
  echo ""
  echo "Usage :"
  echo "  ./scripts/setup-secrets.sh              Generer tous les secrets"
  echo "  ./scripts/setup-secrets.sh --regenerate  Regenerer (avec confirmation)"
  echo "  ./scripts/setup-secrets.sh --list        Lister les secrets configures"
  echo "  ./scripts/setup-secrets.sh --apply       Appliquer les SealedSecrets"
  echo "  ./scripts/setup-secrets.sh --help        Afficher cette aide"
  echo ""
  echo "Secrets generes :"
  echo "  - PostgreSQL  : postgres, replicator, app_user (3 passwords)"
  echo "  - Redis       : requirepass (1 password)"
  echo "  - Samba-AD    : admin, ldap_bind (2 passwords)"
  echo "  - Grafana     : admin (1 password)"
  echo "  - Traefik     : dashboard basic auth (1 password)"
  echo "  - Backend     : jwt_secret, jwt_refresh, db_password (3 secrets)"
  echo "  - Frontend    : nextauth_secret (1 secret)"
  echo "  - S3 Backup   : access_key, secret_key (2 credentials)"
  echo ""
  echo "Fichiers generes :"
  echo "  kubernetes/secrets/          Secrets YAML (non committes)"
  echo "  kubernetes/secrets/sealed/   SealedSecrets (a committer)"
  echo "  .secrets.env                 Copie locale des valeurs"
  echo ""
  exit 0
}

# =============================================================================
# Action : list
# =============================================================================
list_secrets() {
  echo ""
  echo -e "${BOLD}Secrets configures${NC}"
  echo ""

  if [ -f "${ENV_FILE}" ]; then
    echo "  Source : ${ENV_FILE}"
    echo ""
    printf "  %-35s %s\n" "Variable" "Status"
    printf "  %-35s %s\n" "-----------------------------------" "--------"
    while IFS='=' read -r key _value; do
      [[ "${key}" =~ ^#.*$ ]] && continue
      [[ -z "${key}" ]] && continue
      printf "  %-35s %s\n" "${key}" "Set"
    done < "${ENV_FILE}"
  else
    log_warn "Fichier .secrets.env non trouve"
    echo "  Executer : ./scripts/setup-secrets.sh"
  fi

  echo ""

  if [ -d "${SEALED_DIR}" ]; then
    SEALED_COUNT=$(find "${SEALED_DIR}" -name "*-sealed.yaml" 2>/dev/null | wc -l)
    log_info "SealedSecrets disponibles : ${SEALED_COUNT}"
    find "${SEALED_DIR}" -name "*-sealed.yaml" -exec basename {} \; 2>/dev/null | sort | while read -r f; do
      echo "    ${f}"
    done
  fi

  echo ""
  exit 0
}

# =============================================================================
# Action : apply
# =============================================================================
apply_secrets() {
  echo ""
  echo -e "${BOLD}Application des SealedSecrets${NC}"
  echo ""

  if [ ! -d "${SEALED_DIR}" ]; then
    log_error "Aucun SealedSecret trouve dans ${SEALED_DIR}"
    log_info "Executer d'abord : ./scripts/setup-secrets.sh"
    exit 1
  fi

  SEALED_FILES=$(find "${SEALED_DIR}" -name "*-sealed.yaml" 2>/dev/null)
  if [ -z "${SEALED_FILES}" ]; then
    log_error "Aucun fichier SealedSecret a appliquer"
    exit 1
  fi

  APPLIED=0
  FAILED=0

  for file in ${SEALED_FILES}; do
    name=$(basename "${file}")
    if kubectl apply -f "${file}" 2>/dev/null; then
      log_ok "Applied: ${name}"
      APPLIED=$((APPLIED + 1))
    else
      log_error "Failed: ${name}"
      FAILED=$((FAILED + 1))
    fi
  done

  echo ""
  log_info "Appliques : ${APPLIED}, Echoues : ${FAILED}"
  exit "${FAILED}"
}

# =============================================================================
# Action : generate / regenerate
# =============================================================================
generate_secrets() {
  echo ""
  echo -e "${BOLD}============================================${NC}"
  echo -e "${BOLD}  Generation des secrets infrastructure${NC}"
  echo -e "${BOLD}============================================${NC}"
  echo ""

  # --- Verification pre-requis ---
  check_prerequisites

  # --- Confirmation si regeneration ---
  if [ "${ACTION}" = "regenerate" ]; then
    if [ -f "${ENV_FILE}" ]; then
      log_warn "Des secrets existent deja dans ${ENV_FILE}"
      echo ""
      read -rp "  Regenerer TOUS les secrets ? Les anciens seront sauvegardes. (oui/non) : " confirm
      if [ "${confirm}" != "oui" ]; then
        log_info "Annule."
        exit 0
      fi

      # Backup des secrets existants
      mkdir -p "${BACKUP_DIR}"
      BACKUP_FILE="${BACKUP_DIR}/secrets-$(date +%Y%m%d-%H%M%S).env"
      cp "${ENV_FILE}" "${BACKUP_FILE}"
      chmod 600 "${BACKUP_FILE}"
      log_ok "Backup sauvegarde : ${BACKUP_FILE}"
      echo ""
    fi
  elif [ -f "${ENV_FILE}" ] && [ "${ACTION}" = "generate" ]; then
    log_warn "Des secrets existent deja. Utiliser --regenerate pour les remplacer."
    log_info "Utiliser --list pour voir les secrets actuels."
    exit 0
  fi

  # --- Creer les repertoires ---
  mkdir -p "${SECRETS_DIR}" "${SEALED_DIR}"

  # --- Initialiser le fichier .secrets.env ---
  cat > "${ENV_FILE}" <<'HEADER'
# =============================================================================
# Infrastructure Secrets - GENERE AUTOMATIQUEMENT
# =============================================================================
# NE JAMAIS COMMITTER CE FICHIER DANS GIT
# Genere par : scripts/setup-secrets.sh
# =============================================================================

HEADER
  echo "# Date de generation : $(date '+%Y-%m-%d %H:%M:%S')" >> "${ENV_FILE}"
  echo "" >> "${ENV_FILE}"

  # --- Verifier .gitignore ---
  GITIGNORE="${PROJECT_ROOT}/.gitignore"
  if [ -f "${GITIGNORE}" ]; then
    for pattern in ".secrets.env" ".secrets-backup/" "kubernetes/secrets/*.yaml"; do
      if ! grep -qF "${pattern}" "${GITIGNORE}" 2>/dev/null; then
        echo "${pattern}" >> "${GITIGNORE}"
        log_info "Ajoute a .gitignore : ${pattern}"
      fi
    done
  else
    cat > "${GITIGNORE}" <<'GITIGNORE_CONTENT'
# Secrets - NE JAMAIS COMMITTER
.secrets.env
.secrets-backup/
kubernetes/secrets/*.yaml

# SealedSecrets (chiffres) peuvent etre committes
# kubernetes/secrets/sealed/
GITIGNORE_CONTENT
    log_ok ".gitignore cree"
  fi

  SEALED_OK=0
  SEALED_FAIL=0

  # =====================================================================
  # 1. PostgreSQL
  # =====================================================================
  log_step "1/8 - Generation secrets PostgreSQL"

  PG_POSTGRES_PASSWORD=$(generate_password ${PW_LENGTH})
  PG_REPLICATOR_PASSWORD=$(generate_password ${PW_LENGTH})
  PG_APP_PASSWORD=$(generate_password ${PW_LENGTH})

  echo "# --- PostgreSQL ---" >> "${ENV_FILE}"
  append_env "POSTGRES_PASSWORD" "${PG_POSTGRES_PASSWORD}"
  append_env "POSTGRES_REPLICATOR_PASSWORD" "${PG_REPLICATOR_PASSWORD}"
  append_env "POSTGRES_APP_PASSWORD" "${PG_APP_PASSWORD}"
  echo "" >> "${ENV_FILE}"

  SECRET_FILE=$(create_k8s_secret_yaml "postgresql-secrets" "production" \
    "POSTGRES_PASSWORD=${PG_POSTGRES_PASSWORD}" \
    "REPLICATION_PASSWORD=${PG_REPLICATOR_PASSWORD}" \
    "APP_USER_PASSWORD=${PG_APP_PASSWORD}")

  if seal_secret "${SECRET_FILE}"; then
    SEALED_OK=$((SEALED_OK + 1))
  else
    SEALED_FAIL=$((SEALED_FAIL + 1))
  fi

  log_ok "PostgreSQL secrets : 3 passwords generes"

  # =====================================================================
  # 2. Redis
  # =====================================================================
  log_step "2/8 - Generation secrets Redis"

  REDIS_PASSWORD=$(generate_password ${PW_LENGTH})

  echo "# --- Redis ---" >> "${ENV_FILE}"
  append_env "REDIS_PASSWORD" "${REDIS_PASSWORD}"
  echo "" >> "${ENV_FILE}"

  SECRET_FILE=$(create_k8s_secret_yaml "redis-secrets" "production" \
    "REDIS_PASSWORD=${REDIS_PASSWORD}")

  if seal_secret "${SECRET_FILE}"; then
    SEALED_OK=$((SEALED_OK + 1))
  else
    SEALED_FAIL=$((SEALED_FAIL + 1))
  fi

  log_ok "Redis secret : 1 password genere"

  # =====================================================================
  # 3. Samba-AD
  # =====================================================================
  log_step "3/8 - Generation secrets Samba-AD"

  SAMBA_ADMIN_PASSWORD=$(generate_password ${PW_LENGTH})
  SAMBA_BIND_PASSWORD=$(generate_password ${PW_LENGTH_SHORT})

  echo "# --- Samba-AD ---" >> "${ENV_FILE}"
  append_env "SAMBA_ADMIN_PASSWORD" "${SAMBA_ADMIN_PASSWORD}"
  append_env "SAMBA_LDAP_BIND_PASSWORD" "${SAMBA_BIND_PASSWORD}"
  echo "" >> "${ENV_FILE}"

  SECRET_FILE=$(create_k8s_secret_yaml "samba-secrets" "production" \
    "ADMIN_PASSWORD=${SAMBA_ADMIN_PASSWORD}" \
    "LDAP_BIND_PASSWORD=${SAMBA_BIND_PASSWORD}")

  if seal_secret "${SECRET_FILE}"; then
    SEALED_OK=$((SEALED_OK + 1))
  else
    SEALED_FAIL=$((SEALED_FAIL + 1))
  fi

  log_ok "Samba-AD secrets : 2 passwords generes"

  # =====================================================================
  # 4. Grafana
  # =====================================================================
  log_step "4/8 - Generation secrets Grafana"

  GRAFANA_ADMIN_PASSWORD=$(generate_password ${PW_LENGTH_SHORT})

  echo "# --- Grafana ---" >> "${ENV_FILE}"
  append_env "GRAFANA_ADMIN_PASSWORD" "${GRAFANA_ADMIN_PASSWORD}"
  echo "" >> "${ENV_FILE}"

  SECRET_FILE=$(create_k8s_secret_yaml "grafana-secrets" "monitoring" \
    "GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}" \
    "GF_SECURITY_ADMIN_USER=admin")

  if seal_secret "${SECRET_FILE}"; then
    SEALED_OK=$((SEALED_OK + 1))
  else
    SEALED_FAIL=$((SEALED_FAIL + 1))
  fi

  log_ok "Grafana secret : 1 password genere"

  # =====================================================================
  # 5. Traefik Dashboard
  # =====================================================================
  log_step "5/8 - Generation secrets Traefik Dashboard"

  TRAEFIK_DASHBOARD_PASSWORD=$(generate_password ${PW_LENGTH_SHORT})
  TRAEFIK_BASIC_AUTH=$(generate_bcrypt_hash "${TRAEFIK_DASHBOARD_PASSWORD}")

  echo "# --- Traefik Dashboard ---" >> "${ENV_FILE}"
  append_env "TRAEFIK_DASHBOARD_PASSWORD" "${TRAEFIK_DASHBOARD_PASSWORD}"
  append_env "TRAEFIK_BASIC_AUTH" "${TRAEFIK_BASIC_AUTH}"
  echo "" >> "${ENV_FILE}"

  SECRET_FILE=$(create_k8s_secret_yaml "traefik-dashboard-auth" "ingress" \
    "users=${TRAEFIK_BASIC_AUTH}")

  if seal_secret "${SECRET_FILE}"; then
    SEALED_OK=$((SEALED_OK + 1))
  else
    SEALED_FAIL=$((SEALED_FAIL + 1))
  fi

  log_ok "Traefik Dashboard secret : 1 password + basic auth generes"

  # =====================================================================
  # 6. Backend NestJS
  # =====================================================================
  log_step "6/8 - Generation secrets Backend"

  BACKEND_JWT_SECRET=$(generate_hex ${JWT_LENGTH})
  BACKEND_JWT_REFRESH_SECRET=$(generate_hex ${JWT_LENGTH})
  BACKEND_DB_PASSWORD="${PG_APP_PASSWORD}"  # Reutilise le password PG app_user

  echo "# --- Backend NestJS ---" >> "${ENV_FILE}"
  append_env "BACKEND_JWT_SECRET" "${BACKEND_JWT_SECRET}"
  append_env "BACKEND_JWT_REFRESH_SECRET" "${BACKEND_JWT_REFRESH_SECRET}"
  append_env "BACKEND_DATABASE_PASSWORD" "${BACKEND_DB_PASSWORD}"
  echo "" >> "${ENV_FILE}"

  SECRET_FILE=$(create_k8s_secret_yaml "backend-secrets" "production" \
    "JWT_SECRET=${BACKEND_JWT_SECRET}" \
    "JWT_REFRESH_SECRET=${BACKEND_JWT_REFRESH_SECRET}" \
    "DATABASE_PASSWORD=${BACKEND_DB_PASSWORD}" \
    "REDIS_PASSWORD=${REDIS_PASSWORD}" \
    "LDAP_BIND_PASSWORD=${SAMBA_BIND_PASSWORD}")

  if seal_secret "${SECRET_FILE}"; then
    SEALED_OK=$((SEALED_OK + 1))
  else
    SEALED_FAIL=$((SEALED_FAIL + 1))
  fi

  log_ok "Backend secrets : 3 secrets generes (JWT + DB + references)"

  # =====================================================================
  # 7. Frontend Next.js
  # =====================================================================
  log_step "7/8 - Generation secrets Frontend"

  NEXTAUTH_SECRET=$(generate_hex ${JWT_LENGTH})

  echo "# --- Frontend Next.js ---" >> "${ENV_FILE}"
  append_env "NEXTAUTH_SECRET" "${NEXTAUTH_SECRET}"
  echo "" >> "${ENV_FILE}"

  SECRET_FILE=$(create_k8s_secret_yaml "frontend-secrets" "production" \
    "NEXTAUTH_SECRET=${NEXTAUTH_SECRET}")

  if seal_secret "${SECRET_FILE}"; then
    SEALED_OK=$((SEALED_OK + 1))
  else
    SEALED_FAIL=$((SEALED_FAIL + 1))
  fi

  log_ok "Frontend secret : 1 secret genere"

  # =====================================================================
  # 8. S3 Backup Credentials
  # =====================================================================
  log_step "8/8 - Generation credentials S3 Backup"

  S3_ACCESS_KEY=$(generate_password ${PW_LENGTH_SHORT})
  S3_SECRET_KEY=$(generate_password ${PW_LENGTH})

  echo "# --- S3 Backup ---" >> "${ENV_FILE}"
  append_env "S3_ACCESS_KEY" "${S3_ACCESS_KEY}"
  append_env "S3_SECRET_KEY" "${S3_SECRET_KEY}"
  echo "" >> "${ENV_FILE}"

  SECRET_FILE=$(create_k8s_secret_yaml "s3-backup-credentials" "production" \
    "AWS_ACCESS_KEY_ID=${S3_ACCESS_KEY}" \
    "AWS_SECRET_ACCESS_KEY=${S3_SECRET_KEY}" \
    "AWS_ENDPOINT=https://fsn1.your-objectstorage.com" \
    "AWS_REGION=fsn1" \
    "WALG_S3_PREFIX=s3://saas-backups/walg")

  if seal_secret "${SECRET_FILE}"; then
    SEALED_OK=$((SEALED_OK + 1))
  else
    SEALED_FAIL=$((SEALED_FAIL + 1))
  fi

  log_ok "S3 Backup credentials : 2 credentials generes"

  # --- Securiser le fichier .secrets.env ---
  chmod 600 "${ENV_FILE}"

  # =====================================================================
  # Recapitulatif
  # =====================================================================
  echo ""
  echo -e "${BOLD}============================================${NC}"
  echo -e "${BOLD}  Recapitulatif${NC}"
  echo -e "${BOLD}============================================${NC}"
  echo ""
  log_ok "PostgreSQL secrets  : 3 passwords (postgres, replicator, app_user)"
  log_ok "Redis secret        : 1 password (requirepass)"
  log_ok "Samba-AD secrets    : 2 passwords (admin, ldap_bind)"
  log_ok "Grafana secret      : 1 password (admin)"
  log_ok "Traefik secret      : 1 password + basic auth hash"
  log_ok "Backend secrets     : 3 secrets (jwt, jwt_refresh, db_password)"
  log_ok "Frontend secret     : 1 secret (nextauth)"
  log_ok "S3 Backup           : 2 credentials (access_key, secret_key)"
  echo ""
  echo -e "  ${BOLD}Total : 14 secrets generes${NC}"
  echo ""

  if [ "${HAS_KUBESEAL}" = true ]; then
    echo -e "  SealedSecrets crees : ${SEALED_OK} OK, ${SEALED_FAIL} echecs"
  else
    echo -e "  ${YELLOW}SealedSecrets non crees (kubeseal absent)${NC}"
  fi

  echo ""
  echo -e "  ${YELLOW}IMPORTANT :${NC}"
  echo -e "  ${YELLOW}Secrets sauvegardes dans : ${ENV_FILE}${NC}"
  echo -e "  ${YELLOW}Ce fichier est PRIVE - ne JAMAIS le committer dans Git !${NC}"
  echo ""
  echo "  Secrets YAML (non chiffres) : ${SECRETS_DIR}/"
  echo "  SealedSecrets (chiffres)    : ${SEALED_DIR}/"
  echo ""
  echo "  Pour appliquer les SealedSecrets :"
  echo "    ./scripts/setup-secrets.sh --apply"
  echo ""
  echo "  Pour voir un secret apres deploiement :"
  echo "    kubectl get secret <name> -n <namespace> -o jsonpath='{.data.<key>}' | base64 -d"
  echo ""
  echo -e "${BOLD}============================================${NC}"
}

# =============================================================================
# Main
# =============================================================================
case "${ACTION}" in
  help)       show_help ;;
  list)       list_secrets ;;
  apply)      apply_secrets ;;
  generate)   generate_secrets ;;
  regenerate) generate_secrets ;;
  *)          show_help ;;
esac
