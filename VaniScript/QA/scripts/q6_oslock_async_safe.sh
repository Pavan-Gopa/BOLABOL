#!/usr/bin/env bash
# QA: q6_oslock_async_safe.sh — Q6 uses async-safe OSAllocatedUnfairLock (not NSLock)
# Asserts:
#   1. QwenStreamingProvider state guarded by OSAllocatedUnfairLock(initialState: QwenStreamGuard())
#   2. `import os` present (OSAllocatedUnfairLock lives in os)
#   3. NSLock is NOT used in code (only allowed inside a comment explaining the choice)
#   4. lock.withLock used for state transitions
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE="$PROJECT_ROOT/AppleSilicon/Sources/VaniScriptCore/QwenAgentSupport.swift"

echo "=== q6_oslock_async_safe: OSAllocatedUnfairLock ==="
FAILURES=0

[ -f "$CORE" ] || { echo "FAIL: QwenAgentSupport.swift not found"; exit 1; }

# 1. OSAllocatedUnfairLock with QwenStreamGuard state
grep -q 'OSAllocatedUnfairLock(initialState: QwenStreamGuard())' "$CORE" || \
    { echo "FAIL: OSAllocatedUnfairLock(initialState: QwenStreamGuard()) not found"; FAILURES=$((FAILURES+1)); }

# 2. import os
grep -q '^import os' "$CORE" || \
    { echo "FAIL: 'import os' missing (needed for OSAllocatedUnfairLock)"; FAILURES=$((FAILURES+1)); }

# 3. NSLock must NOT appear in non-comment code lines
if grep -v '^[[:space:]]*//' "$CORE" | grep -q 'NSLock'; then
    echo "FAIL: NSLock used in code (must use async-safe OSAllocatedUnfairLock)"
    FAILURES=$((FAILURES+1))
fi

# 4. lock.withLock used
grep -q 'lock.withLock' "$CORE" || \
    { echo "FAIL: lock.withLock not used for state transitions"; FAILURES=$((FAILURES+1)); }

# QwenStreamGuard holds the Process + isCancelled
grep -q 'var activeProcess: Process?' "$CORE" || \
    { echo "FAIL: QwenStreamGuard.activeProcess missing"; FAILURES=$((FAILURES+1)); }
grep -q 'var isCancelled = false' "$CORE" || \
    { echo "FAIL: QwenStreamGuard.isCancelled missing"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: q6_oslock_async_safe — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: q6_oslock_async_safe — OSAllocatedUnfairLock used, no NSLock in code"
exit 0
