#!/usr/bin/env bash
# QA: q6_no_zombie.sh — Q6 register-before-start (no zombie / unkillable child)
# Asserts:
#   1. The active process is registered (under lock) BEFORE process.run() is called,
#      so a concurrent cancel() can always reach the pid.
#   2. A proceed guard throws .cancelled if cancel() raced ahead of launch.
#   3. activeProcess is cleared after completion (no stale reference -> no zombie tracking).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE="$PROJECT_ROOT/AppleSilicon/Sources/VaniScriptCore/QwenAgentSupport.swift"

echo "=== q6_no_zombie: register-before-start ==="
FAILURES=0

[ -f "$CORE" ] || { echo "FAIL: QwenAgentSupport.swift not found"; exit 1; }

# 1. Ordering: activeProcess registration line must come BEFORE process.run() line.
REG_LINE=$(grep -n '\$0.activeProcess = process' "$CORE" | head -1 | cut -d: -f1)
RUN_LINE=$(grep -n 'try process.run()' "$CORE" | head -1 | cut -d: -f1)
[ -n "$REG_LINE" ] || { echo "FAIL: no activeProcess registration found"; FAILURES=$((FAILURES+1)); }
[ -n "$RUN_LINE" ] || { echo "FAIL: no process.run() call found"; FAILURES=$((FAILURES+1)); }
if [ -n "$REG_LINE" ] && [ -n "$RUN_LINE" ]; then
    if [ "$REG_LINE" -ge "$RUN_LINE" ]; then
        echo "FAIL: activeProcess registered AFTER process.run() (line $REG_LINE >= $RUN_LINE) — cancel race window"
        FAILURES=$((FAILURES+1))
    fi
fi

# 2. proceed guard throws .cancelled
grep -q 'guard proceed else' "$CORE" || \
    { echo "FAIL: no proceed guard before launch"; FAILURES=$((FAILURES+1)); }
grep -q 'throw QwenChatError.cancelled' "$CORE" || \
    { echo "FAIL: cancelled race not surfaced as QwenChatError.cancelled"; FAILURES=$((FAILURES+1)); }

# 3. activeProcess cleared after completion
grep -q 'clear active process after completion' "$CORE" || \
    { echo "WARN: no explicit post-completion cleanup comment"; }

# The post-completion lock block must nil out activeProcess (second occurrence).
CLEAR_COUNT=$(grep -c '\$0.activeProcess = nil' "$CORE")
if [ "$CLEAR_COUNT" -lt 2 ]; then
    echo "FAIL: activeProcess not cleared in both cancel() and post-completion (found $CLEAR_COUNT, want >=2)"
    FAILURES=$((FAILURES+1))
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: q6_no_zombie — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: q6_no_zombie — register-before-start ordering verified (reg line $REG_LINE < run line $RUN_LINE)"
exit 0
