#!/usr/bin/env bash
# A7 (§11 req 6): CloudBalanceServiceTests present — parsers credits/key (+null), per-key cap,
# Ollama plan, .estimated/.none no-fetch guard, empty-key no-fetch, quiet fallback, TTL cache,
# force refresh. Network mocked (no live URLSession/keys).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Tests/VaniScriptCoreTests/CloudBalanceServiceTests.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing (A7 unit tests)"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Tests/VaniScriptCoreTests/CloudBalanceServiceTests.swift").read_text(encoding="utf-8")
if '@Suite("CloudBalanceService (A7)")' not in text:
    raise SystemExit("FAIL: @Suite(\"CloudBalanceService (A7)\") missing")
if "@testable import VaniScriptCore" not in text:
    raise SystemExit("FAIL: @testable import VaniScriptCore missing")
for n in (
    "parseCredits",          # credits parser
    "parseKey",              # key parser (+null tolerance)
    "limit_remaining",       # key fields
    "mapsPerKeyCap",         # per-key cap mapping (never over-report)
    "remaining: 4.0",        # per-key cap wins over the larger account balance
    "Plan-based (GPU time)", # Ollama plan
    ".estimated",            # guard no-fetch
    ".unavailable",          # quiet fallback / guard result
    "force: true",           # force refresh bypasses cache
    "statusCode: 401",       # HTTP error → quiet fallback
):
    if n not in text:
        raise SystemExit(f"FAIL: A7 tests missing coverage: {n}")
# Network must be mocked — no real shared session, no real keys.
if "URLSession.shared" in text:
    raise SystemExit("FAIL: tests must mock network, not use URLSession.shared")
print("PASS: CloudBalanceServiceTests cover parsers/cap/Ollama/guard/quiet/cache/force on mocked network.")
PY
