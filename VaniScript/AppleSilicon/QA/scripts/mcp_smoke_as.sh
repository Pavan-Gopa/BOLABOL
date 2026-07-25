#!/usr/bin/env bash
# QA/scripts/mcp_smoke_as.sh — Apple Silicon MCP server static smoke.
# Deterministic static smoke (no live server probe, to keep the suite idempotent
# and non-flaky): verifies the MCP bridge + core contracts wire the documented
# Apple Silicon SSE endpoint (loopback :19790) and SSE transport.
#   - mcp_bridge.py exists, binds PORT 19790, uses an /sse listener
#   - McpContracts.swift defaultEndpoint is http://127.0.0.1:19790/sse
# Exit 0 = green. Dev-workflow QA script, not product code.

set -uo pipefail

AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

echo "MCP static smoke (AS :19790) — cwd: $AS_DIR"

fail=0

BRIDGE="$AS_DIR/mcp_bridge.py"
if [[ ! -f "$BRIDGE" ]]; then
  echo "FAIL: mcp_bridge.py missing"
  fail=1
else
  echo "OK: mcp_bridge.py present"
  if grep -qE 'PORT[[:space:]]*=[[:space:]]*19790' "$BRIDGE"; then
    echo "OK: mcp_bridge.py binds PORT 19790"
  else
    echo "FAIL: mcp_bridge.py does not bind PORT 19790"
    fail=1
  fi
  if grep -qi 'sse' "$BRIDGE"; then
    echo "OK: mcp_bridge.py uses SSE transport"
  else
    echo "FAIL: mcp_bridge.py has no SSE transport"
    fail=1
  fi
fi

CONTRACTS="$AS_DIR/Sources/VaniScriptCore/McpContracts.swift"
if [[ ! -f "$CONTRACTS" ]]; then
  echo "FAIL: McpContracts.swift missing"
  fail=1
elif grep -qF 'http://127.0.0.1:19790/sse' "$CONTRACTS"; then
  echo "OK: McpContracts.swift defaultEndpoint is http://127.0.0.1:19790/sse"
else
  echo "FAIL: McpContracts.swift missing defaultEndpoint http://127.0.0.1:19790/sse"
  fail=1
fi

if [[ $fail -ne 0 ]]; then
  echo "RESULT: FAIL (mcp_smoke_as)"
  exit 1
fi
echo "RESULT: PASS (mcp_smoke_as)"
exit 0
