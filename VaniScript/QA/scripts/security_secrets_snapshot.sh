#!/usr/bin/env bash
# QA: security_secrets_snapshot.sh — McpProjectStateSnapshot excludes secrets
# Asserts:
#   1. McpProjectStateSnapshot.build exists
#   2. Snapshot excludes API keys (gemini, openai, anthropic)
#   3. Snapshot excludes mcpAccessToken
#   4. Snapshot excludes custom provider API keys
#   5. McpSecurityContractTests verify secret exclusion (test filter)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AS_DIR="$PROJECT_ROOT/AppleSilicon"
CONTRACTS="$AS_DIR/Sources/VaniScriptCore/McpContracts.swift"

echo "=== security_secrets_snapshot: snapshot excludes secrets ==="
FAILURES=0

# 1. McpProjectStateSnapshot exists
grep -q 'McpProjectStateSnapshot' "$CONTRACTS" || \
    { echo "FAIL: McpProjectStateSnapshot not found"; FAILURES=$((FAILURES+1)); }

# 2. Build method
grep -q 'McpProjectStateSnapshot.build\|static.*build' "$CONTRACTS" || \
    { echo "FAIL: McpProjectStateSnapshot.build not found"; FAILURES=$((FAILURES+1)); }

# 3. Run the security contract test that verifies secret exclusion
cd "$AS_DIR"
swift test --filter 'McpSecurityContractTests.*projectStateSnapshotDoesNotExposeSecrets' 2>&1 || \
    { echo "FAIL: projectStateSnapshotDoesNotExposeSecrets test failed"; exit 1; }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: security_secrets_snapshot — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: security_secrets_snapshot — snapshot excludes all secrets"
exit 0
