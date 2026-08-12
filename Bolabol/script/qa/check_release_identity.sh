#!/usr/bin/env bash
# Release packaging identity (Bolabol naming, not NativeBolabol prefix in product).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail=0

if [ ! -f script/build_release_dmg.sh ]; then
  echo "FAIL: build_release_dmg.sh missing"
  fail=1
fi

if ! grep -q 'Bolabol' script/build_release_dmg.sh README.md 2>/dev/null; then
  echo "FAIL: Bolabol product name missing from release scripts/README"
  fail=1
fi

# Info.plist product bits if present
if [ -f Sources/NativeBolabol/Resources/Info.plist ]; then
  if ! grep -q 'CFBundle' Sources/NativeBolabol/Resources/Info.plist; then
    echo "FAIL: Info.plist missing CFBundle keys"
    fail=1
  fi
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "OK: release identity"
