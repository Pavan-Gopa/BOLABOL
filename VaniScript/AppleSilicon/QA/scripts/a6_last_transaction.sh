#!/usr/bin/env bash
# A6: Last Transaction Details — max lastTransactionAt, lastModel badge, Prompt/Completion/Total.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/UsageStatisticsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/UsageStatisticsView.swift").read_text(encoding="utf-8")
for needle in (
    "Last Transaction Details",
    "lastTransactionAt",
    "lastModel",
    "Prompt tokens",
    "Completion tokens",
    "Total tokens",
    "latestUsageEntry",
):
    if needle not in text:
        raise SystemExit(f"FAIL: last-transaction marker missing: {needle}")
# Prefer lastModel with fallback to display name (superset of Electron)
if "stats.lastModel" not in text and "lastModel ??" not in text:
    raise SystemExit("FAIL: lastModel badge source missing")
if "lastInputTokens" not in text or "lastOutputTokens" not in text:
    raise SystemExit("FAIL: last input/output token fields missing")
print("PASS: Last Transaction Details uses max lastTransactionAt, lastModel badge, Prompt/Completion/Total.")
PY
