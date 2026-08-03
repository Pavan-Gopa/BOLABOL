#!/usr/bin/env bash
# Package.swift targets and product surface.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail=0
for needle in NativeBolabol NativeBolabolCore NativeBolabolPolishWorker NativeBolabolCoreTests; do
  if ! grep -q "$needle" Package.swift; then
    echo "FAIL: Package.swift missing $needle"
    fail=1
  fi
done

# Source trees exist
for dir in Sources/NativeBolabol Sources/NativeBolabolCore Sources/NativeBolabolPolishWorker Tests/NativeBolabolCoreTests; do
  if [ ! -d "$dir" ]; then
    echo "FAIL: missing directory $dir"
    fail=1
  fi
done

# Polish worker entry
if [ ! -f Sources/NativeBolabolPolishWorker/main.swift ]; then
  echo "FAIL: polish worker main.swift missing"
  fail=1
fi

# Core must not import AppKit/SwiftUI (keeps unit tests pure)
if grep -RIn --include='*.swift' -E '^import (AppKit|SwiftUI|Cocoa)' Sources/NativeBolabolCore 2>/dev/null | grep -v '^$' >/dev/null; then
  echo "FAIL: NativeBolabolCore imports AppKit/SwiftUI (breaks pure unit tests)"
  grep -RIn --include='*.swift' -E '^import (AppKit|SwiftUI|Cocoa)' Sources/NativeBolabolCore || true
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "OK: package + targets"
