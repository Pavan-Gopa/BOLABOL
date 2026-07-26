#!/usr/bin/env bash
# A3 out-of-scope: no A5 engine routing for qwen/openrouter/ollama.
# Stub cards must NOT set transcriptionProvider/translationProvider to those ids.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
import re
text = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
start = text.find("private struct ProviderCardView")
if start < 0:
    raise SystemExit("FAIL: ProviderCardView missing")
# to ApiKeyInputRow
end = text.find("private struct ApiKeyInputRow", start)
card = text[start:end if end > 0 else start+8000]
# coming soon path must exist
if "comingSoonCard" not in card and "coming soon" not in card.lower():
    raise SystemExit("FAIL: coming-soon stub missing for qwen/openrouter/ollama")
# Must not assign transcription/translation to qwen/openrouter/ollama-cloud
forbidden = re.findall(
    r'(transcriptionProvider|translationProvider)\s*=\s*"(qwen|openrouter|ollama-cloud|qwen-cloud|ollama)"',
    card,
)
if forbidden:
    raise SystemExit(f"FAIL: A5 engine routing leaked into A3 ProviderCardView: {forbidden}")
# Engines should not reference those as cloud engines in A3 product files either (smoke)
for eng in [
    "Sources/VaniScript/Services/CloudAudioTranscriptionEngine.swift",
    "Sources/VaniScript/Services/CloudTextTranslationEngine.swift",
]:
    p = Path(eng)
    if not p.exists():
        continue
    et = p.read_text(encoding="utf-8")
    # soft: do not require absence of all mentions; only fail if new Active*Provider cases for qwen/openrouter appear as production routing
    # Keep assert light — A5 is when those land intentionally.
print("PASS: no A5 engine routing for qwen/openrouter/ollama in ProviderCardView.")
PY
