#!/usr/bin/env bash
# QA: routes_selector.sh — ChatSidebarView route selector for codex/grok/qwen
# Asserts:
#   1. ChatRoute enum has mcp and gemini cases
#   2. MCP route guard accepts codex, grok, AND qwen
#   3. Qwen route dispatches to QwenAgentService
#   4. Grok route dispatches to GrokAgentService
#   5. Codex route dispatches to CodexAgentService (default)
#   6. Agent model menu switches on qwen/grok/codex
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHAT_VIEW="$PROJECT_ROOT/AppleSilicon/Sources/VaniScript/Views/ChatSidebarView.swift"

echo "=== routes_selector: codex/grok/qwen in ChatSidebarView ==="
FAILURES=0

[ -f "$CHAT_VIEW" ] || { echo "FAIL: ChatSidebarView.swift not found"; exit 1; }

# 1. ChatRoute enum
grep -q 'case mcp' "$CHAT_VIEW" || { echo "FAIL: ChatRoute.mcp not found"; FAILURES=$((FAILURES+1)); }
grep -q 'case gemini' "$CHAT_VIEW" || { echo "FAIL: ChatRoute.gemini not found"; FAILURES=$((FAILURES+1)); }

# 2. MCP route guard accepts all three agents
grep -q 'McpClientProfileID.codex' "$CHAT_VIEW" || { echo "FAIL: codex not in route guard"; FAILURES=$((FAILURES+1)); }
grep -q 'McpClientProfileID.grok' "$CHAT_VIEW" || { echo "FAIL: grok not in route guard"; FAILURES=$((FAILURES+1)); }
grep -q 'McpClientProfileID.qwen' "$CHAT_VIEW" || { echo "FAIL: qwen not in route guard"; FAILURES=$((FAILURES+1)); }

# 3. Qwen route dispatch
grep -q 'QwenAgentService\|qwenModelMenu' "$CHAT_VIEW" || { echo "FAIL: Qwen dispatch not found"; FAILURES=$((FAILURES+1)); }

# 4. Grok route dispatch
grep -q 'GrokAgentService\|grokModelMenu' "$CHAT_VIEW" || { echo "FAIL: Grok dispatch not found"; FAILURES=$((FAILURES+1)); }

# 5. Codex route dispatch
grep -q 'CodexAgentService\|codexModelMenu' "$CHAT_VIEW" || { echo "FAIL: Codex dispatch not found"; FAILURES=$((FAILURES+1)); }

# 6. Agent model menu switches
grep -q 'agentModelMenu' "$CHAT_VIEW" || { echo "FAIL: agentModelMenu not found"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: routes_selector — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: routes_selector — codex/grok/qwen routes verified in ChatSidebarView"
exit 0
