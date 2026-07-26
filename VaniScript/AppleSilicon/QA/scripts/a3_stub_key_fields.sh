#!/usr/bin/env bash
# A3: stub providers write keys to correct AppSettings fields
# (qwenApiKey / openrouterApiKey / ollamaCloudApiKey).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
start = text.find("private var apiKeyPath")
if start < 0:
    # also accept computed property name variants
    start = text.find("apiKeyPath")
if start < 0:
    raise SystemExit("FAIL: apiKeyPath mapping for stub providers missing")
# look at a window
window = text[start:start+800]
checks = [
    ("qwenID", r"\.qwenApiKey"),
    ("openrouterID", r"\.openrouterApiKey"),
    ("ollamaCloudID", r"\.ollamaCloudApiKey"),
]
import re
for id_const, keypath in checks:
    if id_const not in window:
        raise SystemExit(f"FAIL: CloudProviderCatalog.{id_const} not mapped in apiKeyPath")
    if not re.search(keypath, window):
        raise SystemExit(f"FAIL: keyPath {keypath} missing for stub providers")
# AppSettings still has the fields
settings = Path("Sources/VaniScriptCore/AppSettings.swift").read_text(encoding="utf-8")
for field in ("qwenApiKey", "openrouterApiKey", "ollamaCloudApiKey"):
    if f"public var {field}" not in settings and f"var {field}" not in settings:
        raise SystemExit(f"FAIL: AppSettings missing field {field}")
print("PASS: stub providers map to qwenApiKey/openrouterApiKey/ollamaCloudApiKey.")
PY
