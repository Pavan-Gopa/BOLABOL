#!/usr/bin/env bash
# A4 Verifier-accepted scope: Anthropic stays ReadOnly Text Model; OpenAI transcription whisper-1.
# These are NOT product bugs — assert the intended deferred design remains.
# Step-aware: A5+ may mention CloudKeyModelRow in nearby MARK comments; only the
# anthropicCard *body* is checked (not the following cloudProviderCard docs).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

python3 - <<'PY'
from pathlib import Path
import re
settings = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
# Anthropic card keeps ReadOnlyRow for Text Model (no CloudKeyModelRow for anthropic)
start = settings.find("private var anthropicCard")
if start < 0:
    raise SystemExit("FAIL: anthropicCard missing")
# Bound the card body to its own declaration: from `private var anthropicCard`
# up to (not including) the next `// MARK:` or next `private var`/`private func`.
rest = settings[start:]
# Prefer ending at the first blank-line + MARK or next peer member at indent-4.
m = re.search(r'\n    // MARK:|\n    private (var|func) \w+', rest[len("private var anthropicCard"):])
if m:
    end = start + len("private var anthropicCard") + m.start()
else:
    end = start + 800
card = settings[start:end]
if 'ReadOnlyRow(title: "Text Model"' not in card:
    raise SystemExit("FAIL: Anthropic must keep ReadOnlyRow Text Model (Verifier OK scope)")
# Only fail if CloudKeyModelRow is *used* in the card body (not a later MARK comment).
if re.search(r'\bCloudKeyModelRow\s*\(', card):
    raise SystemExit("FAIL: Anthropic must not use CloudKeyModelRow (no settings field)")

audio = Path("Sources/VaniScript/Services/CloudAudioTranscriptionEngine.swift").read_text(encoding="utf-8")
if '"whisper-1"' not in audio:
    raise SystemExit("FAIL: OpenAI transcription should remain whisper-1 (Verifier OK deferred)")
print("PASS: Anthropic ReadOnly + whisper-1 deferred scope OK (not bugs).")
PY
