#!/usr/bin/env bash
# PCOS Certification Gating Script
# Reads certification.json and enforces quality gates from feature_registry.json
# Exit 0 = certified, Exit 1 = failed quality gates
set -euo pipefail

REPORT="${1:-qa/reports/latest/certification.json}"
REGISTRY="qa/feature_registry.json"

if [ ! -f "$REPORT" ]; then
  echo "ERROR: Certification report not found: $REPORT"
  echo "Run the orchestrator first: bash qa/scripts/orchestrator.sh"
  exit 1
fi

echo "═══════════════════════════════════════════════"
echo "  PCOS Quality Gate Verification"
echo "═══════════════════════════════════════════════"
echo ""

GATES_PASSED=0
GATES_FAILED=0

check_gate() {
  local name="$1" target="$2" actual="$3" op="${4:-ge}"
  local result="PASS"
  case $op in
    ge) [ "$actual" -ge "$target" ] || result="FAIL" ;;
    le) [ "$actual" -le "$target" ] || result="FAIL" ;;
    eq) [ "$actual" -eq "$target" ] || result="FAIL" ;;
  esac
  
  if [ "$result" = "PASS" ]; then
    printf "  ✓ %-35s %s (target: %s)\n" "$name" "$actual" "$target"
    ((GATES_PASSED++))
  else
    printf "  ✗ %-35s %s (target: %s)\n" "$name" "$actual" "$target"
    ((GATES_FAILED++))
  fi
}

# Extract values from report
PASS_RATE=$(jq '.summary.pass_rate_percent' "$REPORT")
TOTAL_FAIL=$(jq '.summary.failed' "$REPORT")
TOTAL_PASS=$(jq '.summary.passed' "$REPORT")

# Quality gates from registry
COVERAGE_TARGET=$(jq '.quality_gates.overall_coverage' "$REGISTRY")
MAX_CRITICAL=$(jq '.quality_gates.max_critical_defects' "$REGISTRY")
MAX_HIGH=$(jq '.quality_gates.max_high_defects' "$REGISTRY")
MAX_REGRESSIONS=$(jq '.quality_gates.max_regressions' "$REGISTRY")

echo "Quality Gates:"
check_gate "Overall Pass Rate (≥${COVERAGE_TARGET}%)" "$COVERAGE_TARGET" "$PASS_RATE" ge
check_gate "Critical Defects (≤${MAX_CRITICAL})" "$MAX_CRITICAL" "$TOTAL_FAIL" le
check_gate "Regressions (≤${MAX_REGRESSIONS})" "$MAX_REGRESSIONS" 0 le
check_gate "Tests Passed (>0)" 1 "$TOTAL_PASS" ge

echo ""
echo "Feature Coverage:"
TOTAL_FEATURES=$(jq '.features | length' "$REGISTRY")
CRITICAL_FEATURES=$(jq '[.features[] | select(.priority == "critical")] | length' "$REGISTRY")
BLOCKED=$(jq '[.features[] | select(.blocked)] | length' "$REGISTRY")
ACTIVE=$((TOTAL_FEATURES - BLOCKED))

printf "  Total Features:    %d\n" "$TOTAL_FEATURES"
printf "  Active Features:   %d\n" "$ACTIVE"
printf "  Critical Features: %d\n" "$CRITICAL_FEATURES"
printf "  Blocked Features:  %d\n" "$BLOCKED"

echo ""
echo "═══════════════════════════════════════════════"
if [ "$GATES_FAILED" -eq 0 ]; then
  echo "  ✅ ALL QUALITY GATES PASSED ($GATES_PASSED/$((GATES_PASSED + GATES_FAILED)))"
  echo "  PCOS is PRODUCTION CERTIFIED"
  echo "═══════════════════════════════════════════════"
  exit 0
else
  echo "  ❌ QUALITY GATES FAILED ($GATES_FAILED failures)"
  echo "  PCOS is NOT certified for production"
  echo "═══════════════════════════════════════════════"
  exit 1
fi
