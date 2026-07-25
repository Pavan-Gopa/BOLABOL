#!/usr/bin/env bash
# QA: provider_qwen_tests.sh — Qwen agent parser unit tests (Q2 delta)
# Asserts: QwenAgentSupportTests suite passes (swift test --filter)
# Covers: NDJSON parsing, model catalog, fallback chain, error handling
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AS_DIR="$PROJECT_ROOT/AppleSilicon"

echo "=== provider_qwen_tests: QwenAgentSupportTests ==="
cd "$AS_DIR"
swift test --filter QwenAgentSupportTests 2>&1
echo "PASS: provider_qwen_tests — QwenAgentSupportTests green"
exit 0
