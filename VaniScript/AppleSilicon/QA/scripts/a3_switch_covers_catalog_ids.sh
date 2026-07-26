#!/usr/bin/env bash
# A3: ProviderCardView switch uses catalog ID constants; catalog still has all 7 providers.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

# Catalog order regression (A1)
ORDER_FILE="Sources/VaniScriptCore/CloudProviderCatalog.swift"
grep -q 'geminiID, openaiID, anthropicID, qwenID, openrouterID, ollamaCloudID, customID' "$ORDER_FILE" || {
  echo "FAIL: catalog fixed order broken (A1 regression)"
  exit 1
}

FILE="Sources/VaniScript/Views/SettingsView.swift"
for id in geminiID openaiID anthropicID customID; do
  grep -Fq "CloudProviderCatalog.$id" "$FILE" || {
    echo "FAIL: SettingsView missing CloudProviderCatalog.$id reference"
    exit 1
  }
done
# stub ids in apiKeyPath
for id in qwenID openrouterID ollamaCloudID; do
  grep -Fq "CloudProviderCatalog.$id" "$FILE" || {
    echo "FAIL: SettingsView missing CloudProviderCatalog.$id for stub key mapping"
    exit 1
  }
done
echo "PASS: catalog IDs used in SettingsView; fixed order intact."
