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

# Step-awareness: this gate encodes a DOC-ONLY invariant that is only meaningful for
# doc-only steps (Q5/Q7/A8). Once the track advances to a CODE step (e.g. A2 — usage
# recording, which legitimately modifies its approved .swift target_files), enforcing
# "no code in the diff" would be a false positive. Read current_step from STATE.yaml and
# treat the gate as N/A (PASS) for any non-doc-only step.
STATE_FILE="$AS_DIR/AI_Workflow_Kit/docs/AI/STATE.yaml"
current_step=""
if [[ -f "$STATE_FILE" ]]; then
  current_step="$(sed -nE 's/^current_step:[[:space:]]*([A-Za-z0-9_-]+).*/\1/p' "$STATE_FILE" | head -1)"
fi
case "$current_step" in
  Q5|Q7|A8)
    echo "current_step='$current_step' is a doc-only step — enforcing the no-code gate."
    ;;
  *)
    echo "NOTE: current_step='${current_step:-unknown}' is a CODE step; the Q7 doc-only gate is N/A."
    echo "OK: doc-only gate skipped — a code step legitimately changes approved target_files."
    echo "RESULT: PASS (q7_doc_only_no_code, step-aware N/A)"
    exit 0
    ;;
esac

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
