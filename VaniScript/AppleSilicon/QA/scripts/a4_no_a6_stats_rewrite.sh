#!/usr/bin/env bash
# A4 out-of-scope: Cloud Usage Statistics section not rewritten (A6 territory).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }
grep -q 'Cloud Usage Statistics' "$FILE" || {
  echo "FAIL: Cloud Usage Statistics section missing (must remain for A6)"; exit 1
}
# BudgetBar / StatItem still present (A3 stats skeleton)
grep -Eq 'StatItem|BudgetBar|Reset' "$FILE" || {
  echo "FAIL: stats UI helpers (StatItem/BudgetBar/Reset) missing"; exit 1
}
echo "PASS: Cloud Usage Statistics section still present (no A6 rewrite required)."
