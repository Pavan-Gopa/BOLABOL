#!/usr/bin/env bash
# QA: q5_endpoint_electron.sh — Q5 smoke: Electron SSE endpoint really exists in code
# Asserts:
#   1. Electron/electron/main.js exists
#   2. Server listens on 19789 bound to 127.0.0.1
#   3. /sse route is handled
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MAIN="$PROJECT_ROOT/Electron/electron/main.js"

echo "=== q5_endpoint_electron: Electron SSE :19789 in code ==="

# 1. File exists
[ -f "$MAIN" ] || { echo "FAIL: Electron/electron/main.js not found"; exit 1; }

# 2. listen(19789, '127.0.0.1')
grep -q "listen(19789, '127.0.0.1'" "$MAIN" || \
    { echo "FAIL: .listen(19789, '127.0.0.1') not found in main.js"; exit 1; }

# 3. /sse route handler
grep -q "'/sse'" "$MAIN" || { echo "FAIL: /sse route not found in main.js"; exit 1; }

echo "PASS: q5_endpoint_electron — SSE :19789 loopback endpoint present in Electron code"
exit 0
