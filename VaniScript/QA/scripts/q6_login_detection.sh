#!/usr/bin/env bash
# QA: q6_login_detection.sh — Q6 maps CLI auth failure to .notLoggedIn via stderr
# Asserts:
#   1. A stderr collector gathers child stderr lines (QwenStreamingStderrCollector)
#   2. On non-zero exit, stderr is inspected for a "login" hint
#   3. A login hint surfaces as QwenChatError.notLoggedIn (not a generic upstream error)
#   4. Non-auth non-zero exit still surfaces as QwenChatError.upstream with the exit code
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE="$PROJECT_ROOT/AppleSilicon/Sources/VaniScriptCore/QwenAgentSupport.swift"

echo "=== q6_login_detection: stderr login -> .notLoggedIn ==="
FAILURES=0

[ -f "$CORE" ] || { echo "FAIL: QwenAgentSupport.swift not found"; exit 1; }

# 1. stderr collector actor
grep -q 'QwenStreamingStderrCollector' "$CORE" || \
    { echo "FAIL: stderr collector missing"; FAILURES=$((FAILURES+1)); }
grep -q 'standardError = errors' "$CORE" || \
    { echo "FAIL: child stderr not piped"; FAILURES=$((FAILURES+1)); }

# 2. login hint inspection on non-zero exit
grep -q 'lowered.contains("login")' "$CORE" || \
    { echo "FAIL: stderr not inspected for login hint"; FAILURES=$((FAILURES+1)); }

# 3. notLoggedIn surfaced
grep -q 'throw QwenChatError.notLoggedIn' "$CORE" || \
    { echo "FAIL: login hint not mapped to QwenChatError.notLoggedIn"; FAILURES=$((FAILURES+1)); }

# 4. generic upstream error with exit code for other failures
grep -q 'QwenChatError.upstream("qwen exited with code' "$CORE" || \
    { echo "FAIL: non-auth failure not surfaced as upstream(exit code)"; FAILURES=$((FAILURES+1)); }

# Ordering: exit-code guard precedes the login check
EXIT_LINE=$(grep -n 'guard exitCode == 0 else' "$CORE" | head -1 | cut -d: -f1)
LOGIN_LINE=$(grep -n 'lowered.contains("login")' "$CORE" | head -1 | cut -d: -f1)
if [ -n "$EXIT_LINE" ] && [ -n "$LOGIN_LINE" ] && [ "$EXIT_LINE" -ge "$LOGIN_LINE" ]; then
    echo "FAIL: exit-code guard not before login detection"
    FAILURES=$((FAILURES+1))
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: q6_login_detection — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: q6_login_detection — stderr login hint -> .notLoggedIn, else .upstream(code)"
exit 0
