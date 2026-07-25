#!/usr/bin/env bash
# QA: security_no_tokens_argv.sh — Tokens NEVER in process arguments
# Asserts:
#   1. QwenAgentService: accessToken NOT in process.arguments
#   2. CodexAgentService: accessToken NOT in process.arguments
#   3. GrokAgentService: accessToken NOT in process.arguments
#   4. No token string interpolation in arguments arrays
#   5. Token env var name is VANISCRIPT_MCP_TOKEN (not the token value)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AS_DIR="$PROJECT_ROOT/AppleSilicon"
CODEX_SVC="$AS_DIR/Sources/VaniScript/Services/CodexAgentService.swift"
GROK_SVC="$AS_DIR/Sources/VaniScript/Services/GrokAgentService.swift"
QWEN_SVC="$AS_DIR/Sources/VaniScript/Services/QwenAgentService.swift"

echo "=== security_no_tokens_argv: tokens not in argv ==="
FAILURES=0

for SVC in "$CODEX_SVC" "$GROK_SVC" "$QWEN_SVC"; do
    NAME=$(basename "$SVC")
    # Extract the process.arguments block and check for accessToken interpolation
    ARGS_BLOCK=$(sed -n '/process\.arguments/,/]/p' "$SVC")
    if echo "$ARGS_BLOCK" | grep -q 'accessToken\|mcpConfiguration\.accessToken'; then
        echo "FAIL: $NAME has accessToken in process.arguments"
        FAILURES=$((FAILURES+1))
    fi
done

# Verify token goes via environment, not argv
for SVC in "$CODEX_SVC" "$GROK_SVC" "$QWEN_SVC"; do
    NAME=$(basename "$SVC")
    grep -q 'VANISCRIPT_MCP_TOKEN' "$SVC" || \
        { echo "FAIL: $NAME missing VANISCRIPT_MCP_TOKEN env key"; FAILURES=$((FAILURES+1)); }
done

# Codex uses bearer_token_env_var (references env var name, not value)
grep -q 'bearer_token_env_var' "$CODEX_SVC" || \
    { echo "WARN: CodexAgentService missing bearer_token_env_var pattern"; }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: security_no_tokens_argv — $FAILURES token leak(s) in argv"
    exit 1
fi

echo "PASS: security_no_tokens_argv — no tokens in process arguments"
exit 0
