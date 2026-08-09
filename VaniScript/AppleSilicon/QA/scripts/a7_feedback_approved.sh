#!/usr/bin/env bash
# A7: FEEDBACK.md Verifier [APPROVED] for A7 with handoff claims.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="AI_Workflow_Kit/docs/AI/FEEDBACK.md"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

STATE_FILE="AI_Workflow_Kit/docs/AI/STATE.yaml"
current_step="$(sed -nE 's/^current_step:[[:space:]]*([A-Za-z0-9_-]+).*/\1/p' "$STATE_FILE" | head -1)"
if [[ -n "$current_step" && "$current_step" != "A7" ]]; then
  echo "NOTE: current_step='$current_step' (not A7); A7 FEEDBACK gate is N/A."
  echo "RESULT: PASS (a7_feedback_approved, step-aware N/A)"
  exit 0
fi

python3 - <<'PY'
from pathlib import Path
text = Path("AI_Workflow_Kit/docs/AI/FEEDBACK.md").read_text(encoding="utf-8")
state = Path("AI_Workflow_Kit/docs/AI/STATE.yaml").read_text(encoding="utf-8") if Path("AI_Workflow_Kit/docs/AI/STATE.yaml").exists() else ""
import re
m = re.search(r'^current_step:\s*([A-Za-z0-9_-]+)', state, re.M)
step = m.group(1) if m else "A7"

if "A7" not in text:
    raise SystemExit("FAIL: FEEDBACK does not mention A7")
if "[APPROVED]" not in text:
    raise SystemExit("FAIL: FEEDBACK missing [APPROVED]")

# The A7 verification report is the head of the file at step A7.
if step == "A7":
    head = text[:6000]
    if "A7" not in head:
        raise SystemExit("FAIL: FEEDBACK head does not mention A7")
    if "[APPROVED]" not in head:
        raise SystemExit("FAIL: A7 FEEDBACK missing [APPROVED] in head")

for needle in (
    "CloudBalanceService",
    "OpenRouter",
    "Plan-based (GPU time)",
    "331",
):
    if needle not in text:
        raise SystemExit(f"FAIL: A7 FEEDBACK missing claim: {needle}")
print(f"PASS: FEEDBACK.md A7 is [APPROVED] with expected handoff claims (step={step}).")
PY
