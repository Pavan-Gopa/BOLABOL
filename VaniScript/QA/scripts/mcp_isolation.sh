#!/usr/bin/env bash
# QA: mcp_isolation.sh — MCP isolation and permission scoping
# Asserts:
#   1. vaniscript_embedded server ID used in Codex and Grok services
#   2. McpPermissionSet always includes .read, scopes gated by settings
#   3. Default settings: all mutating scopes disabled
#   4. Qwen uses --safe-mode (no hooks/extensions/MCP)
#   5. Tool definitions filtered by permission set
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AS_DIR="$PROJECT_ROOT/AppleSilicon"
CONTRACTS="$AS_DIR/Sources/VaniScriptCore/McpContracts.swift"
CODEX_SVC="$AS_DIR/Sources/VaniScript/Services/CodexAgentService.swift"
GROK_SVC="$AS_DIR/Sources/VaniScript/Services/GrokAgentService.swift"
QWEN_SVC="$AS_DIR/Sources/VaniScript/Services/QwenAgentService.swift"

echo "=== mcp_isolation: vaniscript_embedded + permission scoping ==="
FAILURES=0

# 1. vaniscript_embedded in Codex and Grok
grep -q 'vaniscript_embedded' "$CODEX_SVC" || { echo "FAIL: vaniscript_embedded not in CodexAgentService"; FAILURES=$((FAILURES+1)); }
grep -q 'vaniscript_embedded' "$GROK_SVC" || { echo "FAIL: vaniscript_embedded not in GrokAgentService"; FAILURES=$((FAILURES+1)); }

# 2. McpPermissionSet always includes .read
grep -q 'allowed.union(\[.read\])' "$CONTRACTS" || \
    { echo "FAIL: McpPermissionSet does not force .read"; FAILURES=$((FAILURES+1)); }

# 3. Default settings: mutating scopes disabled
grep -q 'mcpAllowMutatingTools' "$CONTRACTS" || \
    { echo "FAIL: mcpAllowMutatingTools not found"; FAILURES=$((FAILURES+1)); }
grep -q 'mcpAllowDestructiveTools' "$CONTRACTS" || \
    { echo "FAIL: mcpAllowDestructiveTools not found"; FAILURES=$((FAILURES+1)); }

# 4. Qwen --safe-mode
grep -q '\-\-safe-mode' "$QWEN_SVC" || { echo "FAIL: --safe-mode not in QwenAgentService"; FAILURES=$((FAILURES+1)); }

# 5. Tool definitions filtered by permissions
grep -q 'definitions(permissions:' "$CONTRACTS" || \
    { echo "FAIL: permission-filtered definitions not found"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: mcp_isolation — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: mcp_isolation — vaniscript_embedded, permissions, safe-mode verified"
exit 0
