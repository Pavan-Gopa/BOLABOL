#!/usr/bin/env bash
# QA: q5_mcp_instructions_section.sh — Q5 doc: External Qwen CLI section in MCP_INSTRUCTIONS.md
# Asserts:
#   1. MCP_INSTRUCTIONS.md exists
#   2. Contains "External Qwen CLI" section
#   3. Documents `qwen mcp add` connection option
#   4. Documents `.qwen/settings.json` connection option
#   5. Documents Electron port 19789
#   6. Documents Apple Silicon port 19790
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOC="$PROJECT_ROOT/AppleSilicon/MCP_INSTRUCTIONS.md"

echo "=== q5_mcp_instructions_section: External Qwen CLI doc section ==="

# 1. File exists
[ -f "$DOC" ] || { echo "FAIL: MCP_INSTRUCTIONS.md not found"; exit 1; }

# 2. External Qwen CLI section
grep -q 'External Qwen CLI' "$DOC" || { echo "FAIL: 'External Qwen CLI' section missing"; exit 1; }

# 3. qwen mcp add option
grep -q 'qwen mcp add' "$DOC" || { echo "FAIL: 'qwen mcp add' option missing"; exit 1; }

# 4. .qwen/settings.json option
grep -q '.qwen/settings.json' "$DOC" || { echo "FAIL: '.qwen/settings.json' option missing"; exit 1; }

# 5. Electron port 19789
grep -q '19789' "$DOC" || { echo "FAIL: Electron port 19789 missing"; exit 1; }

# 6. Apple Silicon port 19790
grep -q '19790' "$DOC" || { echo "FAIL: Apple Silicon port 19790 missing"; exit 1; }

echo "PASS: q5_mcp_instructions_section — External Qwen CLI, both options, both ports documented"
exit 0
