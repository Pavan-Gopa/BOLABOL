#!/usr/bin/env bash
# Post-A6 redesign of UsageStatisticsView (last STT/MT cards, balance, purpose).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/UsageStatisticsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }
python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/UsageStatisticsView.swift").read_text(encoding="utf-8")
required = [
    "Cloud API Usage",
    "lastTransactionsSection",
    "Last Transcription",
    "Last Translation",
    "No usage recorded yet",
    "Reset Statistics",
    "realBalanceProviders",
    "CloudBalanceRow",
    "lastPurpose",
    "estimateCost",
]
missing = [r for r in required if r not in text]
if missing:
    raise SystemExit("FAIL: UsageStatisticsView redesign missing: " + ", ".join(missing))
if "settings.usage" not in text and "store.settings.usage" not in text:
    raise SystemExit("FAIL: UsageStatisticsView does not read settings.usage")
print("PASS: UsageStatisticsView redesign markers present (STT/MT last cards + balance).")
PY
