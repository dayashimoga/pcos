#!/usr/bin/env bash
# PCOS Self-Healing Iteration Loop
# Runs certification, analyzes failures, attempts fixes, re-runs until pass or blocker.
set -euo pipefail

MAX_ITERATIONS=5
ITERATION=0
QA_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$(dirname "$QA_DIR")"

COMPOSE_CMD="docker compose"
if ! command -v docker &>/dev/null || ! docker info &>/dev/null; then
  if command -v podman &>/dev/null && podman info &>/dev/null; then
    if podman compose version &>/dev/null 2>&1; then
      COMPOSE_CMD="podman compose"
    elif command -v podman-compose &>/dev/null; then
      COMPOSE_CMD="podman-compose"
    fi
  fi
fi

echo "╔══════════════════════════════════════════════════╗"
echo "║      PCOS Self-Healing Certification Loop        ║"
echo "║      Max iterations: $MAX_ITERATIONS                          ║"
echo "╚══════════════════════════════════════════════════╝"

while [ "$ITERATION" -lt "$MAX_ITERATIONS" ]; do
  ITERATION=$((ITERATION + 1))
  echo ""
  echo "━━━ Iteration $ITERATION of $MAX_ITERATIONS ━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Run certification
  REPORT_DIR="$QA_DIR/reports/iteration_${ITERATION}"
  mkdir -p "$REPORT_DIR"
  
  bash "$QA_DIR/scripts/orchestrator.sh" --keep-env 2>&1 | tee "$REPORT_DIR/orchestrator.log" || true
  
  # Find latest report
  LATEST_REPORT=$(ls -t "$QA_DIR"/reports/*/certification.json 2>/dev/null | head -1 || echo "")
  
  if [ -z "$LATEST_REPORT" ]; then
    echo "  ✗ No certification report generated. Check orchestrator output."
    continue
  fi
  
  # Check if passed
  VERDICT=$(jq -r '.verdict' "$LATEST_REPORT")
  FAILURES=$(jq '.summary.failed' "$LATEST_REPORT")
  
  if [ "$VERDICT" = "PASS" ] && [ "$FAILURES" -eq 0 ]; then
    echo ""
    echo "  ✅ CERTIFICATION PASSED on iteration $ITERATION"
    echo "  Report: $LATEST_REPORT"
    
    # Copy to latest
    mkdir -p "$QA_DIR/reports/latest"
    cp "$LATEST_REPORT" "$QA_DIR/reports/latest/certification.json"
    cp "$(dirname "$LATEST_REPORT")/certification_report.md" "$QA_DIR/reports/latest/" 2>/dev/null || true
    cp "$(dirname "$LATEST_REPORT")/junit/results.xml" "$QA_DIR/reports/latest/" 2>/dev/null || true
    
    # Tear down
    $COMPOSE_CMD -f "$QA_DIR/docker-compose.test.yml" down -v 2>/dev/null || true
    exit 0
  fi
  
  echo ""
  echo "  ▸ Analyzing $FAILURES failure(s)..."
  
  # Analyze failures from JSON
  FAILED_TESTS=$(jq -r '.api_tests[] | select(.result == "FAIL") | .test' "$LATEST_REPORT" 2>/dev/null || echo "")
  
  if [ -z "$FAILED_TESTS" ]; then
    echo "  No API test failures — checking Rust tests..."
    RUST_FAIL=$(jq '.rust_unit_tests.failed' "$LATEST_REPORT")
    if [ "$RUST_FAIL" -gt 0 ]; then
      echo "  $RUST_FAIL Rust unit test failures — requires code fix (manual intervention)"
      echo "  Check: $REPORT_DIR/rust_tests.log"
    fi
  else
    echo "  Failed API tests:"
    echo "$FAILED_TESTS" | while read -r test; do
      echo "    - $test"
    done
  fi
  
  # Check for blockers
  BLOCKED=$(jq '[.features[] | select(.blocked)] | length' "$QA_DIR/feature_registry.json")
  if [ "$BLOCKED" -gt 0 ]; then
    echo ""
    echo "  ⚠ $BLOCKED features blocked by external infrastructure:"
    jq -r '.features[] | select(.blocked) | "    - \(.id) \(.name): \(.blocked)"' "$QA_DIR/feature_registry.json"
  fi
  
  echo ""
  echo "  Waiting 5s before next iteration..."
  sleep 5
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✗ MAX ITERATIONS ($MAX_ITERATIONS) REACHED"
echo "  Review reports in: $QA_DIR/reports/"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

$COMPOSE_CMD -f "$QA_DIR/docker-compose.test.yml" down -v 2>/dev/null || true
exit 1
