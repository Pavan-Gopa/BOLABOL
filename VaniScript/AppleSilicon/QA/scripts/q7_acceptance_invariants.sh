#!/usr/bin/env bash
# QA/scripts/q7_acceptance_invariants.sh — Q7 delta (doc-only).
# Asserts QWEN_MCP_ACCEPTANCE.md restates the track invariants (case-insensitive):
#   - "no silent fallback"   - "token"   - "vaniscript_embedded"   - "Codex/Grok"
# Idempotent, deterministic. Exit 0 = pass. QA script, not product code.

set -uo pipefail

AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC="$AS_DIR/AI_Workflow_Kit/docs/QWEN_MCP_ACCEPTANCE.md"

echo "Q7 acceptance invariants — $DOC"

if [[ ! -f "$DOC" ]]; then
  echo "FAIL: acceptance doc missing: $DOC"
  exit 1
fi

fail=0
for needle in "no silent fallback" "token" "vaniscript_embedded" "Codex/Grok"; do
  if grep -qiF "$needle" "$DOC"; then
    echo "OK: invariant mentioned — '$needle'"
  else
    echo "FAIL: invariant missing — '$needle'"
    fail=1
  fi
done

if [[ $fail -ne 0 ]]; then
  echo "RESULT: FAIL (q7_acceptance_invariants)"
  exit 1
fi
echo "RESULT: PASS (q7_acceptance_invariants)"
exit 0
