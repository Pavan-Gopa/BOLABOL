#!/usr/bin/env bash
# Model-level capability helpers (post-A5 / CPS RC-03 direction).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/CloudProviderCatalog.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }
for fn in supportsTranscription supportsTranslation supportsVision sttPricing modelPricingDetails; do
  grep -q "func $fn" "$FILE" || { echo "FAIL: missing CloudProviderCatalog.$fn"; exit 1; }
done
grep -Eq 'whisper|grok-stt|parakeet|deepgram' "$FILE" || {
  echo "FAIL: audio model heuristics missing"; exit 1
}
echo "PASS: dynamic model capability helpers present on CloudProviderCatalog."
