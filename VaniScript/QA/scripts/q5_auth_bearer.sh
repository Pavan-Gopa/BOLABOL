#!/usr/bin/env bash
# QA: q5_auth_bearer.sh — Q5 smoke: Bearer token auth middleware in Electron code
# Asserts:
#   1. Electron/electron/main.js exists
#   2. isMcpAuthorized middleware defined
#   3. Checks the authorization header
#   4. Validates the 'bearer ' scheme prefix
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MAIN="$PROJECT_ROOT/Electron/electron/main.js"

echo "=== q5_auth_bearer: Bearer token middleware in Electron code ==="

# 1. File exists
[ -f "$MAIN" ] || { echo "FAIL: Electron/electron/main.js not found"; exit 1; }

# 2. isMcpAuthorized middleware
grep -q 'function isMcpAuthorized' "$MAIN" || \
    { echo "FAIL: isMcpAuthorized middleware not found in main.js"; exit 1; }

# 3. authorization header read
grep -q "req.headers\['authorization'\]" "$MAIN" || \
    { echo "FAIL: authorization header not checked in main.js"; exit 1; }

# 4. bearer scheme prefix
grep -q "startsWith('bearer ')" "$MAIN" || \
    { echo "FAIL: 'bearer ' scheme prefix not validated in main.js"; exit 1; }

echo "PASS: q5_auth_bearer — isMcpAuthorized checks Authorization: Bearer header"
exit 0
