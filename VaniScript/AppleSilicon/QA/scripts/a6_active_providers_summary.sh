#!/usr/bin/env bash
# A6: summary Transcribing / Translation via providerDisplayName + legacy engine id normalize.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/UsageStatisticsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/UsageStatisticsView.swift").read_text(encoding="utf-8")
for needle in (
    "Transcribing",
    "Translation / Editing",
    "providerDisplayName",
    "transcriptionProvider",
    "translationProvider",
    "gemini-cloud",
    "gpt-cloud",
    "engineDisplayName",
):
    if needle not in text:
        raise SystemExit(f"FAIL: active-providers summary marker missing: {needle}")
print("PASS: active providers summary uses providerDisplayName + legacy id normalize.")
PY
