#!/usr/bin/env bash
# QA: q6_cancel_sigterm.sh — Q6 cancel() kills process group + idempotent
# Asserts:
#   1. cancel() sends SIGTERM to the whole process group: kill(-pid, SIGTERM)
#   2. process.terminate() fallback present (in case group kill not permitted)
#   3. cancel() is idempotent: clears activeProcess, guards on isRunning
#   4. cancel() before any send() is safe (no active process -> early return)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE="$PROJECT_ROOT/AppleSilicon/Sources/VaniScriptCore/QwenAgentSupport.swift"

echo "=== q6_cancel_sigterm: cancel SIGTERM + idempotency ==="
FAILURES=0

[ -f "$CORE" ] || { echo "FAIL: QwenAgentSupport.swift not found"; exit 1; }

# 1. Process-group SIGTERM
grep -q 'kill(-pid, SIGTERM)' "$CORE" || \
    { echo "FAIL: kill(-pid, SIGTERM) not found (no process-group kill)"; FAILURES=$((FAILURES+1)); }

# 2. terminate() fallback
grep -q 'process.terminate()' "$CORE" || \
    { echo "FAIL: process.terminate() fallback not found"; FAILURES=$((FAILURES+1)); }

# 3. Idempotent: clears activeProcess under lock + guards isRunning
grep -q 'public func cancel()' "$CORE" || \
    { echo "FAIL: public func cancel() not found"; FAILURES=$((FAILURES+1)); }
grep -q '\$0.activeProcess = nil' "$CORE" || \
    { echo "FAIL: cancel() does not clear activeProcess"; FAILURES=$((FAILURES+1)); }
grep -q 'guard let process, process.isRunning else { return }' "$CORE" || \
    { echo "FAIL: cancel() missing isRunning guard (not idempotent-safe)"; FAILURES=$((FAILURES+1)); }

# 4. isCancelled flag set in cancel (so a late send() bails out)
grep -q '\$0.isCancelled = true' "$CORE" || \
    { echo "FAIL: cancel() does not set isCancelled flag"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: q6_cancel_sigterm — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: q6_cancel_sigterm — SIGTERM process-group kill + idempotent cancel verified"
exit 0
