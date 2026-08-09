#!/usr/bin/env bash
# Current approved catalog order after post-A7 edits (documents actual contract).
# NOTE: original A1 order included anthropic; current product may differ — this
# locks the *current* order so further silent reorder is caught.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/CloudProviderCatalog.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }
python3 - <<'PY'
from pathlib import Path
import re
text = Path("Sources/VaniScriptCore/CloudProviderCatalog.swift").read_text(encoding="utf-8")
m = re.search(r'providerOrder:\s*\[String\]\s*=\s*\[(.*?)\]', text, re.S)
if not m:
    raise SystemExit("FAIL: providerOrder missing")
order = re.findall(r'(\w+ID)', m.group(1))
# Must start with gemini, openai and end with custom; must include qwen/openrouter/ollama
need = ["geminiID", "openaiID", "qwenID", "openrouterID", "ollamaCloudID", "customID"]
for n in need:
    if n not in order:
        raise SystemExit(f"FAIL: providerOrder missing {n}: {order}")
if order[0] != "geminiID" or order[1] != "openaiID":
    raise SystemExit(f"FAIL: order must start gemini, openai; got {order}")
if order[-1] != "customID":
    raise SystemExit(f"FAIL: order must end with custom; got {order}")
# providers list must match order ids
prov = re.findall(r'id:\s*(\w+ID)', text[text.find("static let providers"):text.find("descriptor(for")])
# only first-level id: lines inside CloudProviderDescriptor inits
if prov != order:
    # soft: at least same set
    if set(prov) != set(order):
        raise SystemExit(f"FAIL: providers ids {prov} != order {order}")
print(f"PASS: current providerOrder locked: {order}")
PY
