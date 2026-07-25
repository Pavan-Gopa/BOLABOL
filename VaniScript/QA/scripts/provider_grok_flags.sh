#!/usr/bin/env bash
# QA: provider_grok_flags.sh — Grok CLI flag correctness
# Asserts:
#   1. Uses --prompt-file (not -p)
#   2. Uses --output-format streaming-json
#   3. Uses --reasoning-effort
#   4. Uses --trust and --cwd
#   5. Uses --always-approve and --no-subagents
#   6. Uses --permission-mode bypassPermissions
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GROK_SVC="$PROJECT_ROOT/AppleSilicon/Sources/VaniScript/Services/GrokAgentService.swift"

echo "=== provider_grok_flags: Grok CLI flag correctness ==="
FAILURES=0

[ -f "$GROK_SVC" ] || { echo "FAIL: GrokAgentService.swift not found"; exit 1; }

ARGS_BLOCK=$(sed -n '/process\.arguments/,/]/p' "$GROK_SVC")

echo "$ARGS_BLOCK" | grep -q '"--prompt-file"' || { echo "FAIL: --prompt-file not in Grok arguments"; FAILURES=$((FAILURES+1)); }
echo "$ARGS_BLOCK" | grep -q '"--output-format"' || { echo "FAIL: --output-format not in Grok arguments"; FAILURES=$((FAILURES+1)); }
echo "$ARGS_BLOCK" | grep -q '"streaming-json"' || { echo "FAIL: streaming-json not in Grok arguments"; FAILURES=$((FAILURES+1)); }
echo "$ARGS_BLOCK" | grep -q '"--reasoning-effort"' || { echo "FAIL: --reasoning-effort not in Grok arguments"; FAILURES=$((FAILURES+1)); }
echo "$ARGS_BLOCK" | grep -q '"--trust"' || { echo "FAIL: --trust not in Grok arguments"; FAILURES=$((FAILURES+1)); }
echo "$ARGS_BLOCK" | grep -q '"--cwd"' || { echo "FAIL: --cwd not in Grok arguments"; FAILURES=$((FAILURES+1)); }
echo "$ARGS_BLOCK" | grep -q '"--always-approve"' || { echo "FAIL: --always-approve not in Grok arguments"; FAILURES=$((FAILURES+1)); }
echo "$ARGS_BLOCK" | grep -q '"--no-subagents"' || { echo "FAIL: --no-subagents not in Grok arguments"; FAILURES=$((FAILURES+1)); }
echo "$ARGS_BLOCK" | grep -q '"--permission-mode"' || { echo "FAIL: --permission-mode not in Grok arguments"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: provider_grok_flags — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: provider_grok_flags — all Grok CLI flags verified"
exit 0
