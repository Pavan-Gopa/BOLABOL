#!/usr/bin/env bash
# A5: FEEDBACK.md Verifier [APPROVED] with A5 handoff claims.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="AI_Workflow_Kit/docs/AI/FEEDBACK.md"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("AI_Workflow_Kit/docs/AI/FEEDBACK.md").read_text(encoding="utf-8")
head = text[:6000]
if "A5" not in head:
    raise SystemExit("FAIL: FEEDBACK head does not mention A5")
if "[APPROVED]" not in head:
    raise SystemExit("FAIL: A5 FEEDBACK missing [APPROVED] in head")
for needle in (
    "CloudChatRouter",
    "ProviderRegistry",
    "cloudProviderCard",
    "generateOpenAICompatible",
    "supportsTranscription",
    "320",
):
    if needle not in text[:8000]:
        raise SystemExit(f"FAIL: A5 FEEDBACK missing claim: {needle}")
print("PASS: FEEDBACK.md A5 is [APPROVED] with expected handoff claims.")
PY
