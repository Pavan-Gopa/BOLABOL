#!/usr/bin/env bash
# QA: q6_streaming_api_surface.sh — Q6 public streaming API surface in VaniScriptCore
# Asserts (all symbols public in QwenAgentSupport.swift):
#   1. QwenStreamingProvider  — public final class conforming to QwenChatProvider
#   2. QwenChatChunk          — public struct (Sendable, Equatable)
#   3. QwenChatError          — public enum (LocalizedError, Sendable, Equatable)
#   4. QwenChatProvider       — public protocol (Sendable)
#   5. QwenChatHistoryItem    — public struct (Sendable, Equatable)
#   6. QwenChatChunk.Kind cases: .text(String), .toolUse(String), .done(QwenAgentRun)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE="$PROJECT_ROOT/AppleSilicon/Sources/VaniScriptCore/QwenAgentSupport.swift"

echo "=== q6_streaming_api_surface: public API surface ==="
FAILURES=0

[ -f "$CORE" ] || { echo "FAIL: QwenAgentSupport.swift not found"; exit 1; }

# 1-5. Public type declarations
grep -q 'public final class QwenStreamingProvider: QwenChatProvider' "$CORE" || \
    { echo "FAIL: QwenStreamingProvider not public final class QwenChatProvider"; FAILURES=$((FAILURES+1)); }
grep -q 'public struct QwenChatChunk: Sendable, Equatable' "$CORE" || \
    { echo "FAIL: QwenChatChunk not public/Sendable/Equatable"; FAILURES=$((FAILURES+1)); }
grep -q 'public enum QwenChatError: LocalizedError, Sendable, Equatable' "$CORE" || \
    { echo "FAIL: QwenChatError not public/LocalizedError/Sendable/Equatable"; FAILURES=$((FAILURES+1)); }
grep -q 'public protocol QwenChatProvider: Sendable' "$CORE" || \
    { echo "FAIL: QwenChatProvider not public/Sendable protocol"; FAILURES=$((FAILURES+1)); }
grep -q 'public struct QwenChatHistoryItem: Sendable, Equatable' "$CORE" || \
    { echo "FAIL: QwenChatHistoryItem not public/Sendable/Equatable"; FAILURES=$((FAILURES+1)); }

# 6. Kind cases
grep -q 'case text(String)' "$CORE" || \
    { echo "FAIL: Kind.text(String) missing"; FAILURES=$((FAILURES+1)); }
grep -q 'case toolUse(String)' "$CORE" || \
    { echo "FAIL: Kind.toolUse(String) missing"; FAILURES=$((FAILURES+1)); }
grep -q 'case done(QwenAgentRun)' "$CORE" || \
    { echo "FAIL: Kind.done(QwenAgentRun) missing"; FAILURES=$((FAILURES+1)); }

# Public init / send / cancel on the provider
grep -q 'public init()' "$CORE" || \
    { echo "FAIL: QwenStreamingProvider.public init() missing"; FAILURES=$((FAILURES+1)); }
grep -q 'public func send(' "$CORE" || \
    { echo "FAIL: QwenChatProvider.send not public"; FAILURES=$((FAILURES+1)); }
grep -q 'public func cancel()' "$CORE" || \
    { echo "FAIL: QwenChatProvider.cancel not public"; FAILURES=$((FAILURES+1)); }

# AsyncThrowingStream return type
grep -q 'AsyncThrowingStream<QwenChatChunk, Error>' "$CORE" || \
    { echo "FAIL: send() does not return AsyncThrowingStream<QwenChatChunk, Error>"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: q6_streaming_api_surface — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: q6_streaming_api_surface — all 5 public types + Kind cases verified"
exit 0
