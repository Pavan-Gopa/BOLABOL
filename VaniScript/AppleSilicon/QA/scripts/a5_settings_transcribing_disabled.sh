#!/usr/bin/env bash
# A5: Transcribing toggle disabled + tooltip when !supportsTranscription; Translation when key.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")

# cloudProviderToggles takes supportsTranscription
if "func cloudProviderToggles" not in text and "cloudProviderToggles(" not in text:
    raise SystemExit("FAIL: cloudProviderToggles helper missing")

# Disabled when !supportsTranscription
if ".disabled(!hasKey || !supportsTranscription)" not in text:
    # allow whitespace variants
    import re
    if not re.search(r"\.disabled\(!hasKey\s*\|\|\s*!supportsTranscription\)", text):
        raise SystemExit("FAIL: Transcribing not disabled when !supportsTranscription")

# Tooltip / help for unavailable transcription
if ".help(supportsTranscription" not in text and "no verified audio transcription" not in text.lower():
    raise SystemExit("FAIL: missing help/tooltip for disabled Transcribing")

# Explanatory copy when unavailable
if "Transcribing is unavailable" not in text:
    raise SystemExit("FAIL: missing 'Transcribing is unavailable' explanation copy")

# Translation only needs hasKey
if ".disabled(!hasKey)" not in text:
    raise SystemExit("FAIL: Translation toggle should disable only on missing key")

# Translation assigns engine id (catalog id)
if "settings.translationProvider = isTranslation ? \"mlx-native\" : engineID" not in text:
    raise SystemExit("FAIL: Translation toggle must set translationProvider to engineID")

print("PASS: Transcribing disabled+tooltip when unsupported; Translation gated by key only.")
PY
