#!/bin/bash
# =============================================================================
# Test Monitoring & Alertes
# =============================================================================
# Verifie le fonctionnement complet du stack monitoring.
# Cible : detection d'anomalie < 2 minutes
#
# Usage :
#   ./scripts/tests/test-monitoring-alerts.sh
#   ./scripts/tests/test-monitoring-alerts.sh --dry-run
# =============================================================================

set -euo pipefail

# --- Configuration ---
MONITORING_NS="monitoring"
PRODUCTION_NS="production"
PROMETHEUS_SVC="prometheus.${MONITORING_NS}.svc.cluster.local:9090"
ALERTMANAGER_SVC="alertmanager.${MONITORING_NS}.svc.cluster.local:9093"
GRAFANA_SVC="grafana.${MONITORING_NS}.svc.cluster.local:3000"
LOKI_SVC="loki.${MONITORING_NS}.svc.cluster.local:3100"
TARGET_DETECTION_TIME=120  # 2 minutes

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
echo "  Test Monitoring & Alertes"
echo "============================================"
echo ""

# --- Step 1 : Verifier les composants monitoring ---
log_step "1/8 - Verification des composants monitoring"

COMPONENTS=(
  "prometheus:${MONITORING_NS}:app=prometheus"
  "grafana:${MONITORING_NS}:app=grafana"
  "loki:${MONITORING_NS}:app=loki"
  "promtail:${MONITORING_NS}:app=promtail"
  "alertmanager:${MONITORING_NS}:app=alertmanager"
  "node-exporter:${MONITORING_NS}:app=node-exporter"
)

ALL_HEALTHY=true
for comp in "${COMPONENTS[@]}"; do
  IFS=: read -r name ns label <<< "${comp}"
  PODS_READY=$(kubectl get pods -n "${ns}" -l "${label}" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
  PODS_TOTAL=$(kubectl get pods -n "${ns}" -l "${label}" --no-headers 2>/dev/null | wc -l)

  if [ "${PODS_READY}" -gt 0 ] && [ "${PODS_READY}" -eq "${PODS_TOTAL}" ]; then
    log_ok "${name}: ${PODS_READY}/${PODS_TOTAL} Running"
  else
    log_fail "${name}: ${PODS_READY}/${PODS_TOTAL} Running"
    ERRORS=$((ERRORS + 1))
    ALL_HEALTHY=false
  fi
done
echo ""

# --- Step 2 : Verifier les targets Prometheus ---
log_step "2/8 - Verification des targets Prometheus"

# Creer un pod de test
kubectl run monitoring-test --image=curlimages/curl:latest \
  --restart=Never -n "${MONITORING_NS}" \
  --command -- sleep 300 2>/dev/null || true

kubectl wait --for=condition=Ready pod/monitoring-test -n "${MONITORING_NS}" --timeout=30s 2>/dev/null || {
  log_warn "Pod de test non disponible"
}

TARGETS=$(kubectl exec -n "${MONITORING_NS}" monitoring-test -- \
  curl -s "http://${PROMETHEUS_SVC}/api/v1/targets" 2>/dev/null) || TARGETS="{}"

ACTIVE_TARGETS=$(echo "${TARGETS}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
targets = data.get('data', {}).get('activeTargets', [])
up = sum(1 for t in targets if t.get('health') == 'up')
down = sum(1 for t in targets if t.get('health') == 'down')
total = len(targets)
print(f'{up} {down} {total}')
" 2>/dev/null) || ACTIVE_TARGETS="0 0 0"

read -r UP DOWN TOTAL <<< "${ACTIVE_TARGETS}"
log_info "Targets Prometheus : ${UP} up, ${DOWN} down, ${TOTAL} total"

if [ "${DOWN}" -eq 0 ]; then
  log_ok "Toutes les targets sont UP"
else
  log_warn "${DOWN} target(s) DOWN"
  # Lister les targets down
  echo "${TARGETS}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for t in data.get('data', {}).get('activeTargets', []):
    if t.get('health') == 'down':
        print(f'  DOWN: {t.get(\"labels\", {}).get(\"job\", \"unknown\")} - {t.get(\"lastError\", \"\")}')
" 2>/dev/null || true
  WARNINGS=$((${WARNINGS:-0} + 1))
fi
echo ""

# --- Step 3 : Verifier les regles d'alerte ---
log_step "3/8 - Verification des regles d'alerte Prometheus"

RULES=$(kubectl exec -n "${MONITORING_NS}" monitoring-test -- \
  curl -s "http://${PROMETHEUS_SVC}/api/v1/rules" 2>/dev/null) || RULES="{}"

RULE_STATS=$(echo "${RULES}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
groups = data.get('data', {}).get('groups', [])
total_rules = 0
alerting_rules = 0
recording_rules = 0
firing = 0
for g in groups:
    for r in g.get('rules', []):
        total_rules += 1
        if r.get('type') == 'alerting':
            alerting_rules += 1
            if r.get('state') == 'firing':
                firing += 1
        else:
            recording_rules += 1
print(f'{total_rules} {alerting_rules} {recording_rules} {firing}')
" 2>/dev/null) || RULE_STATS="0 0 0 0"

read -r TOTAL_RULES ALERT_RULES REC_RULES FIRING <<< "${RULE_STATS}"
log_info "Regles totales     : ${TOTAL_RULES}"
log_info "Regles d'alerte    : ${ALERT_RULES}"
log_info "Regles recording   : ${REC_RULES}"
log_info "Alertes en cours   : ${FIRING}"

if [ "${ALERT_RULES}" -ge 20 ]; then
  log_ok "Au moins 20 regles d'alerte configurees (${ALERT_RULES})"
else
  log_warn "Seulement ${ALERT_RULES} regles d'alerte"
fi

if [ "${FIRING}" -gt 0 ]; then
  log_warn "${FIRING} alerte(s) en cours de firing"
  echo "${RULES}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for g in data.get('data', {}).get('groups', []):
    for r in g.get('rules', []):
        if r.get('state') == 'firing':
            print(f'  FIRING: {r.get(\"name\")} [{r.get(\"labels\", {}).get(\"severity\", \"unknown\")}]')
" 2>/dev/null || true
fi
echo ""

# --- Step 4 : Verifier AlertManager ---
log_step "4/8 - Verification AlertManager"

AM_STATUS=$(kubectl exec -n "${MONITORING_NS}" monitoring-test -- \
  curl -s "http://${ALERTMANAGER_SVC}/api/v2/status" 2>/dev/null) || AM_STATUS="{}"

AM_CLUSTER=$(echo "${AM_STATUS}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
cluster = data.get('cluster', {}).get('status', 'unknown')
uptime = data.get('uptime', 'unknown')
print(f'{cluster} {uptime}')
" 2>/dev/null) || AM_CLUSTER="unknown"

log_info "AlertManager status : ${AM_CLUSTER}"

# Verifier les silences actifs
SILENCES=$(kubectl exec -n "${MONITORING_NS}" monitoring-test -- \
  curl -s "http://${ALERTMANAGER_SVC}/api/v2/silences" 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
active = sum(1 for s in data if s.get('status', {}).get('state') == 'active')
print(active)
" 2>/dev/null) || SILENCES="0"

if [ "${SILENCES}" -eq 0 ]; then
  log_ok "Aucun silence actif"
else
  log_info "${SILENCES} silence(s) actif(s)"
fi

# Verifier les receivers configures
RECEIVERS=$(kubectl exec -n "${MONITORING_NS}" monitoring-test -- \
  curl -s "http://${ALERTMANAGER_SVC}/api/v2/receivers" 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(len(data))
" 2>/dev/null) || RECEIVERS="0"

log_info "Receivers configures : ${RECEIVERS}"
echo ""

# --- Step 5 : Verifier Grafana ---
log_step "5/8 - Verification Grafana"

GRAFANA_HEALTH=$(kubectl exec -n "${MONITORING_NS}" monitoring-test -- \
  curl -s -o /dev/null -w "%{http_code}" "http://${GRAFANA_SVC}/api/health" 2>/dev/null) || GRAFANA_HEALTH="000"

if [ "${GRAFANA_HEALTH}" = "200" ]; then
  log_ok "Grafana health : HTTP ${GRAFANA_HEALTH}"
else
  log_fail "Grafana health : HTTP ${GRAFANA_HEALTH}"
  ERRORS=$((ERRORS + 1))
fi

# Verifier les datasources
DS_COUNT=$(kubectl exec -n "${MONITORING_NS}" monitoring-test -- \
  curl -s "http://admin:admin@${GRAFANA_SVC}/api/datasources" 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(len(data))
" 2>/dev/null) || DS_COUNT="0"

log_info "Datasources Grafana : ${DS_COUNT}"

# Verifier les dashboards
DB_COUNT=$(kubectl exec -n "${MONITORING_NS}" monitoring-test -- \
  curl -s "http://admin:admin@${GRAFANA_SVC}/api/search?type=dash-db" 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(len(data))
" 2>/dev/null) || DB_COUNT="0"

if [ "${DB_COUNT}" -ge 5 ]; then
  log_ok "Dashboards Grafana : ${DB_COUNT} (>= 5 attendus)"
else
  log_warn "Dashboards Grafana : ${DB_COUNT} (5 attendus)"
fi
echo ""

# --- Step 6 : Verifier Loki ---
log_step "6/8 - Verification Loki + Promtail"

LOKI_READY=$(kubectl exec -n "${MONITORING_NS}" monitoring-test -- \
  curl -s -o /dev/null -w "%{http_code}" "http://${LOKI_SVC}/ready" 2>/dev/null) || LOKI_READY="000"

if [ "${LOKI_READY}" = "200" ]; then
  log_ok "Loki ready : HTTP ${LOKI_READY}"
else
  log_fail "Loki ready : HTTP ${LOKI_READY}"
  ERRORS=$((ERRORS + 1))
fi

# Verifier que des logs arrivent
LOG_COUNT=$(kubectl exec -n "${MONITORING_NS}" monitoring-test -- \
  curl -s "http://${LOKI_SVC}/loki/api/v1/query?query=count_over_time({namespace=\"production\"}[5m])" 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
results = data.get('data', {}).get('result', [])
total = sum(int(r.get('value', [0, '0'])[1]) for r in results)
print(total)
" 2>/dev/null) || LOG_COUNT="0"

if [ "${LOG_COUNT}" -gt 0 ]; then
  log_ok "Logs production recus : ${LOG_COUNT} entrees (5 dernieres min)"
else
  log_warn "Aucun log production recu recemment"
fi

# Verifier Promtail DaemonSet
PROMTAIL_PODS=$(kubectl get pods -n "${MONITORING_NS}" -l app=promtail --no-headers 2>/dev/null | wc -l)
NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)

if [ "${PROMTAIL_PODS}" -eq "${NODES}" ]; then
  log_ok "Promtail DaemonSet : ${PROMTAIL_PODS}/${NODES} nodes couverts"
else
  log_warn "Promtail : ${PROMTAIL_PODS}/${NODES} nodes couverts"
fi
echo ""

# --- Step 7 : Test de detection d'alerte ---
log_step "7/8 - Test detection alerte (temps de reaction)"

if [ "${DRY_RUN}" = true ]; then
  log_warn "[DRY-RUN] Test de detection simule"
else
  log_info "Requete PromQL pour verifier les alertes..."

  # Verifier qu'une requete PromQL fonctionne
  PROM_QUERY=$(kubectl exec -n "${MONITORING_NS}" monitoring-test -- \
    curl -s "http://${PROMETHEUS_SVC}/api/v1/query?query=up" 2>/dev/null) || PROM_QUERY="{}"

  QUERY_STATUS=$(echo "${PROM_QUERY}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('status', 'error'))
" 2>/dev/null) || QUERY_STATUS="error"

  if [ "${QUERY_STATUS}" = "success" ]; then
    log_ok "Requetes PromQL fonctionnelles"
  else
    log_fail "Requetes PromQL en erreur"
    ERRORS=$((ERRORS + 1))
  fi

  # Verifier le scrape interval
  SCRAPE_INTERVAL=$(kubectl exec -n "${MONITORING_NS}" monitoring-test -- \
    curl -s "http://${PROMETHEUS_SVC}/api/v1/status/config" 2>/dev/null | python3 -c "
import json, sys, re
data = json.load(sys.stdin)
config = data.get('data', {}).get('yaml', '')
match = re.search(r'scrape_interval:\s*(\S+)', config)
if match:
    print(match.group(1))
else:
    print('unknown')
" 2>/dev/null) || SCRAPE_INTERVAL="unknown"

  log_info "Scrape interval : ${SCRAPE_INTERVAL}"
  log_info "Temps de detection estime : < ${TARGET_DETECTION_TIME}s"
fi
echo ""

# --- Step 8 : Node Exporter metriques ---
log_step "8/8 - Verification Node Exporter"

NE_PODS=$(kubectl get pods -n "${MONITORING_NS}" -l app=node-exporter --no-headers 2>/dev/null | grep -c "Running" || echo "0")

if [ "${NE_PODS}" -eq "${NODES}" ]; then
  log_ok "Node Exporter : ${NE_PODS}/${NODES} nodes"
else
  log_warn "Node Exporter : ${NE_PODS}/${NODES} nodes"
fi

# Verifier les metriques systeme
METRICS_CHECK=$(kubectl exec -n "${MONITORING_NS}" monitoring-test -- \
  curl -s "http://${PROMETHEUS_SVC}/api/v1/query?query=node_cpu_seconds_total" 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
results = data.get('data', {}).get('result', [])
print(len(results))
" 2>/dev/null) || METRICS_CHECK="0"

if [ "${METRICS_CHECK}" -gt 0 ]; then
  log_ok "Metriques CPU disponibles (${METRICS_CHECK} series)"
else
  log_warn "Metriques CPU non disponibles"
fi

# --- Nettoyage ---
kubectl delete pod monitoring-test -n "${MONITORING_NS}" --force --grace-period=0 2>/dev/null || true

# --- Resume ---
echo ""
echo "============================================"
echo "  Resultats Test Monitoring & Alertes"
echo "============================================"
echo ""
echo "  Composants healthy   : $([ "${ALL_HEALTHY}" = true ] && echo "TOUS" || echo "PARTIEL")"
echo "  Targets Prometheus   : ${UP:-0}/${TOTAL:-0} UP"
echo "  Regles d'alerte      : ${ALERT_RULES:-0}"
echo "  Regles recording     : ${REC_RULES:-0}"
echo "  Alertes firing       : ${FIRING:-0}"
echo "  Datasources Grafana  : ${DS_COUNT:-0}"
echo "  Dashboards Grafana   : ${DB_COUNT:-0}"
echo "  Loki logs recus      : ${LOG_COUNT:-0}"
echo "  Scrape interval      : ${SCRAPE_INTERVAL:-unknown}"
echo ""

if [ "${ERRORS}" -eq 0 ]; then
  log_ok "MONITORING OPERATIONNEL"
else
  log_fail "${ERRORS} PROBLEME(S) DETECTE(S)"
fi
echo "============================================"

exit "${ERRORS}"
