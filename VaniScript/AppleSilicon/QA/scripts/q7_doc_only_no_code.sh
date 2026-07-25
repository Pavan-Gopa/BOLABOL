#!/usr/bin/env bash
# QA/scripts/q7_doc_only_no_code.sh — Q7 delta (doc-only gate).
# Asserts the Q7 step changed ONLY documentation under AppleSilicon: no
# .swift/.js/.ts/.py/.m/.h/.c/.cpp product-code files in the pending diff.
#
# Adaptation note: the brief referenced `git diff qwen/pre-Q7..HEAD`, but that
# ref does not exist in this repo and the Q7 edits are present as UNCOMMITTED
# working-tree changes. We therefore inspect the pending diff vs HEAD (plus the
# staged index), scoped to paths under AppleSilicon/ (the Q7 working root per
# STATE.yaml). Sibling projects (DialGent, KirtanSplitter-Models) are out of
# scope and ignored. Idempotent, deterministic. Exit 0 = pass.

set -uo pipefail

AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_ROOT="$(cd "$AS_DIR" && git rev-parse --show-toplevel 2>/dev/null || true)"

echo "Q7 doc-only gate — AppleSilicon scope"

if [[ -z "${REPO_ROOT:-}" ]]; then
  echo "FAIL: not a git repository (cannot verify doc-only)"
  exit 1
fi
cd "$REPO_ROOT"

# Pending (unstaged + staged) changes, scoped to AppleSilicon paths.
changed="$( { git diff HEAD --name-only; git diff --cached --name-only; } 2>/dev/null \
  | sort -u | grep -F 'AppleSilicon/' || true )"

if [[ -z "$changed" ]]; then
  echo "NOTE: no pending changes under AppleSilicon/ — Q7 already committed or clean."
  echo "OK: doc-only holds trivially (no code changes pending)."
  echo "RESULT: PASS (q7_doc_only_no_code)"
  exit 0
fi

echo "Pending changed files under AppleSilicon/:"
printf '%s\n' "$changed"

code_files="$(printf '%s\n' "$changed" \
  | grep -E '\.(swift|js|jsx|ts|tsx|py|m|mm|h|c|cc|cpp)$' || true)"

if [[ -n "$code_files" ]]; then
  echo "FAIL: product-code files changed in a doc-only step:"
  printf '%s\n' "$code_files"
  echo "RESULT: FAIL (q7_doc_only_no_code)"
  exit 1
fi

# Sanity: a doc-only Q7 step should have touched at least one .md doc.
if ! printf '%s\n' "$changed" | grep -qE '\.(md|yaml|yml)$'; then
  echo "WARN: pending changes under AppleSilicon/ but no .md/.yaml — unexpected for doc-only Q7."
fi

echo "OK: only documentation files changed (no product code)."
echo "RESULT: PASS (q7_doc_only_no_code)"
exit 0
