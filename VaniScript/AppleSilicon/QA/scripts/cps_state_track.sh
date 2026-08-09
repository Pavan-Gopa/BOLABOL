#!/usr/bin/env bash
# CPS: STATE.yaml is on CLOUD_PROVIDER_STABILIZATION / CPS-* step.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="AI_Workflow_Kit/docs/AI/STATE.yaml"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }
grep -Eq '^track:[[:space:]]*CLOUD_PROVIDER_STABILIZATION' "$FILE" || {
  echo "FAIL: track is not CLOUD_PROVIDER_STABILIZATION"; exit 1
}
step="$(sed -nE 's/^current_step:[[:space:]]*([A-Za-z0-9_-]+).*/\1/p' "$FILE" | head -1)"
if [[ "$step" != CPS* && "$step" != CLOUD_PROVIDER* && "$step" != API_USAGE_DONE ]]; then
  echo "FAIL: unexpected current_step='$step' for CPS track"; exit 1
fi
echo "PASS: STATE track=CLOUD_PROVIDER_STABILIZATION step=$step"
