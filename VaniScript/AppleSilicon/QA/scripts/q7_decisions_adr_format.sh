#!/usr/bin/env bash
# QA/scripts/q7_decisions_adr_format.sh — Q7 delta (doc-only).
# Asserts the Q7 ADR uses the dated decision id format D-YYYY-MM-DD-Q7
# (concretely D-2026-07-26-Q7, or an equivalent D-<date>-Q7 heading).
# Idempotent, deterministic. Exit 0 = pass. QA script, not product code.

set -uo pipefail

AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC="$AS_DIR/AI_Workflow_Kit/docs/DECISIONS.md"

echo "Q7 DECISIONS ADR format — $DOC"

if [[ ! -f "$DOC" ]]; then
  echo "FAIL: DECISIONS missing: $DOC"
  exit 1
fi

# Prefer the exact id; accept any D-<date>-Q7 heading as equivalent.
if grep -qF 'D-2026-07-26-Q7' "$DOC"; then
  echo "OK: exact ADR id 'D-2026-07-26-Q7' present"
  echo "RESULT: PASS (q7_decisions_adr_format)"
  exit 0
fi

if grep -qE 'D-[0-9]{4}-[0-9]{2}-[0-9]{2}-Q7' "$DOC"; then
  echo "OK: equivalent D-<date>-Q7 ADR id present"
  grep -nE 'D-[0-9]{4}-[0-9]{2}-[0-9]{2}-Q7' "$DOC"
  echo "RESULT: PASS (q7_decisions_adr_format)"
  exit 0
fi

echo "FAIL: no D-<date>-Q7 ADR id found in DECISIONS.md"
echo "RESULT: FAIL (q7_decisions_adr_format)"
exit 1
