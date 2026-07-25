#!/usr/bin/env bash
# QA: provider_codex_tests.sh — Codex agent parser unit tests
# Asserts: CodexAgentSupportTests suite passes (swift test --filter)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AS_DIR="$PROJECT_ROOT/AppleSilicon"

echo "=== provider_codex_tests: CodexAgentSupportTests ==="
cd "$AS_DIR"
swift test --filter CodexAgentSupportTests 2>&1
echo "PASS: provider_codex_tests — CodexAgentSupportTests green"
exit 0
