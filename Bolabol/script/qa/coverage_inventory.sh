#!/usr/bin/env bash
# Reproducible SwiftPM source coverage inventory. Use --refresh to regenerate
# the profile before reporting; otherwise the latest local coverage run is used.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [ "${1:-}" = "--refresh" ]; then
  swift test --enable-code-coverage
fi

BIN_PATH="$(swift build --show-bin-path)"
PROFILE="$BIN_PATH/codecov/default.profdata"
TEST_BINARY="$BIN_PATH/NativeBolabolPackageTests.xctest/Contents/MacOS/NativeBolabolPackageTests"

if [ ! -f "$PROFILE" ]; then
  echo "BLOCKED_BY_ARTIFACT: missing coverage profile: $PROFILE" >&2
  echo "Run: $0 --refresh" >&2
  exit 2
fi
if [ ! -x "$TEST_BINARY" ]; then
  echo "BLOCKED_BY_ARTIFACT: missing test binary: $TEST_BINARY" >&2
  echo "Run: $0 --refresh" >&2
  exit 2
fi

xcrun llvm-cov report "$TEST_BINARY" \
  -instr-profile="$PROFILE" \
  -ignore-filename-regex='(.build|Tests|scratch|docs)/'
