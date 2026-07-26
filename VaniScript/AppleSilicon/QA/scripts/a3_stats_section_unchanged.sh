#!/usr/bin/env bash
# A3: "Cloud Usage Statistics" section still present (A6 territory — do not delete).
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
if 'SettingsSection(title: "Cloud Usage Statistics")' not in tab:
    raise SystemExit("FAIL: Cloud Usage Statistics section missing from apiKeysTab")
for needle in ("Reset All Statistics", "estimateCost", "StatItem", "BudgetBar"):
    if needle not in tab:
        raise SystemExit(f"FAIL: stats section marker missing: {needle}")
# defaultProviders list for stats should still exist (legacy stats surface)
if 'defaultProviders' not in tab and '["gemini", "openai", "anthropic"]' not in tab:
    raise SystemExit("FAIL: stats provider list appears removed/changed unexpectedly")
print("PASS: Cloud Usage Statistics section still present in apiKeysTab (A6 territory intact).")
PY
