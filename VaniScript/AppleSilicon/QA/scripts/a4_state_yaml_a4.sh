#!/usr/bin/env bash
# A4: STATE.yaml current_step A4; implementation+review approved.
# Step-aware: when the track advances past A4 this gate is N/A (PASS).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="AI_Workflow_Kit/docs/AI/STATE.yaml"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

current_step="$(sed -nE 's/^current_step:[[:space:]]*([A-Za-z0-9_]+).*/\1/p' "$FILE" | head -1)"
if [[ "$current_step" != "A4" ]]; then
  echo "NOTE: current_step='$current_step' (not A4); A4 STATE gate is N/A."
  echo "RESULT: PASS (a4_state_yaml_a4, step-aware N/A)"
  exit 0
fi

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
