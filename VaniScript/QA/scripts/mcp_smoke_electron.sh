#!/usr/bin/env bash
# QA: mcp_smoke_electron.sh — Electron MCP server SSE endpoint verification
# Asserts:
#   1. Electron main.js exists
#   2. SSE endpoint at /sse path
#   3. Port 19789
#   4. /message POST endpoint for JSON-RPC
#   5. mcp_bridge.py exists and targets 19789
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MAIN_JS="$PROJECT_ROOT/Electron/electron/main.js"
BRIDGE="$PROJECT_ROOT/Electron/mcp_bridge.py"

echo "=== mcp_smoke_electron: Electron MCP server SSE :19789 ==="

# 1. main.js exists
[ -f "$MAIN_JS" ] || { echo "FAIL: Electron/electron/main.js not found"; exit 1; }

# 2. SSE endpoint
grep -q "'/sse'" "$MAIN_JS" || { echo "FAIL: /sse endpoint not found in Electron main.js"; exit 1; }

# 3. Port 19789
grep -q '19789' "$MAIN_JS" || { echo "FAIL: port 19789 not found in Electron main.js"; exit 1; }

# 4. /message POST endpoint
grep -q "'/message'" "$MAIN_JS" || { echo "FAIL: /message endpoint not found"; exit 1; }

# 5. mcp_bridge.py targets 19789
[ -f "$BRIDGE" ] || { echo "FAIL: mcp_bridge.py not found"; exit 1; }
grep -q '19789' "$BRIDGE" || { echo "FAIL: mcp_bridge.py does not target port 19789"; exit 1; }

echo "PASS: mcp_smoke_electron — SSE :19789, /message, bridge verified"
exit 0
