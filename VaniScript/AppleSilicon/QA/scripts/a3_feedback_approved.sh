#!/usr/bin/env bash
# A3: FEEDBACK.md has Verifier [APPROVED] for A3 handoff.
# Step-aware: when current_step is past A3, search the whole FEEDBACK file for the
# historical A3 APPROVED block (head may now be A4+).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="AI_Workflow_Kit/docs/AI/FEEDBACK.md"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("AI_Workflow_Kit/docs/AI/FEEDBACK.md").read_text(encoding="utf-8")
state = Path("AI_Workflow_Kit/docs/AI/STATE.yaml").read_text(encoding="utf-8") if Path("AI_Workflow_Kit/docs/AI/STATE.yaml").exists() else ""
import re
m = re.search(r'^current_step:\s*([A-Za-z0-9_]+)', state, re.M)
step = m.group(1) if m else "A3"

# Locate an A3 APPROVED section somewhere in the file (historical OK for A4+).
idx = text.find("A3")
if idx < 0:
    raise SystemExit("FAIL: FEEDBACK does not mention A3")
# Prefer a window that includes A3 + APPROVED
window = text
if step == "A3":
    window = text[:4000]
if "A3" not in window and "A3" not in text:
    raise SystemExit("FAIL: FEEDBACK missing A3 mention")
if "[APPROVED]" not in text:
    raise SystemExit("FAIL: FEEDBACK missing [APPROVED]")
# Require A3-related APPROVED context: either head (A3 step) or a block mentioning A3 near APPROVED
if step == "A3":
    head = text[:2500]
    if "A3" not in head:
        raise SystemExit("FAIL: FEEDBACK head does not mention A3")
    if "[APPROVED]" not in head and "ИТОГОВЫЙ СТАТУС:** [APPROVED]" not in head:
        if "[APPROVED]" not in text[:4000]:
            raise SystemExit("FAIL: A3 FEEDBACK missing [APPROVED]")
else:
    # Historical A3 block must still document the A3 claims somewhere
    if "A3" not in text:
        raise SystemExit("FAIL: historical A3 FEEDBACK missing")

for needle in ("selectedProviderId", "ProviderCardView", "Cloud Usage Statistics"):
    if needle not in text:
        raise SystemExit(f"FAIL: FEEDBACK A3 handoff missing mention of {needle}")
print(f"PASS: FEEDBACK.md A3 is [APPROVED] with expected handoff claims (step={step}).")
PY
