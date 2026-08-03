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

require Sources/NativeBolabolCore/Services/RecordingTranscriptionWorkflow.swift
require Sources/NativeBolabolCore/Services/PolishingWorkflow.swift
require Sources/NativeBolabolCore/Support/SpeechCleanupNormalizer.swift
require Sources/NativeBolabolCore/Services/ModelOutputSanitizer.swift
require Sources/NativeBolabolCore/Services/LocalRuleBasedPolishingEngine.swift
require Sources/NativeBolabolCore/Services/TranscriptionLanguageRouting.swift
require Sources/NativeBolabol/Services/WhisperKitTranscriptionEngine.swift
require Sources/NativeBolabol/Services/ParakeetTranscriptionEngine.swift
require Sources/NativeBolabol/Services/MLXSwiftPolishingEngine.swift
require Sources/NativeBolabol/Services/AudioRecorder.swift
require Sources/NativeBolabol/Services/AudioFileImporter.swift

# Placeholder used by all polish prompts
if ! grep -q '\${transcription}' Sources/NativeBolabolCore/Services/PromptTemplate.swift; then
  echo "FAIL: PromptTemplate placeholder \${transcription} missing"
  fail=1
fi

# Backends
if ! grep -q 'localWhisper' Sources/NativeBolabolCore/Models/TranscriptionBackend.swift; then
  echo "FAIL: localWhisper backend missing"
  fail=1
fi
if ! grep -q 'geminiCloud' Sources/NativeBolabolCore/Models/TranscriptionBackend.swift; then
  echo "FAIL: geminiCloud backend missing"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "OK: transcription + polishing pipeline"
