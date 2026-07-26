#!/usr/bin/env bash
set -euo pipefail

FILE="Sources/VaniScriptCore/AppSettings.swift"
for field in lastModel lastTransactionAt; do
  if ! grep -q "decodeIfPresent(.*, forKey: .$field)" "$FILE"; then
    echo "FAIL: $field is not using decodeIfPresent in ProviderUsage (AppSettings.swift)"
    exit 1
  fi
done
echo "PASS: ProviderUsage new fields use decodeIfPresent."
