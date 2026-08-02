#!/usr/bin/env bash
# Release packaging identity (Blaboom naming, not NativeBlaboom prefix in product).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail=0

if [ ! -f script/build_release_dmg.sh ]; then
  echo "FAIL: build_release_dmg.sh missing"
  fail=1
fi

if ! grep -q 'Blaboom' script/build_release_dmg.sh README.md 2>/dev/null; then
  echo "FAIL: Blaboom product name missing from release scripts/README"
  fail=1
fi

# Info.plist product bits if present
if [ -f Sources/NativeBlaboom/Resources/Info.plist ]; then
  if ! grep -q 'CFBundle' Sources/NativeBlaboom/Resources/Info.plist; then
    echo "FAIL: Info.plist missing CFBundle keys"
    fail=1
  fi
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "OK: release identity"
