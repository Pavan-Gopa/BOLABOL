#!/usr/bin/env bash
# QA: qwen_mcp_wiring.sh — Qwen Q3 MCP wiring (replaces qwen_safe_mode.sh)
# Asserts:
#   1. --safe-mode is NOT in arguments (Q3 removed it to enable MCP)
#   2. writeIsolatedMcpConfig is called before spawn
#   3. Prompt contains MCP tool instructions (vaniscript_embedded, search_help)
#   4. No --trust / --cwd (Qwen uses --scope project, not Grok flags)
#   5. Token only via env (VANISCRIPT_MCP_TOKEN in QwenMcpConfig)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
QWEN_SVC="$PROJECT_ROOT/AppleSilicon/Sources/VaniScript/Services/QwenAgentService.swift"
QWEN_MCP="$PROJECT_ROOT/AppleSilicon/Sources/VaniScriptCore/QwenMcpConfig.swift"

echo "=== qwen_mcp_wiring: Q3 MCP wiring ==="
FAILURES=0

[ -f "$QWEN_SVC" ] || { echo "FAIL: QwenAgentService.swift not found"; exit 1; }
[ -f "$QWEN_MCP" ] || { echo "FAIL: QwenMcpConfig.swift not found"; exit 1; }

# 1. --safe-mode must NOT be present (Q3 enables MCP)
if grep -v '^\s*//' "$QWEN_SVC" | grep -q '"\-\-safe-mode"'; then
    echo "FAIL: --safe-mode still present (Q3 must remove it)"
    FAILURES=$((FAILURES+1))
fi

# 2. writeIsolatedMcpConfig called
grep -q 'writeIsolatedMcpConfig' "$QWEN_SVC" || \
    { echo "FAIL: writeIsolatedMcpConfig not called"; FAILURES=$((FAILURES+1)); }

# 3. Prompt contains MCP tool instructions
grep -q 'vaniscript_embedded' "$QWEN_SVC" || \
    { echo "FAIL: prompt missing vaniscript_embedded"; FAILURES=$((FAILURES+1)); }
grep -q 'search_help' "$QWEN_SVC" || \
    { echo "FAIL: prompt missing search_help instruction"; FAILURES=$((FAILURES+1)); }

# 4. No --trust / --cwd (Qwen isolation is via --scope project, not Grok flags)
if grep -v '^\s*//' "$QWEN_SVC" | grep -q '"\-\-trust"'; then
    echo "FAIL: --trust found (Qwen must not use Grok flags)"
    FAILURES=$((FAILURES+1))
fi
if grep -v '^\s*//' "$QWEN_SVC" | grep -q '"\-\-cwd"'; then
    echo "FAIL: --cwd found (Qwen must not use Grok flags)"
    FAILURES=$((FAILURES+1))
fi

# 5. Token key defined in QwenMcpConfig
grep -q 'accessTokenEnvironmentKey.*=.*"VANISCRIPT_MCP_TOKEN"' "$QWEN_MCP" || \
    { echo "FAIL: VANISCRIPT_MCP_TOKEN not in QwenMcpConfig"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: qwen_mcp_wiring — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: qwen_mcp_wiring — Q3 MCP wiring verified"
exit 0
