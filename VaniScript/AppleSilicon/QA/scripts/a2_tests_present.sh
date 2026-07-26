#!/usr/bin/env bash
# QA/scripts/a2_tests_present.sh — A2 (Done §5): UsageRecorder is covered by unit tests
# on mock data. Assert the suite exists in VaniScriptCoreTests, is the A2 suite, imports
# the Core module testably, and contains exactly 14 @Test cases (per FEEDBACK/ADR).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

FILE="Tests/VaniScriptCoreTests/UsageRecorderTests.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

grep -Fq '@Suite("UsageRecorder (A2)")' "$FILE" \
  || { echo "FAIL: UsageRecorderTests must declare @Suite(\"UsageRecorder (A2)\")"; exit 1; }
grep -Fq "@testable import VaniScriptCore" "$FILE" \
  || { echo "FAIL: tests must @testable import VaniScriptCore"; exit 1; }

n="$(grep -Fc "@Test(" "$FILE")"
[[ "$n" -eq 14 ]] || { echo "FAIL: expected exactly 14 @Test cases in UsageRecorderTests, got $n"; exit 1; }

echo "PASS: UsageRecorderTests (A2) present with 14 @Test cases."
