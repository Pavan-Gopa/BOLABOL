#!/usr/bin/env bash
# QA: regression_swift_test.sh — Full Swift test suite regression
# Asserts: All VaniScriptCoreTests pass (257 tests across 39 suites)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AS_DIR="$PROJECT_ROOT/AppleSilicon"

echo "=== regression_swift_test: full swift test suite ==="
cd "$AS_DIR"
swift test 2>&1
echo "PASS: regression_swift_test — all Swift tests green"
exit 0
