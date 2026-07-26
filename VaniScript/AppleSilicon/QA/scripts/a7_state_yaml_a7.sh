#!/usr/bin/env bash
# A7: STATE.yaml current_step A7; implementation+review approved; target_files mention CloudBalanceService.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="AI_Workflow_Kit/docs/AI/STATE.yaml"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

current_step="$(sed -nE 's/^current_step:[[:space:]]*([A-Za-z0-9_]+).*/\1/p' "$FILE" | head -1)"
if [[ "$current_step" != "A7" ]]; then
  if [[ "$current_step" =~ ^A([8-9]|[1-9][0-9]+)$ ]] || [[ "$current_step" == "A8" || "$current_step" == "API_USAGE_DONE" ]]; then
    echo "NOTE: current_step='$current_step' (not A7); A7 STATE gate is N/A."
    echo "RESULT: PASS (a7_state_yaml_a7, step-aware N/A)"
    exit 0
  fi
  echo "FAIL: current_step is not A7 (got '$current_step')"; exit 1
fi

grep -Eq '^current_step:[[:space:]]*A7\b' "$FILE" || { echo "FAIL: current_step is not A7"; exit 1; }
grep -A2 '^implementation:' "$FILE" | grep -q 'status: approved' || { echo "FAIL: implementation.status not approved"; exit 1; }
grep -A2 '^review:' "$FILE" | grep -q 'status: approved' || { echo "FAIL: review.status not approved"; exit 1; }
grep -q 'CloudBalanceService' "$FILE" || { echo "FAIL: STATE target_files should mention CloudBalanceService"; exit 1; }
echo "PASS: STATE.yaml is on A7 with implementation+review approved."
