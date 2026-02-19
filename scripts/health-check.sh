#!/bin/bash
# =============================================================================
# Infrastructure Health Check
# =============================================================================
# Verification complete de l'etat de l'infrastructure SaaS HA.
# Retourne un code de sortie base sur la sante globale.
#
# Usage :
#   ./scripts/health-check.sh                      # Check complet
#   ./scripts/health-check.sh --quick              # Nodes + pods seulement
#   ./scripts/health-check.sh --verbose            # Sortie detaillee
#   ./scripts/health-check.sh --json               # Output JSON
#   ./scripts/health-check.sh --component=storage  # Check un composant
#
# Codes de sortie :
#   0 : Tout OK
#   1 : Warnings presents
#   2 : Erreurs critiques
# =============================================================================

set -uo pipefail

# --- Configuration ---
NAMESPACES=("production" "monitoring" "ingress" "argocd" "kube-system")
CHECK_TIMEOUT=5
RESTART_WARN_THRESHOLD=5
DISK_WARN_PERCENT=80
DISK_CRIT_PERCENT=90
CERT_WARN_DAYS=30

# --- Options ---
MODE="full"
VERBOSE=false
JSON_OUTPUT=false
COMPONENT=""

for arg in "$@"; do
  case "$arg" in
    --quick)     MODE="quick" ;;
    --verbose)   VERBOSE=true ;;
    --json)      JSON_OUTPUT=true ;;
    --component=*) COMPONENT="${arg#*=}"; MODE="component" ;;
    --help|-h)   MODE="help" ;;
  esac
done

# --- Couleurs (desactivees si JSON) ---
if [ "${JSON_OUTPUT}" = true ]; then
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
  PASS=''; FAIL=''; WARN_ICON=''
else
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  NC='\033[0m'
  PASS='\xE2\x9C\x85'
  FAIL='\xE2\x9D\x8C'
  WARN_ICON='\xE2\x9A\xA0\xEF\xB8\x8F'
fi

# --- Compteurs globaux ---
TOTAL_CHECKS=0
TOTAL_OK=0
TOTAL_WARN=0
TOTAL_CRIT=0

# --- JSON accumulator ---
JSON_RESULTS="[]"

record_check() {
  local component="$1"
  local name="$2"
  local status="$3"  # ok, warn, crit
  local message="$4"

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  case "${status}" in
    ok)   TOTAL_OK=$((TOTAL_OK + 1)) ;;
    warn) TOTAL_WARN=$((TOTAL_WARN + 1)) ;;
    crit) TOTAL_CRIT=$((TOTAL_CRIT + 1)) ;;
  esac

  if [ "${JSON_OUTPUT}" = true ]; then
    JSON_RESULTS=$(echo "${JSON_RESULTS}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
data.append({
    'component': '${component}',
    'check': '${name}',
    'status': '${status}',
    'message': '${message}'
})
print(json.dumps(data))
" 2>/dev/null)
  fi
}

print_ok()   {
  local msg="$1"
  [ "${JSON_OUTPUT}" = false ] && echo -e "  ${GREEN}${PASS} ${msg}${NC}"
}

print_warn() {
  local msg="$1"
  [ "${JSON_OUTPUT}" = false ] && echo -e "  ${YELLOW}${WARN_ICON}  ${msg}${NC}"
}

print_crit() {
  local msg="$1"
  [ "${JSON_OUTPUT}" = false ] && echo -e "  ${RED}${FAIL} ${msg}${NC}"
}

print_info() {
  local msg="$1"
  [ "${JSON_OUTPUT}" = false ] && echo -e "  ${BLUE}   ${msg}${NC}"
}

section_header() {
  local num="$1"
  local total="$2"
  local title="$3"
  [ "${JSON_OUTPUT}" = false ] && echo -e "\n${CYAN}[${num}/${total}] ${title}${NC}"
}

# =============================================================================
# Help
# =============================================================================
if [ "${MODE}" = "help" ]; then
  echo ""
  echo "Infrastructure Health Check"
  echo ""
  echo "Usage :"
  echo "  ./scripts/health-check.sh                      Check complet"
  echo "  ./scripts/health-check.sh --quick              Nodes + pods"
  echo "  ./scripts/health-check.sh --verbose            Sortie detaillee"
  echo "  ./scripts/health-check.sh --json               Output JSON"
  echo "  ./scripts/health-check.sh --component=cluster  Check specifique"
  echo ""
  echo "Components : cluster, pods, services, certificates, storage, monitoring, argocd"
  echo ""
  echo "Exit codes : 0=OK, 1=Warnings, 2=Critical"
  exit 0
fi

# =============================================================================
# Pre-checks
# =============================================================================
if ! command -v kubectl &>/dev/null; then
  echo "ERROR: kubectl not found"
  exit 2
fi

if ! kubectl cluster-info &>/dev/null 2>&1; then
  echo "ERROR: Cannot connect to Kubernetes cluster"
  exit 2
fi

# Determiner le nombre de sections selon le mode
case "${MODE}" in
  quick) TOTAL_SECTIONS=2 ;;
  component) TOTAL_SECTIONS=1 ;;
  *) TOTAL_SECTIONS=7 ;;
esac

# =============================================================================
# Banner
# =============================================================================
if [ "${JSON_OUTPUT}" = false ]; then
  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}  INFRASTRUCTURE HEALTH CHECK${NC}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo "  $(date '+%Y-%m-%d %H:%M:%S')  |  Mode: ${MODE}"
fi

# =============================================================================
# 1. K3s Cluster
# =============================================================================
check_cluster() {
  section_header 1 "${TOTAL_SECTIONS}" "Checking K3s Cluster..."

  # Node count et status
  NODES_JSON=$(kubectl get nodes -o json 2>/dev/null) || {
    print_crit "Cannot fetch nodes"
    record_check "cluster" "nodes" "crit" "Cannot fetch nodes"
    return
  }

  NODE_COUNT=$(echo "${NODES_JSON}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(len(data.get('items', [])))
" 2>/dev/null) || NODE_COUNT=0

  NODES_READY=0
  NODES_NOTREADY=0

  echo "${NODES_JSON}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for node in data.get('items', []):
    name = node['metadata']['name']
    version = node['status']['nodeInfo']['kubeletVersion']
    ready = 'Unknown'
    for cond in node.get('status', {}).get('conditions', []):
        if cond['type'] == 'Ready':
            ready = cond['status']
    print(f'{name}|{version}|{ready}')
" 2>/dev/null | while IFS='|' read -r name version ready; do
    if [ "${ready}" = "True" ]; then
      print_ok "${name}: Ready (${version})"
      record_check "cluster" "node-${name}" "ok" "Ready ${version}"
    else
      print_crit "${name}: NotReady (${version})"
      record_check "cluster" "node-${name}" "crit" "NotReady"
    fi
  done

  # Recompter les nodes (le pipe subshell ne propage pas les variables)
  NODES_READY=$(echo "${NODES_JSON}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
ready = 0
for node in data.get('items', []):
    for cond in node.get('status', {}).get('conditions', []):
        if cond['type'] == 'Ready' and cond['status'] == 'True':
            ready += 1
print(ready)
" 2>/dev/null) || NODES_READY=0

  if [ "${NODE_COUNT}" -lt 2 ]; then
    print_warn "Only ${NODE_COUNT} node(s) detected (expected 2)"
    record_check "cluster" "node-count" "warn" "${NODE_COUNT}/2 nodes"
  elif [ "${NODES_READY}" -lt "${NODE_COUNT}" ]; then
    record_check "cluster" "node-ready" "crit" "${NODES_READY}/${NODE_COUNT} ready"
  else
    record_check "cluster" "node-ready" "ok" "${NODES_READY}/${NODE_COUNT} ready"
  fi

  # Control plane components
  if [ "${VERBOSE}" = true ]; then
    CP_PODS=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    print_info "Control plane pods running: ${CP_PODS}"
  fi
}

# =============================================================================
# 2. Pods
# =============================================================================
check_pods() {
  section_header 2 "${TOTAL_SECTIONS}" "Checking Pods..."

  for ns in "${NAMESPACES[@]}"; do
    # Verifier que le namespace existe
    if ! kubectl get namespace "${ns}" &>/dev/null 2>&1; then
      print_warn "${ns}: Namespace not found"
      record_check "pods" "ns-${ns}" "warn" "Namespace not found"
      continue
    fi

    PODS_INFO=$(kubectl get pods -n "${ns}" --no-headers 2>/dev/null) || continue
    TOTAL_PODS=$(echo "${PODS_INFO}" | grep -c "." 2>/dev/null || echo "0")
    RUNNING_PODS=$(echo "${PODS_INFO}" | grep -c "Running" 2>/dev/null || echo "0")
    COMPLETED_PODS=$(echo "${PODS_INFO}" | grep -c "Completed" 2>/dev/null || echo "0")
    ACTIVE_PODS=$((TOTAL_PODS - COMPLETED_PODS))

    if [ "${ACTIVE_PODS}" -eq 0 ]; then
      print_warn "${ns}: No pods found"
      record_check "pods" "ns-${ns}" "warn" "No pods"
    elif [ "${RUNNING_PODS}" -eq "${ACTIVE_PODS}" ]; then
      print_ok "${ns}: ${RUNNING_PODS}/${ACTIVE_PODS} Running"
      record_check "pods" "ns-${ns}" "ok" "${RUNNING_PODS}/${ACTIVE_PODS} Running"
    else
      PROBLEM_PODS=$((ACTIVE_PODS - RUNNING_PODS))
      print_crit "${ns}: ${RUNNING_PODS}/${ACTIVE_PODS} Running (${PROBLEM_PODS} problem(s))"
      record_check "pods" "ns-${ns}" "crit" "${RUNNING_PODS}/${ACTIVE_PODS} Running"

      # Afficher les pods problematiques
      echo "${PODS_INFO}" | grep -v "Running\|Completed" | while read -r line; do
        POD_NAME=$(echo "${line}" | awk '{print $1}')
        POD_STATUS=$(echo "${line}" | awk '{print $3}')
        print_info "  ${POD_NAME}: ${POD_STATUS}"
      done
    fi

    # Verifier les restarts excessifs
    HIGH_RESTARTS=$(kubectl get pods -n "${ns}" -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
high = []
for pod in data.get('items', []):
    name = pod['metadata']['name']
    for cs in pod.get('status', {}).get('containerStatuses', []):
        restarts = cs.get('restartCount', 0)
        if restarts > ${RESTART_WARN_THRESHOLD}:
            high.append(f'{name}:{restarts}')
if high:
    print('|'.join(high))
" 2>/dev/null) || HIGH_RESTARTS=""

    if [ -n "${HIGH_RESTARTS}" ]; then
      IFS='|' read -ra RESTART_LIST <<< "${HIGH_RESTARTS}"
      for entry in "${RESTART_LIST[@]}"; do
        POD_NAME="${entry%%:*}"
        RESTART_COUNT="${entry##*:}"
        print_warn "${ns}/${POD_NAME}: ${RESTART_COUNT} restarts (>${RESTART_WARN_THRESHOLD})"
        record_check "pods" "restarts-${POD_NAME}" "warn" "${RESTART_COUNT} restarts"
      done
    fi
  done
}

# =============================================================================
# 3. Services
# =============================================================================
check_services() {
  section_header 3 "${TOTAL_SECTIONS}" "Checking Services..."

  # Creer un pod de test
  kubectl run hc-probe --image=curlimages/curl:latest \
    --restart=Never -n default --labels="app=health-check" \
    --command -- sleep 120 &>/dev/null 2>&1 || true

  # Attendre qu'il soit ready (avec timeout)
  kubectl wait --for=condition=Ready pod/hc-probe -n default \
    --timeout=30s &>/dev/null 2>&1 || {
    print_warn "Health check probe pod not ready, skipping service checks"
    record_check "services" "probe" "warn" "Probe pod unavailable"
    return
  }

  # Definition des services a checker
  declare -A SERVICES
  SERVICES=(
    ["PostgreSQL Primary"]="production|postgresql|5432|tcp"
    ["Redis Master"]="production|redis|6379|tcp"
    ["Backend API"]="production|backend|3000|http|/health"
    ["Frontend"]="production|frontend|3001|http|/"
    ["Grafana"]="monitoring|grafana|3000|http|/api/health"
    ["Prometheus"]="monitoring|prometheus|9090|http|/-/healthy"
    ["Traefik"]="ingress|traefik-internal|8080|http|/ping"
  )

  for svc_name in "PostgreSQL Primary" "Redis Master" "Backend API" "Frontend" "Grafana" "Prometheus" "Traefik"; do
    IFS='|' read -r ns svc port proto path <<< "${SERVICES[${svc_name}]}"
    path="${path:-/}"

    SVC_HOST="${svc}.${ns}.svc.cluster.local"

    if [ "${proto}" = "tcp" ]; then
      # TCP check via nc
      RESULT=$(kubectl exec -n default hc-probe -- \
        sh -c "nc -z -w ${CHECK_TIMEOUT} ${SVC_HOST} ${port} 2>&1 && echo OK || echo FAIL" \
        2>/dev/null) || RESULT="FAIL"

      if [[ "${RESULT}" == *"OK"* ]]; then
        print_ok "${svc_name}: Responding (${SVC_HOST}:${port})"
        record_check "services" "${svc_name}" "ok" "TCP port ${port} open"
      else
        print_crit "${svc_name}: Not responding"
        record_check "services" "${svc_name}" "crit" "TCP port ${port} closed"
        [ "${VERBOSE}" = true ] && print_info "Fix: kubectl get pods -n ${ns} -l app=${svc}"
      fi
    else
      # HTTP check via curl
      HTTP_CODE=$(kubectl exec -n default hc-probe -- \
        curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout "${CHECK_TIMEOUT}" \
        "http://${SVC_HOST}:${port}${path}" 2>/dev/null) || HTTP_CODE="000"

      if [ "${HTTP_CODE}" = "200" ]; then
        print_ok "${svc_name}: HTTP ${HTTP_CODE}"
        record_check "services" "${svc_name}" "ok" "HTTP ${HTTP_CODE}"
      elif [ "${HTTP_CODE}" = "000" ]; then
        print_crit "${svc_name}: Not responding"
        record_check "services" "${svc_name}" "crit" "Connection failed"
        [ "${VERBOSE}" = true ] && print_info "Fix: kubectl get pods -n ${ns} -l app=${svc}"
      else
        print_warn "${svc_name}: HTTP ${HTTP_CODE}"
        record_check "services" "${svc_name}" "warn" "HTTP ${HTTP_CODE}"
      fi
    fi
  done

  # Nettoyage du pod de test
  kubectl delete pod hc-probe -n default --force --grace-period=0 &>/dev/null 2>&1 || true
}

# =============================================================================
# 4. Certificates
# =============================================================================
check_certificates() {
  section_header 4 "${TOTAL_SECTIONS}" "Checking Certificates..."

  CERTS_JSON=$(kubectl get certificates --all-namespaces -o json 2>/dev/null) || {
    print_warn "No certificates found or cert-manager not installed"
    record_check "certificates" "cert-manager" "warn" "Not available"
    return
  }

  echo "${CERTS_JSON}" | python3 -c "
import json, sys
from datetime import datetime, timezone, timedelta

data = json.load(sys.stdin)
certs = data.get('items', [])

if not certs:
    print('NONE')
    sys.exit(0)

now = datetime.now(timezone.utc)
warn_threshold = timedelta(days=${CERT_WARN_DAYS})

for cert in certs:
    name = cert['metadata']['name']
    ns = cert['metadata']['namespace']
    ready = False
    for cond in cert.get('status', {}).get('conditions', []):
        if cond.get('type') == 'Ready' and cond.get('status') == 'True':
            ready = True

    not_after = cert.get('status', {}).get('notAfter', '')
    days_left = -1
    if not_after:
        try:
            exp = datetime.fromisoformat(not_after.replace('Z', '+00:00'))
            days_left = (exp - now).days
        except:
            pass

    if not ready:
        print(f'CRIT|{ns}/{name}|Not Ready (certificate not issued)|{days_left}')
    elif days_left >= 0 and days_left < ${CERT_WARN_DAYS}:
        print(f'WARN|{ns}/{name}|Valid (expires in {days_left} days)|{days_left}')
    elif days_left < 0 and not_after:
        print(f'CRIT|{ns}/{name}|EXPIRED|{days_left}')
    else:
        expires = f'expires in {days_left} days' if days_left >= 0 else 'no expiry info'
        print(f'OK|{ns}/{name}|Valid ({expires})|{days_left}')
" 2>/dev/null | while IFS='|' read -r status name message days; do
    case "${status}" in
      OK)   print_ok "${name}: ${message}"
            record_check "certificates" "${name}" "ok" "${message}" ;;
      WARN) print_warn "${name}: ${message}"
            record_check "certificates" "${name}" "warn" "${message}" ;;
      CRIT) print_crit "${name}: ${message}"
            record_check "certificates" "${name}" "crit" "${message}" ;;
      NONE) print_info "No certificates found"
            record_check "certificates" "none" "warn" "No certificates" ;;
    esac
  done
}

# =============================================================================
# 5. Storage
# =============================================================================
check_storage() {
  section_header 5 "${TOTAL_SECTIONS}" "Checking Storage..."

  # PVC status
  PVC_JSON=$(kubectl get pvc --all-namespaces -o json 2>/dev/null) || {
    print_warn "Cannot fetch PVCs"
    record_check "storage" "pvcs" "warn" "Cannot fetch"
    return
  }

  PVC_TOTAL=$(echo "${PVC_JSON}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(len(data.get('items', [])))
" 2>/dev/null) || PVC_TOTAL=0

  PVC_BOUND=$(echo "${PVC_JSON}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
bound = sum(1 for p in data.get('items', []) if p.get('status', {}).get('phase') == 'Bound')
print(bound)
" 2>/dev/null) || PVC_BOUND=0

  if [ "${PVC_TOTAL}" -eq 0 ]; then
    print_info "No PVCs found"
    record_check "storage" "pvcs" "ok" "No PVCs"
  elif [ "${PVC_BOUND}" -eq "${PVC_TOTAL}" ]; then
    print_ok "All PVCs: Bound (${PVC_BOUND}/${PVC_TOTAL})"
    record_check "storage" "pvcs" "ok" "${PVC_BOUND}/${PVC_TOTAL} Bound"
  else
    PENDING=$((PVC_TOTAL - PVC_BOUND))
    print_crit "PVCs: ${PVC_BOUND}/${PVC_TOTAL} Bound (${PENDING} pending)"
    record_check "storage" "pvcs" "crit" "${PENDING} PVC(s) not bound"

    if [ "${VERBOSE}" = true ]; then
      echo "${PVC_JSON}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for p in data.get('items', []):
    phase = p.get('status', {}).get('phase', 'Unknown')
    if phase != 'Bound':
        name = p['metadata']['name']
        ns = p['metadata']['namespace']
        print(f'    {ns}/{name}: {phase}')
" 2>/dev/null
    fi
  fi

  # Disk usage sur les nodes via kubectl top ou metriques
  NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null) || NODES=""
  for node in ${NODES}; do
    # Essayer d'obtenir l'usage disque via kubectl debug ou conditions
    DISK_PRESSURE=$(kubectl get node "${node}" -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for cond in data.get('status', {}).get('conditions', []):
    if cond['type'] == 'DiskPressure':
        print(cond['status'])
        break
" 2>/dev/null) || DISK_PRESSURE="Unknown"

    if [ "${DISK_PRESSURE}" = "False" ]; then
      print_ok "${node} disk: No pressure"
      record_check "storage" "disk-${node}" "ok" "No disk pressure"
    elif [ "${DISK_PRESSURE}" = "True" ]; then
      print_crit "${node} disk: PRESSURE DETECTED"
      record_check "storage" "disk-${node}" "crit" "Disk pressure"
    else
      print_info "${node} disk: Status unknown"
      record_check "storage" "disk-${node}" "ok" "Status unknown"
    fi
  done
}

# =============================================================================
# 6. Monitoring
# =============================================================================
check_monitoring() {
  section_header 6 "${TOTAL_SECTIONS}" "Checking Monitoring..."

  # Creer un pod probe si necessaire
  kubectl run hc-mon-probe --image=curlimages/curl:latest \
    --restart=Never -n monitoring --labels="app=health-check" \
    --command -- sleep 60 &>/dev/null 2>&1 || true

  kubectl wait --for=condition=Ready pod/hc-mon-probe -n monitoring \
    --timeout=20s &>/dev/null 2>&1 || {
    print_warn "Monitoring probe unavailable, skipping detailed checks"
    record_check "monitoring" "probe" "warn" "Probe unavailable"
    return
  }

  PROM_SVC="prometheus.monitoring.svc.cluster.local:9090"

  # Prometheus targets
  TARGETS_RESULT=$(kubectl exec -n monitoring hc-mon-probe -- \
    curl -s --connect-timeout "${CHECK_TIMEOUT}" \
    "http://${PROM_SVC}/api/v1/targets" 2>/dev/null) || TARGETS_RESULT="{}"

  TARGET_STATS=$(echo "${TARGETS_RESULT}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
targets = data.get('data', {}).get('activeTargets', [])
up = sum(1 for t in targets if t.get('health') == 'up')
down = sum(1 for t in targets if t.get('health') == 'down')
total = len(targets)
print(f'{up}|{down}|{total}')
" 2>/dev/null) || TARGET_STATS="0|0|0"

  IFS='|' read -r T_UP T_DOWN T_TOTAL <<< "${TARGET_STATS}"

  if [ "${T_TOTAL}" -eq 0 ]; then
    print_warn "Prometheus: No targets found"
    record_check "monitoring" "prometheus-targets" "warn" "No targets"
  elif [ "${T_DOWN}" -eq 0 ]; then
    print_ok "Prometheus targets: ${T_UP}/${T_TOTAL} up"
    record_check "monitoring" "prometheus-targets" "ok" "${T_UP}/${T_TOTAL} up"
  else
    print_warn "Prometheus targets: ${T_UP}/${T_TOTAL} up (${T_DOWN} down)"
    record_check "monitoring" "prometheus-targets" "warn" "${T_DOWN} targets down"

    if [ "${VERBOSE}" = true ]; then
      echo "${TARGETS_RESULT}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for t in data.get('data', {}).get('activeTargets', []):
    if t.get('health') == 'down':
        job = t.get('labels', {}).get('job', 'unknown')
        err = t.get('lastError', '')[:80]
        print(f'    DOWN: {job} - {err}')
" 2>/dev/null
    fi
  fi

  # Active alerts
  ALERTS_RESULT=$(kubectl exec -n monitoring hc-mon-probe -- \
    curl -s --connect-timeout "${CHECK_TIMEOUT}" \
    "http://${PROM_SVC}/api/v1/alerts" 2>/dev/null) || ALERTS_RESULT="{}"

  FIRING_ALERTS=$(echo "${ALERTS_RESULT}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
alerts = data.get('data', {}).get('alerts', [])
firing = [a for a in alerts if a.get('state') == 'firing']
print(len(firing))
for a in firing:
    name = a.get('labels', {}).get('alertname', 'unknown')
    severity = a.get('labels', {}).get('severity', 'unknown')
    print(f'  {name}|{severity}')
" 2>/dev/null) || FIRING_ALERTS="0"

  FIRING_COUNT=$(echo "${FIRING_ALERTS}" | head -1)
  if [ "${FIRING_COUNT}" -eq 0 ] 2>/dev/null; then
    print_ok "Active alerts: None"
    record_check "monitoring" "alerts" "ok" "No firing alerts"
  else
    print_warn "Active alerts: ${FIRING_COUNT} firing"
    record_check "monitoring" "alerts" "warn" "${FIRING_COUNT} firing"
    echo "${FIRING_ALERTS}" | tail -n +2 | while IFS='|' read -r aname asev; do
      [ -n "${aname}" ] && print_info "- ${aname} [${asev}]"
    done
  fi

  # Grafana datasources
  GRAFANA_SVC="grafana.monitoring.svc.cluster.local:3000"
  DS_COUNT=$(kubectl exec -n monitoring hc-mon-probe -- \
    curl -s --connect-timeout "${CHECK_TIMEOUT}" \
    "http://admin:admin@${GRAFANA_SVC}/api/datasources" 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(len(data))
except:
    print(0)
" 2>/dev/null) || DS_COUNT="0"

  if [ "${DS_COUNT}" -ge 2 ]; then
    print_ok "Grafana datasources: ${DS_COUNT} connected"
    record_check "monitoring" "grafana-ds" "ok" "${DS_COUNT} datasources"
  elif [ "${DS_COUNT}" -gt 0 ]; then
    print_warn "Grafana datasources: ${DS_COUNT} (expected >= 2)"
    record_check "monitoring" "grafana-ds" "warn" "${DS_COUNT} datasources"
  else
    print_warn "Grafana datasources: Cannot verify"
    record_check "monitoring" "grafana-ds" "warn" "Cannot verify"
  fi

  # Nettoyage
  kubectl delete pod hc-mon-probe -n monitoring --force --grace-period=0 &>/dev/null 2>&1 || true
}

# =============================================================================
# 7. ArgoCD
# =============================================================================
check_argocd() {
  section_header 7 "${TOTAL_SECTIONS}" "Checking ArgoCD..."

  APPS_JSON=$(kubectl get applications -n argocd -o json 2>/dev/null) || {
    print_warn "ArgoCD not available or no applications"
    record_check "argocd" "apps" "warn" "Not available"
    return
  }

  APP_STATS=$(echo "${APPS_JSON}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
apps = data.get('items', [])
total = len(apps)
synced = 0
healthy = 0
out_of_sync = []
degraded = []

for app in apps:
    name = app['metadata']['name']
    sync_status = app.get('status', {}).get('sync', {}).get('status', 'Unknown')
    health_status = app.get('status', {}).get('health', {}).get('status', 'Unknown')

    if sync_status == 'Synced':
        synced += 1
    else:
        out_of_sync.append(f'{name}:{sync_status}')

    if health_status == 'Healthy':
        healthy += 1
    elif health_status not in ('Healthy', 'Progressing'):
        degraded.append(f'{name}:{health_status}')

print(f'{synced}|{healthy}|{total}')
for oos in out_of_sync:
    print(f'OOS|{oos}')
for deg in degraded:
    print(f'DEG|{deg}')
" 2>/dev/null) || APP_STATS="0|0|0"

  SYNC_LINE=$(echo "${APP_STATS}" | head -1)
  IFS='|' read -r SYNCED HEALTHY TOTAL_APPS <<< "${SYNC_LINE}"

  # Sync status
  if [ "${SYNCED}" -eq "${TOTAL_APPS}" ]; then
    print_ok "Applications: ${SYNCED}/${TOTAL_APPS} synced"
    record_check "argocd" "sync" "ok" "${SYNCED}/${TOTAL_APPS} synced"
  else
    OOS_COUNT=$((TOTAL_APPS - SYNCED))
    print_warn "Applications: ${SYNCED}/${TOTAL_APPS} synced (${OOS_COUNT} OutOfSync)"
    record_check "argocd" "sync" "warn" "${OOS_COUNT} OutOfSync"

    echo "${APP_STATS}" | grep "^OOS|" | while IFS='|' read -r _ entry; do
      APP_NAME="${entry%%:*}"
      APP_STATUS="${entry##*:}"
      print_info "- ${APP_NAME}: ${APP_STATUS}"
    done
  fi

  # Health status
  if [ "${HEALTHY}" -eq "${TOTAL_APPS}" ]; then
    print_ok "Health: ${HEALTHY}/${TOTAL_APPS} healthy"
    record_check "argocd" "health" "ok" "${HEALTHY}/${TOTAL_APPS} healthy"
  else
    UNHEALTHY=$((TOTAL_APPS - HEALTHY))
    print_warn "Health: ${HEALTHY}/${TOTAL_APPS} healthy (${UNHEALTHY} issue(s))"
    record_check "argocd" "health" "warn" "${UNHEALTHY} unhealthy"

    echo "${APP_STATS}" | grep "^DEG|" | while IFS='|' read -r _ entry; do
      APP_NAME="${entry%%:*}"
      APP_STATUS="${entry##*:}"
      print_info "- ${APP_NAME}: ${APP_STATUS}"
    done
  fi
}

# =============================================================================
# Execute checks
# =============================================================================
case "${MODE}" in
  quick)
    check_cluster
    check_pods
    ;;
  component)
    case "${COMPONENT}" in
      cluster)      TOTAL_SECTIONS=1; check_cluster ;;
      pods)         TOTAL_SECTIONS=1; check_pods ;;
      services)     TOTAL_SECTIONS=1; check_services ;;
      certificates) TOTAL_SECTIONS=1; check_certificates ;;
      storage)      TOTAL_SECTIONS=1; check_storage ;;
      monitoring)   TOTAL_SECTIONS=1; check_monitoring ;;
      argocd)       TOTAL_SECTIONS=1; check_argocd ;;
      *)
        echo "Unknown component: ${COMPONENT}"
        echo "Available: cluster, pods, services, certificates, storage, monitoring, argocd"
        exit 2
        ;;
    esac
    ;;
  full)
    check_cluster
    check_pods
    check_services
    check_certificates
    check_storage
    check_monitoring
    check_argocd
    ;;
esac

# =============================================================================
# Summary
# =============================================================================
if [ "${JSON_OUTPUT}" = true ]; then
  # JSON output
  python3 -c "
import json
results = json.loads('${JSON_RESULTS}')
summary = {
    'timestamp': '$(date -u +%Y-%m-%dT%H:%M:%SZ)',
    'mode': '${MODE}',
    'total_checks': ${TOTAL_CHECKS},
    'ok': ${TOTAL_OK},
    'warnings': ${TOTAL_WARN},
    'critical': ${TOTAL_CRIT},
    'status': 'critical' if ${TOTAL_CRIT} > 0 else ('warning' if ${TOTAL_WARN} > 0 else 'healthy'),
    'exit_code': 2 if ${TOTAL_CRIT} > 0 else (1 if ${TOTAL_WARN} > 0 else 0),
    'checks': results
}
print(json.dumps(summary, indent=2))
" 2>/dev/null
else
  # Text summary
  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}  SUMMARY${NC}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  Total checks  : ${TOTAL_CHECKS}"
  echo -e "  ${GREEN}OK${NC}            : ${TOTAL_OK}"

  if [ "${TOTAL_WARN}" -gt 0 ]; then
    echo -e "  ${YELLOW}Warnings${NC}      : ${TOTAL_WARN}"
  else
    echo -e "  Warnings      : 0"
  fi

  if [ "${TOTAL_CRIT}" -gt 0 ]; then
    echo -e "  ${RED}Critical${NC}      : ${TOTAL_CRIT}"
  else
    echo -e "  Critical      : 0"
  fi

  echo ""

  if [ "${TOTAL_CRIT}" -gt 0 ]; then
    echo -e "  Overall Status: ${RED}${BOLD}CRITICAL${NC} ${FAIL}"
    echo -e "  Exit code: 2"
  elif [ "${TOTAL_WARN}" -gt 0 ]; then
    echo -e "  Overall Status: ${YELLOW}${BOLD}HEALTHY${NC} ${WARN_ICON}"
    echo -e "  Exit code: 1 (warnings present)"
  else
    echo -e "  Overall Status: ${GREEN}${BOLD}HEALTHY${NC} ${PASS}"
    echo -e "  Exit code: 0"
  fi

  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
fi

# Exit code
if [ "${TOTAL_CRIT}" -gt 0 ]; then
  exit 2
elif [ "${TOTAL_WARN}" -gt 0 ]; then
  exit 1
else
  exit 0
fi
