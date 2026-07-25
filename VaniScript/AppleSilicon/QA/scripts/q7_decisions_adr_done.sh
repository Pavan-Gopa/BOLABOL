#!/usr/bin/env bash
# QA/scripts/q7_decisions_adr_done.sh — Q7 delta (doc-only).
# Asserts DECISIONS.md records the QWEN_MCP track completion ADR:
#   - "QWEN_MCP track complete"   - "QWEN_DONE"
# Idempotent, deterministic. Exit 0 = pass. QA script, not product code.

set -uo pipefail

AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC="$AS_DIR/AI_Workflow_Kit/docs/DECISIONS.md"

echo "Q7 DECISIONS ADR done — $DOC"

if [[ ! -f "$DOC" ]]; then
  echo "FAIL: DECISIONS missing: $DOC"
  exit 1
fi

fail=0
for needle in "QWEN_MCP track complete" "QWEN_DONE"; do
  if grep -qF "$needle" "$DOC"; then
    echo "OK: present — '$needle'"
  else
    echo "FAIL: missing — '$needle'"
    fail=1
  fi
done

if [[ $fail -ne 0 ]]; then
  echo "RESULT: FAIL (q7_decisions_adr_done)"
  exit 1
fi
echo "RESULT: PASS (q7_decisions_adr_done)"
exit 0
