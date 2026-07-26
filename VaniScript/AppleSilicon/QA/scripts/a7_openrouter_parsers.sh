#!/usr/bin/env bash
# A7 (§11, ADR): OpenRouter provider — GET /api/v1/credits + /api/v1/key (Bearer),
# pure static parsers parseCredits/parseKey (unit-tested on mocked JSON).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/CloudBalanceService.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScriptCore/CloudBalanceService.swift").read_text(encoding="utf-8")
for n in (
    "https://openrouter.ai/api/v1/credits",
    "https://openrouter.ai/api/v1/key",
    "public static func parseCredits",
    "public static func parseKey",
    "public static func creditsRequest",
    "public static func keyRequest",
    "Authorization",
    "Bearer",
    "total_credits",
    "total_usage",
    "limit_remaining",
):
    if n not in text:
        raise SystemExit(f"FAIL: OpenRouter provider missing: {n}")
# Parsers must throw a typed error on malformed bodies (quiet fallback upstream).
if "unparsableResponse" not in text:
    raise SystemExit("FAIL: parsers must throw .unparsableResponse on bad bodies")
print("PASS: OpenRouter credits+key endpoints, Bearer auth, pure parsers present.")
PY
