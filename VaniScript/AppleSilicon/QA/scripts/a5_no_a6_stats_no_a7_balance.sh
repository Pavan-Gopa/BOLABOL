#!/usr/bin/env bash
# A5 out-of-scope: no A6 stats UI rewrite; no A7 CloudBalanceService.
# Step-aware:
#   pre-A6 → old Cloud Usage Statistics section intact
#   A6+    → stats half N/A (A6 owns rewrite); still enforce no A7 balance service
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


# Post-API_USAGE and subsequent tracks count as A7+.
if [[ "$current_step" == CPS* || "$current_step" == CLOUD_PROVIDER* || "$current_step" == LASR-* || "$current_step" == API_USAGE_DONE || "$current_step" == APIUSAGE_DONE ]]; then
  _post_api_usage=1
else
  _post_api_usage=0
fi
a6_or_later=0
if [[ "$current_step" =~ ^A([6-9]|[1-9][0-9]+)$ ]] || [[ "$current_step" == "A6" || "$current_step" == "A7" || "$current_step" == "A8" || "$current_step" == "API_USAGE_DONE" ]] || [[ "$_post_api_usage" -eq 1 ]]; then
  a6_or_later=1
fi

if [[ "$a6_or_later" -eq 1 ]]; then
  echo "NOTE: current_step='$current_step' (≥ A6); A5 no-A6-stats-rewrite half is N/A."
  if [[ ! -f "Sources/VaniScript/Views/UsageStatisticsView.swift" ]]; then
    echo "FAIL: A6+ expects UsageStatisticsView.swift"; exit 1
  fi
  grep -q 'UsageStatisticsView()' "$FILE" || {
    echo "FAIL: A6+ SettingsView must wire UsageStatisticsView()"; exit 1
  }
else
  grep -q 'Cloud Usage Statistics' "$FILE" || {
    echo "FAIL: Cloud Usage Statistics section missing (must remain for A6)"; exit 1
  }
  grep -Eq 'StatItem|BudgetBar|Reset' "$FILE" || {
    echo "FAIL: stats UI helpers (StatItem/BudgetBar/Reset) missing"; exit 1
  }
fi

# No A7 balance service file introduced (all steps until A7)
if [[ -f "Sources/VaniScriptCore/CloudBalanceService.swift" ]] || \
   [[ -f "Sources/VaniScript/Services/CloudBalanceService.swift" ]]; then
  # Allow when current_step is A7+
  if [[ "$current_step" =~ ^A([7-9]|[1-9][0-9]+)$ ]] || [[ "$current_step" == "A7" || "$current_step" == "A8" || "$current_step" == "API_USAGE_DONE" ]] || [[ "$_post_api_usage" -eq 1 ]]; then
    echo "NOTE: CloudBalanceService present but current_step='$current_step' (≥ A7) — OK."
  else
    echo "FAIL: CloudBalanceService present (A7 out of scope for A5/A6)"; exit 1
  fi
fi
if grep -REq 'struct CloudBalanceService|class CloudBalanceService|enum CloudBalanceService|func fetchBalance' \
  Sources/VaniScriptCore Sources/VaniScript 2>/dev/null; then
  if [[ "$current_step" =~ ^A([7-9]|[1-9][0-9]+)$ ]] || [[ "$current_step" == "A7" || "$current_step" == "A8" || "$current_step" == "API_USAGE_DONE" ]] || [[ "$_post_api_usage" -eq 1 ]]; then
    :
  else
    echo "FAIL: balance service API leaked before A7"; exit 1
  fi
fi

if [[ "$a6_or_later" -eq 1 ]]; then
  echo "PASS: A6+ stats rewrite accepted; A7 balance presence is step-aware (step=$current_step)."
else
  echo "PASS: no A6 stats rewrite; no A7 balance service."
fi
