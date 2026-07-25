#!/usr/bin/env bash
# QA: q5_no_fallback_doc.sh — Q5 doc: explicitly states no silent MCP->API fallback
# Asserts:
#   1. MCP_INSTRUCTIONS.md exists
#   2. States "no silent MCP" fallback invariant
#   3. Mentions fallback explicitly
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOC="$PROJECT_ROOT/AppleSilicon/MCP_INSTRUCTIONS.md"

echo "=== q5_no_fallback_doc: no silent MCP->API fallback documented ==="

# 1. File exists
[ -f "$DOC" ] || { echo "FAIL: MCP_INSTRUCTIONS.md not found"; exit 1; }

# 2. "no silent MCP" invariant present (ASCII-safe match)
grep -q 'no silent MCP' "$DOC" || { echo "FAIL: 'no silent MCP' invariant missing"; exit 1; }

# 3. fallback mentioned
grep -qi 'fallback' "$DOC" || { echo "FAIL: 'fallback' not mentioned in doc"; exit 1; }

echo "PASS: q5_no_fallback_doc — doc states no silent MCP->API fallback"
exit 0
