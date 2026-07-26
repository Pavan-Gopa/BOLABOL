#!/usr/bin/env bash
# QA/scripts/a2_decisions_adr.sh — A2: the step must be recorded as an ADR in
# DECISIONS.md (id D-2026-07-26-A2), documenting the usage-recording decision, the
# best-effort invariant (§14.4), the transcription scope note (deferred to A5/A6), and
# the green verification. Assert all of these are present.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

FILE="AI_Workflow_Kit/docs/DECISIONS.md"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

grep -Fq "## D-2026-07-26-A2" "$FILE" \
  || { echo "FAIL: ADR 'D-2026-07-26-A2' header missing"; exit 1; }
grep -Fiq "usage recording" "$FILE" \
  || { echo "FAIL: ADR must describe usage recording"; exit 1; }
grep -Fq "§14.4" "$FILE" \
  || { echo "FAIL: ADR must reference the best-effort invariant §14.4"; exit 1; }
grep -Fq "UsageRecorder.swift" "$FILE" \
  || { echo "FAIL: ADR must reference the new UsageRecorder.swift"; exit 1; }
grep -Fq "NativeProcessingPipeline" "$FILE" \
  || { echo "FAIL: ADR must document the transcription scope note (NativeProcessingPipeline)"; exit 1; }
grep -Fq "287 tests" "$FILE" \
  || { echo "FAIL: ADR must record the green verification (287 tests)"; exit 1; }

echo "PASS: DECISIONS.md records ADR D-2026-07-26-A2 (usage recording, §14.4, scope note, 287 tests)."
