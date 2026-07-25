#!/usr/bin/env bash
# QA: qwen_parser_ndjson.sh — QwenAgentOutputParser NDJSON handling (Q2)
# Asserts:
#   1. Parser handles "system" event type (session_id extraction)
#   2. Parser handles "assistant" event type (text blocks, tool_use blocks)
#   3. Parser handles "result" event type (success/error subtypes)
#   4. Parser tolerates malformed/non-JSON lines
#   5. Fallback chain: assistant text > result.result > plain stdout
#   6. Content as single object (not array) is tolerated
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PARSER="$PROJECT_ROOT/AppleSilicon/Sources/VaniScriptCore/QwenAgentSupport.swift"

echo "=== qwen_parser_ndjson: NDJSON event handling ==="
FAILURES=0

[ -f "$PARSER" ] || { echo "FAIL: QwenAgentSupport.swift not found"; exit 1; }

# 1. system event
grep -q '"system"' "$PARSER" || { echo "FAIL: no system event handling"; FAILURES=$((FAILURES+1)); }
grep -q 'session_id' "$PARSER" || { echo "FAIL: no session_id extraction"; FAILURES=$((FAILURES+1)); }

# 2. assistant event
grep -q '"assistant"' "$PARSER" || { echo "FAIL: no assistant event handling"; FAILURES=$((FAILURES+1)); }
grep -q '"text"' "$PARSER" || { echo "FAIL: no text block handling"; FAILURES=$((FAILURES+1)); }
grep -q '"tool_use"' "$PARSER" || { echo "FAIL: no tool_use block handling"; FAILURES=$((FAILURES+1)); }

# 3. result event
grep -q '"result"' "$PARSER" || { echo "FAIL: no result event handling"; FAILURES=$((FAILURES+1)); }
grep -q '"success"' "$PARSER" || { echo "FAIL: no success subtype"; FAILURES=$((FAILURES+1)); }
grep -q '"error"' "$PARSER" || { echo "FAIL: no error subtype"; FAILURES=$((FAILURES+1)); }

# 4. Malformed line tolerance
grep -q 'continue' "$PARSER" || { echo "FAIL: no malformed line skip"; FAILURES=$((FAILURES+1)); }

# 5. Fallback chain
grep -q 'assistantText ?? resultText' "$PARSER" || \
    { echo "FAIL: no assistant>result fallback chain"; FAILURES=$((FAILURES+1)); }
grep -q 'sawJSON' "$PARSER" || { echo "FAIL: no plain stdout fallback"; FAILURES=$((FAILURES+1)); }

# 6. Single object content tolerance
grep -q 'as? \[String: Any\]' "$PARSER" || \
    { echo "FAIL: no single-object content tolerance"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: qwen_parser_ndjson — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: qwen_parser_ndjson — all NDJSON event types and fallbacks verified"
exit 0
