#!/usr/bin/env bash
# QA: q6_ndjson_parser.sh — Q6 streaming NDJSON parsing in QwenStreamingProvider
# Asserts (real-time chunk streaming, not the batch QwenAgentOutputParser):
#   1. Streams stdout line-by-line (bytes.lines)
#   2. Parses assistant.message.content[] blocks
#   3. text block -> QwenChatChunk(kind: .text(...))
#   4. tool_use block -> QwenChatChunk(kind: .toolUse(...))
#   5. Final .done chunk emitted
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE="$PROJECT_ROOT/AppleSilicon/Sources/VaniScriptCore/QwenAgentSupport.swift"

echo "=== q6_ndjson_parser: streaming NDJSON -> QwenChatChunk ==="
FAILURES=0

[ -f "$CORE" ] || { echo "FAIL: QwenAgentSupport.swift not found"; exit 1; }

# 1. Line-by-line streaming
grep -q 'fileHandleForReading.bytes.lines' "$CORE" || \
    { echo "FAIL: no bytes.lines streaming"; FAILURES=$((FAILURES+1)); }

# 2. assistant / message / content keys parsed in the streaming path
grep -q '"assistant"' "$CORE" || { echo "FAIL: no assistant event handling"; FAILURES=$((FAILURES+1)); }
grep -q '"message"' "$CORE" || { echo "FAIL: no message key handling"; FAILURES=$((FAILURES+1)); }
grep -q '"content"' "$CORE" || { echo "FAIL: no content key handling"; FAILURES=$((FAILURES+1)); }

# 3. text block -> .text chunk
grep -q 'QwenChatChunk(kind: .text(text))' "$CORE" || \
    { echo "FAIL: text block not yielded as .text chunk"; FAILURES=$((FAILURES+1)); }

# 4. tool_use block -> .toolUse chunk
grep -q '"tool_use"' "$CORE" || { echo "FAIL: no tool_use block handling"; FAILURES=$((FAILURES+1)); }
grep -q 'QwenChatChunk(kind: .toolUse(name))' "$CORE" || \
    { echo "FAIL: tool_use block not yielded as .toolUse chunk"; FAILURES=$((FAILURES+1)); }

# 5. done chunk
grep -q 'QwenChatChunk(kind: .done(' "$CORE" || \
    { echo "FAIL: no .done chunk emitted"; FAILURES=$((FAILURES+1)); }

# block type/text extraction
grep -q 'block\["type"\] as? String' "$CORE" || \
    { echo "FAIL: block type not extracted"; FAILURES=$((FAILURES+1)); }
grep -q 'block\["text"\] as? String' "$CORE" || \
    { echo "FAIL: block text not extracted"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: q6_ndjson_parser — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: q6_ndjson_parser — streaming NDJSON -> .text/.toolUse/.done verified"
exit 0
