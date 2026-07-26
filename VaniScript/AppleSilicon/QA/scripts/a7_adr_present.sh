#!/usr/bin/env bash
# A7: ADR D-2026-07-26-A7 present in DECISIONS.md with the verified OpenRouter shapes + honesty rules.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="AI_Workflow_Kit/docs/DECISIONS.md"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("AI_Workflow_Kit/docs/DECISIONS.md").read_text(encoding="utf-8")
if "D-2026-07-26-A7" not in text:
    raise SystemExit("FAIL: ADR D-2026-07-26-A7 missing")
adr = text.split("D-2026-07-26-A7", 1)[1]
adr = adr[:6000]
for n in (
    "CloudBalanceService",
    "BalanceProvider",
    "BalanceInfo",
    "/api/v1/credits",
    "/api/v1/key",
    "limit_remaining",
    "Plan-based (GPU time)",
    ".unavailable",
    "331",
):
    if n not in adr:
        raise SystemExit(f"FAIL: A7 ADR missing: {n}")
print("PASS: ADR D-2026-07-26-A7 present with OpenRouter shapes + honesty rules + 331 tests.")
PY
