#!/usr/bin/env bash
# QA/scripts/q7_readme_qwen_provider.sh — Q7 delta (doc-only).
# Asserts README.md lists Qwen as an AI provider (provider bullet present).
# Idempotent, deterministic. Exit 0 = pass. QA script, not product code.

set -uo pipefail

AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC="$AS_DIR/README.md"

echo "Q7 README Qwen-provider — $DOC"

if [[ ! -f "$DOC" ]]; then
  echo "FAIL: README missing: $DOC"
  exit 1
fi

fail=0

if grep -qF 'Qwen' "$DOC"; then
  echo "OK: 'Qwen' mentioned in README"
else
  echo "FAIL: 'Qwen' not mentioned in README"
  fail=1
fi

# Provider bullet, same shape as Codex/Grok ("- **Qwen** ...").
if grep -qE '^[[:space:]]*-[[:space:]]*\*\*Qwen\*\*' "$DOC"; then
  echo "OK: Qwen provider bullet present (- **Qwen** ...)"
else
  echo "FAIL: Qwen provider bullet missing (expected '- **Qwen** ...')"
  fail=1
fi

if [[ $fail -ne 0 ]]; then
  echo "RESULT: FAIL (q7_readme_qwen_provider)"
  exit 1
fi
echo "RESULT: PASS (q7_readme_qwen_provider)"
exit 0
