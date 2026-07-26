#!/usr/bin/env bash
# A4: STATE.yaml current_step A4; implementation+review approved.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="AI_Workflow_Kit/docs/AI/STATE.yaml"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

grep -Eq '^current_step:[[:space:]]*A4\b' "$FILE" || {
  echo "FAIL: current_step is not A4"; exit 1
}
grep -A2 '^implementation:' "$FILE" | grep -q 'status: approved' || {
  echo "FAIL: implementation.status not approved"; exit 1
}
grep -A2 '^review:' "$FILE" | grep -q 'status: approved' || {
  echo "FAIL: review.status not approved"; exit 1
}
echo "PASS: STATE.yaml is on A4 with implementation+review approved."
