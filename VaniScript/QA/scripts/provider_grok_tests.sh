#!/usr/bin/env bash
# QA: provider_grok_tests.sh — Grok agent parser unit tests
# Asserts: GrokAgentSupportTests suite passes (swift test --filter)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AS_DIR="$PROJECT_ROOT/AppleSilicon"

echo "=== provider_grok_tests: GrokAgentSupportTests ==="
cd "$AS_DIR"
swift test --filter GrokAgentSupportTests 2>&1
echo "PASS: provider_grok_tests — GrokAgentSupportTests green"
exit 0
