#!/usr/bin/env bash
# QA/scripts/q7_readme_no_rewrite.sh — Q7 delta (doc-only).
# Asserts the original README sections survived the Q7 edit (extend, not rewrite):
#   - "## Direction"   - "## Local Run"
# Idempotent, deterministic. Exit 0 = pass. QA script, not product code.

set -uo pipefail

AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC="$AS_DIR/README.md"

echo "Q7 README no-rewrite — $DOC"

if [[ ! -f "$DOC" ]]; then
  echo "FAIL: README missing: $DOC"
  exit 1
fi

fail=0
for needle in "## Direction" "## Local Run"; do
  if grep -qF "$needle" "$DOC"; then
    echo "OK: original section preserved — '$needle'"
  else
    echo "FAIL: original section removed — '$needle'"
    fail=1
  fi
done

if [[ $fail -ne 0 ]]; then
  echo "RESULT: FAIL (q7_readme_no_rewrite)"
  exit 1
fi
echo "RESULT: PASS (q7_readme_no_rewrite)"
exit 0
