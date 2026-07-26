#!/usr/bin/env bash
# A4: CloudKeyValidator.status(forHTTPStatus) — 2xx valid, 401/403 invalid, 429 valid, other invalid.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/CloudKeyValidator.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
import re
text = Path("Sources/VaniScriptCore/CloudKeyValidator.swift").read_text(encoding="utf-8")
if "status(forHTTPStatus" not in text:
    raise SystemExit("FAIL: status(forHTTPStatus:) missing")
for case in ("case idle", "case checking", "case valid", "case invalid"):
    if case not in text:
        raise SystemExit(f"FAIL: status case missing: {case}")
if "200...299" not in text and "200..<300" not in text:
    raise SystemExit("FAIL: 2xx range mapping missing")
if not re.search(r"case\s+401\s*,\s*403|case\s+401|403", text):
    raise SystemExit("FAIL: 401/403 mapping missing")
if "429" not in text:
    raise SystemExit("FAIL: 429 mapping missing")
# Isolate the 429 case arm: from "case 429" to next case/default
m = re.search(r"case\s+429\s*:(.*?)(?:case\s+|default\s*:)", text, re.S)
if not m:
    raise SystemExit("FAIL: could not locate case 429 arm")
arm = m.group(1)
if ".valid" not in arm:
    raise SystemExit("FAIL: 429 must map to .valid")
# 401/403 must be invalid
m401 = re.search(r"case\s+401\s*,\s*403\s*:(.*?)(?:case\s+|default\s*:)", text, re.S)
if not m401:
    m401 = re.search(r"case\s+401.*?:(.*?)(?:case\s+|default\s*:)", text, re.S)
if not m401 or ".invalid" not in m401.group(1):
    raise SystemExit("FAIL: 401/403 must map to .invalid")
# default → invalid
if "default:" not in text or ".invalid" not in text[text.find("default:"):text.find("default:")+200]:
    raise SystemExit("FAIL: default non-2xx must map to .invalid")
print("PASS: CloudKeyValidator status map 2xx/401/403/429/other present.")
PY
