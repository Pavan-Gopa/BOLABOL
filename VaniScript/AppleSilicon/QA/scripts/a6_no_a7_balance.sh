#!/usr/bin/env bash
# A6 out-of-scope: no A7 CloudBalanceService / real balance network.
# Step-aware (QA maintenance, not product bug):
#   pre-A7 → CloudBalanceService must be absent; UsageStatisticsView has no balance code
#   A7+    → balance half is N/A (A7 owns it); instead assert the A7 contract:
#            UsageStatisticsView reuses CloudBalanceRow but never touches URLSession directly.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

STATE_FILE="AI_Workflow_Kit/docs/AI/STATE.yaml"
current_step=""
if [[ -f "$STATE_FILE" ]]; then
  current_step="$(sed -nE 's/^current_step:[[:space:]]*([A-Za-z0-9_]+).*/\1/p' "$STATE_FILE" | head -1)"
fi

a7_or_later=0
if [[ "$current_step" =~ ^A([7-9]|[1-9][0-9]+)$ ]] || [[ "$current_step" == "A7" || "$current_step" == "A8" || "$current_step" == "API_USAGE_DONE" ]]; then
  a7_or_later=1
fi

USAGE="Sources/VaniScript/Views/UsageStatisticsView.swift"
[[ -f "$USAGE" ]] || { echo "FAIL: $USAGE missing"; exit 1; }

if [[ "$a7_or_later" -eq 1 ]]; then
  echo "NOTE: current_step='$current_step' (≥ A7); A6 no-A7-balance half is N/A — asserting A7 contract instead."
  # A7 reuses the shared balance row...
  grep -q 'CloudBalanceRow' "$USAGE" || {
    echo "FAIL: A7+ UsageStatisticsView must reuse CloudBalanceRow"; exit 1
  }
  # ...but the view still must not open URLSession/URLRequest itself (network lives in the service).
  if grep -Eq 'URLSession|URLRequest' "$USAGE"; then
    echo "FAIL: UsageStatisticsView must not touch URLSession/URLRequest directly (A7)"; exit 1
  fi
  echo "PASS: A7+ — UsageStatisticsView reuses CloudBalanceRow, no direct network (step=$current_step)."
  exit 0
fi

# ---- pre-A7 strict path (original A6 invariant) ----
if [[ -f "Sources/VaniScriptCore/CloudBalanceService.swift" ]] || \
   [[ -f "Sources/VaniScript/Services/CloudBalanceService.swift" ]]; then
  echo "FAIL: CloudBalanceService present (A7 out of scope for A6)"; exit 1
fi

if grep -REq 'struct CloudBalanceService|class CloudBalanceService|enum CloudBalanceService|func fetchBalance' \
  Sources/VaniScriptCore Sources/VaniScript 2>/dev/null; then
  echo "FAIL: balance service API present (A7)"; exit 1
fi

if grep -Eq 'URLSession|URLRequest|fetchBalance|CloudBalance|openrouterCredits' "$USAGE"; then
  echo "FAIL: UsageStatisticsView appears to include A7 network/balance code"; exit 1
fi
echo "PASS: no A7 balance service; UsageStatisticsView has no network balance calls."

