#!/usr/bin/env bash
# Honesty: estimated cost path must show a billing disclaimer somewhere in usage UI.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/UsageStatisticsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }
python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/UsageStatisticsView.swift").read_text(encoding="utf-8")
exact = "Cost is an estimate based on locally counted text tokens; provider billing can differ."
# Accept exact A6 string OR a clear estimate/billing honesty phrase
if exact in text:
    print("PASS: exact A6 disclaimer present.")
    raise SystemExit(0)
lower = text.lower()
has_estimate = "estimate" in lower or "estimated" in lower
has_billing = "billing" in lower or "provider" in lower and "differ" in lower
has_disclaimer_word = "disclaimer" in lower or "estimate based" in lower
if has_estimate and (has_billing or has_disclaimer_word or "can differ" in lower):
    print("PASS: estimate honesty language present (non-exact variant).")
    raise SystemExit(0)
# If only estimateCost helper without user-facing disclaimer — FAIL
raise SystemExit(
    "FAIL: UsageStatisticsView missing user-facing estimate/billing disclaimer "
    "(A6 contract: Cost is an estimate... provider billing can differ.)"
)
PY
