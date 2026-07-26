#!/usr/bin/env bash
# A5: model precedence — settings override vs catalog default; blank key → nil.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

python3 - <<'PY'
from pathlib import Path
src = Path("Sources/VaniScriptCore/ProviderRegistry.swift").read_text(encoding="utf-8")
test = Path("Tests/VaniScriptCoreTests/CloudProviderRoutingTests.swift").read_text(encoding="utf-8")

# Source: empty model → descriptor.defaultTextModel
if "defaultTextModel" not in src:
    raise SystemExit("FAIL: model fallback to descriptor.defaultTextModel missing")
if "qwenCloudModel" not in src or "openrouterModel" not in src or "ollamaCloudModel" not in src:
    raise SystemExit("FAIL: router not reading settings model fields")

# Tests cover override + missing key + unknown ids
for n in (
    "qwenModelOverride",
    "missingKeyReturnsNil",
    "unknownIdsReturnNil",
    "qwen-plus",  # catalog default in test
):
    if n not in test:
        raise SystemExit(f"FAIL: routing tests missing {n}")

print("PASS: CloudChatRouter model fallback + settings override + nil on blank key.")
PY
