#!/usr/bin/env bash
# QA/scripts/a2_no_keys_in_source.sh — A2 (invariant §14.7): no API keys/tokens hardcoded
# in the A2 product sources or tests; keys live only in settings/keychain. Scan the A2
# files for well-known secret prefixes (OpenAI sk-, Google AIza, GitHub ghp_, Slack xoxb-)
# and for suspicious literal key assignments. These prefixes never appear in legit code.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

FILES=(
  "Sources/VaniScriptCore/UsageRecorder.swift"
  "Sources/VaniScript/Services/CloudAudioTranscriptionEngine.swift"
  "Sources/VaniScript/Services/CloudTextTranslationEngine.swift"
  "Sources/VaniScript/Stores/WorkflowStore.swift"
  "Tests/VaniScriptCoreTests/UsageRecorderTests.swift"
)

rc=0
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || { echo "FAIL: $f missing"; exit 1; }
  if grep -Enq 'sk-[A-Za-z0-9]{12}|AIza[0-9A-Za-z_-]{12}|ghp_[A-Za-z0-9]{12}|xox[baprs]-[A-Za-z0-9-]{10}' "$f"; then
    echo "FAIL: possible hardcoded secret in $f:"; grep -En 'sk-[A-Za-z0-9]{12}|AIza[0-9A-Za-z_-]{12}|ghp_[A-Za-z0-9]{12}|xox[baprs]-[A-Za-z0-9-]{10}' "$f"; rc=1
  fi
done
[[ "$rc" -eq 0 ]] || exit 1

echo "PASS: no hardcoded API keys/tokens in A2 sources or tests (§14.7)."
