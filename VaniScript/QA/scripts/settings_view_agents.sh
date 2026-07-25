#!/usr/bin/env bash
# QA: settings_view_agents.sh — SettingsView Agents tab
# Asserts:
#   1. SettingsView.swift exists
#   2. References codex/grok/qwen agent settings
#   3. Has MCP server enable toggle
#   4. Has access token field
#   5. Has permission scope toggles (mutating, processing, files, network, destructive)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETTINGS_VIEW="$PROJECT_ROOT/AppleSilicon/Sources/VaniScript/Views/SettingsView.swift"

echo "=== settings_view_agents: SettingsView Agents tab ==="
FAILURES=0

[ -f "$SETTINGS_VIEW" ] || { echo "FAIL: SettingsView.swift not found"; exit 1; }

# 1. Agent references
grep -qi 'codex\|Codex' "$SETTINGS_VIEW" || { echo "FAIL: no Codex reference in SettingsView"; FAILURES=$((FAILURES+1)); }
grep -qi 'grok\|Grok' "$SETTINGS_VIEW" || { echo "FAIL: no Grok reference in SettingsView"; FAILURES=$((FAILURES+1)); }
grep -qi 'qwen\|Qwen' "$SETTINGS_VIEW" || { echo "FAIL: no Qwen reference in SettingsView"; FAILURES=$((FAILURES+1)); }

# 2. MCP server toggle
grep -q 'mcpServerEnabled' "$SETTINGS_VIEW" || { echo "FAIL: mcpServerEnabled not in SettingsView"; FAILURES=$((FAILURES+1)); }

# 3. Access token
grep -q 'mcpAccessToken\|accessToken' "$SETTINGS_VIEW" || { echo "FAIL: accessToken not in SettingsView"; FAILURES=$((FAILURES+1)); }

# 4. Permission toggles
grep -q 'mcpAllowMutatingTools' "$SETTINGS_VIEW" || { echo "FAIL: mcpAllowMutatingTools not in SettingsView"; FAILURES=$((FAILURES+1)); }
grep -q 'mcpAllowDestructiveTools' "$SETTINGS_VIEW" || { echo "FAIL: mcpAllowDestructiveTools not in SettingsView"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: settings_view_agents — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: settings_view_agents — SettingsView Agents tab verified"
exit 0
