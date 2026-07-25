#!/usr/bin/env bash
# QA: q5_endpoint_as.sh — Q5 smoke: Apple Silicon SSE endpoint really exists in code
# Asserts:
#   1. McpServer.swift exists
#   2. /sse endpoint handled
#   3. Default port 19790 (McpContracts.swift)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MCP_SERVER="$PROJECT_ROOT/AppleSilicon/Sources/VaniScript/Services/McpServer.swift"
MCP_CONTRACTS="$PROJECT_ROOT/AppleSilicon/Sources/VaniScriptCore/McpContracts.swift"

echo "=== q5_endpoint_as: AS SSE :19790 in code ==="

# 1. File exists
[ -f "$MCP_SERVER" ] || { echo "FAIL: McpServer.swift not found"; exit 1; }

# 2. /sse endpoint
grep -q '"/sse"' "$MCP_SERVER" || { echo "FAIL: /sse endpoint not found in McpServer.swift"; exit 1; }

# 3. Port 19790
grep -q '19790' "$MCP_CONTRACTS" || { echo "FAIL: port 19790 not found in McpContracts.swift"; exit 1; }

echo "PASS: q5_endpoint_as — SSE :19790 endpoint present in Apple Silicon code"
exit 0
