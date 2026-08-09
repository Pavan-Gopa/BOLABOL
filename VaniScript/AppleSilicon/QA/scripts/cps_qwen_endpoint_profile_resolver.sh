#!/usr/bin/env bash
# Qwen endpoint profile: resolvedQwenBaseUrl + Token Plan key prefixes (OBS-001).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/AppSettings.swift"
CAT="Sources/VaniScriptCore/CloudModelCatalog.swift"
REG="Sources/VaniScriptCore/ProviderRegistry.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }
grep -q "func resolvedQwenBaseUrl" "$FILE" || { echo "FAIL: resolvedQwenBaseUrl missing"; exit 1; }
grep -q "qwenBaseUrl" "$FILE" || { echo "FAIL: qwenBaseUrl field missing"; exit 1; }
python3 - <<'PY'
from pathlib import Path
app = Path("Sources/VaniScriptCore/AppSettings.swift").read_text(encoding="utf-8")
cat = Path("Sources/VaniScriptCore/CloudModelCatalog.swift").read_text(encoding="utf-8")
reg = Path("Sources/VaniScriptCore/ProviderRegistry.swift").read_text(encoding="utf-8")
combined = app + "\n" + cat
if "sk-sp-" not in combined and "sk-ws-" not in combined:
    raise SystemExit("FAIL: Token Plan key prefix routing (sk-sp-/sk-ws-) missing")
if "token-plan" not in combined:
    raise SystemExit("FAIL: token-plan base host missing")
if "dashscope-intl" not in combined:
    raise SystemExit("FAIL: default dashscope-intl host missing")
if "resolvedQwenBaseUrl" not in reg:
    raise SystemExit("FAIL: CloudChatRouter/ProviderRegistry does not call resolvedQwenBaseUrl")
print("PASS: Qwen endpoint profile resolver + Token Plan hosts wired into router.")
PY
