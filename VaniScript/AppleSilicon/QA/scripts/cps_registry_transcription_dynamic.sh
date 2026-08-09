#!/usr/bin/env bash
# ProviderRegistry transcription options use dynamic supportsTranscription.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/ProviderRegistry.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }
python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScriptCore/ProviderRegistry.swift").read_text(encoding="utf-8")
idx = text.find("availableTranscriptionProviders")
chunk = text[idx:idx+1800]
if "supportsTranscription" not in chunk:
    raise SystemExit("FAIL: availableTranscriptionProviders does not call supportsTranscription")
if "CloudChatRouter" not in chunk:
    raise SystemExit("FAIL: transcription registry not using CloudChatRouter")
print("PASS: registry transcription gating is dynamic via supportsTranscription + CloudChatRouter.")
PY
