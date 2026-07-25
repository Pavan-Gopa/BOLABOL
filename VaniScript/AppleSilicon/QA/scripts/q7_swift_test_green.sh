#!/usr/bin/env bash
# QA/scripts/q7_swift_test_green.sh — Q7 regression gate.
# Asserts `swift test` is green: zero test failures and a non-empty test run.
# The acceptance doc claims 267 tests / 40 suites; we hard-fail on ANY failure
# and soft-warn if the executed count drops below 267 (count drift is a warning,
# not a failure, to avoid false negatives on harmless test-count changes).
# Idempotent. Exit 0 = pass. QA script, not product code.

set -uo pipefail

AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

echo "Q7 swift test green — cwd: $AS_DIR"

out_file="$(mktemp -t q7_swift_test.XXXXXX)"
trap 'rm -f "$out_file"' EXIT

if ! swift test 2>&1 | tee "$out_file" | tail -25; then
  echo "FAIL: swift test exited non-zero"
  exit 1
fi

# Belt-and-suspenders: any explicit non-zero failure count anywhere => fail.
if grep -qE 'with [1-9][0-9]* failures?' "$out_file"; then
  echo "FAIL: swift test reported failures:"
  grep -nE 'with [1-9][0-9]* failures?' "$out_file" | tail -5
  exit 1
fi

# Primary signal: swift-testing summary, e.g.
#   "Test run with 267 tests in 40 suites passed after 0.139 seconds."
# (SwiftPM also prints an XCTest-style "Executed 0 tests, with 0 failures" line
#  when there are no XCTest cases; we must NOT read that one.)
ts_line="$(grep -E 'Test run with [0-9]+ tests?' "$out_file" | tail -1 || true)"

if [[ -n "$ts_line" ]]; then
  echo "summary: $ts_line"
  if printf '%s' "$ts_line" | grep -q 'failed'; then
    echo "FAIL: swift-testing test run failed"
    exit 1
  fi
  tests_count="$(printf '%s' "$ts_line" | sed -nE 's/.*Test run with ([0-9]+) tests?.*/\1/p')"
  tests_count="${tests_count:-0}"
  echo "executed: $tests_count (swift-testing)  failures: 0"
  if [[ "$tests_count" -lt 1 ]]; then
    echo "FAIL: no tests executed"
    exit 1
  fi
  if [[ "$tests_count" -lt 267 ]]; then
    echo "WARN: executed $tests_count tests (< 267 claimed in acceptance) — count drift, not failing."
  fi
  echo "OK: swift test green ($tests_count tests, 0 failures)"
  echo "RESULT: PASS (q7_swift_test_green)"
  exit 0
fi

# Fallback: classic XCTest summary "Executed N tests, with M failures ...".
xc_line="$(grep -E 'Executed [0-9]+ tests?' "$out_file" | tail -1 || true)"
if [[ -n "$xc_line" ]]; then
  echo "summary: $xc_line"
  tests_count="$(printf '%s' "$xc_line" | sed -nE 's/.*Executed ([0-9]+) tests?.*/\1/p')"
  failures_count="$(printf '%s' "$xc_line" | sed -nE 's/.*with ([0-9]+) failures?.*/\1/p')"
  tests_count="${tests_count:-0}"
  failures_count="${failures_count:-0}"
  echo "executed: $tests_count (XCTest)  failures: $failures_count"
  if [[ "$failures_count" -ne 0 ]]; then
    echo "FAIL: $failures_count test failure(s)"
    exit 1
  fi
  if [[ "$tests_count" -lt 1 ]]; then
    echo "FAIL: no tests executed"
    exit 1
  fi
  if [[ "$tests_count" -lt 267 ]]; then
    echo "WARN: executed $tests_count tests (< 267 claimed in acceptance) — count drift, not failing."
  fi
  echo "OK: swift test green ($tests_count tests, 0 failures)"
  echo "RESULT: PASS (q7_swift_test_green)"
  exit 0
fi

echo "FAIL: no test summary found (neither swift-testing nor XCTest) — run did not complete"
exit 1
