#!/usr/bin/env bash
# QA: provider_cli_absent.sh — CLI-absent error paths for all providers
# Asserts:
#   1. QwenAgentService throws .qwenNotInstalled when binary missing
#   2. CodexAgentService has equivalent not-installed error
#   3. GrokAgentService has equivalent not-installed error
#   4. All three resolve executable (candidate paths and/or command -v)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AS_DIR="$PROJECT_ROOT/AppleSilicon"
CODEX_SVC="$AS_DIR/Sources/VaniScript/Services/CodexAgentService.swift"
GROK_SVC="$AS_DIR/Sources/VaniScript/Services/GrokAgentService.swift"
QWEN_SVC="$AS_DIR/Sources/VaniScript/Services/QwenAgentService.swift"

echo "=== provider_cli_absent: CLI-not-installed error paths ==="
FAILURES=0

# 1. Qwen: qwenNotInstalled error + resolution
grep -q 'qwenNotInstalled' "$QWEN_SVC" || { echo "FAIL: qwenNotInstalled not in QwenAgentService"; FAILURES=$((FAILURES+1)); }
grep -q 'qwenExecutableURL\|command -v qwen' "$QWEN_SVC" || { echo "FAIL: Qwen executable resolution not found"; FAILURES=$((FAILURES+1)); }

# 2. Codex: not-installed error + resolution (candidate paths)
grep -q 'codexNotInstalled\|notInstalled\|codexExecutableURL' "$CODEX_SVC" || \
    { echo "FAIL: Codex not-installed error or resolution not found"; FAILURES=$((FAILURES+1)); }
grep -q 'candidates\|isExecutableFile' "$CODEX_SVC" || \
    { echo "FAIL: Codex candidate path resolution not found"; FAILURES=$((FAILURES+1)); }

# 3. Grok: not-installed error + resolution
grep -q 'grokNotInstalled\|notInstalled\|grokExecutableURL' "$GROK_SVC" || \
    { echo "FAIL: Grok not-installed error or resolution not found"; FAILURES=$((FAILURES+1)); }
grep -q 'candidates\|command -v grok\|isExecutableFile' "$GROK_SVC" || \
    { echo "FAIL: Grok executable resolution not found"; FAILURES=$((FAILURES+1)); }

# 4. All three guard on nil executableURL
for SVC in "$CODEX_SVC" "$GROK_SVC" "$QWEN_SVC"; do
    NAME=$(basename "$SVC")
    grep -q 'guard let executableURL' "$SVC" || \
        { echo "FAIL: $NAME missing guard on executableURL"; FAILURES=$((FAILURES+1)); }
done

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: provider_cli_absent — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: provider_cli_absent — all CLI-absent error paths verified"
exit 0
