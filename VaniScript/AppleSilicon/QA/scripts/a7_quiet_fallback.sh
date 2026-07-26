#!/usr/bin/env bash
# A7 (ADR §4): quiet fallback — any network/parse error → .unavailable (no crash/throw to UI).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/CloudBalanceService.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
import re
text = Path("Sources/VaniScriptCore/CloudBalanceService.swift").read_text(encoding="utf-8")
# Typed errors kept internal to the fetch path.
for n in (
    "public enum CloudBalanceError",
    "case requestFailed(provider: String, status: Int)",
    "case unparsableResponse(provider: String)",
):
    if n not in text:
        raise SystemExit(f"FAIL: CloudBalanceError missing: {n}")
# balance() must catch and return .unavailable quietly (no rethrow).
m = re.search(r"public func balance\((.*?)\n    \}", text, re.S)
if not m:
    raise SystemExit("FAIL: balance() not found")
body = m.group(1)
if "do {" not in body or "} catch {" not in body:
    raise SystemExit("FAIL: balance() must wrap fetch in do/catch")
if "return .unavailable" not in body.split("} catch {", 1)[1]:
    raise SystemExit("FAIL: catch branch must return .unavailable (quiet fallback)")
# Non-2xx HTTP must throw requestFailed (so the catch can quiet it).
if "requestFailed(provider:" not in text:
    raise SystemExit("FAIL: non-2xx must throw .requestFailed")
print("PASS: quiet fallback — errors mapped to .unavailable, never surfaced to UI.")
PY
