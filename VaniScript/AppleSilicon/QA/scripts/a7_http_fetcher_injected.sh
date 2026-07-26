#!/usr/bin/env bash
# A7 (§14): network only via injected CloudHTTPFetcher (reuse from A4 CloudModelCatalog);
# no direct URLSession in the balance service → parsers testable on mocks, no live keys.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/CloudBalanceService.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScriptCore/CloudBalanceService.swift").read_text(encoding="utf-8")
if "CloudHTTPFetcher" not in text:
    raise SystemExit("FAIL: must use the injected CloudHTTPFetcher")
if "CloudHTTP.live" not in text:
    raise SystemExit("FAIL: default fetcher must be CloudHTTP.live")
if "URLSession" in text:
    raise SystemExit("FAIL: CloudBalanceService must not touch URLSession directly (use injected fetcher)")
# The fetcher typealias must live in CloudModelCatalog (A4 reuse), not redefined here.
cat = Path("Sources/VaniScriptCore/CloudModelCatalog.swift").read_text(encoding="utf-8")
if "public typealias CloudHTTPFetcher" not in cat:
    raise SystemExit("FAIL: CloudHTTPFetcher typealias missing from CloudModelCatalog (A4)")
if "typealias CloudHTTPFetcher" in text:
    raise SystemExit("FAIL: CloudHTTPFetcher must be reused from A4, not redefined in CloudBalanceService")
print("PASS: network only via injected CloudHTTPFetcher (A4 reuse); no direct URLSession.")
PY
