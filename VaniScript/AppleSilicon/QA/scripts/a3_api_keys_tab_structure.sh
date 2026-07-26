#!/usr/bin/env bash
# A3: apiKeysTab structure — Cloud Provider picker section, conditional card, stats.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
start = text.find("private var apiKeysTab")
end = text.find("private var customProvidersSection")
if start < 0 or end <= start:
    raise SystemExit("FAIL: apiKeysTab / customProvidersSection boundaries missing")
tab = text[start:end]
# Order: Cloud Provider section before stats
i_cp = tab.find('SettingsSection(title: "Cloud Provider")')
i_stats = tab.find('SettingsSection(title: "Cloud Usage Statistics")')
if i_cp < 0:
    raise SystemExit("FAIL: Cloud Provider section missing")
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
print("PASS: apiKeysTab structure = Cloud Provider picker → conditional card → stats.")
PY
