#!/usr/bin/env bash
# QA: q5_qwen_settings_format.sh — Q5 doc: valid .qwen/settings.json example
# Asserts MCP_INSTRUCTIONS.md contains a settings.json example with fields:
#   1. mcpServers root
#   2. url
#   3. transport
#   4. headers
#   5. trust
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOC="$PROJECT_ROOT/AppleSilicon/MCP_INSTRUCTIONS.md"

echo "=== q5_qwen_settings_format: .qwen/settings.json example fields ==="

# 0. File exists
[ -f "$DOC" ] || { echo "FAIL: MCP_INSTRUCTIONS.md not found"; exit 1; }

# 1. mcpServers root
grep -q '"mcpServers"' "$DOC" || { echo "FAIL: mcpServers root missing in settings.json example"; exit 1; }

# 2. url field
grep -q '"url"' "$DOC" || { echo "FAIL: url field missing in settings.json example"; exit 1; }

# 3. transport field
grep -q '"transport"' "$DOC" || { echo "FAIL: transport field missing in settings.json example"; exit 1; }

# 4. headers field
grep -q '"headers"' "$DOC" || { echo "FAIL: headers field missing in settings.json example"; exit 1; }

# 5. trust field
grep -q '"trust"' "$DOC" || { echo "FAIL: trust field missing in settings.json example"; exit 1; }

echo "PASS: q5_qwen_settings_format — settings.json example has url/transport/headers/trust"
exit 0
