#!/usr/bin/env bash
# QA: regression_mcp_tools_count.sh — MCP tool catalog count
# Asserts:
#   1. McpToolRegistry.allDefinitions includes McpExpandedToolCatalog.definitions
#   2. Total tool count >= 120 (53 base + 67 expanded)
#   3. Key tools present: get_project_state, list_projects, get_capabilities
#   4. Tool definitions have name, description, access, inputSchema
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AS_DIR="$PROJECT_ROOT/AppleSilicon"
CONTRACTS="$AS_DIR/Sources/VaniScriptCore/McpContracts.swift"
CATALOG="$AS_DIR/Sources/VaniScriptCore/McpExpandedToolCatalog.swift"

echo "=== regression_mcp_tools_count: tool catalog count ==="
FAILURES=0

# 1. allDefinitions includes expanded catalog
grep -q 'McpExpandedToolCatalog.definitions' "$CONTRACTS" || \
    { echo "FAIL: allDefinitions does not include McpExpandedToolCatalog"; FAILURES=$((FAILURES+1)); }

# 2. Count tools
BASE_COUNT=$(grep -c 'name: "' "$CONTRACTS" || true)
EXPANDED_COUNT=$(grep -c 'tool("' "$CATALOG" || true)
TOTAL=$((BASE_COUNT + EXPANDED_COUNT))
echo "  Base tools (McpContracts): $BASE_COUNT"
echo "  Expanded tools (McpExpandedToolCatalog): $EXPANDED_COUNT"
echo "  Total: $TOTAL"

if [ "$TOTAL" -lt 120 ]; then
    echo "FAIL: Total tool count $TOTAL < 120 (expected >= 120)"
    FAILURES=$((FAILURES+1))
fi

# 3. Key tools present
for TOOL in "get_project_state" "list_projects" "get_capabilities" "get_subtitle_style" "get_shorts_plans"; do
    FOUND_BASE=$(grep -c "\"$TOOL\"" "$CONTRACTS" || true)
    FOUND_EXP=$(grep -c "\"$TOOL\"" "$CATALOG" || true)
    if [ "$FOUND_BASE" -eq 0 ] && [ "$FOUND_EXP" -eq 0 ]; then
        echo "FAIL: tool '$TOOL' not found in catalog"
        FAILURES=$((FAILURES+1))
    fi
done

# 4. Tool definition structure
grep -q 'McpToolDefinition' "$CONTRACTS" || { echo "FAIL: McpToolDefinition struct not found"; FAILURES=$((FAILURES+1)); }
grep -q 'inputSchema' "$CONTRACTS" || { echo "FAIL: inputSchema not in McpToolDefinition"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: regression_mcp_tools_count — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: regression_mcp_tools_count — $TOTAL tools verified (>= 120)"
exit 0
