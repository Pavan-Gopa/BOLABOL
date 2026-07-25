#!/usr/bin/env bash
# QA: q5_auth_alt_header.sh — Q5 smoke: alternate x-vaniscript-mcp-token header accepted
# Asserts:
#   1. Electron/electron/main.js exists
#   2. x-vaniscript-mcp-token header is read by the server
#   3. It is accepted inside the isMcpAuthorized middleware
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MAIN="$PROJECT_ROOT/Electron/electron/main.js"

echo "=== q5_auth_alt_header: x-vaniscript-mcp-token accepted ==="

# 1. File exists
[ -f "$MAIN" ] || { echo "FAIL: Electron/electron/main.js not found"; exit 1; }

# 2. Alternate header read
grep -q "req.headers\['x-vaniscript-mcp-token'\]" "$MAIN" || \
    { echo "FAIL: x-vaniscript-mcp-token header not read in main.js"; exit 1; }

# 3. Accepted within auth middleware (header compared against mcpAccessToken)
grep -A12 'function isMcpAuthorized' "$MAIN" | grep -q 'x-vaniscript-mcp-token' || \
    { echo "FAIL: x-vaniscript-mcp-token not accepted inside isMcpAuthorized"; exit 1; }

echo "PASS: q5_auth_alt_header — server accepts x-vaniscript-mcp-token header"
exit 0
