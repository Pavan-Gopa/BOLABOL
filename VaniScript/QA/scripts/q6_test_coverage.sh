#!/usr/bin/env bash
# QA: q6_test_coverage.sh — Q6 unit tests present and green
# Asserts:
#   1. The 6 new Q6 test functions exist in QwenAgentSupportTests.swift:
#      chatChunkTextEquatable, chatChunkDoneCarriesRun, chatErrorDescriptions,
#      chatErrorUpstreamMessage, chatHistoryItemEquatable, cancelIdempotentNoProcess
#   2. swift test --filter QwenAgentSupportTests passes (whole suite green)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AS_DIR="$PROJECT_ROOT/AppleSilicon"
TESTS="$AS_DIR/Tests/VaniScriptCoreTests/QwenAgentSupportTests.swift"

echo "=== q6_test_coverage: Q6 unit tests ==="
FAILURES=0

[ -f "$TESTS" ] || { echo "FAIL: QwenAgentSupportTests.swift not found"; exit 1; }

# 1. Six Q6 test functions present
for T in "chatChunkTextEquatable" "chatChunkDoneCarriesRun" "chatErrorDescriptions" \
         "chatErrorUpstreamMessage" "chatHistoryItemEquatable" "cancelIdempotentNoProcess"; do
    grep -q "func $T" "$TESTS" || { echo "FAIL: Q6 test $T missing"; FAILURES=$((FAILURES+1)); }
done

# Count @Test attributes in the file (>= 13 total: 7 pre-Q6 + 6 Q6)
TEST_COUNT=$(grep -c '@Test(' "$TESTS")
echo "  @Test count in QwenAgentSupportTests: $TEST_COUNT"
if [ "$TEST_COUNT" -lt 13 ]; then
    echo "FAIL: expected >= 13 @Test cases, found $TEST_COUNT"
    FAILURES=$((FAILURES+1))
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: q6_test_coverage — $FAILURES check(s) failed"
    exit 1
fi

# 2. Run the suite
echo "  running: swift test --filter QwenAgentSupportTests"
cd "$AS_DIR"
swift test --filter QwenAgentSupportTests 2>&1

echo "PASS: q6_test_coverage — 6 Q6 tests present and QwenAgentSupportTests green"
exit 0
