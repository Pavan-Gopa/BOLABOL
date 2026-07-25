#!/usr/bin/env bash
# QA: q6_token_env_only.sh — Q6 streaming provider keeps token out of argv
# Asserts:
#   1. process.arguments in QwenStreamingProvider contains NO token (only -p/-o/-m + prompt/model)
#   2. Token reaches the child only via process.environment = qwenEnvironment(accessToken:)
#   3. qwenEnvironment stores token under QwenMcpConfig.accessTokenEnvironmentKey (env substitution)
#   4. No accessToken written to file / logged in the streaming path
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE="$PROJECT_ROOT/AppleSilicon/Sources/VaniScriptCore/QwenAgentSupport.swift"

echo "=== q6_token_env_only: token never in argv ==="
FAILURES=0

[ -f "$CORE" ] || { echo "FAIL: QwenAgentSupport.swift not found"; exit 1; }

# 1. The process.arguments line must not mention token/accessToken
ARGV_LINES=$(grep -n 'process.arguments' "$CORE" || true)
[ -n "$ARGV_LINES" ] || { echo "FAIL: no process.arguments assignment found"; FAILURES=$((FAILURES+1)); }
if echo "$ARGV_LINES" | grep -iq 'token'; then
    echo "FAIL: process.arguments references a token -> secret would leak into argv"
    echo "$ARGV_LINES" | grep -i 'token'
    FAILURES=$((FAILURES+1))
fi

# The argv must be the fixed CLI flag set (prompt passed as value, not a secret)
grep -q 'process.arguments = \["-p", prompt, "-o", "stream-json", "-m", modelID\]' "$CORE" || \
    { echo "FAIL: streaming argv is not the expected [-p,-o stream-json,-m] shape"; FAILURES=$((FAILURES+1)); }

# 2. Token via environment only
grep -q 'process.environment = qwenEnvironment(' "$CORE" || \
    { echo "FAIL: token not set via process.environment = qwenEnvironment(...)"; FAILURES=$((FAILURES+1)); }
grep -q 'accessToken: mcpConfiguration.accessToken' "$CORE" || \
    { echo "FAIL: qwenEnvironment not fed mcpConfiguration.accessToken"; FAILURES=$((FAILURES+1)); }

# 3. qwenEnvironment stores token under the env key (never inlined into a file)
grep -q 'environment\[QwenMcpConfig.accessTokenEnvironmentKey\] = accessToken' "$CORE" || \
    { echo "FAIL: qwenEnvironment does not store token under accessTokenEnvironmentKey"; FAILURES=$((FAILURES+1)); }

# 4. No file write / logging of accessToken in the streaming file
if grep -n 'accessToken' "$CORE" | grep -iq 'write\|toFile\|FileHandle\|print(\|os_log\|logger'; then
    echo "FAIL: accessToken may be written/logged in QwenAgentSupport.swift"
    FAILURES=$((FAILURES+1))
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: q6_token_env_only — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: q6_token_env_only — token only in child environment, never in argv"
exit 0
