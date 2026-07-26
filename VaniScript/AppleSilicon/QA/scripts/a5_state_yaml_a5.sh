#!/usr/bin/env bash
# A5: STATE.yaml current_step A5; implementation+review approved; qa pending.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="AI_Workflow_Kit/docs/AI/STATE.yaml"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

grep -Eq '^current_step:[[:space:]]*A5\b' "$FILE" || {
  echo "FAIL: current_step is not A5"; exit 1
}
grep -A2 '^implementation:' "$FILE" | grep -q 'status: approved' || {
  echo "FAIL: implementation.status not approved"; exit 1
}
grep -A2 '^review:' "$FILE" | grep -q 'status: approved' || {
  echo "FAIL: review.status not approved"; exit 1
}
echo "PASS: STATE.yaml is on A5 with implementation+review approved."
