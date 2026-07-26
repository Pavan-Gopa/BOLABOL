#!/usr/bin/env bash
# A6 out-of-scope: no A7 CloudBalanceService / real balance network.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

if [[ -f "Sources/VaniScriptCore/CloudBalanceService.swift" ]] || \
   [[ -f "Sources/VaniScript/Services/CloudBalanceService.swift" ]]; then
  echo "FAIL: CloudBalanceService present (A7 out of scope for A6)"; exit 1
fi

if grep -REq 'struct CloudBalanceService|class CloudBalanceService|enum CloudBalanceService|func fetchBalance' \
  Sources/VaniScriptCore Sources/VaniScript 2>/dev/null; then
  echo "FAIL: balance service API present (A7)"; exit 1
fi

# UsageStatisticsView must not call network for balance
USAGE="Sources/VaniScript/Views/UsageStatisticsView.swift"
[[ -f "$USAGE" ]] || { echo "FAIL: $USAGE missing"; exit 1; }
if grep -Eq 'URLSession|URLRequest|fetchBalance|CloudBalance|openrouterCredits' "$USAGE"; then
  echo "FAIL: UsageStatisticsView appears to include A7 network/balance code"; exit 1
fi
echo "PASS: no A7 balance service; UsageStatisticsView has no network balance calls."
