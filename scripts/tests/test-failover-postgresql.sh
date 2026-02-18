#!/bin/bash
# =============================================================================
# Test Failover PostgreSQL (Patroni)
# =============================================================================
# Valide le failover automatique de PostgreSQL via Patroni.
# Mesure le RTO (Recovery Time Objective) - Cible : < 30 secondes
#
# Usage :
#   ./scripts/tests/test-failover-postgresql.sh
#   ./scripts/tests/test-failover-postgresql.sh --dry-run
#
# Pre-requis :
#   - kubectl connecte au cluster
#   - PostgreSQL Patroni deploye (namespace: production)
# =============================================================================

set -euo pipefail

# --- Configuration ---
NAMESPACE="production"
PG_LABEL="app=postgresql"
PATRONI_CLUSTER="postgresql"
TIMEOUT_FAILOVER=60
TARGET_RTO=30

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
echo "  Test Failover PostgreSQL (Patroni)"
echo "============================================"
echo ""

# --- Step 1 : Verifier l'etat initial ---
log_step "1/6 - Verification etat initial du cluster Patroni"

INITIAL_STATE=$(kubectl exec -n "${NAMESPACE}" "${PATRONI_CLUSTER}-0" -- \
  patronictl list -f json 2>/dev/null) || {
  log_fail "Impossible de recuperer l'etat Patroni"
  exit 1
}

# Identifier le primary actuel
PRIMARY_POD=$(echo "${INITIAL_STATE}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for member in data:
    if member.get('Role') == 'Leader' or member.get('State') == 'running':
        print(member['Member'])
        break
" 2>/dev/null) || PRIMARY_POD=""

if [ -z "${PRIMARY_POD}" ]; then
  # Fallback: trouver via label
  PRIMARY_POD=$(kubectl get pods -n "${NAMESPACE}" -l "${PG_LABEL},role=master" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || {
    log_fail "Impossible d'identifier le primary PostgreSQL"
    exit 1
  }
fi

STANDBY_POD=$(echo "${INITIAL_STATE}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for member in data:
    if member.get('Role') == 'Replica' or member.get('State') == 'streaming':
        print(member['Member'])
        break
" 2>/dev/null) || STANDBY_POD=""

log_info "Primary actuel : ${PRIMARY_POD}"
log_info "Standby actuel : ${STANDBY_POD}"

# Afficher l'etat Patroni
kubectl exec -n "${NAMESPACE}" "${PATRONI_CLUSTER}-0" -- patronictl list 2>/dev/null || true
echo ""

# --- Step 2 : Verifier la replication ---
log_step "2/6 - Verification de la replication synchrone"

REPL_LAG=$(kubectl exec -n "${NAMESPACE}" "${PRIMARY_POD}" -- \
  psql -U postgres -t -c "SELECT COALESCE(MAX(replay_lag), interval '0')::text FROM pg_stat_replication;" \
  2>/dev/null | tr -d ' ') || REPL_LAG="unknown"

log_info "Lag de replication : ${REPL_LAG}"

REPL_STATE=$(kubectl exec -n "${NAMESPACE}" "${PRIMARY_POD}" -- \
  psql -U postgres -t -c "SELECT state FROM pg_stat_replication LIMIT 1;" \
  2>/dev/null | tr -d ' ') || REPL_STATE="unknown"

if [ "${REPL_STATE}" = "streaming" ]; then
  log_ok "Replication en mode streaming"
else
  log_warn "Etat replication: ${REPL_STATE}"
fi

# --- Step 3 : Inserer des donnees de test ---
log_step "3/6 - Insertion de donnees de test avant failover"

TEST_TIMESTAMP=$(date +%s)
kubectl exec -n "${NAMESPACE}" "${PRIMARY_POD}" -- \
  psql -U postgres -c "
    CREATE TABLE IF NOT EXISTS failover_test (
      id SERIAL PRIMARY KEY,
      test_id VARCHAR(50),
      created_at TIMESTAMP DEFAULT NOW()
    );
    INSERT INTO failover_test (test_id) VALUES ('pre-failover-${TEST_TIMESTAMP}');
  " 2>/dev/null || {
  log_warn "Impossible d'inserer les donnees de test"
}

log_ok "Donnees de test inserees (test_id: pre-failover-${TEST_TIMESTAMP})"

# --- Step 4 : Declencher le failover ---
log_step "4/6 - Declenchement du failover Patroni"

if [ "${DRY_RUN}" = true ]; then
  log_warn "[DRY-RUN] Failover simule - aucune action reelle"
  echo ""
  echo "  Commande qui serait executee :"
  echo "  kubectl exec -n ${NAMESPACE} ${PATRONI_CLUSTER}-0 -- patronictl switchover --force"
  echo ""
  log_ok "[DRY-RUN] Test termine"
  exit 0
fi

# Enregistrer le timestamp de debut
FAILOVER_START=$(date +%s%N)

# Declencher le switchover Patroni
kubectl exec -n "${NAMESPACE}" "${PATRONI_CLUSTER}-0" -- \
  patronictl switchover --force 2>/dev/null || {
  log_warn "Switchover via patronictl echoue, tentative via failover..."
  kubectl exec -n "${NAMESPACE}" "${PATRONI_CLUSTER}-0" -- \
    patronictl failover --force 2>/dev/null || {
    log_fail "Failover impossible"
    exit 1
  }
}

log_info "Failover declenche, attente de la promotion..."

# --- Step 5 : Mesurer le RTO ---
log_step "5/6 - Mesure du RTO (Recovery Time Objective)"

RECOVERED=false
ELAPSED=0

while [ "${ELAPSED}" -lt "${TIMEOUT_FAILOVER}" ]; do
  sleep 2
  ELAPSED=$(( ($(date +%s%N) - FAILOVER_START) / 1000000000 ))

  # Verifier si un nouveau primary est disponible
  NEW_STATE=$(kubectl exec -n "${NAMESPACE}" "${PATRONI_CLUSTER}-0" -- \
    patronictl list -f json 2>/dev/null) || continue

  NEW_PRIMARY=$(echo "${NEW_STATE}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for member in data:
    if member.get('Role') == 'Leader' and member.get('State') == 'running':
        print(member['Member'])
        break
" 2>/dev/null) || continue

  if [ -n "${NEW_PRIMARY}" ] && [ "${NEW_PRIMARY}" != "${PRIMARY_POD}" ]; then
    FAILOVER_END=$(date +%s%N)
    RTO_MS=$(( (FAILOVER_END - FAILOVER_START) / 1000000 ))
    RTO_SEC=$(( RTO_MS / 1000 ))
    RECOVERED=true
    break
  fi

  echo -ne "\r  Attente... ${ELAPSED}s / ${TIMEOUT_FAILOVER}s"
done
echo ""

if [ "${RECOVERED}" = true ]; then
  log_info "Nouveau primary : ${NEW_PRIMARY}"
  log_info "RTO mesure : ${RTO_SEC} secondes (${RTO_MS}ms)"

  if [ "${RTO_SEC}" -le "${TARGET_RTO}" ]; then
    log_ok "RTO ${RTO_SEC}s <= ${TARGET_RTO}s (cible respectee)"
  else
    log_fail "RTO ${RTO_SEC}s > ${TARGET_RTO}s (cible depassee)"
    ERRORS=$((ERRORS + 1))
  fi
else
  log_fail "Failover non termine apres ${TIMEOUT_FAILOVER}s"
  ERRORS=$((ERRORS + 1))
fi

# --- Step 6 : Verifier l'integrite des donnees ---
log_step "6/6 - Verification de l'integrite des donnees post-failover"

sleep 5  # Attendre stabilisation

# Verifier que les donnees pre-failover sont accessibles
if [ -n "${NEW_PRIMARY:-}" ]; then
  DATA_CHECK=$(kubectl exec -n "${NAMESPACE}" "${NEW_PRIMARY}" -- \
    psql -U postgres -t -c "SELECT COUNT(*) FROM failover_test WHERE test_id = 'pre-failover-${TEST_TIMESTAMP}';" \
    2>/dev/null | tr -d ' ') || DATA_CHECK="0"

  if [ "${DATA_CHECK}" = "1" ]; then
    log_ok "Donnees pre-failover intactes sur le nouveau primary"
  else
    log_fail "Donnees pre-failover perdues (RPO > 0)"
    ERRORS=$((ERRORS + 1))
  fi

  # Inserer des donnees post-failover
  kubectl exec -n "${NAMESPACE}" "${NEW_PRIMARY}" -- \
    psql -U postgres -c "INSERT INTO failover_test (test_id) VALUES ('post-failover-${TEST_TIMESTAMP}');" \
    2>/dev/null && log_ok "Ecriture post-failover reussie" || {
    log_fail "Ecriture post-failover echouee"
    ERRORS=$((ERRORS + 1))
  }

  # Afficher l'etat final
  echo ""
  log_info "Etat final du cluster Patroni :"
  kubectl exec -n "${NAMESPACE}" "${PATRONI_CLUSTER}-0" -- patronictl list 2>/dev/null || true
fi

# Nettoyage table de test
kubectl exec -n "${NAMESPACE}" "${NEW_PRIMARY:-${PATRONI_CLUSTER}-0}" -- \
  psql -U postgres -c "DROP TABLE IF EXISTS failover_test;" 2>/dev/null || true

# --- Resume ---
echo ""
echo "============================================"
echo "  Resultats Test Failover PostgreSQL"
echo "============================================"
echo ""
echo "  Primary initial  : ${PRIMARY_POD}"
echo "  Nouveau primary  : ${NEW_PRIMARY:-N/A}"
echo "  RTO mesure       : ${RTO_SEC:-N/A}s (cible: <${TARGET_RTO}s)"
echo "  Donnees intactes : $([ "${DATA_CHECK:-0}" = "1" ] && echo "OUI" || echo "NON")"
echo "  Replication      : ${REPL_STATE}"
echo ""

if [ "${ERRORS}" -eq 0 ]; then
  log_ok "TOUS LES TESTS REUSSIS"
else
  log_fail "${ERRORS} TEST(S) ECHOUE(S)"
fi
echo "============================================"

exit "${ERRORS}"
