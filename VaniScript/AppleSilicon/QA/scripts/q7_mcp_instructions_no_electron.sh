#!/usr/bin/env bash
# QA/scripts/q7_mcp_instructions_no_electron.sh — Q7 delta (doc-only), BUG-002 invariant.
# AppleSilicon/MCP_INSTRUCTIONS.md must NOT mention "electron" (case-insensitive):
# the native doc describes the Apple Silicon app only. grep -ci electron == 0.
# Idempotent, deterministic. Exit 0 = pass. QA script, not product code.

set -uo pipefail

AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC="$AS_DIR/MCP_INSTRUCTIONS.md"

echo "Q7 MCP_INSTRUCTIONS no-electron (BUG-002) — $DOC"

if [[ ! -f "$DOC" ]]; then
  echo "FAIL: MCP_INSTRUCTIONS missing: $DOC"
  exit 1
fi

count="$(grep -ci electron "$DOC" || true)"
count="${count:-0}"
echo "electron mentions (case-insensitive): $count"

if [[ "$count" -ne 0 ]]; then
  echo "FAIL: BUG-002 invariant violated — 'electron' mentioned in AppleSilicon MCP_INSTRUCTIONS.md"
  grep -ni electron "$DOC"
  echo "RESULT: FAIL (q7_mcp_instructions_no_electron)"
  exit 1
fi

echo "OK: zero 'electron' mentions"
echo "RESULT: PASS (q7_mcp_instructions_no_electron)"
exit 0
