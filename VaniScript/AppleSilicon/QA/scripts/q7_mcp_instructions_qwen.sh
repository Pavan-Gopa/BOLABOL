#!/usr/bin/env bash
# QA/scripts/q7_mcp_instructions_qwen.sh — Q7 delta (doc-only).
# Asserts MCP_INSTRUCTIONS.md has an up-to-date Qwen section:
#   - "External Qwen CLI" heading/link
#   - AS port 19790 and Electron port 19789 referenced
# Idempotent, deterministic. Exit 0 = pass. QA script, not product code.

set -uo pipefail

AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC="$AS_DIR/MCP_INSTRUCTIONS.md"

echo "Q7 MCP_INSTRUCTIONS Qwen-section — $DOC"

if [[ ! -f "$DOC" ]]; then
  echo "FAIL: MCP_INSTRUCTIONS missing: $DOC"
  exit 1
fi

fail=0
for needle in "External Qwen CLI" "19790" "19789"; do
  if grep -qF "$needle" "$DOC"; then
    echo "OK: present — '$needle'"
  else
    echo "FAIL: missing — '$needle'"
    fail=1
  fi
done

if [[ $fail -ne 0 ]]; then
  echo "RESULT: FAIL (q7_mcp_instructions_qwen)"
  exit 1
fi
echo "RESULT: PASS (q7_mcp_instructions_qwen)"
exit 0
