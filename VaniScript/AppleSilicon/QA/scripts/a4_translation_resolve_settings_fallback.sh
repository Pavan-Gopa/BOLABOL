#!/usr/bin/env bash
# A4: CloudTextTranslationEngine resolve — gemini/openai from settings + hardcode fallbacks.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Services/CloudTextTranslationEngine.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
import re
text = Path("Sources/VaniScript/Services/CloudTextTranslationEngine.swift").read_text(encoding="utf-8")
if "resolvedModel" not in text:
    raise SystemExit("FAIL: resolvedModel helper missing")
if "geminiTextModel" not in text:
    raise SystemExit("FAIL: Gemini translation resolve must read geminiTextModel")
if "openaiTextModel" not in text:
    raise SystemExit("FAIL: OpenAI translation resolve must read openaiTextModel")
if "gemini-2.5-flash" not in text:
    raise SystemExit("FAIL: Gemini fallback hardcode missing")
if "gpt-4o-mini" not in text:
    raise SystemExit("FAIL: OpenAI fallback hardcode missing")
if re.search(r'case\s+"qwen', text) or re.search(r'case\s+"openrouter', text) or re.search(r'case\s+"ollama', text):
    raise SystemExit("FAIL: A5 engine routing present in translation resolve")
print("PASS: translation resolve uses settings models + hardcode fallbacks; no A5 routing.")
PY
