#!/usr/bin/env bash
# QA: q5_doc_only_no_code.sh — Q5 commit 50ebb06 changed NO source code
# Asserts:
#   1. Commit 50ebb06 exists
#   2. It changed at least one file
#   3. No .swift / .js / .ts / .py files were touched (doc-only)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMMIT="50ebb06"

echo "=== q5_doc_only_no_code: commit $COMMIT is doc-only ==="

cd "$PROJECT_ROOT"

# 1. Commit exists
git rev-parse --verify "$COMMIT" >/dev/null 2>&1 || \
    { echo "FAIL: commit $COMMIT not found"; exit 1; }

# 2. Changed files list (non-empty)
FILES="$(git show --name-only --format= "$COMMIT")"
[ -n "$FILES" ] || { echo "FAIL: commit $COMMIT changed no files"; exit 1; }

# 3. No source-code extensions touched
if echo "$FILES" | grep -Eq '\.(swift|js|ts|py)$'; then
    echo "FAIL: commit $COMMIT touched source code files:"
    echo "$FILES" | grep -E '\.(swift|js|ts|py)$'
    exit 1
fi

echo "PASS: q5_doc_only_no_code — commit $COMMIT changed docs only (no .swift/.js/.ts/.py)"
exit 0
