#!/usr/bin/env bash
# A5: CloudChatRouter endpoints + Bearer headers for Qwen / OpenRouter / Ollama Cloud.
# No real network — pure string asserts + unit test presence.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/ProviderRegistry.swift"
TEST="Tests/VaniScriptCoreTests/CloudProviderRoutingTests.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }
[[ -f "$TEST" ]] || { echo "FAIL: $TEST missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
src = Path("Sources/VaniScriptCore/ProviderRegistry.swift").read_text(encoding="utf-8")
test = Path("Tests/VaniScriptCoreTests/CloudProviderRoutingTests.swift").read_text(encoding="utf-8")

if "public enum CloudChatRouter" not in src and "enum CloudChatRouter" not in src:
    raise SystemExit("FAIL: CloudChatRouter missing")
if "public struct CloudChatRoute" not in src and "struct CloudChatRoute" not in src:
    raise SystemExit("FAIL: CloudChatRoute missing")

needles = [
    "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions",
    "https://openrouter.ai/api/v1/chat/completions",
    "/v1/chat/completions",
    'Authorization": "Bearer',
    "chatProviderIDs",
]
for n in needles:
    if n not in src:
        raise SystemExit(f"FAIL: CloudChatRouter missing {n!r}")

# Ollama base URL from settings
if "ollamaCloudBaseUrl" not in src:
    raise SystemExit("FAIL: Ollama route missing ollamaCloudBaseUrl")

for t in ("qwenRoute", "openrouterRoute", "ollamaRouteDefaultBase", "ollamaBaseNormalization"):
    if t not in test:
        raise SystemExit(f"FAIL: CloudProviderRoutingTests missing {t}")

print("PASS: CloudChatRouter endpoints (DashScope/OpenRouter/Ollama /v1) + Bearer.")
PY
