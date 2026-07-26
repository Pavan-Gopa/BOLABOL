#!/usr/bin/env bash
# A7 (ADR §6): UsageStatisticsView realBalanceSection reuses CloudBalanceRow, gated by
# balanceKind ∈ {openrouterCredits, ollamaPlan} AND a configured key (no fetch for unused providers).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/UsageStatisticsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/UsageStatisticsView.swift").read_text(encoding="utf-8")
for n in (
    "realBalanceSection",
    "realBalanceProviders",
    "CloudBalanceRow(descriptor:",
    "descriptor.balanceKind == .openrouterCredits",
    ".ollamaPlan",
):
    if n not in text:
        raise SystemExit(f"FAIL: UsageStatisticsView real-balance section missing: {n}")
# Must gate on a configured (non-empty) key.
if ".trimmingCharacters(in: .whitespacesAndNewlines).isEmpty" not in text:
    raise SystemExit("FAIL: realBalanceProviders must gate on a non-empty configured key")
# The section is rendered in the body.
if "realBalanceSection" not in text.split("private var realBalanceSection", 1)[0]:
    raise SystemExit("FAIL: realBalanceSection must be referenced in the view body")
print("PASS: UsageStatisticsView reuses CloudBalanceRow in realBalanceSection (kind + key gated).")
PY
