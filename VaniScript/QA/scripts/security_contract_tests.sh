#!/usr/bin/env bash
# QA: security_contract_tests.sh — McpSecurityContractTests suite
# Asserts: All MCP security contract tests pass (swift test --filter)
# Covers: defaults closed, token generation, profile catalog, tool permissions,
#         secret exclusion from snapshots, client classifier
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AS_DIR="$PROJECT_ROOT/AppleSilicon"

echo "=== security_contract_tests: McpSecurityContractTests ==="
cd "$AS_DIR"
swift test --filter McpSecurityContractTests 2>&1
echo "PASS: security_contract_tests — McpSecurityContractTests green"
exit 0
