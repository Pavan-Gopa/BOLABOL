#!/usr/bin/env bash
# QA: settings_backward_compat.sh — Old JSON without qwen fields decodes correctly
# Asserts:
#   1. decodeIfPresent used for qwenChatModelID (missing key → default)
#   2. decodeIfPresent used for codexChatModelID (missing key → default)
#   3. decodeIfPresent used for grokChatModelID (missing key → default)
#   4. Default values reference catalog defaults
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETTINGS="$PROJECT_ROOT/AppleSilicon/Sources/VaniScriptCore/AppSettings.swift"

echo "=== settings_backward_compat: decodeIfPresent for agent fields ==="
FAILURES=0

# All agent model fields use decodeIfPresent for backward compat
grep -q 'decodeIfPresent.*codexChatModelID' "$SETTINGS" || \
    { echo "FAIL: codexChatModelID not using decodeIfPresent"; FAILURES=$((FAILURES+1)); }
grep -q 'decodeIfPresent.*grokChatModelID' "$SETTINGS" || \
    { echo "FAIL: grokChatModelID not using decodeIfPresent"; FAILURES=$((FAILURES+1)); }
grep -q 'decodeIfPresent.*qwenChatModelID' "$SETTINGS" || \
    { echo "FAIL: qwenChatModelID not using decodeIfPresent"; FAILURES=$((FAILURES+1)); }
grep -q 'decodeIfPresent.*codexChatReasoningEffort' "$SETTINGS" || \
    { echo "FAIL: codexChatReasoningEffort not using decodeIfPresent"; FAILURES=$((FAILURES+1)); }
grep -q 'decodeIfPresent.*grokChatReasoningEffort' "$SETTINGS" || \
    { echo "FAIL: grokChatReasoningEffort not using decodeIfPresent"; FAILURES=$((FAILURES+1)); }

# Defaults reference catalog
grep -q 'CodexChatModelCatalog.defaultModelID' "$SETTINGS" || \
    { echo "FAIL: codex default not from CodexChatModelCatalog"; FAILURES=$((FAILURES+1)); }
grep -q 'GrokChatModelCatalog.defaultModelID' "$SETTINGS" || \
    { echo "FAIL: grok default not from GrokChatModelCatalog"; FAILURES=$((FAILURES+1)); }
grep -q 'QwenChatModelCatalog.defaultModelID' "$SETTINGS" || \
    { echo "FAIL: qwen default not from QwenChatModelCatalog"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: settings_backward_compat — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: settings_backward_compat — all agent fields use decodeIfPresent with catalog defaults"
exit 0
