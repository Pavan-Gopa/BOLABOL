#!/usr/bin/env bash
# CloudModelCatalog injects known OpenRouter STT models into list.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/CloudModelCatalog.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }
python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScriptCore/CloudModelCatalog.swift").read_text(encoding="utf-8")
for m in ("x-ai/grok-stt-1.0", "deepgram/nova-3", "openai/whisper-1", "openRouterSTTModels"):
    if m not in text:
        raise SystemExit(f"FAIL: OpenRouter STT catalog missing {m}")
if "promptPricePer1M" not in text:
    raise SystemExit("FAIL: CloudModel pricing fields missing")
print("PASS: OpenRouter STT model injection + CloudModel metadata fields present.")
PY
