#!/usr/bin/env bash
# A6: old «Cloud Usage Statistics» title + dead estimateCost/StatItem/BudgetBar gone from SettingsView.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
import re
text = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")

if 'SettingsSection(title: "Cloud Usage Statistics")' in text:
    raise SystemExit("FAIL: SettingsSection Cloud Usage Statistics still present")
if re.search(r'struct\s+StatItem\b', text):
    raise SystemExit("FAIL: dead StatItem type still in SettingsView")
if re.search(r'struct\s+BudgetBar\b', text):
    raise SystemExit("FAIL: dead BudgetBar type still in SettingsView")
# estimateCost / formatTokens as private helpers in SettingsView should be gone
if re.search(r'func\s+estimateCost\b', text):
    raise SystemExit("FAIL: dead estimateCost helper still in SettingsView")
if re.search(r'func\s+formatTokens\b', text):
    raise SystemExit("FAIL: dead formatTokens helper still in SettingsView")
# Comment references OK; bare title string in live UI code is not.
# Allow comments mentioning the old name (A6 migration notes).
print("PASS: old Cloud Usage Statistics section + StatItem/BudgetBar/estimateCost removed from SettingsView.")
PY
