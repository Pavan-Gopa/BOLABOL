#!/usr/bin/env bash
# A3: apiKeysTab structure — Cloud Provider picker section, conditional card, stats.
# Step-aware:
#   A3–A5 → stats = SettingsSection("Cloud Usage Statistics")
#   A6+   → stats = UsageStatisticsView() after provider card
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"

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

text = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
start = text.find("private var apiKeysTab")
end = text.find("private var customProvidersSection")
if start < 0 or end <= start:
    raise SystemExit("FAIL: apiKeysTab / customProvidersSection boundaries missing")
tab = text[start:end]

i_cp = tab.find('SettingsSection(title: "Cloud Provider")')
if i_cp < 0:
    raise SystemExit("FAIL: Cloud Provider section missing")

if a6_or_later:
    i_stats = tab.find("UsageStatisticsView()")
    if i_stats < 0:
        raise SystemExit("FAIL: A6+ UsageStatisticsView() missing from apiKeysTab")
    if not (i_cp < i_stats):
        raise SystemExit("FAIL: Cloud Provider section should appear before UsageStatisticsView")
else:
    i_stats = tab.find('SettingsSection(title: "Cloud Usage Statistics")')
    if i_stats < 0:
        raise SystemExit("FAIL: Cloud Usage Statistics missing")
    if not (i_cp < i_stats):
        raise SystemExit("FAIL: Cloud Provider section should appear before Cloud Usage Statistics")

# Picker before conditional card
i_picker = tab.find('Picker("Provider"')
i_custom = tab.find("CloudProviderCatalog.customID")
i_card = tab.find("ProviderCardView(descriptor:")
if i_picker < 0 or i_custom < 0 or i_card < 0:
    raise SystemExit("FAIL: picker/custom/card pieces missing from apiKeysTab")
if not (i_picker < i_custom and i_picker < i_card):
    raise SystemExit("FAIL: Picker should appear before conditional card branches")

label = "UsageStatisticsView" if a6_or_later else "stats"
print(f"PASS: apiKeysTab structure = Cloud Provider picker → conditional card → {label} (step={step}).")
PY
