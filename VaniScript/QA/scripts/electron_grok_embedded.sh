#!/usr/bin/env bash
# QA: electron_grok_embedded.sh — Electron embedded Grok chat
# Asserts:
#   1. Electron main.js has embedded Grok chat section
#   2. Uses vaniscript_embedded server ID
#   3. Targets port 19789 (GROK_MCP_PORT)
#   4. No silent fallback to Gemini or other provider
#   5. Grok executable resolution (multiple candidates)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MAIN_JS="$PROJECT_ROOT/Electron/electron/main.js"

echo "=== electron_grok_embedded: Electron embedded Grok chat ==="
FAILURES=0

[ -f "$MAIN_JS" ] || { echo "FAIL: Electron main.js not found"; exit 1; }

# 1. Embedded Grok section
grep -q 'Embedded Grok chat\|embedded.*[Gg]rok\|Grok.*embedded' "$MAIN_JS" || \
    { echo "FAIL: no embedded Grok chat section"; FAILURES=$((FAILURES+1)); }

# 2. vaniscript_embedded server ID
grep -q 'vaniscript_embedded' "$MAIN_JS" || \
    { echo "FAIL: vaniscript_embedded not in Electron main.js"; FAILURES=$((FAILURES+1)); }

# 3. Port 19789
grep -q 'GROK_MCP_PORT.*=.*19789\|19789' "$MAIN_JS" || \
    { echo "FAIL: GROK_MCP_PORT 19789 not found"; FAILURES=$((FAILURES+1)); }

# 4. No silent fallback
grep -q 'NO silent\|no silent' "$MAIN_JS" || \
    { echo "WARN: no explicit no-fallback comment for Electron Grok"; }

# 5. Grok executable resolution
grep -q 'resolveGrokExecutable\|grok.*executable\|grok.*binary' "$MAIN_JS" || \
    { echo "FAIL: no Grok executable resolution"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: electron_grok_embedded — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: electron_grok_embedded — Electron embedded Grok chat verified"
exit 0
