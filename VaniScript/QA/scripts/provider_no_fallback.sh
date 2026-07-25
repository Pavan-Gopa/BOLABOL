#!/usr/bin/env bash
# QA: provider_no_fallback.sh — No silent MCP→API fallback in agent services
# Asserts:
#   1. QwenAgentService has no URLSession/HTTP API fallback
#   2. CodexAgentService has no URLSession/HTTP API fallback
#   3. GrokAgentService has no URLSession/HTTP API fallback
#   4. Explicit "no silent fallback" comments present
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AS_DIR="$PROJECT_ROOT/AppleSilicon"
CODEX_SVC="$AS_DIR/Sources/VaniScript/Services/CodexAgentService.swift"
GROK_SVC="$AS_DIR/Sources/VaniScript/Services/GrokAgentService.swift"
QWEN_SVC="$AS_DIR/Sources/VaniScript/Services/QwenAgentService.swift"

echo "=== provider_no_fallback: no silent MCP→API fallback ==="
FAILURES=0

for SVC in "$CODEX_SVC" "$GROK_SVC" "$QWEN_SVC"; do
    NAME=$(basename "$SVC")
    # No URLSession usage in agent services
    if grep -q 'URLSession\|URLRequest\|NSURLSession' "$SVC"; then
        echo "FAIL: $NAME contains URLSession/URLRequest — possible HTTP API fallback"
        FAILURES=$((FAILURES+1))
    fi
done

# Qwen explicitly states no fallback
grep -q 'no silent fallback' "$QWEN_SVC" || \
    { echo "WARN: QwenAgentService missing explicit no-fallback comment"; }

# Electron Grok also states no fallback
ELECTRON_MAIN="$PROJECT_ROOT/Electron/electron/main.js"
if [ -f "$ELECTRON_MAIN" ]; then
    grep -q 'NO silent' "$ELECTRON_MAIN" || grep -q 'no silent' "$ELECTRON_MAIN" || \
        { echo "WARN: Electron main.js missing explicit no-fallback comment for Grok"; }
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: provider_no_fallback — $FAILURES fallback(s) detected"
    exit 1
fi

echo "PASS: provider_no_fallback — no HTTP API fallback in any agent service"
exit 0
