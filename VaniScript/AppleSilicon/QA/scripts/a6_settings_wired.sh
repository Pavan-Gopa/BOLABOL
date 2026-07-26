#!/usr/bin/env bash
# A6: SettingsView apiKeysTab wires UsageStatisticsView(); old section title gone.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
start = text.find("private var apiKeysTab")
end = text.find("private var customProvidersSection")
if start < 0 or end <= start:
    raise SystemExit("FAIL: could not isolate apiKeysTab")
tab = text[start:end]
if "UsageStatisticsView()" not in tab:
    raise SystemExit("FAIL: UsageStatisticsView() not wired in apiKeysTab")
if 'SettingsSection(title: "Cloud Usage Statistics")' in tab:
    raise SystemExit("FAIL: old Cloud Usage Statistics SettingsSection still in apiKeysTab")
if 'SettingsSection(title: "Cloud Provider")' not in tab:
    raise SystemExit("FAIL: Cloud Provider section must remain")
if "ProviderCardView(descriptor:" not in tab:
    raise SystemExit("FAIL: ProviderCardView must remain in apiKeysTab")
print("PASS: apiKeysTab wires UsageStatisticsView(); provider card intact; old section removed.")
PY
