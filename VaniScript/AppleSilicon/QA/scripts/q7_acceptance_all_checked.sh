#!/usr/bin/env bash
# QA/scripts/q7_acceptance_all_checked.sh — Q7 delta (doc-only).
# Asserts QWEN_MCP_ACCEPTANCE.md is fully checked: every box [x], no open [ ],
# and the final verdict line "ИТОГ: [PASS]" is present.
# Idempotent, deterministic. Exit 0 = pass. QA script, not product code.

set -uo pipefail

AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC="$AS_DIR/AI_Workflow_Kit/docs/QWEN_MCP_ACCEPTANCE.md"

echo "Q7 acceptance all-checked — $DOC"

if [[ ! -f "$DOC" ]]; then
  echo "FAIL: acceptance doc missing: $DOC"
  exit 1
fi

fail=0

open_count="$(grep -cF '[ ]' "$DOC" || true)"
if [[ "${open_count:-0}" -ne 0 ]]; then
  echo "FAIL: found $open_count unchecked box(es) '[ ]' in acceptance doc"
  grep -nF '[ ]' "$DOC"
  fail=1
else
  echo "OK: no unchecked '[ ]' boxes"
fi

checked_count="$(grep -cF '[x]' "$DOC" || true)"
if [[ "${checked_count:-0}" -lt 1 ]]; then
  echo "FAIL: no checked '[x]' boxes found (doc not filled)"
  fail=1
else
  echo "OK: $checked_count checked '[x]' boxes"
fi

if grep -qF 'ИТОГ: [PASS]' "$DOC"; then
  echo "OK: final verdict 'ИТОГ: [PASS]' present"
else
  echo "FAIL: final verdict 'ИТОГ: [PASS]' missing"
  fail=1
fi

if [[ $fail -ne 0 ]]; then
  echo "RESULT: FAIL (q7_acceptance_all_checked)"
  exit 1
fi
echo "RESULT: PASS (q7_acceptance_all_checked)"
exit 0
