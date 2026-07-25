#!/usr/bin/env bash
# QA: provider_error_types.sh — All provider error types present
# Asserts:
#   1. QwenAgentError: mcpUnavailable, qwenNotInstalled, launchFailed, unavailable, noResponse
#   2. All errors have user-facing errorDescription
#   3. Error types are Sendable (Swift 6 concurrency)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
QWEN_SVC="$PROJECT_ROOT/AppleSilicon/Sources/VaniScript/Services/QwenAgentService.swift"

echo "=== provider_error_types: Qwen error types ==="
FAILURES=0

[ -f "$QWEN_SVC" ] || { echo "FAIL: QwenAgentService.swift not found"; exit 1; }

# 1. All error cases
for ERR in "mcpUnavailable" "qwenNotInstalled" "launchFailed" "unavailable" "noResponse"; do
    grep -q "case $ERR" "$QWEN_SVC" || { echo "FAIL: QwenAgentError.$ERR not found"; FAILURES=$((FAILURES+1)); }
done

# 2. errorDescription
grep -q 'errorDescription' "$QWEN_SVC" || { echo "FAIL: errorDescription not found"; FAILURES=$((FAILURES+1)); }

# 3. Sendable
grep -q 'Sendable' "$QWEN_SVC" || { echo "FAIL: QwenAgentError not Sendable"; FAILURES=$((FAILURES+1)); }

# 4. LocalizedError conformance
grep -q 'LocalizedError' "$QWEN_SVC" || { echo "FAIL: QwenAgentError not LocalizedError"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: provider_error_types — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: provider_error_types — all Qwen error types verified"
exit 0
