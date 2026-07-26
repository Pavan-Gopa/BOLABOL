#!/usr/bin/env bash
set -euo pipefail

FILE="Sources/VaniScriptCore/AppSettings.swift"
for field in qwenApiKey qwenCloudModel qwenBudgetUsd openrouterApiKey openrouterModel openrouterBudgetUsd ollamaCloudApiKey ollamaCloudModel ollamaCloudBaseUrl geminiTextModel openaiTextModel; do
  if ! grep -q "decodeIfPresent(.*, forKey: .$field)" "$FILE"; then
    echo "FAIL: $field is not using decodeIfPresent in AppSettings.swift"
    exit 1
  fi
done
echo "PASS: All A1 AppSettings fields use decodeIfPresent."
