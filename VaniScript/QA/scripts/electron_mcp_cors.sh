#!/usr/bin/env bash
# QA: electron_mcp_cors.sh — Electron MCP server CORS policy
# Asserts:
#   1. Electron MCP server sets CORS headers
#   2. WARN: Access-Control-Allow-Origin: * is overly permissive
#      (AS server restricts to loopback origins only)
#   3. Server binds to 127.0.0.1 only (not 0.0.0.0)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MAIN_JS="$PROJECT_ROOT/Electron/electron/main.js"

echo "=== electron_mcp_cors: Electron MCP CORS policy ==="
FAILURES=0

[ -f "$MAIN_JS" ] || { echo "FAIL: Electron main.js not found"; exit 1; }

# Extract MCP server section
MCP_SECTION=$(sed -n '/function startMcpServer/,/^function /p' "$MAIN_JS" | head -200)

# 1. CORS headers present
echo "$MCP_SECTION" | grep -q 'Access-Control-Allow-Origin' || \
    { echo "FAIL: no CORS headers in Electron MCP server"; FAILURES=$((FAILURES+1)); }

# 2. Check for wildcard CORS (security concern)
if echo "$MCP_SECTION" | grep -q "Access-Control-Allow-Origin.*\*"; then
    echo "WARN: Electron MCP server uses Access-Control-Allow-Origin: * (wildcard)"
    echo "      AS MCP server restricts to loopback origins only."
    echo "      This is a security parity gap (low severity: server is loopback-only)."
fi

# 3. Binds to 127.0.0.1
grep -q "listen(19789, '127.0.0.1'" "$MAIN_JS" || \
    { echo "FAIL: Electron MCP server not bound to 127.0.0.1"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: electron_mcp_cors — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: electron_mcp_cors — CORS policy checked (wildcard warning noted)"
exit 0
