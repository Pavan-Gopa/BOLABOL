#!/usr/bin/env bash
# Ensure test suite covers major Core modules by presence of dedicated tests.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

TEST_DIR="Tests/NativeBlaboomCoreTests"
fail=0

required_test_patterns=(
  APIProvider
  Hotkey
  Glossary
  NoteStore
  Polishing
  Transcription
  ProviderQuick
  HUD
  Cloud
  Prompt
  Usage
  AppText
  Domain
  Starter
  LocalRule
  SharedModel
  Workflow
  Recording
  Onboarding
  Release
)

for pat in "${required_test_patterns[@]}"; do
  if ! ls "$TEST_DIR"/*${pat}* >/dev/null 2>&1 && ! ls "$TEST_DIR"/*$(echo "$pat" | tr '[:upper:]' '[:lower:]')* >/dev/null 2>&1; then
    # softer: grep content for pattern in any test file
    if ! grep -ql "$pat" "$TEST_DIR"/*.swift 2>/dev/null; then
      echo "WARN/FAIL: no test file referencing $pat"
      fail=1
    fi
  fi
done

test_count=$(find "$TEST_DIR" -name '*.swift' | wc -l | tr -d ' ')
if [ "$test_count" -lt 40 ]; then
  echo "FAIL: only $test_count test files (expected ≥ 40)"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "OK: test breadth ($test_count test files)"
