#!/usr/bin/env bash
# QA: regression_test_count.sh — Verify test suite count
# Asserts:
#   1. At least 39 test files in VaniScriptCoreTests
#   2. Key test files exist: McpSecurityContractTests, QwenAgentSupportTests,
#      CodexAgentSupportTests, GrokAgentSupportTests, UniversalSettingsTests
#   3. Test target defined in Package.swift
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AS_DIR="$PROJECT_ROOT/AppleSilicon"
TESTS_DIR="$AS_DIR/Tests/VaniScriptCoreTests"

echo "=== regression_test_count: test suite count ==="
FAILURES=0

# 1. Count test files
TEST_COUNT=$(ls "$TESTS_DIR"/*Tests.swift 2>/dev/null | wc -l | tr -d ' ')
echo "  Test files found: $TEST_COUNT"
if [ "$TEST_COUNT" -lt 39 ]; then
    echo "FAIL: Expected >= 39 test files, found $TEST_COUNT"
    FAILURES=$((FAILURES+1))
fi

# 2. Key test files
for TF in "McpSecurityContractTests.swift" "QwenAgentSupportTests.swift" "CodexAgentSupportTests.swift" "GrokAgentSupportTests.swift" "UniversalSettingsTests.swift" "ProviderRegistryTests.swift"; do
    [ -f "$TESTS_DIR/$TF" ] || { echo "FAIL: $TF not found"; FAILURES=$((FAILURES+1)); }
done

# 3. Test target in Package.swift
grep -q 'testTarget' "$AS_DIR/Package.swift" || { echo "FAIL: testTarget not in Package.swift"; FAILURES=$((FAILURES+1)); }
grep -q 'VaniScriptCoreTests' "$AS_DIR/Package.swift" || { echo "FAIL: VaniScriptCoreTests not in Package.swift"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: regression_test_count — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: regression_test_count — $TEST_COUNT test files verified (>= 39)"
exit 0
