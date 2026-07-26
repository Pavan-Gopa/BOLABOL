#!/usr/bin/env bash
# A7 (§11/§14 honesty): no fake "$" for .estimated providers (Gemini/OpenAI/Anthropic/Qwen/Custom).
# The A6 estimated path (disclaimer + estimated cards) stays intact; balance row only for real kinds.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
USAGE="Sources/VaniScript/Views/UsageStatisticsView.swift"
SETTINGS="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$USAGE" ]] || { echo "FAIL: $USAGE missing"; exit 1; }
[[ -f "$SETTINGS" ]] || { echo "FAIL: $SETTINGS missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
usage = Path("Sources/VaniScript/Views/UsageStatisticsView.swift").read_text(encoding="utf-8")
settings = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")

# A6 estimated path still present (disclaimer + estimated spend) — A7 must not remove it.
if "provider billing can differ" not in usage:
    raise SystemExit("FAIL: A6 estimated disclaimer missing from UsageStatisticsView (estimated path broken)")
# Balance row is gated to real kinds only — estimated providers never get a CloudBalanceRow.
if "descriptor.balanceKind == .openrouterCredits" not in usage:
    raise SystemExit("FAIL: UsageStatisticsView must gate balance on real kinds")
if "descriptor.balanceKind == .openrouterCredits || descriptor.balanceKind == .ollamaPlan" not in settings:
    raise SystemExit("FAIL: SettingsView must gate balance row on real kinds only")
# Ollama plan label is honest (no $ fabricated for a plan-based provider).
core = Path("Sources/VaniScriptCore/CloudBalanceService.swift").read_text(encoding="utf-8")
if "Plan-based (GPU time)" not in core:
    raise SystemExit("FAIL: Ollama honest plan label missing")
print("PASS: no fake $ for estimated providers; A6 estimated path intact; balance gated to real kinds.")
PY
