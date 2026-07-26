#!/usr/bin/env bash
# A4 out-of-scope: no qwen/openrouter/ollama engine routing in cloud engines.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

python3 - <<'PY'
from pathlib import Path
import re
files = [
    Path("Sources/VaniScript/Services/CloudAudioTranscriptionEngine.swift"),
    Path("Sources/VaniScript/Services/CloudTextTranslationEngine.swift"),
]
for f in files:
    text = f.read_text(encoding="utf-8")
    for pat, name in (
        (r'case\s+"qwen', "qwen"),
        (r'case\s+"openrouter', "openrouter"),
        (r'case\s+"ollama', "ollama"),
        (r'transcriptionProvider\s*=\s*"qwen', "qwen transcription assign"),
        (r'translationProvider\s*=\s*"openrouter', "openrouter translation assign"),
    ):
        if re.search(pat, text):
            raise SystemExit(f"FAIL: A5 routing ({name}) found in {f}")
print("PASS: no A5 qwen/openrouter/ollama engine routing in cloud engines.")
PY
