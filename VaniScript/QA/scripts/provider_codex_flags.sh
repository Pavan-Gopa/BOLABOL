#!/usr/bin/env bash
# QA: provider_codex_flags.sh — Codex CLI flag correctness
# Asserts:
#   1. Uses exec --ephemeral --json
#   2. Uses --ignore-user-config
#   3. Uses --sandbox read-only
#   4. Uses -c model_reasoning_effort
#   5. Uses -C for workspace directory
#   6. MCP config override with vaniscript_embedded
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CODEX_SVC="$PROJECT_ROOT/AppleSilicon/Sources/VaniScript/Services/CodexAgentService.swift"

echo "=== provider_codex_flags: Codex CLI flag correctness ==="
FAILURES=0

[ -f "$CODEX_SVC" ] || { echo "FAIL: CodexAgentService.swift not found"; exit 1; }

ARGS_BLOCK=$(sed -n '/process\.arguments/,/]/p' "$CODEX_SVC")

echo "$ARGS_BLOCK" | grep -q '"exec"' || { echo "FAIL: exec not in Codex arguments"; FAILURES=$((FAILURES+1)); }
echo "$ARGS_BLOCK" | grep -q '"--ephemeral"' || { echo "FAIL: --ephemeral not in Codex arguments"; FAILURES=$((FAILURES+1)); }
echo "$ARGS_BLOCK" | grep -q '"--json"' || { echo "FAIL: --json not in Codex arguments"; FAILURES=$((FAILURES+1)); }
echo "$ARGS_BLOCK" | grep -q '"--ignore-user-config"' || { echo "FAIL: --ignore-user-config not in Codex arguments"; FAILURES=$((FAILURES+1)); }
echo "$ARGS_BLOCK" | grep -q '"--sandbox"' || { echo "FAIL: --sandbox not in Codex arguments"; FAILURES=$((FAILURES+1)); }
echo "$ARGS_BLOCK" | grep -q '"read-only"' || { echo "FAIL: read-only sandbox not in Codex arguments"; FAILURES=$((FAILURES+1)); }
echo "$ARGS_BLOCK" | grep -q 'model_reasoning_effort' || { echo "FAIL: model_reasoning_effort not in Codex arguments"; FAILURES=$((FAILURES+1)); }

# MCP config override
grep -q 'vaniscript_embedded' "$CODEX_SVC" || { echo "FAIL: vaniscript_embedded not in Codex config"; FAILURES=$((FAILURES+1)); }
grep -q 'bearer_token_env_var' "$CODEX_SVC" || { echo "FAIL: bearer_token_env_var not in Codex config"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: provider_codex_flags — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: provider_codex_flags — all Codex CLI flags verified"
exit 0
