#!/bin/bash
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

RESULTS_ROOT="$ROOT/QA/scripts/results"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="$RESULTS_ROOT/$RUN_ID"
STATUS_TSV="$RUN_DIR/gates.tsv"
SUMMARY_MD="$RUN_DIR/summary.md"
FULL_LOG="$RUN_DIR/full.log"
COVERAGE_JSON="$RUN_DIR/coverage-gaps.json"
LATEST_SUMMARY="$RESULTS_ROOT/latest-summary.md"
LATEST_STATUS="$RESULTS_ROOT/latest-gates.tsv"
LATEST_LOG="$RESULTS_ROOT/latest.log"
LATEST_COVERAGE="$RESULTS_ROOT/latest-coverage-gaps.json"

mkdir -p "$RUN_DIR"
printf 'gate\tstatus\texit_code\tduration_seconds\n' > "$STATUS_TSV"

PASS=0
FAIL=0
FAILED=()

COMMIT_SHA="$(git rev-parse HEAD 2>/dev/null || printf 'unknown')"
SWIFT_DESC="$(swift --version 2>/dev/null | head -1 || printf 'swift unavailable')"
if command -v sw_vers >/dev/null 2>&1; then
  OS_DESC="$(sw_vers -productName) $(sw_vers -productVersion)"
else
  OS_DESC="$(uname -srm 2>/dev/null || printf 'unknown')"
fi

run_gate() {
  local label="$1"
  shift
  local started finished duration rc status
  started="$(date +%s)"
  echo ""
  echo "── $label ──"
  "$@"
  rc=$?
  finished="$(date +%s)"
  duration=$((finished - started))
  if [[ $rc -eq 0 ]]; then
    status="PASS"
    PASS=$((PASS + 1))
    echo "PASS: $label"
  else
    status="FAIL"
    FAIL=$((FAIL + 1))
    FAILED+=("$label")
    echo "FAIL: $label (exit $rc)"
  fi
  printf '%s\t%s\t%s\t%s\n' "$label" "$status" "$rc" "$duration" >> "$STATUS_TSV"
  return 0
}

run_swift_filter() {
  local pattern="$1"
  swift test --filter "$pattern"
}

write_summary() {
  local result
  if [[ $FAIL -gt 0 ]]; then
    result="RED"
  else
    result="GREEN"
  fi

  {
    echo "# VaniScript Expanded Regression Result"
    echo ""
    echo "- Run ID: \`$RUN_ID\`"
    echo "- UTC timestamp: \`$RUN_ID\`"
    echo "- Commit: \`$COMMIT_SHA\`"
    echo "- Environment: \`$OS_DESC\`"
    echo "- Swift: \`$SWIFT_DESC\`"
    echo "- Result: **$result**"
    echo "- Passed gates: **$PASS**"
    echo "- Failed gates: **$FAIL**"
    echo ""
    echo "> Gate counts are orchestration gates, not individual Swift test-case counts. Exact Swift counts and assertion failures are preserved in \`full.log\`."
    echo ""
    echo "## Gate results"
    echo ""
    echo "| Gate | Status | Exit | Seconds |"
    echo "|---|---:|---:|---:|"
    tail -n +2 "$STATUS_TSV" | while IFS=$'\t' read -r gate status exit_code duration; do
      printf '| %s | %s | %s | %s |\n' "$gate" "$status" "$exit_code" "$duration"
    done
    echo ""
    if [[ $FAIL -gt 0 ]]; then
      echo "## Failed gates"
      echo ""
      for gate in "${FAILED[@]}"; do
        echo "- $gate"
      done
      echo ""
    fi
    echo "## Evidence files"
    echo ""
    echo "- Full transcript: \`QA/scripts/results/$RUN_ID/full.log\`"
    echo "- Gate status table: \`QA/scripts/results/$RUN_ID/gates.tsv\`"
    if [[ -f "$COVERAGE_JSON" ]]; then
      echo "- Coverage-gap inventory: \`QA/scripts/results/$RUN_ID/coverage-gaps.json\`"
    fi
    echo ""
    echo "The runner also refreshes \`latest-summary.md\`, \`latest-gates.tsv\`, and \`latest.log\` for easy pickup by Main/Orchestrator."
  } > "$SUMMARY_MD"

  cp "$SUMMARY_MD" "$LATEST_SUMMARY"
  cp "$STATUS_TSV" "$LATEST_STATUS"
  if [[ -f "$COVERAGE_JSON" ]]; then
    cp "$COVERAGE_JSON" "$LATEST_COVERAGE"
  fi
}

main() {
  echo "== VaniScript expanded destructive regression =="
  echo "Run ID: $RUN_ID"
  echo "Commit: $COMMIT_SHA"
  echo "Environment: $OS_DESC"
  echo "Swift: $SWIFT_DESC"
  echo "Evidence directory: QA/scripts/results/$RUN_ID"
  echo "Policy: collect every failure; do not stop on the first discovered bug."

  run_gate "[1/16] S7 adversarial coordinator" run_swift_filter "S7AdversarialCoordinatorTests"
  run_gate "[2/16] S7 adversarial validator" run_swift_filter "S7AdversarialValidatorTests"
  run_gate "[3/16] S7 contract boundaries" run_swift_filter "S7ContractBoundaryTests"
  run_gate "[4/16] S7 document import adversarial" run_swift_filter "S7DocumentImportAdversarialTests"
  run_gate "[5/16] S7 scroll edge cases" run_swift_filter "S7ScrollEdgeCaseTests"
  run_gate "[6/16] Project archive adversarial" run_swift_filter "ProjectArchiveAdversarialTests"
  run_gate "[7/16] Timeline cut mapper adversarial" run_swift_filter "TimelineCutTimeMapperAdversarialTests"
  run_gate "[8/16] Starter glossary integrity" run_swift_filter "StarterGlossaryAdversarialTests"
  run_gate "[9/16] MCP audit/cache/confirmation adversarial" run_swift_filter "McpStoreAdversarialTests"
  run_gate "[10/16] Document structured-output + engine/coordinator" run_swift_filter "DocumentCloudStructuredOutputTests|DocumentTranslationEngineTests|DocumentCoordinatorTests"
  run_gate "[11/16] Document planner + budget + review/scroll" run_swift_filter "SemanticChunkPlannerTests|TranslationBudgetPlannerTests|DocumentReviewWorkflowTests|DocumentReviewScrollSyncTests"
  run_gate "[12/16] Document import/export/migration/security" run_swift_filter "DocumentImportServiceTests|DOCXPackageReaderTests|DocumentExportTests|DocumentTranslationExportTests|WorkflowStoreDocumentTests|ProjectMigrationTests"
  run_gate "[13/16] PDF/TXT export completeness regression guard" python3 QA/scripts/s7_export_completeness_guard.py
  run_gate "[14/16] Heuristic whole-app coverage inventory" python3 QA/scripts/test_coverage_inventory.py --json "$COVERAGE_JSON"
  run_gate "[15/16] Existing manifest-driven whole-app QA" bash QA/run_all.sh
  run_gate "[16/16] Full Swift suite" swift test

  echo ""
  echo "=== EXPANDED QA SUMMARY ==="
  echo "PASS gates: $PASS"
  echo "FAIL gates: $FAIL"
  if [[ $FAIL -gt 0 ]]; then
    echo "Failed gates:"
    for gate in "${FAILED[@]}"; do
      echo "  - $gate"
    done
  fi

  write_summary
  echo "Saved summary: QA/scripts/results/$RUN_ID/summary.md"
  echo "Saved full transcript: QA/scripts/results/$RUN_ID/full.log"
  echo "Saved latest summary: QA/scripts/results/latest-summary.md"

  if [[ $FAIL -gt 0 ]]; then
    echo "RESULT: RED"
    return 1
  fi
  echo "RESULT: GREEN"
  return 0
}

set +e
main "$@" 2>&1 | tee "$FULL_LOG"
MAIN_RC=${PIPESTATUS[0]}
cp "$FULL_LOG" "$LATEST_LOG"
exit "$MAIN_RC"
