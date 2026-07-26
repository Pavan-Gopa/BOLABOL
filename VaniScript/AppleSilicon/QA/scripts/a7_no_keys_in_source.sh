#!/usr/bin/env bash
# A7 §14.7: no sk-/AIza/ghp_/xox- secret literals in A7 target sources/tests.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

FILES=(
  "Sources/VaniScriptCore/CloudBalanceService.swift"
  "Sources/VaniScript/Views/SettingsView.swift"
  "Sources/VaniScript/Views/UsageStatisticsView.swift"
  "Tests/VaniScriptCoreTests/CloudBalanceServiceTests.swift"
)

rc=0
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || { echo "FAIL: $f missing"; exit 1; }
  if grep -Enq 'sk-[A-Za-z0-9]{12}|AIza[0-9A-Za-z_-]{12}|ghp_[A-Za-z0-9]{12}|xox[baprs]-[A-Za-z0-9-]{10}' "$f"; then
    echo "FAIL: possible hardcoded secret in $f:"
    grep -En 'sk-[A-Za-z0-9]{12}|AIza[0-9A-Za-z_-]{12}|ghp_[A-Za-z0-9]{12}|xox[baprs]-[A-Za-z0-9-]{10}' "$f"
    rc=1
  fi
done
[[ "$rc" -eq 0 ]] || exit 1
echo "PASS: no hardcoded API keys/tokens in A7 sources/tests (§14.7)."
