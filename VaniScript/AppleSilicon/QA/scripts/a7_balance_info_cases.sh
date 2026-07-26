#!/usr/bin/env bash
# A7 (§11): BalanceInfo has exactly .usd(remaining:total:) / .planLimits(label:detail:) / .unavailable,
# Equatable + Sendable (so SwiftUI state and unit tests can compare).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/CloudBalanceService.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScriptCore/CloudBalanceService.swift").read_text(encoding="utf-8")
if "public enum BalanceInfo" not in text:
    raise SystemExit("FAIL: public enum BalanceInfo missing")
if "Equatable" not in text or "Sendable" not in text:
    raise SystemExit("FAIL: BalanceInfo must be Equatable + Sendable")
for n in (
    "case usd(remaining: Double, total: Double?)",
    "case planLimits(label: String, detail: String)",
    "case unavailable",
):
    if n not in text:
        raise SystemExit(f"FAIL: BalanceInfo missing case: {n}")
print("PASS: BalanceInfo = .usd(remaining:total:) / .planLimits(label:detail:) / .unavailable (Equatable+Sendable).")
PY
