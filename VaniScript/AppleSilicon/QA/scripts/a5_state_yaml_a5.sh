#!/usr/bin/env bash
# A5: STATE.yaml current_step A5; implementation+review approved; qa pending.
# Step-aware: when the track advances past A5 this gate is N/A (PASS).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="AI_Workflow_Kit/docs/AI/STATE.yaml"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

current_step="$(sed -nE 's/^current_step:[[:space:]]*([A-Za-z0-9_]+).*/\1/p' "$FILE" | head -1)"
if [[ "$current_step" != "A5" ]]; then
  echo "NOTE: current_step='$current_step' (not A5); A5 STATE gate is N/A."
  echo "RESULT: PASS (a5_state_yaml_a5, step-aware N/A)"
  exit 0
fi

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
