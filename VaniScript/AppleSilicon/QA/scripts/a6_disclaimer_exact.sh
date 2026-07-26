#!/usr/bin/env bash
# A6: exact Electron disclaimer string (character-for-character).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/UsageStatisticsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

EXACT='Cost is an estimate based on locally counted text tokens; provider billing can differ.'
if ! grep -Fq "$EXACT" "$FILE"; then
  echo "FAIL: exact disclaimer string missing"
  echo "expected: $EXACT"
  exit 1
fi
# Count occurrences — at least one literal
count=$(grep -Fc "$EXACT" "$FILE" || true)
[[ "$count" -ge 1 ]] || { echo "FAIL: disclaimer count < 1"; exit 1; }
echo "PASS: exact disclaimer string present ($count occurrence(s))."
