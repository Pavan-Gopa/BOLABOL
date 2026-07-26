#!/usr/bin/env bash
# A3: @State selectedProviderId defaults to CloudProviderCatalog.geminiID.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

if ! grep -Eq '@State[[:space:]]+private[[:space:]]+var[[:space:]]+selectedProviderId[[:space:]]*=[[:space:]]*CloudProviderCatalog\.geminiID' "$FILE"; then
  echo "FAIL: selectedProviderId must default to CloudProviderCatalog.geminiID"
  exit 1
fi
echo "PASS: selectedProviderId defaults to geminiID."
