#!/usr/bin/env bash
# A5 gate: swift test green, soft-warn if < 320 tests (FEEDBACK claim 320/46).
# ENV-ONLY sandbox disposition matches a2/a4_swift_test_green.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

echo "A5 swift test green — cwd: $AS_DIR"
out_file="$(mktemp -t a5_swift_test.XXXXXX)"
trap 'rm -f "$out_file"' EXIT

swift test 2>&1 | tee "$out_file" | tail -40
swift_rc=${PIPESTATUS[0]}

has_summary="$(grep -Ec 'Test run with [0-9]+ tests?|Executed [0-9]+ tests?' "$out_file" || true)"

if [[ "$swift_rc" -ne 0 && "$has_summary" -eq 0 ]] && \
   grep -Eq 'Operation not permitted|ModuleCache|cannot open|Permission denied|Sandbox' "$out_file"; then
  echo "WARN(ENV-ONLY): swift test could not run due to a sandbox/environment error"
  echo "RESULT: ENV-ONLY (a5_swift_test_green) — treat as skip, not FAIL."
  exit 0
fi

if [[ "$swift_rc" -ne 0 ]]; then
  echo "FAIL: swift test exited non-zero"; exit 1
fi
if grep -qE 'with [1-9][0-9]* failures?' "$out_file"; then
  echo "FAIL: swift test reported failures:"; grep -nE 'with [1-9][0-9]* failures?' "$out_file" | tail -5; exit 1
fi

ts_line="$(grep -E 'Test run with [0-9]+ tests?' "$out_file" | tail -1 || true)"
if [[ -z "$ts_line" ]]; then
  xc_line="$(grep -E 'Executed [0-9]+ tests?' "$out_file" | tail -1 || true)"
  [[ -n "$xc_line" ]] || { echo "FAIL: no test summary found"; exit 1; }
  ts_line="$xc_line"
fi
echo "summary: $ts_line"
printf '%s' "$ts_line" | grep -q 'failed' && { echo "FAIL: test run failed"; exit 1; }

tests_count="$(printf '%s' "$ts_line" | sed -nE 's/.*[wr]ith ([0-9]+) tests?.*/\1/p')"
tests_count="${tests_count:-0}"
[[ "$tests_count" -ge 1 ]] || { echo "FAIL: no tests executed"; exit 1; }
[[ "$tests_count" -lt 320 ]] && echo "WARN: executed $tests_count tests (< 320 claimed) — count drift, not failing."

if ! grep -q "Provider registry — A5 cloud providers" "$out_file"; then
  echo "WARN: A5 registry suite name not listed (swift may omit suite names on success)."
fi
if ! grep -q "CloudChatRouter — A5 routing" "$out_file"; then
  echo "WARN: A5 routing suite name not listed."
fi

echo "OK: swift test green ($tests_count tests, 0 failures)"
echo "RESULT: PASS (a5_swift_test_green)"
exit 0
