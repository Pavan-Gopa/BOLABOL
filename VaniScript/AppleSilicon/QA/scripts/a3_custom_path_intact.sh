#!/usr/bin/env bash
# A3: Custom path still has add/remove custom providers (mechanism unchanged).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

grep -Fq 'private var customProvidersSection' "$FILE" || {
  echo "FAIL: customProvidersSection missing"; exit 1
}
grep -Fq 'Add Custom Provider' "$FILE" || {
  echo "FAIL: Add Custom Provider button missing"; exit 1
}
grep -Fq 'addCustomProvider()' "$FILE" || {
  echo "FAIL: addCustomProvider() not wired"; exit 1
}
# Remove path
grep -Fq 'customCloudProviders.removeAll' "$FILE" || {
  echo "FAIL: remove custom provider (removeAll) missing"; exit 1
}
# Only shown when Custom selected
grep -Fq 'customProvidersSection' "$FILE" || {
  echo "FAIL: customProvidersSection not referenced"; exit 1
}
if ! grep -A2 'selectedProviderId == CloudProviderCatalog.customID' "$FILE" | grep -q 'customProvidersSection'; then
  echo "FAIL: customProvidersSection not gated by customID selection"
  exit 1
fi
echo "PASS: Custom path retains add/remove and is gated by customID."
