#!/usr/bin/env bash
# A3: FEEDBACK.md has Verifier [APPROVED] for A3 handoff.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="AI_Workflow_Kit/docs/AI/FEEDBACK.md"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("AI_Workflow_Kit/docs/AI/FEEDBACK.md").read_text(encoding="utf-8")
# First report block should be A3 APPROVED
head = text[:2500]
if "A3" not in head:
    raise SystemExit("FAIL: FEEDBACK head does not mention A3")
if "[APPROVED]" not in head and "ИТОГОВЫЙ СТАТУС:** [APPROVED]" not in head:
    # broader
    if "[APPROVED]" not in text[:4000]:
        raise SystemExit("FAIL: A3 FEEDBACK missing [APPROVED]")
# Handoff mentions key A3 claims
for needle in ("selectedProviderId", "ProviderCardView", "Cloud Usage Statistics"):
    if needle not in text[:6000]:
        raise SystemExit(f"FAIL: FEEDBACK A3 handoff missing mention of {needle}")
print("PASS: FEEDBACK.md A3 is [APPROVED] with expected handoff claims.")
PY
