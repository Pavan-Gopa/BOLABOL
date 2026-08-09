#!/usr/bin/env bash
# Settings OpenRouter card: separate Audio Transcription + Text Translation sections.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }
python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
for needle in (
    "Audio Transcription Section",
    "Text Translation Section",
    "openrouterTranscriptionModel",
    "openrouterTranslationModel",
    "Use for Transcribing",
    "Use for Translation",
    "CloudProviderCatalog.openrouterID",
):
    if needle not in text:
        raise SystemExit(f"FAIL: OpenRouter dual UI missing marker: {needle}")
print("PASS: OpenRouter dual STT/MT UI sections present.")
PY
