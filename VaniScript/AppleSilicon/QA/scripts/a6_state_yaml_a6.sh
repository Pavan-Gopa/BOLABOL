#!/usr/bin/env bash
# A6: STATE.yaml current_step A6; implementation+review approved.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="AI_Workflow_Kit/docs/AI/STATE.yaml"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

current_step="$(sed -nE 's/^current_step:[[:space:]]*([A-Za-z0-9_]+).*/\1/p' "$FILE" | head -1)"
if [[ "$current_step" != "A6" ]]; then
  # Future: if track advances past A6, soft N/A
  if [[ "$current_step" =~ ^A([7-9]|[1-9][0-9]+)$ ]] || [[ "$current_step" == "A7" || "$current_step" == "A8" ]]; then
    echo "NOTE: current_step='$current_step' (not A6); A6 STATE gate is N/A."
    echo "RESULT: PASS (a6_state_yaml_a6, step-aware N/A)"
    exit 0
  fi
  echo "FAIL: current_step is not A6 (got '$current_step')"; exit 1
fi

grep -Eq '^current_step:[[:space:]]*A6\b' "$FILE" || {
  echo "FAIL: current_step is not A6"; exit 1
}
grep -A2 '^implementation:' "$FILE" | grep -q 'status: approved' || {
  echo "FAIL: implementation.status not approved"; exit 1
}
grep -A2 '^review:' "$FILE" | grep -q 'status: approved' || {
  echo "FAIL: review.status not approved"; exit 1
}
# target_files mention usage stats
grep -q 'UsageStatisticsView' "$FILE" || {
  echo "FAIL: STATE target_files should mention UsageStatisticsView"; exit 1
}
echo "PASS: STATE.yaml is on A6 with implementation+review approved."
