#!/usr/bin/env bash
# A4: listRequest auth per provider — Gemini ?key=, OpenAI Bearer, Anthropic x-api-key, Ollama Bearer.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/CloudModelCatalog.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScriptCore/CloudModelCatalog.swift").read_text(encoding="utf-8")
if "static func listRequest" not in text and "func listRequest" not in text:
    raise SystemExit("FAIL: listRequest missing")
checks = {
    "Gemini query key": ('name: "key"' in text or 'URLQueryItem(name: "key"' in text) and "generativelanguage.googleapis.com" in text,
    "OpenAI Bearer": "Bearer" in text,
    "Anthropic x-api-key": "x-api-key" in text and "anthropic-version" in text,
    "Ollama /api/tags": "/api/tags" in text,
    "custom/none → nil": "case .custom" in text or ".custom, .none" in text or "case .custom, .none" in text,
}
for name, ok in checks.items():
    if not ok:
        raise SystemExit(f"FAIL: listRequest auth missing: {name}")
# Unit tests for Gemini + OpenAI request builders
tests = Path("Tests/VaniScriptCoreTests/CloudModelCatalogTests.swift").read_text(encoding="utf-8")
for needle in ("buildsGeminiRequest", "buildsOpenAIRequest", "buildsOllamaRequest", "customProviderNoRequest"):
    if needle not in tests:
        raise SystemExit(f"FAIL: request-builder test {needle} missing")
print("PASS: listRequest auth shapes + unit tests present.")
PY
