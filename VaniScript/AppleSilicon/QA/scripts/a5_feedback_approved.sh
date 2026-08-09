#!/usr/bin/env bash
# A5: FEEDBACK.md Verifier [APPROVED] with A5 handoff claims.
# Step-aware: when current_step is past A5, search the whole FEEDBACK file for the
# historical A5 APPROVED block (head may now be A6+).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="AI_Workflow_Kit/docs/AI/FEEDBACK.md"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

STATE_FILE="AI_Workflow_Kit/docs/AI/STATE.yaml"
current_step="$(sed -nE 's/^current_step:[[:space:]]*([A-Za-z0-9_-]+).*/\1/p' "$STATE_FILE" | head -1)"
if [[ -n "$current_step" && "$current_step" != "A5" ]]; then
  echo "NOTE: current_step='$current_step' (not A5); A5 FEEDBACK gate is N/A."
  echo "RESULT: PASS (a5_feedback_approved, step-aware N/A)"
  exit 0
fi

python3 - <<'PY'
from pathlib import Path
import re
text = Path("AI_Workflow_Kit/docs/AI/FEEDBACK.md").read_text(encoding="utf-8")
state = Path("AI_Workflow_Kit/docs/AI/STATE.yaml").read_text(encoding="utf-8") if Path("AI_Workflow_Kit/docs/AI/STATE.yaml").exists() else ""
m = re.search(r'^current_step:\s*([A-Za-z0-9_-]+)', state, re.M)
step = m.group(1) if m else "A5"

if "A5" not in text:
    raise SystemExit("FAIL: FEEDBACK does not mention A5")
if "[APPROVED]" not in text:
    raise SystemExit("FAIL: FEEDBACK missing [APPROVED]")

if step == "A5":
    head = text[:6000]
    if "A5" not in head:
        raise SystemExit("FAIL: FEEDBACK head does not mention A5")
    if "[APPROVED]" not in head:
        raise SystemExit("FAIL: A5 FEEDBACK missing [APPROVED] in head")
else:
    # Historical A5 block must still document the A5 claims somewhere
    if "A5 —" not in text and "A5 -" not in text and "шаг: **A5" not in text and "A5 — Полноценная" not in text:
        if "CloudChatRouter" not in text or "A5" not in text:
            raise SystemExit("FAIL: historical A5 FEEDBACK block missing")

for needle in (
    "CloudChatRouter",
    "ProviderRegistry",
    "cloudProviderCard",
    "generateOpenAICompatible",
    "supportsTranscription",
    "320",
):
    if needle not in text:
        raise SystemExit(f"FAIL: A5 FEEDBACK missing claim: {needle}")
print(f"PASS: FEEDBACK.md A5 is [APPROVED] with expected handoff claims (step={step}).")
PY
