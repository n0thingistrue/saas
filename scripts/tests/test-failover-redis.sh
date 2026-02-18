#!/bin/bash
# =============================================================================
# Test Failover Redis (Sentinel)
# =============================================================================
# Valide le failover automatique de Redis via Sentinel.
# Mesure le RTO - Cible : < 15 secondes
#
# Usage :
#   ./scripts/tests/test-failover-redis.sh
#   ./scripts/tests/test-failover-redis.sh --dry-run
# =============================================================================

set -euo pipefail

# --- Configuration ---
NAMESPACE="production"
REDIS_MASTER_LABEL="app=redis,role=master"
REDIS_SENTINEL_LABEL="app=redis-sentinel"
SENTINEL_MASTER_NAME="mymaster"
TIMEOUT_FAILOVER=30
TARGET_RTO=15

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
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

echo "============================================"
echo "  Test Failover Redis (Sentinel)"
echo "============================================"
echo ""

# --- Step 1 : Etat initial ---
log_step "1/5 - Verification etat initial Redis Sentinel"

# Trouver le pod Sentinel
SENTINEL_POD=$(kubectl get pods -n "${NAMESPACE}" -l "${REDIS_SENTINEL_LABEL}" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || {
  log_fail "Aucun pod Sentinel trouve"
  exit 1
}

# Recuperer l'info du master actuel
MASTER_INFO=$(kubectl exec -n "${NAMESPACE}" "${SENTINEL_POD}" -- \
  redis-cli -p 26379 SENTINEL master "${SENTINEL_MASTER_NAME}" 2>/dev/null) || {
  log_fail "Impossible de recuperer les infos Sentinel"
  exit 1
}

MASTER_IP=$(echo "${MASTER_INFO}" | awk '/^ip$/{getline; print}')
MASTER_PORT=$(echo "${MASTER_INFO}" | awk '/^port$/{getline; print}')
NUM_SLAVES=$(echo "${MASTER_INFO}" | awk '/^num-slaves$/{getline; print}')
NUM_SENTINELS=$(echo "${MASTER_INFO}" | awk '/^num-other-sentinels$/{getline; print}')
QUORUM=$(echo "${MASTER_INFO}" | awk '/^quorum$/{getline; print}')

log_info "Master actuel    : ${MASTER_IP}:${MASTER_PORT}"
log_info "Replicas         : ${NUM_SLAVES}"
log_info "Sentinels        : $((NUM_SENTINELS + 1))"
log_info "Quorum           : ${QUORUM}"

# Identifier le pod master
MASTER_POD=$(kubectl get pods -n "${NAMESPACE}" -l "app=redis" \
  -o jsonpath="{.items[?(@.status.podIP=='${MASTER_IP}')].metadata.name}" 2>/dev/null) || MASTER_POD=""

log_info "Master pod       : ${MASTER_POD}"
echo ""

# --- Step 2 : Verifier la replication ---
log_step "2/5 - Verification de la replication"

REPL_INFO=$(kubectl exec -n "${NAMESPACE}" "${MASTER_POD}" -- \
  redis-cli INFO replication 2>/dev/null) || {
  log_warn "Impossible de recuperer les infos de replication"
}

ROLE=$(echo "${REPL_INFO}" | grep "role:" | tr -d '\r' | cut -d: -f2)
CONNECTED_SLAVES=$(echo "${REPL_INFO}" | grep "connected_slaves:" | tr -d '\r' | cut -d: -f2)

if [ "${ROLE}" = "master" ]; then
  log_ok "Role confirme : master"
else
  log_fail "Role inattendu : ${ROLE}"
  ERRORS=$((ERRORS + 1))
fi

if [ "${CONNECTED_SLAVES}" -ge 1 ]; then
  log_ok "Replicas connectes : ${CONNECTED_SLAVES}"
else
  log_fail "Aucun replica connecte"
  ERRORS=$((ERRORS + 1))
fi

# --- Step 3 : Inserer donnees de test ---
log_step "3/5 - Insertion de donnees de test"

TEST_KEY="failover_test_$(date +%s)"
TEST_VALUE="pre-failover-data-$(date +%Y%m%d%H%M%S)"

kubectl exec -n "${NAMESPACE}" "${MASTER_POD}" -- \
  redis-cli SET "${TEST_KEY}" "${TEST_VALUE}" EX 300 2>/dev/null || {
  log_warn "Impossible d'inserer les donnees de test"
}

# Verifier la replication de la cle
sleep 2
REPLICA_POD=$(kubectl get pods -n "${NAMESPACE}" -l "app=redis,role=replica" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || REPLICA_POD=""

if [ -n "${REPLICA_POD}" ]; then
  REPLICA_VALUE=$(kubectl exec -n "${NAMESPACE}" "${REPLICA_POD}" -- \
    redis-cli GET "${TEST_KEY}" 2>/dev/null) || REPLICA_VALUE=""

  if [ "${REPLICA_VALUE}" = "${TEST_VALUE}" ]; then
    log_ok "Donnee repliquee sur le replica"
  else
    log_warn "Donnee non repliquee (lag de replication ?)"
  fi
fi

# --- Step 4 : Declencher le failover ---
log_step "4/5 - Declenchement du failover Sentinel"

if [ "${DRY_RUN}" = true ]; then
  log_warn "[DRY-RUN] Failover simule"
  echo ""
  echo "  Commande : redis-cli -p 26379 SENTINEL failover ${SENTINEL_MASTER_NAME}"
  echo ""
  log_ok "[DRY-RUN] Test termine"
  exit 0
fi

FAILOVER_START=$(date +%s%N)

# Declencher le failover via Sentinel
kubectl exec -n "${NAMESPACE}" "${SENTINEL_POD}" -- \
  redis-cli -p 26379 SENTINEL failover "${SENTINEL_MASTER_NAME}" 2>/dev/null || {
  log_fail "Commande failover echouee"
  exit 1
}

log_info "Failover declenche, attente de la promotion..."

# --- Step 5 : Mesurer le RTO ---
log_step "5/5 - Mesure du RTO et verification"

RECOVERED=false
ELAPSED=0

while [ "${ELAPSED}" -lt "${TIMEOUT_FAILOVER}" ]; do
  sleep 1
  ELAPSED=$(( ($(date +%s%N) - FAILOVER_START) / 1000000000 ))

  # Verifier le nouveau master via Sentinel
  NEW_MASTER_IP=$(kubectl exec -n "${NAMESPACE}" "${SENTINEL_POD}" -- \
    redis-cli -p 26379 SENTINEL get-master-addr-by-name "${SENTINEL_MASTER_NAME}" \
    2>/dev/null | head -1) || continue

  if [ -n "${NEW_MASTER_IP}" ] && [ "${NEW_MASTER_IP}" != "${MASTER_IP}" ]; then
    # Verifier que le nouveau master accepte les ecritures
    NEW_MASTER_POD=$(kubectl get pods -n "${NAMESPACE}" -l "app=redis" \
      -o jsonpath="{.items[?(@.status.podIP=='${NEW_MASTER_IP}')].metadata.name}" 2>/dev/null) || continue

    WRITE_OK=$(kubectl exec -n "${NAMESPACE}" "${NEW_MASTER_POD}" -- \
      redis-cli SET failover_write_test "ok" EX 60 2>/dev/null) || continue

    if [ "${WRITE_OK}" = "OK" ]; then
      FAILOVER_END=$(date +%s%N)
      RTO_MS=$(( (FAILOVER_END - FAILOVER_START) / 1000000 ))
      RTO_SEC=$(( RTO_MS / 1000 ))
      RECOVERED=true
      break
    fi
  fi

  echo -ne "\r  Attente... ${ELAPSED}s / ${TIMEOUT_FAILOVER}s"
done
echo ""

if [ "${RECOVERED}" = true ]; then
  log_info "Nouveau master   : ${NEW_MASTER_IP} (${NEW_MASTER_POD})"
  log_info "RTO mesure       : ${RTO_SEC}s (${RTO_MS}ms)"

  if [ "${RTO_SEC}" -le "${TARGET_RTO}" ]; then
    log_ok "RTO ${RTO_SEC}s <= ${TARGET_RTO}s (cible respectee)"
  else
    log_fail "RTO ${RTO_SEC}s > ${TARGET_RTO}s (cible depassee)"
    ERRORS=$((ERRORS + 1))
  fi

  # Verifier les donnees pre-failover
  RECOVERED_VALUE=$(kubectl exec -n "${NAMESPACE}" "${NEW_MASTER_POD}" -- \
    redis-cli GET "${TEST_KEY}" 2>/dev/null) || RECOVERED_VALUE=""

  if [ "${RECOVERED_VALUE}" = "${TEST_VALUE}" ]; then
    log_ok "Donnees pre-failover intactes (RPO = 0)"
  else
    log_fail "Donnees pre-failover perdues"
    ERRORS=$((ERRORS + 1))
  fi

  # Nettoyage
  kubectl exec -n "${NAMESPACE}" "${NEW_MASTER_POD}" -- \
    redis-cli DEL "${TEST_KEY}" failover_write_test 2>/dev/null || true
else
  log_fail "Failover non termine apres ${TIMEOUT_FAILOVER}s"
  ERRORS=$((ERRORS + 1))
fi

# --- Resume ---
echo ""
echo "============================================"
echo "  Resultats Test Failover Redis"
echo "============================================"
echo ""
echo "  Master initial   : ${MASTER_IP} (${MASTER_POD})"
echo "  Nouveau master   : ${NEW_MASTER_IP:-N/A} (${NEW_MASTER_POD:-N/A})"
echo "  RTO mesure       : ${RTO_SEC:-N/A}s (cible: <${TARGET_RTO}s)"
echo "  Replicas         : ${NUM_SLAVES}"
echo "  Sentinels        : $((NUM_SENTINELS + 1))"
echo "  Donnees intactes : $([ "${RECOVERED_VALUE:-}" = "${TEST_VALUE}" ] && echo "OUI" || echo "NON")"
echo ""

if [ "${ERRORS}" -eq 0 ]; then
  log_ok "TOUS LES TESTS REUSSIS"
else
  log_fail "${ERRORS} TEST(S) ECHOUE(S)"
fi
echo "============================================"

exit "${ERRORS}"
