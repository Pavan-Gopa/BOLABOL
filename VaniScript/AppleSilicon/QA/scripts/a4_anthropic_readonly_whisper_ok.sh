#!/usr/bin/env bash
# A4 Verifier-accepted scope: Anthropic stays ReadOnly Text Model; OpenAI transcription whisper-1.
# These are NOT product bugs — assert the intended deferred design remains.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

python3 - <<'PY'
from pathlib import Path
settings = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
# Anthropic card keeps ReadOnlyRow for Text Model (no CloudKeyModelRow for anthropic)
start = settings.find("private var anthropicCard")
if start < 0:
    raise SystemExit("FAIL: anthropicCard missing")
# next private var after anthropicCard
import re
m = re.search(r'private var \w+', settings[start+10:])
end = start + 10 + (m.start() if m else 2000)
card = settings[start:end]
if 'ReadOnlyRow(title: "Text Model"' not in card:
    raise SystemExit("FAIL: Anthropic must keep ReadOnlyRow Text Model (Verifier OK scope)")
if "CloudKeyModelRow" in card:
    raise SystemExit("FAIL: Anthropic must not use CloudKeyModelRow in A4 (no settings field)")

audio = Path("Sources/VaniScript/Services/CloudAudioTranscriptionEngine.swift").read_text(encoding="utf-8")
if '"whisper-1"' not in audio:
    raise SystemExit("FAIL: OpenAI transcription should remain whisper-1 (Verifier OK deferred)")
print("PASS: Anthropic ReadOnly + whisper-1 deferred scope OK (not bugs).")
PY
