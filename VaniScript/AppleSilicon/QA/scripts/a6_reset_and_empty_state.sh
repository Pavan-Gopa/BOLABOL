#!/usr/bin/env bash
# A6: Reset → settings.usage = [:]; empty state «No usage recorded yet.»
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/UsageStatisticsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/UsageStatisticsView.swift").read_text(encoding="utf-8")
if "No usage recorded yet." not in text:
    raise SystemExit("FAIL: empty state string missing")
if "Reset Statistics" not in text:
    raise SystemExit("FAIL: Reset Statistics button label missing")
if "settings.usage = [:]" not in text and "settings.usage=[:]" not in text:
    raise SystemExit("FAIL: Reset must assign settings.usage = [:]")
if "updateSettings" not in text:
    raise SystemExit("FAIL: Reset should go through store.updateSettings")
print("PASS: Reset clears usage = [:]; empty state present.")
PY
