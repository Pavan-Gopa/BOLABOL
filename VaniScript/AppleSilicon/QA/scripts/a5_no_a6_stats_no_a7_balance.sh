#!/usr/bin/env bash
# A5 out-of-scope: no A6 stats UI rewrite; no A7 CloudBalanceService.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

grep -q 'Cloud Usage Statistics' "$FILE" || {
  echo "FAIL: Cloud Usage Statistics section missing (must remain for A6)"; exit 1
}
grep -Eq 'StatItem|BudgetBar|Reset' "$FILE" || {
  echo "FAIL: stats UI helpers (StatItem/BudgetBar/Reset) missing"; exit 1
}

# No A7 balance service file introduced
if [[ -f "Sources/VaniScriptCore/CloudBalanceService.swift" ]] || \
   [[ -f "Sources/VaniScript/Services/CloudBalanceService.swift" ]]; then
  echo "FAIL: CloudBalanceService present (A7 out of scope for A5)"; exit 1
fi
if grep -REq 'CloudBalanceService|openrouterCredits|fetchBalance' \
  Sources/VaniScriptCore Sources/VaniScript/Services 2>/dev/null; then
  # openrouterCredits may exist as enum case in catalog from A1 — only fail on service
  if grep -REq 'struct CloudBalanceService|class CloudBalanceService|enum CloudBalanceService|func fetchBalance' \
    Sources/VaniScriptCore Sources/VaniScript 2>/dev/null; then
    echo "FAIL: balance service API leaked into A5"; exit 1
  fi
fi
echo "PASS: no A6 stats rewrite; no A7 balance service."
