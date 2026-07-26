#!/usr/bin/env bash
# A6: per-model cards — N transactions badge, 6 metrics, estimateCost, remaining vs budget.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/UsageStatisticsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/UsageStatisticsView.swift").read_text(encoding="utf-8")
for needle in (
    "transactions",
    "stats.sessions",
    "Prompt / input tokens",
    "Completion tokens",
    "Total tokens",
    "Audio min",
    "Estimated spent",
    "Estimated remaining",
    "estimateCost",
    "budgetLimit",
    "usageCard",
):
    if needle not in text:
        raise SystemExit(f"FAIL: per-model card marker missing: {needle}")
# remaining = max(0, budget - spent) pattern
if "budget - spent" not in text and "budget-spent" not in text:
    raise SystemExit("FAIL: remaining vs budget calculation missing")
print("PASS: per-model cards have N transactions, 6 metrics, estimateCost, remaining vs budget.")
PY
