#!/usr/bin/env bash
# A7 (ADR §2): OpenRouter balance mapping — accountRemaining = credits − usage;
# per-key cap via min(...) (never over-report); total = key limit ?? credits.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/CloudBalanceService.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
import re
text = Path("Sources/VaniScriptCore/CloudBalanceService.swift").read_text(encoding="utf-8")
if "public static func balance(creditsData: Data, keyData: Data) throws -> BalanceInfo" not in text:
    raise SystemExit("FAIL: static balance(creditsData:keyData:) mapper missing")
# account remaining = total_credits - total_usage
if not re.search(r"totalCredits\s*-\s*totalUsage", text):
    raise SystemExit("FAIL: accountRemaining must be totalCredits - totalUsage")
# per-key cap: min(accountRemaining, keyRemaining) — never over-report
if not re.search(r"min\(\s*accountRemaining\s*,\s*keyRemaining\s*\)", text):
    raise SystemExit("FAIL: per-key cap must use min(accountRemaining, keyRemaining)")
# total = key limit ?? credits (fallback)
if "??" not in text or "keyLimit" not in text:
    raise SystemExit("FAIL: total must fall back from keyLimit ?? credits")
if ".usd(remaining:" not in text:
    raise SystemExit("FAIL: mapper must return .usd(remaining:total:)")
print("PASS: OpenRouter mapping = credits−usage, per-key min() cap, total = keyLimit ?? credits.")
PY
