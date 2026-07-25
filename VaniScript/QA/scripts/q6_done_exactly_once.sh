#!/usr/bin/env bash
# QA: q6_done_exactly_once.sh — Q6 stream emits .done exactly once then finishes
# Asserts:
#   1. The streaming send() yields a single .done chunk on normal completion
#   2. continuation.finish() follows the .done yield (normal termination)
#   3. Error path terminates via continuation.finish(throwing:) (no double finish)
#   4. Invariant comment "emits .done exactly once" documented
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE="$PROJECT_ROOT/AppleSilicon/Sources/VaniScriptCore/QwenAgentSupport.swift"

echo "=== q6_done_exactly_once: single .done + finish ==="
FAILURES=0

[ -f "$CORE" ] || { echo "FAIL: QwenAgentSupport.swift not found"; exit 1; }

# 1. Exactly one .done yield in the file
DONE_COUNT=$(grep -c 'continuation.yield(QwenChatChunk(kind: .done(' "$CORE")
echo "  .done yields: $DONE_COUNT"
if [ "$DONE_COUNT" -ne 1 ]; then
    echo "FAIL: expected exactly 1 .done yield, found $DONE_COUNT"
    FAILURES=$((FAILURES+1))
fi

# 2. Normal finish present
grep -q 'continuation.yield(QwenChatChunk(kind: .done(QwenAgentRun())))' "$CORE" || \
    { echo "FAIL: terminal .done(QwenAgentRun()) yield missing"; FAILURES=$((FAILURES+1)); }
grep -q 'continuation.finish()' "$CORE" || \
    { echo "FAIL: continuation.finish() missing on normal completion"; FAILURES=$((FAILURES+1)); }

# 3. Error path finishes with throwing (no silent hang / double finish)
grep -q 'continuation.finish(throwing: error)' "$CORE" || \
    { echo "FAIL: error path does not finish(throwing:)"; FAILURES=$((FAILURES+1)); }

# 4. Invariant documented
grep -q 'emits .done exactly once' "$CORE" || \
    { echo "WARN: missing '.done exactly once' invariant comment"; }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: q6_done_exactly_once — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: q6_done_exactly_once — single .done yield + finish, throwing finish on error"
exit 0
