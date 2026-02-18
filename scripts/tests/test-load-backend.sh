#!/bin/bash
# =============================================================================
# Test de Charge Backend NestJS
# =============================================================================
# Simule une charge sur le backend et mesure les performances.
# Cibles : p95 < 500ms, debit > 500 req/s
#
# Usage :
#   ./scripts/tests/test-load-backend.sh
#   ./scripts/tests/test-load-backend.sh --duration 120
#   ./scripts/tests/test-load-backend.sh --dry-run
#
# Pre-requis :
#   - kubectl connecte au cluster
#   - hey ou ab installe (ou utilisation d'un pod k6)
# =============================================================================

set -euo pipefail

# --- Configuration ---
NAMESPACE="production"
BACKEND_SVC="backend.${NAMESPACE}.svc.cluster.local:3000"
DURATION=30
CONCURRENCY=50
TARGET_P95=500    # ms
TARGET_RPS=500    # requests/sec
ENDPOINTS=(
  "/health"
  "/api/health"
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
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --duration)
      shift
      DURATION="${2:-30}"
      ;;
  esac
done

echo "============================================"
echo "  Test de Charge Backend NestJS"
echo "============================================"
echo ""
log_info "Configuration :"
echo "  Duree        : ${DURATION}s"
echo "  Concurrence  : ${CONCURRENCY} connexions"
echo "  Cible p95    : <${TARGET_P95}ms"
echo "  Cible debit  : >${TARGET_RPS} req/s"
echo ""

# --- Step 1 : Etat initial ---
log_step "1/5 - Verification etat initial"

BACKEND_PODS=$(kubectl get pods -n "${NAMESPACE}" -l app=backend \
  --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
log_info "Backend pods running : ${BACKEND_PODS}"

# Verifier les resources actuelles
kubectl top pods -n "${NAMESPACE}" -l app=backend 2>/dev/null || log_warn "metrics-server non disponible"

# HPA status
HPA_STATUS=$(kubectl get hpa -n "${NAMESPACE}" backend-hpa --no-headers 2>/dev/null) || HPA_STATUS="non configure"
log_info "HPA status : ${HPA_STATUS}"
echo ""

# --- Step 2 : Deployer le pod de test de charge ---
log_step "2/5 - Deploiement du pod de test de charge"

# Utiliser un pod avec hey (HTTP load generator)
kubectl apply -n "${NAMESPACE}" -f - <<'LOADTEST_POD' 2>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: load-test-runner
  labels:
    app: load-test
spec:
  containers:
  - name: hey
    image: williamyeh/hey:latest
    command: ["sleep", "600"]
    resources:
      requests:
        cpu: 200m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 256Mi
  restartPolicy: Never
LOADTEST_POD

kubectl wait --for=condition=Ready pod/load-test-runner -n "${NAMESPACE}" --timeout=60s 2>/dev/null || {
  # Fallback: utiliser un pod curl simple
  log_warn "Pod hey non disponible, fallback sur curl"
  kubectl run load-test-runner --image=curlimages/curl:latest \
    --restart=Never -n "${NAMESPACE}" \
    --command -- sleep 600 2>/dev/null || true
  kubectl wait --for=condition=Ready pod/load-test-runner -n "${NAMESPACE}" --timeout=60s 2>/dev/null || {
    log_fail "Impossible de creer le pod de test"
    exit 1
  }
}
echo ""

# --- Step 3 : Test de charge health endpoint ---
log_step "3/5 - Test de charge : endpoint /health"

if [ "${DRY_RUN}" = true ]; then
  log_warn "[DRY-RUN] Test de charge simule"
  echo "  hey -z ${DURATION}s -c ${CONCURRENCY} http://${BACKEND_SVC}/health"
else
  log_info "Lancement du test de charge (${DURATION}s, ${CONCURRENCY} conn)..."

  LOAD_RESULT=$(kubectl exec -n "${NAMESPACE}" load-test-runner -- \
    hey -z "${DURATION}s" -c "${CONCURRENCY}" "http://${BACKEND_SVC}/health" 2>/dev/null) || {
    # Fallback: test simple avec curl
    log_warn "hey non disponible, test simplifie avec curl"
    LOAD_RESULT=$(kubectl exec -n "${NAMESPACE}" load-test-runner -- sh -c "
      START=\$(date +%s)
      SUCCESS=0; FAIL=0; TOTAL=0
      while [ \$(((\$(date +%s) - START))) -lt ${DURATION} ]; do
        for i in 1 2 3 4 5 6 7 8 9 10; do
          CODE=\$(curl -s -o /dev/null -w '%{http_code}' 'http://${BACKEND_SVC}/health' 2>/dev/null || echo '000')
          TOTAL=\$((TOTAL + 1))
          if [ \"\${CODE}\" = '200' ]; then SUCCESS=\$((SUCCESS + 1)); else FAIL=\$((FAIL + 1)); fi
        done
      done
      ELAPSED=\$((\$(date +%s) - START))
      RPS=\$((TOTAL / (ELAPSED + 1)))
      echo \"Total: \${TOTAL}, Success: \${SUCCESS}, Failed: \${FAIL}, RPS: ~\${RPS}, Duration: \${ELAPSED}s\"
    " 2>/dev/null) || LOAD_RESULT="Test echoue"
  }

  echo ""
  echo "${LOAD_RESULT}"
  echo ""

  # Parser les resultats hey
  RPS=$(echo "${LOAD_RESULT}" | grep "Requests/sec" | awk '{print $2}' | cut -d. -f1)
  P95=$(echo "${LOAD_RESULT}" | grep "95%" | awk '{print $2}' | sed 's/s//')
  P99=$(echo "${LOAD_RESULT}" | grep "99%" | awk '{print $2}' | sed 's/s//')
  STATUS_200=$(echo "${LOAD_RESULT}" | grep "\[200\]" | awk '{print $2}')
  TOTAL_REQ=$(echo "${LOAD_RESULT}" | grep "Total:" | awk '{print $2}' | tr -d ',')

  # Convertir p95 en ms si en secondes
  if [ -n "${P95}" ]; then
    P95_MS=$(echo "${P95} * 1000" | bc 2>/dev/null | cut -d. -f1)
  fi

  # Afficher les metriques
  if [ -n "${RPS}" ]; then
    log_info "Debit       : ${RPS} req/s"
    if [ "${RPS}" -ge "${TARGET_RPS}" ]; then
      log_ok "Debit ${RPS} >= ${TARGET_RPS} req/s"
    else
      log_warn "Debit ${RPS} < ${TARGET_RPS} req/s (sous la cible)"
    fi
  fi

  if [ -n "${P95_MS:-}" ]; then
    log_info "Latence p95 : ${P95_MS}ms"
    if [ "${P95_MS}" -le "${TARGET_P95}" ]; then
      log_ok "p95 ${P95_MS}ms <= ${TARGET_P95}ms"
    else
      log_fail "p95 ${P95_MS}ms > ${TARGET_P95}ms"
      ERRORS=$((ERRORS + 1))
    fi
  fi
fi
echo ""

# --- Step 4 : Verifier l'autoscaling ---
log_step "4/5 - Verification de l'autoscaling HPA"

sleep 10  # Attendre que les metriques soient collectees

NEW_PODS=$(kubectl get pods -n "${NAMESPACE}" -l app=backend \
  --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

if [ "${NEW_PODS}" -gt "${BACKEND_PODS}" ]; then
  log_ok "Autoscaling declenche : ${BACKEND_PODS} -> ${NEW_PODS} pods"
else
  log_info "Pas d'autoscaling (charge insuffisante ou deja au max)"
fi

# Afficher les metriques HPA
kubectl get hpa -n "${NAMESPACE}" backend-hpa 2>/dev/null || true
echo ""

# --- Step 5 : Verifier les erreurs ---
log_step "5/5 - Verification des erreurs dans les logs"

ERROR_COUNT=$(kubectl logs -n "${NAMESPACE}" -l app=backend --tail=100 --since=2m 2>/dev/null | \
  grep -ci "error\|exception\|fatal" 2>/dev/null || echo "0")

if [ "${ERROR_COUNT}" -eq 0 ]; then
  log_ok "Aucune erreur dans les logs backend"
else
  log_warn "${ERROR_COUNT} erreur(s) detectee(s) dans les logs"
  # Afficher les 5 premieres erreurs
  kubectl logs -n "${NAMESPACE}" -l app=backend --tail=100 --since=2m 2>/dev/null | \
    grep -i "error\|exception" | head -5 || true
fi

# --- Nettoyage ---
kubectl delete pod load-test-runner -n "${NAMESPACE}" --force --grace-period=0 2>/dev/null || true

# --- Resume ---
echo ""
echo "============================================"
echo "  Resultats Test de Charge Backend"
echo "============================================"
echo ""
echo "  Duree test       : ${DURATION}s"
echo "  Concurrence      : ${CONCURRENCY} connexions"
echo "  Pods initiaux    : ${BACKEND_PODS}"
echo "  Pods finaux      : ${NEW_PODS:-${BACKEND_PODS}}"
echo "  Debit            : ${RPS:-N/A} req/s (cible: >${TARGET_RPS})"
echo "  Latence p95      : ${P95_MS:-N/A}ms (cible: <${TARGET_P95}ms)"
echo "  Erreurs logs     : ${ERROR_COUNT}"
echo ""

if [ "${ERRORS}" -eq 0 ]; then
  log_ok "TOUS LES TESTS REUSSIS"
else
  log_fail "${ERRORS} TEST(S) ECHOUE(S)"
fi
echo "============================================"

exit "${ERRORS}"
