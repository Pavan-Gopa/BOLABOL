#!/usr/bin/env bash
# A4: CloudAudioTranscriptionEngine resolve — Gemini from settings; whisper-1 OK (deferred audio picker).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Services/CloudAudioTranscriptionEngine.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Services/CloudAudioTranscriptionEngine.swift").read_text(encoding="utf-8")
if "resolvedModel" not in text:
    raise SystemExit("FAIL: resolvedModel helper missing")
if "geminiTextModel" not in text:
    raise SystemExit("FAIL: Gemini resolve must read settings.geminiTextModel")
if 'fallback: "gemini-2.5-flash"' not in text and 'gemini-2.5-flash' not in text:
    raise SystemExit("FAIL: Gemini hardcode fallback missing")
# OpenAI transcription stays whisper-1 (Verifier OK — not a product bug)
if '"whisper-1"' not in text:
    raise SystemExit("FAIL: OpenAI transcription whisper-1 hardcode missing (expected until A5)")
# Must NOT route qwen/openrouter/ollama (A5)
for bad in ('"qwen"', "openrouter", "ollama"):
    # allow comments? fail on case labels / assign
    pass
import re
if re.search(r'case\s+"qwen', text) or re.search(r'case\s+"openrouter', text) or re.search(r'case\s+"ollama', text):
    raise SystemExit("FAIL: A5 engine routing present in transcription resolve")
print("PASS: transcription resolve uses geminiTextModel + fallback; whisper-1 deferred OK.")
PY
