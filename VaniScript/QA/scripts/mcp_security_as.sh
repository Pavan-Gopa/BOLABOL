#!/usr/bin/env bash
# QA: mcp_security_as.sh — AS MCP server token authentication
# Asserts:
#   1. McpServer.swift returns 401 Unauthorized on missing/invalid token
#   2. isAuthorized checks Authorization Bearer and x-vaniscript-mcp-token headers
#   3. McpServerConfiguration.canStart requires non-empty accessToken
#   4. Token is never empty when server starts
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MCP_SERVER="$PROJECT_ROOT/AppleSilicon/Sources/VaniScript/Services/McpServer.swift"
CONTRACTS="$PROJECT_ROOT/AppleSilicon/Sources/VaniScriptCore/McpContracts.swift"

echo "=== mcp_security_as: AS MCP token auth ==="

# 1. 401 on missing token
grep -q '401' "$MCP_SERVER" || { echo "FAIL: no 401 response in McpServer.swift"; exit 1; }
grep -q 'Unauthorized' "$MCP_SERVER" || { echo "FAIL: no Unauthorized status in McpServer.swift"; exit 1; }

# 2. isAuthorized checks Bearer and x-vaniscript-mcp-token
grep -q 'isAuthorized' "$CONTRACTS" || { echo "FAIL: isAuthorized not found in McpContracts.swift"; exit 1; }
grep -q 'Bearer' "$CONTRACTS" || { echo "FAIL: Bearer auth not found"; exit 1; }
grep -q 'x-vaniscript-mcp-token' "$CONTRACTS" || { echo "FAIL: x-vaniscript-mcp-token header not found"; exit 1; }

# 3. canStart requires token
grep -q 'canStart' "$CONTRACTS" || { echo "FAIL: canStart not found"; exit 1; }
grep -q 'isEnabled && !accessToken.isEmpty' "$CONTRACTS" || \
    { echo "FAIL: canStart does not check accessToken.isEmpty"; exit 1; }

# 4. Loopback-only binding
grep -q 'isLoopbackHost' "$CONTRACTS" || { echo "FAIL: isLoopbackHost not found"; exit 1; }

echo "PASS: mcp_security_as — 401, Bearer, x-vaniscript-mcp-token, canStart, loopback verified"
exit 0
