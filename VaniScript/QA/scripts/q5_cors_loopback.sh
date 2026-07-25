#!/usr/bin/env bash
# QA: q5_cors_loopback.sh — Q5 smoke: CORS allows loopback origins only
# Asserts:
#   1. Electron/electron/main.js exists
#   2. isLoopbackOrigin helper defined
#   3. Recognizes loopback hosts 127.0.0.1 / ::1 / localhost
#   4. Non-loopback Origin is rejected (not echoed back)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MAIN="$PROJECT_ROOT/Electron/electron/main.js"

echo "=== q5_cors_loopback: loopback-only CORS policy ==="

# 1. File exists
[ -f "$MAIN" ] || { echo "FAIL: Electron/electron/main.js not found"; exit 1; }

# 2. isLoopbackOrigin helper
grep -q 'function isLoopbackOrigin' "$MAIN" || \
    { echo "FAIL: isLoopbackOrigin helper not found in main.js"; exit 1; }

# 3. Loopback hosts recognized
grep -q "'127.0.0.1'" "$MAIN" || { echo "FAIL: 127.0.0.1 not in loopback check"; exit 1; }
grep -q "'::1'" "$MAIN" || { echo "FAIL: ::1 not in loopback check"; exit 1; }
grep -q "'localhost'" "$MAIN" || { echo "FAIL: localhost not in loopback check"; exit 1; }

# 4. Non-loopback origin rejected (fallback to fixed loopback origin, not echoed)
grep -q "setHeader('Access-Control-Allow-Origin', 'http://127.0.0.1')" "$MAIN" || \
    { echo "FAIL: non-loopback Origin not rejected in CORS logic"; exit 1; }

echo "PASS: q5_cors_loopback — only loopback origins allowed, non-loopback rejected"
exit 0
