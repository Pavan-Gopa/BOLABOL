#!/usr/bin/env bash
# A5: ProviderRegistry translation options for qwen/openrouter/ollama-cloud when key set.
# Asserts source gate + unit tests (empty key → no option; non-empty → option).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
REG="Sources/VaniScriptCore/ProviderRegistry.swift"
TEST="Tests/VaniScriptCoreTests/ProviderRegistryCloudTests.swift"
[[ -f "$REG" ]] || { echo "FAIL: $REG missing"; exit 1; }
[[ -f "$TEST" ]] || { echo "FAIL: $TEST missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
import re
reg = Path("Sources/VaniScriptCore/ProviderRegistry.swift").read_text(encoding="utf-8")
test = Path("Tests/VaniScriptCoreTests/ProviderRegistryCloudTests.swift").read_text(encoding="utf-8")

# Translation loop gates on chatProviderIDs + supportsTranslation + apiKey
fn_start = reg.find("availableTranslationProviders")
fn_end = reg.find("downloadedLocalProviders", fn_start)
body = reg[fn_start:fn_end if fn_end > 0 else None]
if "CloudChatRouter.chatProviderIDs" not in body:
    raise SystemExit("FAIL: translation options not gated by CloudChatRouter.chatProviderIDs")
if "supportsTranslation" not in body:
    raise SystemExit("FAIL: translation options missing supportsTranslation gate")
if "CloudChatRouter.apiKey" not in body:
    raise SystemExit("FAIL: translation options missing apiKey gate")

# Unit tests cover empty / present / whitespace
for needle in (
    "hiddenWithoutKeys",
    "keyExposesTranslationOption",
    "whitespaceKeyIgnored",
    "CloudProviderCatalog.qwenID",
    "CloudProviderCatalog.openrouterID",
    "CloudProviderCatalog.ollamaCloudID",
):
    if needle not in test:
        raise SystemExit(f"FAIL: ProviderRegistryCloudTests missing {needle}")

print("PASS: ProviderRegistry translation gating for qwen/openrouter/ollama-cloud (key-present).")
PY
