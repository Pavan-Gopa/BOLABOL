#!/usr/bin/env bash
# A5: ADR D-2026-07-26-A5 in DECISIONS.md (endpoints/capabilities/ids).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="AI_Workflow_Kit/docs/DECISIONS.md"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("AI_Workflow_Kit/docs/DECISIONS.md").read_text(encoding="utf-8")
if "D-2026-07-26-A5" not in text:
    raise SystemExit("FAIL: ADR D-2026-07-26-A5 missing")
# Key decision points
for n in (
    "CloudChatRouter",
    "compatible-mode",
    "openrouter.ai/api/v1/chat/completions",
    "supportsTranscription",
    "cloudProviderCard",
    "generateOpenAICompatible",
):
    if n not in text:
        raise SystemExit(f"FAIL: A5 ADR missing claim: {n}")
print("PASS: DECISIONS.md records D-2026-07-26-A5 with endpoints/capabilities/ids.")
PY
