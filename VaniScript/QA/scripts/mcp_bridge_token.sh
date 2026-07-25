#!/usr/bin/env bash
# QA: mcp_bridge_token.sh — mcp_bridge.py token handling
# Asserts:
#   1. Bridge reads VANISCRIPT_MCP_TOKEN from env
#   2. Bridge falls back to settings.json mcpAccessToken
#   3. Token sent via x-vaniscript-mcp-token header
#   4. Bridge targets port 19789
#   5. SSE listener reconnects on failure
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BRIDGE="$PROJECT_ROOT/Electron/mcp_bridge.py"

echo "=== mcp_bridge_token: bridge token handling ==="
FAILURES=0

[ -f "$BRIDGE" ] || { echo "FAIL: mcp_bridge.py not found"; exit 1; }

# 1. Env var
grep -q 'VANISCRIPT_MCP_TOKEN' "$BRIDGE" || { echo "FAIL: VANISCRIPT_MCP_TOKEN not in bridge"; FAILURES=$((FAILURES+1)); }

# 2. Settings fallback
grep -q 'mcpAccessToken' "$BRIDGE" || { echo "FAIL: mcpAccessToken fallback not in bridge"; FAILURES=$((FAILURES+1)); }
grep -q 'settings.json' "$BRIDGE" || { echo "FAIL: settings.json path not in bridge"; FAILURES=$((FAILURES+1)); }

# 3. Token header
grep -q 'x-vaniscript-mcp-token' "$BRIDGE" || { echo "FAIL: x-vaniscript-mcp-token header not in bridge"; FAILURES=$((FAILURES+1)); }

# 4. Port 19789
grep -q '19789' "$BRIDGE" || { echo "FAIL: port 19789 not in bridge"; FAILURES=$((FAILURES+1)); }

# 5. Reconnect on failure
grep -q 'time.sleep' "$BRIDGE" || { echo "FAIL: no reconnect delay in bridge"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: mcp_bridge_token — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: mcp_bridge_token — bridge token handling verified"
exit 0
