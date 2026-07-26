#!/usr/bin/env bash
# A3 out-of-scope: no A5 engine routing for qwen/openrouter/ollama.
# Step-aware: N/A when current_step ≥ A5 (A5 intentionally adds that routing).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

STATE_FILE="AI_Workflow_Kit/docs/AI/STATE.yaml"
current_step=""
if [[ -f "$STATE_FILE" ]]; then
  current_step="$(sed -nE 's/^current_step:[[:space:]]*([A-Za-z0-9_]+).*/\1/p' "$STATE_FILE" | head -1)"
fi

# A5+ owns engine routing; A3 negative assert is historical only.
if [[ "$current_step" =~ ^A([5-9]|[1-9][0-9]+)$ ]] || [[ "$current_step" == "A5" || "$current_step" == "A6" || "$current_step" == "A7" || "$current_step" == "A8" ]]; then
  echo "NOTE: current_step='$current_step' (≥ A5); A3 no-A5-routing gate is N/A."
  echo "RESULT: PASS (a3_no_a5_engine_routing, step-aware N/A)"
  exit 0
fi

python3 - <<'PY'
from pathlib import Path
import re
text = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
start = text.find("private struct ProviderCardView")
if start < 0:
    raise SystemExit("FAIL: ProviderCardView missing")
end = text.find("private struct ApiKeyInputRow", start)
card = text[start:end if end > 0 else start+8000]
# coming soon path must exist pre-A5
if "comingSoonCard" not in card and "coming soon" not in card.lower():
    raise SystemExit("FAIL: coming-soon stub missing for qwen/openrouter/ollama")
# Must not assign transcription/translation to qwen/openrouter/ollama-cloud
forbidden = re.findall(
    r'(transcriptionProvider|translationProvider)\s*=\s*"(qwen|openrouter|ollama-cloud|qwen-cloud|ollama)"',
    card,
)
if forbidden:
    raise SystemExit(f"FAIL: A5 engine routing leaked into A3 ProviderCardView: {forbidden}")
print("PASS: no A5 engine routing for qwen/openrouter/ollama in ProviderCardView.")
PY
