#!/usr/bin/env bash
# A3: "Cloud Usage Statistics" section still present (A6 territory — do not delete).
# Step-aware:
#   A3–A5 → old SettingsSection "Cloud Usage Statistics" + helpers present
#   A6+   → replaced by UsageStatisticsView (Electron tab 7); old section gone by design
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

STATE_FILE="AI_Workflow_Kit/docs/AI/STATE.yaml"
current_step=""
if [[ -f "$STATE_FILE" ]]; then
  current_step="$(sed -nE 's/^current_step:[[:space:]]*([A-Za-z0-9_]+).*/\1/p' "$STATE_FILE" | head -1)"
fi

python3 - "$current_step" <<'PY'
import re, sys
from pathlib import Path

step = (sys.argv[1] or "A3").strip()
a6_or_later = bool(re.match(r"^A([6-9]|\d{2,})$", step)) or step in (
    "A6", "A7", "A8", "APIUSAGE_DONE", "API_USAGE_DONE",
)

settings = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
start = settings.find("private var apiKeysTab")
end = settings.find("private var customProvidersSection")
if start < 0 or end <= start:
    raise SystemExit("FAIL: could not isolate apiKeysTab")
tab = settings[start:end]

if a6_or_later:
    usage_file = Path("Sources/VaniScript/Views/UsageStatisticsView.swift")
    if not usage_file.is_file():
        raise SystemExit("FAIL: A6+ expects UsageStatisticsView.swift")
    usage = usage_file.read_text(encoding="utf-8")
    if "struct UsageStatisticsView" not in usage:
        raise SystemExit("FAIL: A6+ UsageStatisticsView struct missing")
    if "UsageStatisticsView()" not in tab:
        raise SystemExit("FAIL: A6+ apiKeysTab must wire UsageStatisticsView()")
    if 'SettingsSection(title: "Cloud Usage Statistics")' in tab:
        raise SystemExit("FAIL: A6+ old Cloud Usage Statistics SettingsSection must be removed")
    print(f"PASS: A6+ stats replaced by UsageStatisticsView (step={step}; old section retired by design).")
else:
    if 'SettingsSection(title: "Cloud Usage Statistics")' not in tab:
        raise SystemExit("FAIL: Cloud Usage Statistics section missing from apiKeysTab")
    for needle in ("Reset All Statistics", "estimateCost", "StatItem", "BudgetBar"):
        if needle not in tab:
            raise SystemExit(f"FAIL: stats section marker missing: {needle}")
    if 'defaultProviders' not in tab and '["gemini", "openai", "anthropic"]' not in tab:
        raise SystemExit("FAIL: stats provider list appears removed/changed unexpectedly")
    print(f"PASS: Cloud Usage Statistics section still present in apiKeysTab (step={step}; A6 territory intact).")
PY
