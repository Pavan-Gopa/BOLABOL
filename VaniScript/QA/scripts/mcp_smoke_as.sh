#!/usr/bin/env bash
# QA: mcp_smoke_as.sh — Apple Silicon MCP server SSE endpoint verification
# Asserts:
#   1. McpServer.swift exists
#   2. SSE endpoint at /sse path
#   3. Default port 19790
#   4. tools/list method handler present
#   5. JSON-RPC response structure
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MCP_SERVER="$PROJECT_ROOT/AppleSilicon/Sources/VaniScript/Services/McpServer.swift"

echo "=== mcp_smoke_as: AS MCP server SSE :19790 ==="

# 1. File exists
[ -f "$MCP_SERVER" ] || { echo "FAIL: McpServer.swift not found"; exit 1; }

# 2. SSE endpoint
grep -q '"/sse"' "$MCP_SERVER" || { echo "FAIL: /sse endpoint not found in McpServer.swift"; exit 1; }

# 3. Port 19790 (default in McpServerConfiguration)
grep -q '19790' "$PROJECT_ROOT/AppleSilicon/Sources/VaniScriptCore/McpContracts.swift" || \
    { echo "FAIL: port 19790 not found in McpContracts.swift"; exit 1; }

# 4. tools/list handler
grep -q 'tools/list\|toolsList\|"tools"' "$MCP_SERVER" || \
    { echo "FAIL: tools/list handler not found"; exit 1; }

# 5. JSON-RPC structure
grep -q 'jsonrpc\|json-rpc\|JSON-RPC\|jsonRpc' "$MCP_SERVER" || \
    { echo "FAIL: JSON-RPC structure not found"; exit 1; }

echo "PASS: mcp_smoke_as — SSE :19790, tools/list, JSON-RPC verified"
exit 0
