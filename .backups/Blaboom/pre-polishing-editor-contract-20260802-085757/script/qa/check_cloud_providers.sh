#!/usr/bin/env bash
# Cloud polishing provider surface: kinds, engines, UI order.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail=0
API="Sources/NativeBlaboomCore/Models/APIProviderSettings.swift"

for kind in google openAI qwen openRouter custom; do
  if ! grep -q "case $kind" "$API"; then
    echo "FAIL: missing APIProviderKind.$kind"
    fail=1
  fi
done

for engine in cloud-google cloud-openai cloud-qwen cloud-openrouter cloud-custom; do
  if ! grep -q "$engine" "$API"; then
    echo "FAIL: missing polishingEngineID $engine"
    fail=1
  fi
done

# UI order Google → OpenAI → Qwen → OpenRouter → Custom
if ! grep -q 'polishingUICases.*=.*\[\.google, \.openAI, \.qwen, \.openRouter, \.custom\]' "$API"; then
  echo "FAIL: polishingUICases order drifted"
  fail=1
fi

# App has API settings view + cloud engines
for f in \
  Sources/NativeBlaboom/Views/Settings/APIProvidersSettingsView.swift \
  Sources/NativeBlaboom/Services/CloudTextPolishingEngine.swift \
  Sources/NativeBlaboom/Services/CloudProviderModelCatalog.swift \
  Sources/NativeBlaboom/Services/GeminiCloudDictationEngine.swift; do
  if [ ! -f "$f" ]; then
    echo "FAIL: missing $f"
    fail=1
  fi
done

# Qwen Token Plan default base URL
if ! grep -q 'token-plan' "$API"; then
  echo "FAIL: Qwen Token Plan base URL missing"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "OK: cloud provider surface"
