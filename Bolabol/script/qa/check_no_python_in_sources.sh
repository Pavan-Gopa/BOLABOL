#!/usr/bin/env bash
# Enforces that Sources/ contains zero Python files, zero Python imports,
# and zero Process spawning of python/pip/nemo binaries.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

SOURCES="Sources"
[ -d "$SOURCES" ] || { echo "FAIL: $SOURCES directory not found"; exit 1; }

FAILED=0

# 1. No .py files or __pycache__ in Sources
py_files=$(find "$SOURCES" -type f \( -name "*.py" -o -name "*.pyc" \) 2>/dev/null || true)
if [ -n "$py_files" ]; then
  echo "FAIL: Found Python files inside $SOURCES:"
  echo "$py_files"
  FAILED=1
fi

# 2. No Python/process execution in Swift sources
if grep -rnE "\bpython[0-9.]*\b|\bpip[0-9.]*\b|\bnemo\b|/usr/bin/env python" "$SOURCES"; then
  echo "FAIL: Found Python reference/invocation in $SOURCES"
  FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
  echo "FAIL: Python contract broken in Sources/"
  exit 1
fi

echo "OK: Sources/ is 100% native Swift with zero Python files or runtime invocations"
