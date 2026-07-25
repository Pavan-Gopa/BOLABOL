#!/usr/bin/env bash
# QA: q6_history_item_public.sh — Q6 QwenChatHistoryItem moved to VaniScriptCore
# Asserts:
#   1. QwenChatHistoryItem is a public struct in VaniScriptCore (QwenAgentSupport.swift)
#   2. It is Sendable + Equatable with public sender/text fields and public init
#   3. The duplicate definition was REMOVED from the app-layer QwenAgentService.swift
#      (single source of truth so QwenChatProvider protocol can reference it)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE="$PROJECT_ROOT/AppleSilicon/Sources/VaniScriptCore/QwenAgentSupport.swift"
SVC="$PROJECT_ROOT/AppleSilicon/Sources/VaniScript/Services/QwenAgentService.swift"

echo "=== q6_history_item_public: QwenChatHistoryItem in Core ==="
FAILURES=0

[ -f "$CORE" ] || { echo "FAIL: QwenAgentSupport.swift not found"; exit 1; }
[ -f "$SVC" ] || { echo "FAIL: QwenAgentService.swift not found"; exit 1; }

# 1. Public struct in Core
grep -q 'public struct QwenChatHistoryItem: Sendable, Equatable' "$CORE" || \
    { echo "FAIL: QwenChatHistoryItem not public/Sendable/Equatable in Core"; FAILURES=$((FAILURES+1)); }

# 2. Public members
grep -q 'public let sender: String' "$CORE" || \
    { echo "FAIL: sender not public"; FAILURES=$((FAILURES+1)); }
grep -q 'public let text: String' "$CORE" || \
    { echo "FAIL: text not public"; FAILURES=$((FAILURES+1)); }
grep -q 'public init(sender: String, text: String)' "$CORE" || \
    { echo "FAIL: public init(sender:text:) missing"; FAILURES=$((FAILURES+1)); }

# 3. Duplicate removed from app-layer service
if grep -q 'struct QwenChatHistoryItem' "$SVC"; then
    echo "FAIL: QwenChatHistoryItem still defined in QwenAgentService.swift (duplicate, must be removed)"
    FAILURES=$((FAILURES+1))
fi

# Service must import VaniScriptCore to use the shared type
grep -q 'import VaniScriptCore' "$SVC" || \
    { echo "FAIL: QwenAgentService does not import VaniScriptCore"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: q6_history_item_public — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: q6_history_item_public — QwenChatHistoryItem public in Core, duplicate removed"
exit 0
