#!/usr/bin/env bash
# A7 (ADR §6): SettingsView CloudBalanceRow — module-visible (not private), renders only for
# balanceKind ∈ {openrouterCredits, ollamaPlan}; displayText for .usd/.planLimits/.unavailable;
# Refresh button + ProgressView; lazy .task(id: apiKey).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
import re
text = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
# Module-visible struct (shared with UsageStatisticsView) — must NOT be `private struct`.
if "struct CloudBalanceRow: View" not in text:
    raise SystemExit("FAIL: CloudBalanceRow struct missing")
if re.search(r"private struct CloudBalanceRow", text):
    raise SystemExit("FAIL: CloudBalanceRow must be module-visible (internal), not private")
# Gating in the provider card: only real-balance kinds render the row.
if "descriptor.balanceKind == .openrouterCredits || descriptor.balanceKind == .ollamaPlan" not in text:
    raise SystemExit("FAIL: provider card must gate CloudBalanceRow on openrouterCredits/ollamaPlan")
# Display wording per BalanceInfo case. (The literal "Plan-based (GPU time)" label lives in
# CloudBalanceService.swift; the row renders whichever .planLimits label it is given.)
for n in ("remaining / ", " limit", "Estimated only", ".planLimits(label", ".usd(remaining"):
    if n not in text:
        raise SystemExit(f"FAIL: CloudBalanceRow display missing: {n}")
# Lazy load + Refresh + loading indicator.
for n in (".task(id: apiKey)", "arrow.clockwise", "ProgressView", "force: true", "CloudBalanceService()"):
    if n not in text:
        raise SystemExit(f"FAIL: CloudBalanceRow missing: {n}")
print("PASS: SettingsView CloudBalanceRow — gated, module-visible, lazy + Refresh + quiet 'Estimated only'.")
PY
