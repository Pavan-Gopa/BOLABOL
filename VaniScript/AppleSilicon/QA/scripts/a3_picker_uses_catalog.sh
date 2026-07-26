#!/usr/bin/env bash
# A3: Provider Picker iterates CloudProviderCatalog.providers (fixed catalog order),
# not a hardcoded gemini/openai-only list.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

# Extract apiKeysTab body (from "private var apiKeysTab" to next top-level private var at same indent)
# Simple: assert ForEach(CloudProviderCatalog.providers) inside SettingsView near selectedProviderId.
grep -Fq 'ForEach(CloudProviderCatalog.providers)' "$FILE" || {
  echo "FAIL: Picker must ForEach(CloudProviderCatalog.providers) for catalog order"
  exit 1
}
grep -Fq 'Picker("Provider", selection: $selectedProviderId)' "$FILE" || {
  echo "FAIL: Picker(\"Provider\", selection: \$selectedProviderId) missing"
  exit 1
}
# Must NOT hardcode only gemini/openai tags in the picker path.
if grep -n 'Text("Google Gemini").tag("gemini")' "$FILE" >/dev/null 2>&1 && ! grep -Fq 'CloudProviderCatalog.providers' "$FILE"; then
  echo "FAIL: hardcoded provider tags without catalog"
  exit 1
fi
echo "PASS: Provider Picker uses CloudProviderCatalog.providers (catalog order)."
