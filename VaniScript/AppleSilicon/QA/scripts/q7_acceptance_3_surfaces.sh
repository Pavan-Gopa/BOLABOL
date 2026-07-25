#!/usr/bin/env bash
# QA/scripts/q7_acceptance_3_surfaces.sh — Q7 delta (doc-only).
# Asserts QWEN_MCP_ACCEPTANCE.md documents all three Qwen access surfaces:
#   1. External Qwen MCP   2. Apple Silicon embedded   3. Electron embedded.
# Idempotent, deterministic. Exit 0 = pass. QA script, not product code.

set -uo pipefail

AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC="$AS_DIR/AI_Workflow_Kit/docs/QWEN_MCP_ACCEPTANCE.md"

echo "Q7 acceptance 3-surfaces — $DOC"

if [[ ! -f "$DOC" ]]; then
  echo "FAIL: acceptance doc missing: $DOC"
  exit 1
fi

fail=0
for needle in "External Qwen MCP" "Apple Silicon embedded" "Electron embedded"; do
  if grep -qF "$needle" "$DOC"; then
    echo "OK: surface present — '$needle'"
  else
    echo "FAIL: surface missing — '$needle'"
    fail=1
  fi
done

if [[ $fail -ne 0 ]]; then
  echo "RESULT: FAIL (q7_acceptance_3_surfaces)"
  exit 1
fi
echo "RESULT: PASS (q7_acceptance_3_surfaces)"
exit 0
