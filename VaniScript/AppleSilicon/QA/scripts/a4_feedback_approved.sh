#!/usr/bin/env bash
# A4: FEEDBACK.md Verifier [APPROVED] for A4 with key handoff claims.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="AI_Workflow_Kit/docs/AI/FEEDBACK.md"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("AI_Workflow_Kit/docs/AI/FEEDBACK.md").read_text(encoding="utf-8")
head = text[:5000]
if "A4" not in head:
    raise SystemExit("FAIL: FEEDBACK head does not mention A4")
if "[APPROVED]" not in head:
    raise SystemExit("FAIL: A4 FEEDBACK missing [APPROVED] in head")
for needle in (
    "CloudKeyValidator",
    "CloudModelCatalog",
    "CloudKeyModelRow",
    "geminiTextModel",
    "whisper-1",
):
    if needle not in text[:8000]:
        raise SystemExit(f"FAIL: A4 FEEDBACK missing claim: {needle}")
print("PASS: FEEDBACK.md A4 is [APPROVED] with expected handoff claims.")
PY
