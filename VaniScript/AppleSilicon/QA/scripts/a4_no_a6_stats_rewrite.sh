#!/usr/bin/env bash
# A4 out-of-scope: Cloud Usage Statistics section not rewritten (A6 territory).
# Step-aware:
#   pre-A6 → old section + StatItem/BudgetBar present
#   A6+    → rewrite is intentional; assert UsageStatisticsView instead (N/A for "no rewrite")
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

STATE_FILE="AI_Workflow_Kit/docs/AI/STATE.yaml"
current_step=""
if [[ -f "$STATE_FILE" ]]; then
  current_step="$(sed -nE 's/^current_step:[[:space:]]*([A-Za-z0-9_-]+).*/\1/p' "$STATE_FILE" | head -1)"
fi

# A6+ intentionally rewrites stats UI — this negative gate is N/A (PASS with inverted product assert).
if [[ "$current_step" =~ ^A([6-9]|[1-9][0-9]+)$ ]] || [[ "$current_step" == "A6" || "$current_step" == "A7" || "$current_step" == "A8" ]]; then
  if [[ ! -f "Sources/VaniScript/Views/UsageStatisticsView.swift" ]]; then
    echo "FAIL: A6+ expects UsageStatisticsView.swift"; exit 1
  fi
  grep -q 'UsageStatisticsView()' "$FILE" || {
    echo "FAIL: A6+ SettingsView must wire UsageStatisticsView()"; exit 1
  }
  echo "NOTE: current_step='$current_step' (≥ A6); A4 no-A6-rewrite gate is N/A (stats rewrite owned by A6)."
  echo "RESULT: PASS (a4_no_a6_stats_rewrite, step-aware N/A; UsageStatisticsView present)"
  exit 0
fi

grep -q 'Cloud Usage Statistics' "$FILE" || {
  echo "FAIL: Cloud Usage Statistics section missing (must remain for A6)"; exit 1
}
# BudgetBar / StatItem still present (A3 stats skeleton)
grep -Eq 'StatItem|BudgetBar|Reset' "$FILE" || {
  echo "FAIL: stats UI helpers (StatItem/BudgetBar/Reset) missing"; exit 1
}
echo "PASS: Cloud Usage Statistics section still present (no A6 rewrite required)."
