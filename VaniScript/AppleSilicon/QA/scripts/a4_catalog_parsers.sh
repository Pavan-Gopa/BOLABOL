#!/usr/bin/env bash
# A4: CloudModelCatalog parsers — OpenAI data[].id, Gemini strip models/, Ollama models[].name, Anthropic data[].id.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/CloudModelCatalog.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScriptCore/CloudModelCatalog.swift").read_text(encoding="utf-8")
if "func parse(data:" not in text and "static func parse" not in text:
    raise SystemExit("FAIL: parse(data:endpoint:provider:) missing")
# Gemini strip
if "stripGeminiPrefix" not in text or "models/" not in text:
    raise SystemExit("FAIL: Gemini models/ strip missing")
# OpenAI + Anthropic share data[].id shape
if ".openAICompatible" not in text or ".anthropic" not in text:
    raise SystemExit("FAIL: openAICompatible/anthropic endpoint cases missing")
if "OpenAICompatibleModelList" not in text and 'decoded.data.map' not in text:
    raise SystemExit("FAIL: OpenAI-compatible data[].id parse path missing")
# Ollama tags
if "ollamaTags" not in text or "OllamaTagList" not in text:
    raise SystemExit("FAIL: Ollama tags parser missing")
# Unit tests for the three shapes
tests = Path("Tests/VaniScriptCoreTests/CloudModelCatalogTests.swift").read_text(encoding="utf-8")
for needle in ("parsesOpenAIModels", "parsesGeminiModels", "parsesOllamaTags"):
    if needle not in tests:
        raise SystemExit(f"FAIL: unit test {needle} missing")
if "gemini-2.5-flash" not in tests:
    raise SystemExit("FAIL: Gemini strip assertion missing in tests")
print("PASS: OpenAI/Gemini/Ollama(+Anthropic shared) parsers present with unit tests.")
PY
