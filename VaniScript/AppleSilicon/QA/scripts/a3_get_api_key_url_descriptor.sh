#!/usr/bin/env bash
# A3: Get API Key URL comes from descriptor.getApiKeyURL (catalog SSOT).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

# ProviderCardView must pass descriptor.getApiKeyURL into ApiKeyInputRow
count=$(grep -c 'urlString: descriptor.getApiKeyURL' "$FILE" || true)
if [[ "$count" -lt 1 ]]; then
  echo "FAIL: ApiKeyInputRow must use descriptor.getApiKeyURL (got $count matches)"
  exit 1
fi
# Catalog still defines getApiKeyURL on descriptors
grep -Fq 'getApiKeyURL' "Sources/VaniScriptCore/CloudProviderCatalog.swift" || {
  echo "FAIL: CloudProviderCatalog missing getApiKeyURL"; exit 1
}
echo "PASS: Get API Key URL sourced from descriptor.getApiKeyURL ($count call sites)."
