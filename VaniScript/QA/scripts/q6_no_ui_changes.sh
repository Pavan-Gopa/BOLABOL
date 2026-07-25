#!/usr/bin/env bash
# QA: q6_no_ui_changes.sh — Q6 touched NO UI files (API-hardening only)
# Asserts (working tree vs qwen/pre-Q6 baseline):
#   1. ChatSidebarView.swift and SettingsView.swift are NOT modified
#   2. No file under Sources/VaniScript/Views is modified
#   3. The expected Q6 source/test files ARE the ones modified
#      (QwenAgentSupport.swift, QwenAgentService.swift, QwenAgentSupportTests.swift)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== q6_no_ui_changes: no UI changes in Q6 ==="
FAILURES=0

cd "$PROJECT_ROOT"

# Resolve baseline: prefer the pre-Q6 tag, fall back to the known checkpoint commit.
BASE="$(git rev-parse --verify qwen/pre-Q6 2>/dev/null || echo b779a23)"
git rev-parse --verify "$BASE" >/dev/null 2>&1 || { echo "FAIL: baseline $BASE not resolvable"; exit 1; }
echo "  baseline: $BASE"

# Changed source/test files (working tree vs baseline), scoped to AppleSilicon code.
CHANGED="$(git diff --name-only "$BASE" -- AppleSilicon/Sources AppleSilicon/Tests)"
echo "  changed code files:"
echo "$CHANGED" | sed 's/^/    /'

# 1. Specific UI views must be untouched
for UI in "ChatSidebarView.swift" "SettingsView.swift"; do
    if echo "$CHANGED" | grep -q "$UI"; then
        echo "FAIL: $UI was modified in Q6 (UI must be unchanged)"
        FAILURES=$((FAILURES+1))
    fi
done

# 2. Nothing under the Views directory at all
if echo "$CHANGED" | grep -q 'Sources/VaniScript/Views/'; then
    echo "FAIL: a file under Sources/VaniScript/Views was modified in Q6"
    echo "$CHANGED" | grep 'Sources/VaniScript/Views/'
    FAILURES=$((FAILURES+1))
fi

# 3. Expected Q6 files are present in the diff
for F in "Sources/VaniScriptCore/QwenAgentSupport.swift" \
         "Sources/VaniScript/Services/QwenAgentService.swift" \
         "Tests/VaniScriptCoreTests/QwenAgentSupportTests.swift"; do
    echo "$CHANGED" | grep -q "$F" || \
        { echo "FAIL: expected Q6 change missing: $F"; FAILURES=$((FAILURES+1)); }
done

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: q6_no_ui_changes — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: q6_no_ui_changes — no UI/Views changes; only Q6 API files modified"
exit 0
