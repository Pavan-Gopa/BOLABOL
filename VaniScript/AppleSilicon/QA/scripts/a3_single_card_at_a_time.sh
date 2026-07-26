#!/usr/bin/env bash
# A3: only ONE provider card rendered at a time (conditional on selectedProviderId),
# not all provider sections always expanded.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

# Conditional branch for Custom vs ProviderCardView
grep -Fq 'if selectedProviderId == CloudProviderCatalog.customID' "$FILE" || {
  echo "FAIL: missing Custom branch on selectedProviderId"
  exit 1
}
grep -Fq 'ProviderCardView(descriptor:' "$FILE" || {
  echo "FAIL: missing ProviderCardView(descriptor:) render path"
  exit 1
}
# Exactly one call site for ProviderCardView(descriptor: in SettingsView (the card, not the struct)
count=$(grep -c 'ProviderCardView(descriptor:' "$FILE" || true)
if [[ "$count" -ne 1 ]]; then
  echo "FAIL: expected exactly 1 ProviderCardView(descriptor:) call site, got $count"
  exit 1
fi
# Old always-expanded multi-section pattern should not remain in apiKeysTab as separate always-on sections.
# Heuristic: no simultaneous standalone SettingsSection titles for all of Google Gemini + OpenAI + Anthropic in apiKeysTab.
# ProviderCardView uses descriptor.label dynamically — OK. Fail if we still have 3 separate always-rendered section titles outside the switch.
# Check that apiKeysTab does not contain hardcoded "Google Gemini" SettingsSection alongside "OpenAI" as siblings always shown.
python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
# Isolate apiKeysTab through customProvidersSection start
start = text.find("private var apiKeysTab")
end = text.find("private var customProvidersSection")
if start < 0 or end < 0 or end <= start:
    raise SystemExit("FAIL: could not isolate apiKeysTab")
tab = text[start:end]
# Must not have multiple always-on provider SettingsSection titles for gemini/openai/anthropic outside conditionals
# After A3, apiKeysTab should only have "Cloud Provider" + optional card + "Cloud Usage Statistics"
if tab.count('SettingsSection(title: "Google Gemini"') > 0:
    raise SystemExit("FAIL: always-expanded 'Google Gemini' section still in apiKeysTab")
if tab.count('SettingsSection(title: "OpenAI"') > 0:
    raise SystemExit("FAIL: always-expanded 'OpenAI' section still in apiKeysTab")
if tab.count('SettingsSection(title: "Anthropic"') > 0:
    raise SystemExit("FAIL: always-expanded 'Anthropic' section still in apiKeysTab")
if "Cloud Provider" not in tab:
    raise SystemExit("FAIL: 'Cloud Provider' section missing from apiKeysTab")
print("PASS: apiKeysTab renders one card via selectedProviderId (not always-expanded sections).")
PY
