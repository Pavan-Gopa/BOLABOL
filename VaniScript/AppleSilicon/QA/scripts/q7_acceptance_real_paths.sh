#!/usr/bin/env bash
# QA/scripts/q7_acceptance_real_paths.sh — Q7 delta (doc-only).
# Asserts QWEN_MCP_ACCEPTANCE.md is filled with the REAL verified values from Q1–Q6:
#   - AS MCP port 19790
#   - Electron MCP port 19789
#   - verified model id qwen3.8-max-preview (DECISIONS D-2026-07-25 Q1, [high])
#   - verified Qwen CLI binary /Users/pavan/.local/bin/qwen
# The acceptance header claims it is "filled with real paths/commands"; any missing
# token is a doc-completeness defect. Idempotent, deterministic. Exit 0 = pass.

set -uo pipefail

AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC="$AS_DIR/AI_Workflow_Kit/docs/QWEN_MCP_ACCEPTANCE.md"

echo "Q7 acceptance real-paths — $DOC"

if [[ ! -f "$DOC" ]]; then
  echo "FAIL: acceptance doc missing: $DOC"
  exit 1
fi

fail=0
for needle in "19790" "19789" "qwen3.8-max-preview" "/Users/pavan/.local/bin/qwen"; do
  if grep -qF "$needle" "$DOC"; then
    echo "OK: real value present — '$needle'"
  else
    echo "FAIL: real value missing — '$needle'"
    fail=1
  fi
done

if [[ $fail -ne 0 ]]; then
  echo "RESULT: FAIL (q7_acceptance_real_paths)"
  exit 1
fi
echo "RESULT: PASS (q7_acceptance_real_paths)"
exit 0
