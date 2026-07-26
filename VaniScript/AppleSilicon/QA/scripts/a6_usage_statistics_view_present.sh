#!/usr/bin/env bash
# A6: UsageStatisticsView.swift present with struct + role header.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/UsageStatisticsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/UsageStatisticsView.swift").read_text(encoding="utf-8")
if "struct UsageStatisticsView" not in text:
    raise SystemExit("FAIL: struct UsageStatisticsView missing")
if "import SwiftUI" not in text:
    raise SystemExit("FAIL: SwiftUI import missing")
if "import VaniScriptCore" not in text:
    raise SystemExit("FAIL: VaniScriptCore import missing")
if "A6" not in text:
    raise SystemExit("FAIL: A6 role markers missing")
if "settings.usage" not in text and "store.settings.usage" not in text:
    raise SystemExit("FAIL: must read settings.usage")
print("PASS: UsageStatisticsView.swift present with struct + A6 markers.")
PY
