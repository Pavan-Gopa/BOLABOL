#!/usr/bin/env bash
# App stores that bridge Core models to UI must exist.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail=0
for store in \
  AccessibilityPermissionStore \
  GeneralSettingsStore \
  HotkeySettingsStore \
  PolishingEngineStore \
  PromptTemplateStore \
  TranscriptionEngineStore \
  TranscriptionModelStore \
  UsageStatisticsStore; do
  if [ ! -f "Sources/NativeBolabol/Stores/${store}.swift" ]; then
    echo "FAIL: missing store $store"
    fail=1
  fi
done

# Core stores
for store in NoteStore GlossaryStore; do
  if [ ! -f "Sources/NativeBolabolCore/Stores/${store}.swift" ]; then
    echo "FAIL: missing Core store $store"
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "OK: stores wiring"
