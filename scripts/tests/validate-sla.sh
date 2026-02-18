#!/bin/bash
# =============================================================================
# Validation SLA (Service Level Agreement)
# =============================================================================
# Calcule et valide les metriques SLA de l'infrastructure.
# Cible : SLA >= 99.5% (43.8h downtime max/an)
#
# Usage :
#   ./scripts/tests/validate-sla.sh
#   ./scripts/tests/validate-sla.sh --period 30d     # 30 derniers jours
#   ./scripts/tests/validate-sla.sh --dry-run
# =============================================================================

set -euo pipefail

# --- Configuration ---
MONITORING_NS="monitoring"
PRODUCTION_NS="production"
PROMETHEUS_SVC="prometheus.${MONITORING_NS}.svc.cluster.local:9090"
TARGET_SLA=99.5
PERIOD="30d"
MAX_ANNUAL_DOWNTIME_HOURS=43.8

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
    --period) shift; PERIOD="${2:-30d}" ;;
  esac
done

echo "============================================"
echo "  Validation SLA Infrastructure"
echo "============================================"
echo "  Periode  : ${PERIOD}"
echo "  Cible    : >= ${TARGET_SLA}%"
echo "============================================"
echo ""

# Creer un pod de test
kubectl run sla-test --image=curlimages/curl:latest \
  --restart=Never -n "${MONITORING_NS}" \
  --command -- sleep 300 2>/dev/null || true

kubectl wait --for=condition=Ready pod/sla-test -n "${MONITORING_NS}" --timeout=30s 2>/dev/null || {
  log_warn "Pod de test non disponible"
}

# Fonction pour executer une requete PromQL
prom_query() {
  local query="$1"
  kubectl exec -n "${MONITORING_NS}" sla-test -- \
    curl -s --data-urlencode "query=${query}" \
    "http://${PROMETHEUS_SVC}/api/v1/query" 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
results = data.get('data', {}).get('result', [])
if results:
    print(results[0].get('value', [0, '0'])[1])
else:
    print('N/A')
" 2>/dev/null || echo "N/A"
}

# =============================================================================
# 1. Disponibilite Backend
# =============================================================================
log_step "1/7 - Disponibilite Backend API"

BACKEND_UPTIME=$(prom_query "avg_over_time(up{job=\"kubernetes-pods\",app=\"backend\"}[${PERIOD}]) * 100")

if [ "${BACKEND_UPTIME}" != "N/A" ]; then
  BACKEND_SLA=$(echo "${BACKEND_UPTIME}" | cut -d. -f1-2)
  log_info "Backend uptime : ${BACKEND_SLA}%"

  if (( $(echo "${BACKEND_UPTIME} >= ${TARGET_SLA}" | bc -l 2>/dev/null || echo 0) )); then
    log_ok "Backend SLA >= ${TARGET_SLA}%"
  else
    log_fail "Backend SLA < ${TARGET_SLA}%"
    ERRORS=$((ERRORS + 1))
  fi
else
  log_warn "Metriques backend non disponibles"
fi

# =============================================================================
# 2. Disponibilite Frontend
# =============================================================================
log_step "2/7 - Disponibilite Frontend"

FRONTEND_UPTIME=$(prom_query "avg_over_time(up{job=\"kubernetes-pods\",app=\"frontend\"}[${PERIOD}]) * 100")

if [ "${FRONTEND_UPTIME}" != "N/A" ]; then
  FRONTEND_SLA=$(echo "${FRONTEND_UPTIME}" | cut -d. -f1-2)
  log_info "Frontend uptime : ${FRONTEND_SLA}%"

  if (( $(echo "${FRONTEND_UPTIME} >= ${TARGET_SLA}" | bc -l 2>/dev/null || echo 0) )); then
    log_ok "Frontend SLA >= ${TARGET_SLA}%"
  else
    log_fail "Frontend SLA < ${TARGET_SLA}%"
    ERRORS=$((ERRORS + 1))
  fi
else
  log_warn "Metriques frontend non disponibles"
fi

# =============================================================================
# 3. Disponibilite PostgreSQL
# =============================================================================
log_step "3/7 - Disponibilite PostgreSQL"

PG_UPTIME=$(prom_query "avg_over_time(pg_up{job=\"postgresql\"}[${PERIOD}]) * 100")

if [ "${PG_UPTIME}" != "N/A" ]; then
  PG_SLA=$(echo "${PG_UPTIME}" | cut -d. -f1-2)
  log_info "PostgreSQL uptime : ${PG_SLA}%"

  if (( $(echo "${PG_UPTIME} >= ${TARGET_SLA}" | bc -l 2>/dev/null || echo 0) )); then
    log_ok "PostgreSQL SLA >= ${TARGET_SLA}%"
  else
    log_fail "PostgreSQL SLA < ${TARGET_SLA}%"
    ERRORS=$((ERRORS + 1))
  fi
else
  log_warn "Metriques PostgreSQL non disponibles"
fi

# =============================================================================
# 4. Disponibilite Redis
# =============================================================================
log_step "4/7 - Disponibilite Redis"

REDIS_UPTIME=$(prom_query "avg_over_time(redis_up{job=\"redis\"}[${PERIOD}]) * 100")

if [ "${REDIS_UPTIME}" != "N/A" ]; then
  REDIS_SLA=$(echo "${REDIS_UPTIME}" | cut -d. -f1-2)
  log_info "Redis uptime : ${REDIS_SLA}%"

  if (( $(echo "${REDIS_UPTIME} >= ${TARGET_SLA}" | bc -l 2>/dev/null || echo 0) )); then
    log_ok "Redis SLA >= ${TARGET_SLA}%"
  else
    log_fail "Redis SLA < ${TARGET_SLA}%"
    ERRORS=$((ERRORS + 1))
  fi
else
  log_warn "Metriques Redis non disponibles"
fi

# =============================================================================
# 5. Disponibilite Traefik (Ingress)
# =============================================================================
log_step "5/7 - Disponibilite Traefik Ingress"

TRAEFIK_UPTIME=$(prom_query "avg_over_time(up{job=\"traefik\"}[${PERIOD}]) * 100")

if [ "${TRAEFIK_UPTIME}" != "N/A" ]; then
  TRAEFIK_SLA=$(echo "${TRAEFIK_UPTIME}" | cut -d. -f1-2)
  log_info "Traefik uptime : ${TRAEFIK_SLA}%"

  if (( $(echo "${TRAEFIK_UPTIME} >= ${TARGET_SLA}" | bc -l 2>/dev/null || echo 0) )); then
    log_ok "Traefik SLA >= ${TARGET_SLA}%"
  else
    log_fail "Traefik SLA < ${TARGET_SLA}%"
    ERRORS=$((ERRORS + 1))
  fi
else
  log_warn "Metriques Traefik non disponibles"
fi

# =============================================================================
# 6. Metriques de performance
# =============================================================================
log_step "6/7 - Metriques de performance"

# Taux d'erreur HTTP
ERROR_RATE=$(prom_query "sum(rate(http_requests_total{status=~\"5..\"}[${PERIOD}])) / sum(rate(http_requests_total[${PERIOD}])) * 100")
if [ "${ERROR_RATE}" != "N/A" ]; then
  log_info "Taux d'erreur HTTP 5xx : ${ERROR_RATE}%"
  if (( $(echo "${ERROR_RATE} < 1" | bc -l 2>/dev/null || echo 0) )); then
    log_ok "Taux d'erreur < 1%"
  else
    log_warn "Taux d'erreur >= 1%"
  fi
fi

# Latence p95
LATENCY_P95=$(prom_query "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{job=\"backend\"}[${PERIOD}])) by (le)) * 1000")
if [ "${LATENCY_P95}" != "N/A" ]; then
  log_info "Latence p95 : ${LATENCY_P95}ms"
  if (( $(echo "${LATENCY_P95} < 500" | bc -l 2>/dev/null || echo 0) )); then
    log_ok "Latence p95 < 500ms"
  else
    log_warn "Latence p95 >= 500ms"
  fi
fi

# Restarts de pods
POD_RESTARTS=$(prom_query "sum(increase(kube_pod_container_status_restarts_total{namespace=\"production\"}[${PERIOD}]))")
if [ "${POD_RESTARTS}" != "N/A" ]; then
  RESTARTS_INT=$(echo "${POD_RESTARTS}" | cut -d. -f1)
  log_info "Pod restarts (${PERIOD}) : ${RESTARTS_INT}"
  if [ "${RESTARTS_INT}" -le 5 ]; then
    log_ok "Restarts acceptables (<= 5)"
  else
    log_warn "Nombre de restarts eleve (${RESTARTS_INT})"
  fi
fi
echo ""

# =============================================================================
# 7. Calcul SLA global
# =============================================================================
log_step "7/7 - Calcul SLA global"

# Disponibilite des nodes K8s
NODE_AVAILABILITY=$(prom_query "avg_over_time(kube_node_status_condition{condition=\"Ready\",status=\"true\"}[${PERIOD}]) * 100")

echo ""
echo "============================================"
echo "  Rapport SLA - Periode : ${PERIOD}"
echo "============================================"
echo ""
printf "  %-25s %10s %10s\n" "Service" "Uptime" "Cible"
printf "  %-25s %10s %10s\n" "-------------------------" "----------" "----------"
printf "  %-25s %9s%% %9s%%\n" "Backend API" "${BACKEND_SLA:-N/A}" "${TARGET_SLA}"
printf "  %-25s %9s%% %9s%%\n" "Frontend" "${FRONTEND_SLA:-N/A}" "${TARGET_SLA}"
printf "  %-25s %9s%% %9s%%\n" "PostgreSQL" "${PG_SLA:-N/A}" "${TARGET_SLA}"
printf "  %-25s %9s%% %9s%%\n" "Redis" "${REDIS_SLA:-N/A}" "${TARGET_SLA}"
printf "  %-25s %9s%% %9s%%\n" "Traefik Ingress" "${TRAEFIK_SLA:-N/A}" "${TARGET_SLA}"
echo ""

# Calculer le SLA global (minimum de tous les services)
if [ "${BACKEND_SLA:-N/A}" != "N/A" ] && [ "${FRONTEND_SLA:-N/A}" != "N/A" ]; then
  GLOBAL_SLA=$(python3 -c "
values = []
for v in ['${BACKEND_SLA:-0}', '${FRONTEND_SLA:-0}', '${PG_SLA:-0}', '${REDIS_SLA:-0}', '${TRAEFIK_SLA:-0}']:
    try:
        values.append(float(v))
    except:
        pass
if values:
    print(f'{min(values):.2f}')
else:
    print('N/A')
" 2>/dev/null) || GLOBAL_SLA="N/A"

  log_info "SLA Global (minimum) : ${GLOBAL_SLA}%"

  if [ "${GLOBAL_SLA}" != "N/A" ]; then
    # Calculer le downtime annuel projete
    ANNUAL_DOWNTIME=$(python3 -c "
sla = float('${GLOBAL_SLA}')
downtime_hours = (100 - sla) / 100 * 8760
print(f'{downtime_hours:.1f}')
" 2>/dev/null) || ANNUAL_DOWNTIME="N/A"

    log_info "Downtime annuel projete : ${ANNUAL_DOWNTIME}h (max: ${MAX_ANNUAL_DOWNTIME_HOURS}h)"

    if (( $(echo "${GLOBAL_SLA} >= ${TARGET_SLA}" | bc -l 2>/dev/null || echo 0) )); then
      log_ok "SLA GLOBAL >= ${TARGET_SLA}% - OBJECTIF ATTEINT"
    else
      log_fail "SLA GLOBAL < ${TARGET_SLA}% - OBJECTIF NON ATTEINT"
      ERRORS=$((ERRORS + 1))
    fi
  fi
else
  log_warn "Donnees insuffisantes pour calculer le SLA global"
  log_info "Les metriques seront disponibles apres quelques jours de fonctionnement"
fi

echo ""
echo "  Metriques complementaires :"
echo "  Taux erreur HTTP    : ${ERROR_RATE:-N/A}%"
echo "  Latence p95         : ${LATENCY_P95:-N/A}ms"
echo "  Pod restarts        : ${POD_RESTARTS:-N/A}"
echo "  Node availability   : ${NODE_AVAILABILITY:-N/A}%"
echo ""

# --- Nettoyage ---
kubectl delete pod sla-test -n "${MONITORING_NS}" --force --grace-period=0 2>/dev/null || true

# --- Verdict ---
echo "============================================"
if [ "${ERRORS}" -eq 0 ]; then
  log_ok "SLA VALIDE - Objectifs respectes"
else
  log_fail "SLA NON VALIDE - ${ERRORS} objectif(s) non atteint(s)"
fi
echo "============================================"

exit "${ERRORS}"
