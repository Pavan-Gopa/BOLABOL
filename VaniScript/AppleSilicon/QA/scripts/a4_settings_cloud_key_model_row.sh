#!/usr/bin/env bash
# A4: SettingsView CloudKeyModelRow — badge + Picker / editable combo + Retry.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
if "private struct CloudKeyModelRow" not in text:
    raise SystemExit("FAIL: CloudKeyModelRow missing")
# Badge states
for needle in ('"Checking…"', '"● Valid"', '"● Invalid"', "CloudKeyValidationStatus"):
    if needle not in text:
        raise SystemExit(f"FAIL: badge UI missing: {needle}")
# Picker + editable + Retry
for needle in ("Picker(", "Retry", "TextField(", "loadFailed", "manualEntry"):
    if needle not in text:
        raise SystemExit(f"FAIL: model control missing: {needle}")
# Uses validator + catalog
if "CloudKeyValidator" not in text or "CloudModelCatalog" not in text:
    raise SystemExit("FAIL: CloudKeyModelRow must use CloudKeyValidator + CloudModelCatalog")
if "listModels" not in text:
    raise SystemExit("FAIL: CloudKeyModelRow must call listModels")
# Used for Gemini + OpenAI
if text.count("CloudKeyModelRow(") < 2:
    raise SystemExit("FAIL: expected CloudKeyModelRow on both Gemini and OpenAI cards")
print("PASS: CloudKeyModelRow badge + Picker/editable+Retry wired for Gemini/OpenAI.")
PY
