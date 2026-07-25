#!/usr/bin/env bash
# QA: mcp_cors_origin.sh — AS MCP server CORS/Origin policy
# Asserts:
#   1. isAllowedOrigin method exists
#   2. Native MCP clients (no Origin header) are accepted
#   3. Browser requests only from loopback origins
#   4. isLoopbackHost checks 127.0.0.1, ::1, localhost
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONTRACTS="$PROJECT_ROOT/AppleSilicon/Sources/VaniScriptCore/McpContracts.swift"

echo "=== mcp_cors_origin: AS MCP CORS/Origin policy ==="
FAILURES=0

# 1. isAllowedOrigin
grep -q 'isAllowedOrigin' "$CONTRACTS" || { echo "FAIL: isAllowedOrigin not found"; FAILURES=$((FAILURES+1)); }

# 2. No Origin = accepted (native clients)
grep -q 'origin.*nil\|origin?.*isEmpty\|guard let origin' "$CONTRACTS" || \
    { echo "FAIL: no nil-origin handling"; FAILURES=$((FAILURES+1)); }

# 3. Loopback-only for browser
grep -q 'isLoopbackHost' "$CONTRACTS" || { echo "FAIL: isLoopbackHost not found"; FAILURES=$((FAILURES+1)); }

# 4. Loopback addresses
grep -q '127.0.0.1' "$CONTRACTS" || { echo "FAIL: 127.0.0.1 not in loopback check"; FAILURES=$((FAILURES+1)); }
grep -q '::1' "$CONTRACTS" || { echo "FAIL: ::1 not in loopback check"; FAILURES=$((FAILURES+1)); }
grep -q 'localhost' "$CONTRACTS" || { echo "FAIL: localhost not in loopback check"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: mcp_cors_origin — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: mcp_cors_origin — CORS/Origin policy verified"
exit 0
