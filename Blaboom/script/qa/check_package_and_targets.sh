#!/usr/bin/env bash
# Package.swift targets and product surface.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail=0
for needle in NativeBlaboom NativeBlaboomCore NativeBlaboomPolishWorker NativeBlaboomCoreTests; do
  if ! grep -q "$needle" Package.swift; then
    echo "FAIL: Package.swift missing $needle"
    fail=1
  fi
done

# Source trees exist
for dir in Sources/NativeBlaboom Sources/NativeBlaboomCore Sources/NativeBlaboomPolishWorker Tests/NativeBlaboomCoreTests; do
  if [ ! -d "$dir" ]; then
    echo "FAIL: missing directory $dir"
    fail=1
  fi
done

# Polish worker entry
if [ ! -f Sources/NativeBlaboomPolishWorker/main.swift ]; then
  echo "FAIL: polish worker main.swift missing"
  fail=1
fi

# Core must not import AppKit/SwiftUI (keeps unit tests pure)
if grep -RIn --include='*.swift' -E '^import (AppKit|SwiftUI|Cocoa)' Sources/NativeBlaboomCore 2>/dev/null | grep -v '^$' >/dev/null; then
  echo "FAIL: NativeBlaboomCore imports AppKit/SwiftUI (breaks pure unit tests)"
  grep -RIn --include='*.swift' -E '^import (AppKit|SwiftUI|Cocoa)' Sources/NativeBlaboomCore || true
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "OK: package + targets"
