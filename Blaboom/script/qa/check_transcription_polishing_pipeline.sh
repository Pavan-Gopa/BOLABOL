#!/usr/bin/env bash
# Transcription → polishing pipeline Core contracts.
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

require Sources/NativeBlaboomCore/Services/RecordingTranscriptionWorkflow.swift
require Sources/NativeBlaboomCore/Services/PolishingWorkflow.swift
require Sources/NativeBlaboomCore/Support/SpeechCleanupNormalizer.swift
require Sources/NativeBlaboomCore/Services/ModelOutputSanitizer.swift
require Sources/NativeBlaboomCore/Services/LocalRuleBasedPolishingEngine.swift
require Sources/NativeBlaboomCore/Services/TranscriptionLanguageRouting.swift
require Sources/NativeBlaboom/Services/WhisperKitTranscriptionEngine.swift
require Sources/NativeBlaboom/Services/ParakeetTranscriptionEngine.swift
require Sources/NativeBlaboom/Services/MLXSwiftPolishingEngine.swift
require Sources/NativeBlaboom/Services/AudioRecorder.swift
require Sources/NativeBlaboom/Services/AudioFileImporter.swift

# Placeholder used by all polish prompts
if ! grep -q '\${transcription}' Sources/NativeBlaboomCore/Services/PromptTemplate.swift; then
  echo "FAIL: PromptTemplate placeholder \${transcription} missing"
  fail=1
fi

# Backends
if ! grep -q 'localWhisper' Sources/NativeBlaboomCore/Models/TranscriptionBackend.swift; then
  echo "FAIL: localWhisper backend missing"
  fail=1
fi
if ! grep -q 'geminiCloud' Sources/NativeBlaboomCore/Models/TranscriptionBackend.swift; then
  echo "FAIL: geminiCloud backend missing"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "OK: transcription + polishing pipeline"
