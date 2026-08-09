#!/usr/bin/env bash
# A4 out-of-scope: no qwen/openrouter/ollama engine routing in cloud engines.
# Step-aware: N/A when current_step ≥ A5 (A5 intentionally adds that routing).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

STATE_FILE="AI_Workflow_Kit/docs/AI/STATE.yaml"
current_step=""
if [[ -f "$STATE_FILE" ]]; then
  current_step="$(sed -nE 's/^current_step:[[:space:]]*([A-Za-z0-9_-]+).*/\1/p' "$STATE_FILE" | head -1)"
fi

if [[ "$current_step" =~ ^A([5-9]|[1-9][0-9]+)$ ]] || [[ "$current_step" == "A5" || "$current_step" == "A6" || "$current_step" == "A7" || "$current_step" == "A8" ]]; then
  echo "NOTE: current_step='$current_step' (≥ A5); A4 no-A5-routing gate is N/A."
  echo "RESULT: PASS (a4_no_a5_engine_routing, step-aware N/A)"
  exit 0
fi

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
