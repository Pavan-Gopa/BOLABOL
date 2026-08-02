#!/usr/bin/env bash
# Blaboom full QA gate: unit tests + structural contract scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

echo "========================================"
echo " Blaboom QA — unit tests + contracts"
echo "========================================"
echo "Root: $ROOT"
echo

FAILED=0
PASSED=0

run_step() {
  local name="$1"
  shift
  echo "→ $name"
  if "$@"; then
    echo "  ✓ $name"
    PASSED=$((PASSED + 1))
  else
    echo "  ✗ $name"
    FAILED=$((FAILED + 1))
  fi
  echo
}

# 1) Swift unit tests (NativeBlaboomCore)
run_step "swift test (NativeBlaboomCoreTests)" swift test

# 2) Structural / source contracts
for script in "$ROOT"/script/qa/check_*.sh; do
  [ -f "$script" ] || continue
  name="$(basename "$script")"
  run_step "$name" bash "$script"
done

echo "========================================"
echo " Passed: $PASSED  Failed: $FAILED"
echo "========================================"

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
