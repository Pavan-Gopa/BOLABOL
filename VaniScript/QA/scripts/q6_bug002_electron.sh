#!/usr/bin/env bash
# QA: q6_bug002_electron.sh — BUG-002 fix: no literal "Electron" in AS MCP_INSTRUCTIONS.md
# Asserts:
#   1. grep -ci electron AppleSilicon/MCP_INSTRUCTIONS.md == 0 (App Store compliance)
#   2. The reworded phrase "desktop web build" is present (the replacement wording)
#   3. The 19789/19790 port note still distinguishes the two builds without naming Electron
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOC="$PROJECT_ROOT/AppleSilicon/MCP_INSTRUCTIONS.md"

echo "=== q6_bug002_electron: BUG-002 reword ==="
FAILURES=0

[ -f "$DOC" ] || { echo "FAIL: MCP_INSTRUCTIONS.md not found"; exit 1; }

# 1. Zero occurrences of "electron" (case-insensitive)
COUNT=$(grep -ci electron "$DOC" || true)
echo "  electron occurrences: $COUNT"
if [ "$COUNT" -ne 0 ]; then
    echo "FAIL: MCP_INSTRUCTIONS.md still contains 'Electron' ($COUNT occurrence(s)) — breaks AppStoreNativeComplianceTests"
    grep -ni electron "$DOC"
    FAILURES=$((FAILURES+1))
fi

# 2. Replacement wording present
grep -qi 'desktop web build' "$DOC" || \
    { echo "FAIL: replacement phrase 'desktop web build' not found"; FAILURES=$((FAILURES+1)); }

# 3. Port note still present (19789 web build / 19790 native)
grep -q '19789' "$DOC" || { echo "FAIL: port 19789 note missing"; FAILURES=$((FAILURES+1)); }
grep -q '19790' "$DOC" || { echo "FAIL: port 19790 note missing"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: q6_bug002_electron — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: q6_bug002_electron — 0 'Electron' occurrences, reworded to 'desktop web build'"
exit 0
