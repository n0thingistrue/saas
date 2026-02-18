#!/bin/bash
# =============================================================================
# Test Haute Disponibilite Applications
# =============================================================================
# Valide le zero-downtime des applications lors de la perte d'un pod/node.
# Mesure la continuite de service pendant un rolling restart.
#
# Usage :
#   ./scripts/tests/test-ha-applications.sh
#   ./scripts/tests/test-ha-applications.sh --dry-run
# =============================================================================

set -euo pipefail

# --- Configuration ---
NAMESPACE="production"
BACKEND_SVC="backend.${NAMESPACE}.svc.cluster.local:3000"
FRONTEND_SVC="frontend.${NAMESPACE}.svc.cluster.local:3001"
TEST_DURATION=60
REQUEST_INTERVAL=0.5

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
echo "  Test HA Applications"
echo "============================================"
echo ""

# --- Step 1 : Etat initial ---
log_step "1/6 - Verification etat initial des applications"

# Backend
BACKEND_PODS=$(kubectl get pods -n "${NAMESPACE}" -l app=backend --no-headers 2>/dev/null | wc -l)
BACKEND_READY=$(kubectl get pods -n "${NAMESPACE}" -l app=backend --no-headers 2>/dev/null | grep -c "Running" || true)
log_info "Backend pods : ${BACKEND_READY}/${BACKEND_PODS} Running"

# Frontend
FRONTEND_PODS=$(kubectl get pods -n "${NAMESPACE}" -l app=frontend --no-headers 2>/dev/null | wc -l)
FRONTEND_READY=$(kubectl get pods -n "${NAMESPACE}" -l app=frontend --no-headers 2>/dev/null | grep -c "Running" || true)
log_info "Frontend pods : ${FRONTEND_READY}/${FRONTEND_PODS} Running"

# Verifier la distribution sur les nodes
log_info "Distribution des pods :"
kubectl get pods -n "${NAMESPACE}" -l "app in (backend,frontend)" -o wide \
  --no-headers 2>/dev/null | awk '{printf "  %-40s %s\n", $1, $7}'

if [ "${BACKEND_READY}" -lt 2 ]; then
  log_warn "Backend a moins de 2 replicas ready - HA limitee"
fi
if [ "${FRONTEND_READY}" -lt 2 ]; then
  log_warn "Frontend a moins de 2 replicas ready - HA limitee"
fi
echo ""

# --- Step 2 : Test connectivity baseline ---
log_step "2/6 - Test de connectivite baseline"

# Creer un pod de test curl
kubectl run ha-test-client --image=curlimages/curl:latest \
  --restart=Never -n "${NAMESPACE}" \
  --command -- sleep 300 2>/dev/null || true

kubectl wait --for=condition=Ready pod/ha-test-client -n "${NAMESPACE}" --timeout=30s 2>/dev/null || {
  log_fail "Pod de test non ready"
  kubectl delete pod ha-test-client -n "${NAMESPACE}" 2>/dev/null || true
  exit 1
}

# Test backend health
BACKEND_HEALTH=$(kubectl exec -n "${NAMESPACE}" ha-test-client -- \
  curl -s -o /dev/null -w "%{http_code}" "http://${BACKEND_SVC}/health" 2>/dev/null) || BACKEND_HEALTH="000"

if [ "${BACKEND_HEALTH}" = "200" ]; then
  log_ok "Backend health check : HTTP ${BACKEND_HEALTH}"
else
  log_fail "Backend health check : HTTP ${BACKEND_HEALTH}"
  ERRORS=$((ERRORS + 1))
fi

# Test frontend
FRONTEND_HEALTH=$(kubectl exec -n "${NAMESPACE}" ha-test-client -- \
  curl -s -o /dev/null -w "%{http_code}" "http://${FRONTEND_SVC}/" 2>/dev/null) || FRONTEND_HEALTH="000"

if [ "${FRONTEND_HEALTH}" = "200" ]; then
  log_ok "Frontend health check : HTTP ${FRONTEND_HEALTH}"
else
  log_fail "Frontend health check : HTTP ${FRONTEND_HEALTH}"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# --- Step 3 : Test zero-downtime rolling restart Backend ---
log_step "3/6 - Test zero-downtime rolling restart Backend"

if [ "${DRY_RUN}" = true ]; then
  log_warn "[DRY-RUN] Rolling restart simule"
else
  # Lancer des requetes en continu en arriere-plan
  RESULT_FILE="/tmp/ha-test-backend-$$"
  kubectl exec -n "${NAMESPACE}" ha-test-client -- sh -c "
    SUCCESS=0; FAIL=0; TOTAL=0
    for i in \$(seq 1 120); do
      CODE=\$(curl -s -o /dev/null -w '%{http_code}' 'http://${BACKEND_SVC}/health' 2>/dev/null || echo '000')
      TOTAL=\$((TOTAL + 1))
      if [ \"\${CODE}\" = '200' ]; then
        SUCCESS=\$((SUCCESS + 1))
      else
        FAIL=\$((FAIL + 1))
      fi
      sleep 0.5
    done
    echo \"\${SUCCESS} \${FAIL} \${TOTAL}\"
  " > "${RESULT_FILE}" 2>/dev/null &
  CURL_PID=$!

  # Attendre 5s puis declencher le rolling restart
  sleep 5
  log_info "Declenchement rolling restart backend..."
  kubectl rollout restart deployment/backend -n "${NAMESPACE}" 2>/dev/null

  # Attendre la fin des requetes
  wait "${CURL_PID}" 2>/dev/null || true

  if [ -f "${RESULT_FILE}" ]; then
    read -r SUCCESS FAIL TOTAL < "${RESULT_FILE}"
    rm -f "${RESULT_FILE}"

    AVAILABILITY=$(echo "scale=2; ${SUCCESS} * 100 / ${TOTAL}" | bc 2>/dev/null || echo "0")
    log_info "Requetes : ${SUCCESS}/${TOTAL} succes (${AVAILABILITY}%)"

    if [ "${FAIL}" -eq 0 ]; then
      log_ok "Zero-downtime backend : AUCUNE requete perdue"
    elif [ "${FAIL}" -le 2 ]; then
      log_warn "Backend : ${FAIL} requete(s) perdue(s) (acceptable)"
    else
      log_fail "Backend : ${FAIL} requetes perdues"
      ERRORS=$((ERRORS + 1))
    fi
  else
    log_warn "Resultats non disponibles"
  fi

  # Attendre que le rollout soit termine
  kubectl rollout status deployment/backend -n "${NAMESPACE}" --timeout=120s 2>/dev/null || {
    log_warn "Rollout backend non termine dans le delai"
  }
fi
echo ""

# --- Step 4 : Test zero-downtime rolling restart Frontend ---
log_step "4/6 - Test zero-downtime rolling restart Frontend"

if [ "${DRY_RUN}" = true ]; then
  log_warn "[DRY-RUN] Rolling restart simule"
else
  RESULT_FILE="/tmp/ha-test-frontend-$$"
  kubectl exec -n "${NAMESPACE}" ha-test-client -- sh -c "
    SUCCESS=0; FAIL=0; TOTAL=0
    for i in \$(seq 1 120); do
      CODE=\$(curl -s -o /dev/null -w '%{http_code}' 'http://${FRONTEND_SVC}/' 2>/dev/null || echo '000')
      TOTAL=\$((TOTAL + 1))
      if [ \"\${CODE}\" = '200' ]; then
        SUCCESS=\$((SUCCESS + 1))
      else
        FAIL=\$((FAIL + 1))
      fi
      sleep 0.5
    done
    echo \"\${SUCCESS} \${FAIL} \${TOTAL}\"
  " > "${RESULT_FILE}" 2>/dev/null &
  CURL_PID=$!

  sleep 5
  log_info "Declenchement rolling restart frontend..."
  kubectl rollout restart deployment/frontend -n "${NAMESPACE}" 2>/dev/null

  wait "${CURL_PID}" 2>/dev/null || true

  if [ -f "${RESULT_FILE}" ]; then
    read -r SUCCESS FAIL TOTAL < "${RESULT_FILE}"
    rm -f "${RESULT_FILE}"

    AVAILABILITY=$(echo "scale=2; ${SUCCESS} * 100 / ${TOTAL}" | bc 2>/dev/null || echo "0")
    log_info "Requetes : ${SUCCESS}/${TOTAL} succes (${AVAILABILITY}%)"

    if [ "${FAIL}" -eq 0 ]; then
      log_ok "Zero-downtime frontend : AUCUNE requete perdue"
    elif [ "${FAIL}" -le 2 ]; then
      log_warn "Frontend : ${FAIL} requete(s) perdue(s) (acceptable)"
    else
      log_fail "Frontend : ${FAIL} requetes perdues"
      ERRORS=$((ERRORS + 1))
    fi
  fi

  kubectl rollout status deployment/frontend -n "${NAMESPACE}" --timeout=120s 2>/dev/null || true
fi
echo ""

# --- Step 5 : Test pod deletion recovery ---
log_step "5/6 - Test recovery apres suppression de pod"

if [ "${DRY_RUN}" = true ]; then
  log_warn "[DRY-RUN] Suppression pod simulee"
else
  # Supprimer un pod backend
  TARGET_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=backend \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || TARGET_POD=""

  if [ -n "${TARGET_POD}" ]; then
    log_info "Suppression du pod : ${TARGET_POD}"
    DELETE_START=$(date +%s)

    kubectl delete pod "${TARGET_POD}" -n "${NAMESPACE}" --grace-period=5 2>/dev/null

    # Attendre que le nouveau pod soit ready
    RECOVERY_OK=false
    for i in $(seq 1 60); do
      READY_COUNT=$(kubectl get pods -n "${NAMESPACE}" -l app=backend \
        --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
      if [ "${READY_COUNT}" -ge "${BACKEND_PODS}" ]; then
        DELETE_END=$(date +%s)
        RECOVERY_TIME=$((DELETE_END - DELETE_START))
        RECOVERY_OK=true
        break
      fi
      sleep 1
    done

    if [ "${RECOVERY_OK}" = true ]; then
      log_ok "Pod recovery en ${RECOVERY_TIME}s"
    else
      log_fail "Pod non recovery apres 60s"
      ERRORS=$((ERRORS + 1))
    fi
  fi
fi
echo ""

# --- Step 6 : Verifier PodDisruptionBudget ---
log_step "6/6 - Verification PodDisruptionBudget"

PDBS=$(kubectl get pdb -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l)
if [ "${PDBS}" -gt 0 ]; then
  log_ok "PodDisruptionBudgets configures : ${PDBS}"
  kubectl get pdb -n "${NAMESPACE}" 2>/dev/null || true
else
  log_warn "Aucun PodDisruptionBudget configure"
fi

# --- Nettoyage ---
kubectl delete pod ha-test-client -n "${NAMESPACE}" --force --grace-period=0 2>/dev/null || true

# --- Resume ---
echo ""
echo "============================================"
echo "  Resultats Test HA Applications"
echo "============================================"
echo ""
echo "  Backend pods     : ${BACKEND_READY}/${BACKEND_PODS}"
echo "  Frontend pods    : ${FRONTEND_READY}/${FRONTEND_PODS}"
echo "  PDBs configures  : ${PDBS:-0}"
echo ""

if [ "${ERRORS}" -eq 0 ]; then
  log_ok "TOUS LES TESTS REUSSIS"
else
  log_fail "${ERRORS} TEST(S) ECHOUE(S)"
fi
echo "============================================"

exit "${ERRORS}"
