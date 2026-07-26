#!/usr/bin/env bash
# A5: CloudAudioTranscriptionEngine has NO new resolve cases for qwen/openrouter/ollama (honest).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Services/CloudAudioTranscriptionEngine.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
import re
text = Path("Sources/VaniScript/Services/CloudAudioTranscriptionEngine.swift").read_text(encoding="utf-8")

# Extract resolve() body
m = re.search(
    r"static func resolve\(settings: AppSettings, providerID: String\)[^{]*\{([\s\S]*?)\n    \}",
    text,
)
if not m:
    raise SystemExit("FAIL: ActiveCloudTranscriptionProvider.resolve not found")
body = m.group(1)

# Must still handle gemini/gpt
if '"gemini-cloud"' not in body or '"gpt-cloud"' not in body:
    raise SystemExit("FAIL: legacy gemini/gpt transcription resolve missing")

# Must NOT add qwen/openrouter/ollama-cloud cases
for forbidden in ('"qwen"', '"openrouter"', '"ollama-cloud"', '"ollama"'):
    if re.search(rf'case\s+{re.escape(forbidden)}', body):
        raise SystemExit(f"FAIL: transcription resolve has case {forbidden} (should be absent)")

# Honesty comment present
if "intentionally NO resolve" not in text and "supportsTranscription" not in text:
    raise SystemExit("FAIL: honesty comment about no transcription cases missing")

# default returns nil
if "return nil" not in body:
    raise SystemExit("FAIL: transcription resolve default should return nil")

print("PASS: CloudAudioTranscriptionEngine has no new qwen/openrouter/ollama cases (honest).")
PY
