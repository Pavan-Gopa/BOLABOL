#!/usr/bin/env bash
# Polishing prompt/generation policy wiring (anti-chat contract).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail=0
require() {
  if [ ! -f "$1" ]; then
    echo "FAIL: missing $1"
    fail=1
  fi
}

require Sources/NativeBolabolCore/Services/PolishingRequestPolicy.swift
require Tests/NativeBolabolCoreTests/PolishingRequestPolicyTests.swift

# Policy types exist
for needle in PolishingPromptPolicy PolishingGenerationPolicy editorSystemInstruction \
  cloudTemperature instructionRole googleThinkingLevel qwenThinkingEnabled; do
  if ! grep -q "$needle" Sources/NativeBolabolCore/Services/PolishingRequestPolicy.swift; then
    echo "FAIL: policy symbol missing: $needle"
    fail=1
  fi
done

# Cloud engine must prepare prompts via policy and use generation policy
CLOUD=Sources/NativeBolabol/Services/CloudTextPolishingEngine.swift
for needle in PolishingPromptPolicy.prepare PolishingGenerationPolicy.cloudTemperature \
  PolishingGenerationPolicy.instructionRole PolishingGenerationPolicy.qwenThinkingEnabled \
  PolishingGenerationPolicy.googleThinkingLevel; do
  if ! grep -q "$needle" "$CLOUD"; then
    echo "FAIL: CloudTextPolishingEngine missing $needle"
    fail=1
  fi
done

# Local MLX worker must use the same prompt + local temperature policy
WORKER=Sources/NativeBolabolPolishWorker/main.swift
for needle in PolishingPromptPolicy.prepare PolishingGenerationPolicy.localTemperature; do
  if ! grep -q "$needle" "$WORKER"; then
    echo "FAIL: PolishWorker missing $needle"
    fail=1
  fi
done

# renderForChat must refuse elevating ${transcription} into system when it appears before INPUT:
if ! grep -q 'Never elevate source text' Sources/NativeBolabolCore/Services/PromptTemplate.swift \
  && ! grep -q 'Never elevate' Sources/NativeBolabolCore/Services/PromptTemplate.swift; then
  if ! grep -q 'systemInstruction: ""' Sources/NativeBolabolCore/Services/PromptTemplate.swift; then
    echo "FAIL: PromptTemplate.renderForChat safety guard not found"
    fail=1
  fi
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "OK: polishing request policy wiring"
