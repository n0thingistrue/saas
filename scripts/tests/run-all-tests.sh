#!/bin/bash
# =============================================================================
# Run All Tests - Suite de validation complete
# =============================================================================
# Execute tous les tests de validation de l'infrastructure.
# Genere un rapport consolide.
#
# Usage :
#   ./scripts/tests/run-all-tests.sh
#   ./scripts/tests/run-all-tests.sh --dry-run
#   ./scripts/tests/run-all-tests.sh --quick         # Tests rapides uniquement
#   ./scripts/tests/run-all-tests.sh --report         # Generer un rapport fichier
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Configuration ---
DRY_RUN=""
QUICK=false
REPORT=false
REPORT_FILE=""

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN="--dry-run" ;;
    --quick) QUICK=true ;;
    --report) REPORT=true ;;
  esac
done

if [ "${REPORT}" = true ]; then
  REPORT_FILE="/tmp/infra-test-report-$(date +%Y%m%d-%H%M%S).txt"
fi

# --- Couleurs ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[PASS]${NC} $*"; }
log_fail()  { echo -e "${RED}[FAIL]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_step()  { echo -e "${CYAN}[STEP]${NC} $*"; }

# --- Tests a executer ---
declare -A TESTS
declare -A TEST_RESULTS
declare -A TEST_DURATIONS

if [ "${QUICK}" = true ]; then
  TESTS=(
    ["1_security"]="test-security-scan.sh"
    ["2_monitoring"]="test-monitoring-alerts.sh"
    ["3_sla"]="validate-sla.sh"
  )
else
  TESTS=(
    ["1_pg_failover"]="test-failover-postgresql.sh"
    ["2_redis_failover"]="test-failover-redis.sh"
    ["3_ha_apps"]="test-ha-applications.sh"
    ["4_backup"]="test-backup-restore.sh"
    ["5_load"]="test-load-backend.sh"
    ["6_security"]="test-security-scan.sh"
    ["7_monitoring"]="test-monitoring-alerts.sh"
    ["8_sla"]="validate-sla.sh"
  )
fi

# --- Header ---
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║           SUITE DE VALIDATION INFRASTRUCTURE               ║${NC}"
echo -e "${BOLD}║         Infrastructure SaaS HA - RNCP37680                 ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Date       : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Mode       : $([ "${QUICK}" = true ] && echo "Quick" || echo "Complet")"
echo "  Dry-run    : $([ -n "${DRY_RUN}" ] && echo "Oui" || echo "Non")"
echo "  Tests      : ${#TESTS[@]}"
echo ""

[ "${REPORT}" = true ] && echo "  Rapport    : ${REPORT_FILE}"

echo ""
echo "============================================"
echo ""

TOTAL_TESTS=${#TESTS[@]}
PASSED=0
FAILED=0
SKIPPED=0
TOTAL_START=$(date +%s)

# Fonction d'execution avec timeout
run_test() {
  local name="$1"
  local script="$2"
  local script_path="${SCRIPT_DIR}/${script}"

  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}  Test : ${name}${NC}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  if [ ! -f "${script_path}" ]; then
    log_warn "Script non trouve : ${script_path}"
    TEST_RESULTS["${name}"]="SKIP"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  local start_time=$(date +%s)

  # Executer le test avec timeout
  if timeout 300 bash "${script_path}" ${DRY_RUN} 2>&1; then
    TEST_RESULTS["${name}"]="PASS"
    PASSED=$((PASSED + 1))
  else
    local exit_code=$?
    if [ "${exit_code}" -eq 124 ]; then
      log_fail "Test timeout apres 300s"
      TEST_RESULTS["${name}"]="TIMEOUT"
    else
      TEST_RESULTS["${name}"]="FAIL"
    fi
    FAILED=$((FAILED + 1))
  fi

  local end_time=$(date +%s)
  TEST_DURATIONS["${name}"]=$((end_time - start_time))
}

# --- Execution des tests dans l'ordre ---
for key in $(echo "${!TESTS[@]}" | tr ' ' '\n' | sort); do
  run_test "${key}" "${TESTS[${key}]}"
done

TOTAL_END=$(date +%s)
TOTAL_DURATION=$((TOTAL_END - TOTAL_START))

# --- Rapport final ---
echo ""
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║                  RAPPORT DE VALIDATION                     ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Date d'execution : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Duree totale     : ${TOTAL_DURATION}s"
echo ""

printf "  %-30s %-10s %10s\n" "Test" "Resultat" "Duree"
printf "  %-30s %-10s %10s\n" "------------------------------" "----------" "----------"

for key in $(echo "${!TEST_RESULTS[@]}" | tr ' ' '\n' | sort); do
  result="${TEST_RESULTS[${key}]}"
  duration="${TEST_DURATIONS[${key}]:-0}s"

  case "${result}" in
    PASS)    color="${GREEN}" ;;
    FAIL)    color="${RED}" ;;
    TIMEOUT) color="${RED}" ;;
    SKIP)    color="${YELLOW}" ;;
    *)       color="${NC}" ;;
  esac

  printf "  %-30s ${color}%-10s${NC} %10s\n" "${key}" "${result}" "${duration}"
done

echo ""
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Total    : ${TOTAL_TESTS}"
echo -e "  ${GREEN}Passed${NC}   : ${PASSED}"
echo -e "  ${RED}Failed${NC}   : ${FAILED}"
echo -e "  ${YELLOW}Skipped${NC}  : ${SKIPPED}"
echo ""

# --- Metriques cibles RNCP ---
echo -e "${BOLD}  Metriques RNCP37680 :${NC}"
echo "  ┌─────────────────────────────────────────┐"
echo "  │ SLA        : >= 99.5%                   │"
echo "  │ RTO PG     : < 30s                      │"
echo "  │ RTO Redis  : < 15s                      │"
echo "  │ RPO        : < 15 min                   │"
echo "  │ p95        : < 500ms                    │"
echo "  │ Debit      : > 500 req/s                │"
echo "  │ Securite   : 0 CRITICAL                 │"
echo "  │ Detection  : < 2 min                    │"
echo "  └─────────────────────────────────────────┘"
echo ""

# --- Generer le rapport fichier ---
if [ "${REPORT}" = true ] && [ -n "${REPORT_FILE}" ]; then
  {
    echo "================================================================="
    echo "  RAPPORT DE VALIDATION INFRASTRUCTURE"
    echo "  Infrastructure SaaS HA - RNCP37680"
    echo "  Date : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "================================================================="
    echo ""
    echo "Resultats :"
    echo ""
    for key in $(echo "${!TEST_RESULTS[@]}" | tr ' ' '\n' | sort); do
      printf "  %-30s %-10s %10s\n" "${key}" "${TEST_RESULTS[${key}]}" "${TEST_DURATIONS[${key}]:-0}s"
    done
    echo ""
    echo "Total: ${TOTAL_TESTS} | Passed: ${PASSED} | Failed: ${FAILED} | Skipped: ${SKIPPED}"
    echo "Duree totale: ${TOTAL_DURATION}s"
    echo ""
    echo "================================================================="
  } > "${REPORT_FILE}"

  log_info "Rapport sauvegarde : ${REPORT_FILE}"
fi

# --- Verdict final ---
echo "============================================"
if [ "${FAILED}" -eq 0 ]; then
  echo -e "  ${GREEN}${BOLD}VALIDATION REUSSIE${NC}"
  echo "  Tous les tests sont passes."
  echo "  Infrastructure prete pour la production."
else
  echo -e "  ${RED}${BOLD}VALIDATION ECHOUEE${NC}"
  echo "  ${FAILED} test(s) en echec."
  echo "  Corriger les problemes avant mise en production."
fi
echo "============================================"
echo ""

exit "${FAILED}"
