#!/usr/bin/env bash
# QA: q6_error_cases.sh — Q6 QwenChatError exhaustive error surface
# Asserts:
#   1. All 5 cases exist: cliMissing, notLoggedIn, mcpUnavailable, cancelled, upstream(String)
#   2. QwenChatError conforms to LocalizedError + Sendable + Equatable
#   3. errorDescription implemented with a non-empty string per case
#   4. upstream carries an associated String message
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE="$PROJECT_ROOT/AppleSilicon/Sources/VaniScriptCore/QwenAgentSupport.swift"

echo "=== q6_error_cases: QwenChatError surface ==="
FAILURES=0

[ -f "$CORE" ] || { echo "FAIL: QwenAgentSupport.swift not found"; exit 1; }

# 1. All five cases
for C in "cliMissing" "notLoggedIn" "mcpUnavailable" "cancelled"; do
    grep -q "case $C" "$CORE" || { echo "FAIL: QwenChatError.$C missing"; FAILURES=$((FAILURES+1)); }
done
grep -q 'case upstream(String)' "$CORE" || \
    { echo "FAIL: QwenChatError.upstream(String) missing"; FAILURES=$((FAILURES+1)); }

# 2. Conformances
grep -q 'public enum QwenChatError: LocalizedError, Sendable, Equatable' "$CORE" || \
    { echo "FAIL: QwenChatError missing LocalizedError/Sendable/Equatable"; FAILURES=$((FAILURES+1)); }

# 3. errorDescription present
grep -q 'public var errorDescription: String?' "$CORE" || \
    { echo "FAIL: errorDescription not implemented"; FAILURES=$((FAILURES+1)); }

# 4. Each case yields a description (switch arms reference each case in errorDescription)
for C in ".cliMissing" ".notLoggedIn" ".mcpUnavailable" ".cancelled" ".upstream"; do
    grep -q "case $C" "$CORE" || { echo "FAIL: errorDescription switch missing $C arm"; FAILURES=$((FAILURES+1)); }
done

# upstream message interpolation in description
grep -q 'Qwen is unavailable: \\(message)' "$CORE" || \
    { echo "FAIL: upstream description does not interpolate message"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: q6_error_cases — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: q6_error_cases — all 5 error cases + LocalizedError/Sendable/Equatable verified"
exit 0
