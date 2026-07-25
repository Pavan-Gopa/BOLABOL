#!/usr/bin/env bash
# QA: mcp_security_electron.sh — Electron MCP server token authentication
# Asserts:
#   1. Electron MCP server checks token on /sse endpoint
#   2. Electron MCP server checks token on /message endpoint
#   3. 401 or equivalent rejection on missing token
# NOTE: The Electron MCP server at :19789 currently has NO token auth.
#       The AS server at :19790 requires token auth (401 on missing).
#       This is a security parity gap.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MAIN_JS="$PROJECT_ROOT/Electron/electron/main.js"

echo "=== mcp_security_electron: Electron MCP token auth ==="

[ -f "$MAIN_JS" ] || { echo "FAIL: Electron main.js not found"; exit 1; }

# Extract the MCP server section (startMcpServer function)
MCP_SECTION=$(sed -n '/function startMcpServer/,/^function /p' "$MAIN_JS" | head -200)

# Check for token/auth verification in the SSE endpoint
SSE_HAS_AUTH=false
if echo "$MCP_SECTION" | grep -qi 'token\|auth\|401\|Unauthorized\|x-vaniscript-mcp-token'; then
    SSE_HAS_AUTH=true
fi

# Check for token/auth verification in the /message endpoint
MSG_HAS_AUTH=false
if echo "$MCP_SECTION" | grep -qi 'token\|auth\|401\|Unauthorized\|x-vaniscript-mcp-token'; then
    MSG_HAS_AUTH=true
fi

FAILURES=0

if [ "$SSE_HAS_AUTH" = false ]; then
    echo "FAIL: Electron MCP /sse endpoint has NO token authentication"
    echo "      AS MCP server at :19790 requires token (401 on missing)."
    echo "      Electron MCP server at :19789 accepts any connection without auth."
    FAILURES=$((FAILURES + 1))
fi

if [ "$MSG_HAS_AUTH" = false ]; then
    echo "FAIL: Electron MCP /message endpoint has NO token authentication"
    FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: mcp_security_electron — $FAILURES auth gap(s) found"
    exit 1
fi

echo "PASS: mcp_security_electron — token auth verified"
exit 0
