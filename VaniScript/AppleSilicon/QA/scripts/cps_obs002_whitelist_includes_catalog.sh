#!/usr/bin/env bash
# CPS / OBS-002: cloud translation whitelist must include catalog provider ids.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/AppSettings.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }
python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScriptCore/AppSettings.swift").read_text(encoding="utf-8")
idx = text.find("synchronizeLocalModelsWithDisk")
if idx < 0:
    raise SystemExit("FAIL: synchronizeLocalModelsWithDisk missing")
chunk = text[idx:idx+3500]
if "supportedCloudTranslationKeys" not in chunk:
    raise SystemExit("FAIL: supportedCloudTranslationKeys missing in sanitizer")
if "CloudProviderCatalog.providers" not in chunk:
    needed = ["qwen", "openrouter", "ollama-cloud"]
    if not all(n in chunk for n in needed):
        raise SystemExit(
            "FAIL: whitelist must include CloudProviderCatalog.providers or explicit A5 ids "
            "(OBS-002 root cause: openrouter click reset to mlx-native)"
        )
if "gemini-cloud" not in chunk or "gpt-cloud" not in chunk:
    raise SystemExit("FAIL: legacy gemini-cloud/gpt-cloud must remain in whitelist")
print("PASS: OBS-002 whitelist includes catalog cloud ids + legacy gemini-cloud/gpt-cloud.")
PY
