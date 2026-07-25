#!/usr/bin/env bash
# QA: settings_decode.sh — AppSettings codex/grok/qwen sections decode
# Asserts:
#   1. UniversalSettingsTests pass (swift test --filter)
#   2. AppSettings has codexChatModelID, grokChatModelID, qwenChatModelID
#   3. AppSettings has codexChatReasoningEffort, grokChatReasoningEffort
#   4. Q2: qwenChatModelID has NO reasoningEffort field
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AS_DIR="$PROJECT_ROOT/AppleSilicon"
SETTINGS="$AS_DIR/Sources/VaniScriptCore/AppSettings.swift"

echo "=== settings_decode: codex/grok/qwen sections ==="
FAILURES=0

# 1. Run UniversalSettingsTests
cd "$AS_DIR"
swift test --filter UniversalSettingsTests 2>&1 || { echo "FAIL: UniversalSettingsTests failed"; exit 1; }

# 2. All three model ID fields
grep -q 'codexChatModelID' "$SETTINGS" || { echo "FAIL: codexChatModelID missing"; FAILURES=$((FAILURES+1)); }
grep -q 'grokChatModelID' "$SETTINGS" || { echo "FAIL: grokChatModelID missing"; FAILURES=$((FAILURES+1)); }
grep -q 'qwenChatModelID' "$SETTINGS" || { echo "FAIL: qwenChatModelID missing"; FAILURES=$((FAILURES+1)); }

# 3. Reasoning effort for codex and grok
grep -q 'codexChatReasoningEffort' "$SETTINGS" || { echo "FAIL: codexChatReasoningEffort missing"; FAILURES=$((FAILURES+1)); }
grep -q 'grokChatReasoningEffort' "$SETTINGS" || { echo "FAIL: grokChatReasoningEffort missing"; FAILURES=$((FAILURES+1)); }

# 4. Q2: NO qwenChatReasoningEffort
if grep -q 'qwenChatReasoningEffort' "$SETTINGS"; then
    echo "FAIL: qwenChatReasoningEffort should NOT exist (Qwen has no reasoning-effort flag)"
    FAILURES=$((FAILURES+1))
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: settings_decode — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: settings_decode — codex/grok/qwen sections verified"
exit 0
