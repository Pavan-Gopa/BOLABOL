#!/usr/bin/env bash
# QA: qwen_no_reasoning.sh — Qwen has NO reasoningEffort (Q2)
# Asserts:
#   1. QwenAgentService does NOT pass --reasoning-effort
#   2. QwenAgentService does NOT reference reasoningEffort
#   3. AppSettings has NO qwenChatReasoningEffort field
#   4. QwenChatModelOption has NO reasoningEfforts property
#   5. Codex and Grok DO have reasoningEffort (contrast check)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AS_DIR="$PROJECT_ROOT/AppleSilicon"
QWEN_SVC="$AS_DIR/Sources/VaniScript/Services/QwenAgentService.swift"
QWEN_SUPPORT="$AS_DIR/Sources/VaniScriptCore/QwenAgentSupport.swift"
SETTINGS="$AS_DIR/Sources/VaniScriptCore/AppSettings.swift"
CODEX_SVC="$AS_DIR/Sources/VaniScript/Services/CodexAgentService.swift"
GROK_SVC="$AS_DIR/Sources/VaniScript/Services/GrokAgentService.swift"

echo "=== qwen_no_reasoning: no reasoningEffort for Qwen ==="
FAILURES=0

# 1. No --reasoning-effort in QwenAgentService arguments
if grep -q 'reasoning.effort\|reasoningEffort' "$QWEN_SVC"; then
    # Allow the comment "No --reasoning-effort" but not actual usage
    ACTUAL_USAGE=$(grep -v '^\s*//' "$QWEN_SVC" | grep -c 'reasoning.effort\|reasoningEffort' || true)
    if [ "$ACTUAL_USAGE" -gt 0 ]; then
        echo "FAIL: QwenAgentService has reasoningEffort in code (not just comments)"
        FAILURES=$((FAILURES+1))
    fi
fi

# 2. No reasoningEfforts in QwenChatModelOption
if grep -q 'reasoningEfforts' "$QWEN_SUPPORT"; then
    echo "FAIL: QwenChatModelOption has reasoningEfforts property"
    FAILURES=$((FAILURES+1))
fi

# 3. No qwenChatReasoningEffort in AppSettings
if grep -q 'qwenChatReasoningEffort' "$SETTINGS"; then
    echo "FAIL: AppSettings has qwenChatReasoningEffort field"
    FAILURES=$((FAILURES+1))
fi

# 4. Contrast: Codex and Grok DO have reasoningEffort
grep -q 'reasoningEffort' "$CODEX_SVC" || { echo "FAIL: Codex missing reasoningEffort (contrast)"; FAILURES=$((FAILURES+1)); }
grep -q 'reasoningEffort' "$GROK_SVC" || { echo "FAIL: Grok missing reasoningEffort (contrast)"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: qwen_no_reasoning — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: qwen_no_reasoning — Qwen has no reasoningEffort, Codex/Grok do"
exit 0
