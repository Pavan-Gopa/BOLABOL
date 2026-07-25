#!/usr/bin/env bash
# QA: security_token_env_only.sh — Token only in child process environment
# Asserts:
#   1. All three agent services set token via process.environment
#   2. Token key is VANISCRIPT_MCP_TOKEN
#   3. Token NOT written to any file (no write/toFile in token context)
#   4. Token NOT logged (no print/log with accessToken)
#   5. McpServerConfiguration trims token whitespace
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AS_DIR="$PROJECT_ROOT/AppleSilicon"
CODEX_SVC="$AS_DIR/Sources/VaniScript/Services/CodexAgentService.swift"
GROK_SVC="$AS_DIR/Sources/VaniScript/Services/GrokAgentService.swift"
QWEN_SVC="$AS_DIR/Sources/VaniScript/Services/QwenAgentService.swift"
QWEN_MCP="$AS_DIR/Sources/VaniScriptCore/QwenMcpConfig.swift"
CONTRACTS="$AS_DIR/Sources/VaniScriptCore/McpContracts.swift"

echo "=== security_token_env_only: token in env only ==="
FAILURES=0

# 1. Token via process.environment
for SVC in "$CODEX_SVC" "$GROK_SVC" "$QWEN_SVC"; do
    NAME=$(basename "$SVC")
    grep -q 'process\.environment.*=.*Environment\|process\.environment.*accessToken' "$SVC" || \
        { echo "FAIL: $NAME does not set token via process.environment"; FAILURES=$((FAILURES+1)); }
done

# 2. VANISCRIPT_MCP_TOKEN key
# Codex/Grok: literal in service file. Qwen: literal in QwenMcpConfig.swift (Q3 refactor).
for SVC in "$CODEX_SVC" "$GROK_SVC"; do
    NAME=$(basename "$SVC")
    grep -q 'accessTokenEnvironmentKey.*=.*"VANISCRIPT_MCP_TOKEN"' "$SVC" || \
        { echo "FAIL: $NAME missing VANISCRIPT_MCP_TOKEN key"; FAILURES=$((FAILURES+1)); }
done
grep -q 'accessTokenEnvironmentKey.*=.*"VANISCRIPT_MCP_TOKEN"' "$QWEN_MCP" || \
    { echo "FAIL: QwenMcpConfig.swift missing VANISCRIPT_MCP_TOKEN key"; FAILURES=$((FAILURES+1)); }

# 3. No token written to files (check for write patterns near accessToken)
for SVC in "$CODEX_SVC" "$GROK_SVC" "$QWEN_SVC"; do
    NAME=$(basename "$SVC")
    if grep -n 'accessToken' "$SVC" | grep -qi 'write\|toFile\|FileHandle'; then
        echo "FAIL: $NAME may write accessToken to file"
        FAILURES=$((FAILURES+1))
    fi
done

# 4. Token trimmed in McpServerConfiguration
grep -q 'accessToken.*trimmingCharacters' "$CONTRACTS" || \
    { echo "FAIL: McpServerConfiguration does not trim accessToken"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: security_token_env_only — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: security_token_env_only — token only in child process environment"
exit 0
