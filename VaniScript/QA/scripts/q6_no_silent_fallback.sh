#!/usr/bin/env bash
# QA: q6_no_silent_fallback.sh — Q6 streaming provider has no silent MCP->API fallback
# Asserts:
#   1. When MCP cannot start, send() throws QwenChatError.mcpUnavailable (no quiet degradation)
#   2. No URLSession/URLRequest/NSURLSession anywhere in QwenAgentSupport.swift
#   3. Explicit "no silent fallback" invariant comment present
#   4. canStart guard precedes the CLI spawn
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE="$PROJECT_ROOT/AppleSilicon/Sources/VaniScriptCore/QwenAgentSupport.swift"

echo "=== q6_no_silent_fallback: no MCP->API fallback ==="
FAILURES=0

[ -f "$CORE" ] || { echo "FAIL: QwenAgentSupport.swift not found"; exit 1; }

# 1. mcpUnavailable thrown when canStart is false
grep -q 'guard mcpConfiguration.canStart else' "$CORE" || \
    { echo "FAIL: no canStart guard in streaming provider"; FAILURES=$((FAILURES+1)); }
grep -q 'throw QwenChatError.mcpUnavailable' "$CORE" || \
    { echo "FAIL: mcpUnavailable not thrown on canStart==false"; FAILURES=$((FAILURES+1)); }

# 2. No HTTP client usage
if grep -q 'URLSession\|URLRequest\|NSURLSession' "$CORE"; then
    echo "FAIL: QwenAgentSupport.swift contains URLSession/URLRequest — possible silent API fallback"
    FAILURES=$((FAILURES+1))
fi

# 3. Explicit invariant comment
grep -q 'no silent fallback' "$CORE" || \
    { echo "FAIL: missing explicit 'no silent fallback' invariant comment"; FAILURES=$((FAILURES+1)); }

# 4. canStart guard comes before the process spawn
GUARD_LINE=$(grep -n 'guard mcpConfiguration.canStart else' "$CORE" | head -1 | cut -d: -f1)
PROC_LINE=$(grep -n 'let process = Process()' "$CORE" | head -1 | cut -d: -f1)
if [ -n "$GUARD_LINE" ] && [ -n "$PROC_LINE" ] && [ "$GUARD_LINE" -ge "$PROC_LINE" ]; then
    echo "FAIL: canStart guard not before Process() spawn"
    FAILURES=$((FAILURES+1))
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: q6_no_silent_fallback — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: q6_no_silent_fallback — .mcpUnavailable thrown, no HTTP fallback"
exit 0
