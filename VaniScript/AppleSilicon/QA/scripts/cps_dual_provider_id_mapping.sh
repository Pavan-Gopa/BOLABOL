#!/usr/bin/env bash
# Legacy engine ids gemini-cloud/gpt-cloud still resolve; usage normalizes to catalog ids.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
TE="Sources/VaniScript/Services/CloudTextTranslationEngine.swift"
TR="Sources/VaniScript/Services/CloudAudioTranscriptionEngine.swift"
WS="Sources/VaniScript/Stores/WorkflowStore.swift"
for f in "$TE" "$TR" "$WS"; do [[ -f "$f" ]] || { echo "FAIL: $f missing"; exit 1; }; done
grep -q 'case "gemini-cloud"' "$TE" || { echo "FAIL: translation engine missing gemini-cloud"; exit 1; }
grep -q 'case "gpt-cloud"' "$TE" || { echo "FAIL: translation engine missing gpt-cloud"; exit 1; }
grep -q 'case "gemini-cloud"' "$TR" || { echo "FAIL: transcription engine missing gemini-cloud"; exit 1; }
grep -Eq 'normalizedUsageProviderId|gemini-cloud.*gemini|"gemini-cloud": return "gemini"' "$WS" || {
  echo "FAIL: WorkflowStore usage id normalization missing"; exit 1
}
grep -q "CloudChatRouter.route" "$TE" || { echo "FAIL: translation engine missing CloudChatRouter"; exit 1; }
echo "PASS: dual id system (legacy *-cloud + catalog ids) still wired with usage remap."
