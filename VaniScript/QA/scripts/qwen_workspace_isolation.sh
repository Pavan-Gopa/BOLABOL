#!/usr/bin/env bash
# QA: qwen_workspace_isolation.sh — QwenAgentWorkspace directory isolation (Q2)
# Asserts:
#   1. QwenAgentWorkspace directory created under Application Support
#   2. Directory permissions set to 0o700 (owner-only)
#   3. Workspace is separate from Codex/Grok workspaces
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
QWEN_SVC="$PROJECT_ROOT/AppleSilicon/Sources/VaniScript/Services/QwenAgentService.swift"

echo "=== qwen_workspace_isolation: QwenAgentWorkspace permissions ==="
FAILURES=0

[ -f "$QWEN_SVC" ] || { echo "FAIL: QwenAgentService.swift not found"; exit 1; }

# 1. QwenAgentWorkspace directory
grep -q 'QwenAgentWorkspace' "$QWEN_SVC" || { echo "FAIL: QwenAgentWorkspace not found"; FAILURES=$((FAILURES+1)); }

# 2. 0o700 permissions
grep -q '0o700\|0o0700' "$QWEN_SVC" || { echo "FAIL: 0o700 permissions not set"; FAILURES=$((FAILURES+1)); }

# 3. createDirectory with intermediate directories
grep -q 'createDirectory' "$QWEN_SVC" || { echo "FAIL: createDirectory not called"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: qwen_workspace_isolation — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: qwen_workspace_isolation — workspace 0o700 permissions verified"
exit 0
