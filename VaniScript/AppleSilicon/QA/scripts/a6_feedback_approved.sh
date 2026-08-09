#!/usr/bin/env bash
# A6: FEEDBACK.md Verifier [APPROVED] with A6 handoff claims.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="AI_Workflow_Kit/docs/AI/FEEDBACK.md"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

STATE_FILE="AI_Workflow_Kit/docs/AI/STATE.yaml"
current_step="$(sed -nE 's/^current_step:[[:space:]]*([A-Za-z0-9_-]+).*/\1/p' "$STATE_FILE" | head -1)"
if [[ -n "$current_step" && "$current_step" != "A6" ]]; then
  echo "NOTE: current_step='$current_step' (not A6); A6 FEEDBACK gate is N/A."
  echo "RESULT: PASS (a6_feedback_approved, step-aware N/A)"
  exit 0
fi

python3 - <<'PY'
from pathlib import Path
import re
text = Path("AI_Workflow_Kit/docs/AI/FEEDBACK.md").read_text(encoding="utf-8")
state = Path("AI_Workflow_Kit/docs/AI/STATE.yaml").read_text(encoding="utf-8") if Path("AI_Workflow_Kit/docs/AI/STATE.yaml").exists() else ""
m = re.search(r'^current_step:\s*([A-Za-z0-9_-]+)', state, re.M)
step = m.group(1) if m else "A6"

if "A6" not in text:
    raise SystemExit("FAIL: FEEDBACK does not mention A6")
if "[APPROVED]" not in text:
    raise SystemExit("FAIL: FEEDBACK missing [APPROVED]")

if step == "A6":
    head = text[:5000]
    if "A6" not in head:
        raise SystemExit("FAIL: FEEDBACK head does not mention A6")
    if "[APPROVED]" not in head:
        raise SystemExit("FAIL: A6 FEEDBACK missing [APPROVED] in head")

for needle in (
    "UsageStatisticsView",
    "Last Transaction",
    "provider billing can differ",
    "No usage recorded yet",
    "Cloud Usage Statistics",
    "320",
):
    if needle not in text:
        raise SystemExit(f"FAIL: A6 FEEDBACK missing claim: {needle}")
print(f"PASS: FEEDBACK.md A6 is [APPROVED] with expected handoff claims (step={step}).")
PY
