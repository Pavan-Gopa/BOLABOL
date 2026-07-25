#!/usr/bin/env bash
# QA: q6_helpers_internal.sh — Q6 shared CLI helpers visibility
# Asserts:
#   1. App-layer QwenAgentService helpers are internal (NOT private) so tests/peers can reach them:
#      qwenExecutableURL, embeddedWorkspaceURL, writeIsolatedMcpConfig, qwenEnvironment, prompt
#   2. VaniScriptCore exposes the shared helpers as public free functions:
#      qwenExecutableURL, embeddedWorkspaceURL, writeIsolatedMcpConfig, qwenEnvironment, qwenChatPrompt
#   3. send() behaviour in the service is unchanged (still throws QwenAgentError, returns QwenAgentResponse)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE="$PROJECT_ROOT/AppleSilicon/Sources/VaniScriptCore/QwenAgentSupport.swift"
SVC="$PROJECT_ROOT/AppleSilicon/Sources/VaniScript/Services/QwenAgentService.swift"

echo "=== q6_helpers_internal: helper visibility ==="
FAILURES=0

[ -f "$CORE" ] || { echo "FAIL: QwenAgentSupport.swift not found"; exit 1; }
[ -f "$SVC" ] || { echo "FAIL: QwenAgentService.swift not found"; exit 1; }

# 1. Service helpers are internal static funcs (present, and NOT private)
for H in "qwenExecutableURL" "embeddedWorkspaceURL" "writeIsolatedMcpConfig" "qwenEnvironment" "prompt"; do
    grep -q "static func $H" "$SVC" || \
        { echo "FAIL: QwenAgentService.$H helper missing"; FAILURES=$((FAILURES+1)); }
done
# None of those helpers may be private anymore
for H in "qwenExecutableURL" "embeddedWorkspaceURL" "writeIsolatedMcpConfig" "qwenEnvironment" "prompt"; do
    if grep -q "private static func $H" "$SVC"; then
        echo "FAIL: QwenAgentService.$H is still private (must be internal)"
        FAILURES=$((FAILURES+1))
    fi
done

# 2. Core public free functions
for F in "qwenExecutableURL" "embeddedWorkspaceURL" "writeIsolatedMcpConfig" "qwenEnvironment" "qwenChatPrompt"; do
    grep -q "public func $F" "$CORE" || \
        { echo "FAIL: Core public func $F missing"; FAILURES=$((FAILURES+1)); }
done

# 3. Service send() behaviour unchanged
grep -q 'static func send(' "$SVC" || \
    { echo "FAIL: QwenAgentService.send missing"; FAILURES=$((FAILURES+1)); }
grep -q 'async throws -> QwenAgentResponse' "$SVC" || \
    { echo "FAIL: QwenAgentService.send signature changed"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: q6_helpers_internal — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: q6_helpers_internal — service helpers internal, Core helpers public"
exit 0
