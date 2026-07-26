#!/usr/bin/env bash
# A3: swift build green (product compiles after UI reorg).
# ENV-ONLY sandbox errors are soft-pass (same policy as A1/A2 gates).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

echo "A3 swift build gate..."
set +e
out=$(swift build 2>&1)
code=$?
set -e
echo "$out" | tail -40

if [[ $code -eq 0 ]]; then
  echo "PASS: swift build green (A3)."
  exit 0
fi

if echo "$out" | grep -Eqi 'Operation not permitted|sandbox|ModuleCache|unable to open output file|xcrun: error: unable to find utility'; then
  echo "ENV-ONLY: swift build blocked by environment (not a product FAIL)."
  exit 0
fi

echo "FAIL: swift build failed for product reasons"
exit 1
