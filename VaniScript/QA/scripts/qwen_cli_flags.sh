#!/usr/bin/env bash
# QA: qwen_cli_flags.sh — Qwen CLI flag correctness (Q2)
# Asserts:
#   1. Prompt passed via -p (not --prompt-file)
#   2. Output format is -o stream-json (not --output-format streaming-json)
#   3. Model passed via -m
#   4. No --prompt-file flag
#   5. No --output-format flag
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
QWEN_SVC="$PROJECT_ROOT/AppleSilicon/Sources/VaniScript/Services/QwenAgentService.swift"

echo "=== qwen_cli_flags: Qwen CLI flag correctness ==="
FAILURES=0

[ -f "$QWEN_SVC" ] || { echo "FAIL: QwenAgentService.swift not found"; exit 1; }

# Extract arguments block
ARGS_BLOCK=$(sed -n '/process\.arguments/,/]/p' "$QWEN_SVC")

# 1. -p flag for prompt
echo "$ARGS_BLOCK" | grep -q '"-p"' || { echo "FAIL: -p flag not in Qwen arguments"; FAILURES=$((FAILURES+1)); }

# 2. -o stream-json
echo "$ARGS_BLOCK" | grep -q '"-o"' || { echo "FAIL: -o flag not in Qwen arguments"; FAILURES=$((FAILURES+1)); }
echo "$ARGS_BLOCK" | grep -q '"stream-json"' || { echo "FAIL: stream-json not in Qwen arguments"; FAILURES=$((FAILURES+1)); }

# 3. -m for model
echo "$ARGS_BLOCK" | grep -q '"-m"' || { echo "FAIL: -m flag not in Qwen arguments"; FAILURES=$((FAILURES+1)); }

# 4. No --prompt-file
if echo "$ARGS_BLOCK" | grep -q 'prompt-file'; then
    echo "FAIL: --prompt-file found in Qwen arguments (should use -p)"
    FAILURES=$((FAILURES+1))
fi

# 5. No --output-format
if echo "$ARGS_BLOCK" | grep -q 'output-format'; then
    echo "FAIL: --output-format found in Qwen arguments (should use -o)"
    FAILURES=$((FAILURES+1))
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: qwen_cli_flags — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: qwen_cli_flags — -p, -o stream-json, -m verified"
exit 0
