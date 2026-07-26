#!/usr/bin/env bash
set -euo pipefail

FILE="Sources/VaniScriptCore/CloudProviderCatalog.swift"
if ! grep -q 'geminiID, openaiID, anthropicID, qwenID, openrouterID, ollamaCloudID, customID' "$FILE"; then
  echo "FAIL: providerOrder does not match the exact approved order in $FILE"
  exit 1
fi
echo "PASS: CloudProviderCatalog fixed order is correct."
