#!/usr/bin/env bash
# S2 structural contract for Settings -> Local Models recommendations.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

SETTINGS="Sources/NativeBolabol/Views/Settings/LocalModelsSettingsView.swift"
APPTEXT="Sources/NativeBolabolCore/Services/AppText.swift"
ONBOARDING="Sources/NativeBolabol/Views/OnboardingView.swift"
FAILED=0

fail() {
  echo "FAIL: $1"
  FAILED=1
}

require_file() {
  if [ ! -f "$1" ]; then
    fail "missing $1"
  fi
}

require_text() {
  local file="$1"
  local needle="$2"
  local description="$3"
  if ! grep -qF "$needle" "$file"; then
    fail "$description"
  fi
}

require_file "$SETTINGS"
require_file "$APPTEXT"

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

# Settings must use the one shared helper exactly once, with the current
# canonical speech pair and the current shipped catalog.
top_three_calls="$(grep -cE 'OnboardingModelRecommendation[.]topThree[[:space:]]*[(]' "$SETTINGS" || true)"
if [ "$top_three_calls" -ne 1 ]; then
  fail "Settings must contain exactly one topThree call (found $top_three_calls)"
fi

top_three_block="$(grep -B1 -A6 -E 'OnboardingModelRecommendation[.]topThree[[:space:]]*[(]' "$SETTINGS" || true)"
for argument in \
  'let speech = generalSettingsStore.speechLanguages' \
  'primary: speech.primaryLanguageCode' \
  'additional: speech.additionalLanguageCode' \
  'available: transcriptionModelStore.models'; do
  if [[ "$top_three_block" != *"$argument"* ]]; then
    fail "Settings topThree call is missing current input: $argument"
  fi
done

if ! grep -qE '^[[:space:]]*private var recommendedModels: \[TranscriptionModelDescriptor\]' "$SETTINGS"; then
  fail "recommendedModels must remain a computed descriptor property"
fi
if ! grep -qE '^[[:space:]]*private var remainingModels: \[TranscriptionModelDescriptor\]' "$SETTINGS"; then
  fail "remainingModels must remain a computed descriptor property"
fi

recommended_block="$(awk '
/^[[:space:]]*private var recommendedModels: \[TranscriptionModelDescriptor\]/ { capture = 1 }
capture { print }
capture && /^[[:space:]]*private var remainingModels:/ { exit }
' "$SETTINGS")"
for forbidden in '@State' '@StateObject' '@AppStorage' 'setBackend(' 'activate(' 'download(' 'remove(' 'activeModelID' 'reconcileModelStates'; do
  if [[ "$recommended_block" == *"$forbidden"* ]]; then
    fail "recommendation computation must not mutate model/backend state: $forbidden"
  fi
done

# The second group must be the same catalog with only recommended IDs removed.
remaining_block="$(awk '
/^[[:space:]]*private var remainingModels: \[TranscriptionModelDescriptor\]/ { capture = 1 }
capture { print }
capture && /^[[:space:]]*var body:/ { exit }
' "$SETTINGS")"
if [[ "$remaining_block" != *'let recommendedIDs = Set(recommendedModels.map(\.id))'* ]]; then
  fail "remainingModels must derive the recommended ID set"
fi
if [[ "$remaining_block" != *'return transcriptionModelStore.models.filter'* ]]; then
  fail "remainingModels must filter the full current catalog"
fi

recommended_row="$(grep -nF 'ForEach(recommendedModels)' "$SETTINGS" | awk -F: 'NR == 1 { print $1 }' || true)"
remaining_row="$(grep -nF 'ForEach(remainingModels)' "$SETTINGS" | awk -F: 'NR == 1 { print $1 }' || true)"
if [ -z "$recommended_row" ] || [ -z "$remaining_row" ]; then
  fail "Settings must render both recommended and remaining model groups"
elif [ "$recommended_row" -ge "$remaining_row" ]; then
  fail "recommended models must render before the remaining full catalog"
fi

# Keep the existing manual selection and model-management actions intact.
for needle in \
  'backendSelection' \
  'geminiCloudStatusRow' \
  'transcriptionModelStore.reconcileModelStates()' \
  'transcriptionModelStore.download(model)' \
  'transcriptionModelStore.activate(model)' \
  'transcriptionModelStore.remove(model)' \
  'ProgressView(value: state.progressFraction)' \
  'case .failed'; do
  require_text "$SETTINGS" "$needle" "existing Settings model-management contract is missing: $needle"
done

# The qualified helper may have exactly two product call sites: onboarding and
# Settings. This keeps a second ranking helper or an arbitrary runtime call out.
ranking_calls="$(grep -RIn --include='*.swift' -E 'OnboardingModelRecommendation[.]topThree[[:space:]]*[(]' Sources || true)"
ranking_call_count="$(printf '%s\n' "$ranking_calls" | awk 'NF { count++ } END { print count + 0 }')"
if [ "$ranking_call_count" -ne 2 ]; then
  fail "shared topThree must have exactly two product call sites (found $ranking_call_count)"
fi
while IFS= read -r line; do
  [ -n "$line" ] || continue
  case "$line" in
    *"$ONBOARDING:"*|*"$SETTINGS:"*) ;;
    *) fail "topThree call appears outside onboarding or Settings: $line" ;;
  esac
done <<< "$ranking_calls"

# S2 is presentation-only and must not add runtime Python or Canary wiring.
if ! bash script/qa/check_no_python_in_sources.sh >/dev/null; then
  fail "Python runtime contract failed"
fi
if ! bash script/qa/check_no_canary_product.sh >/dev/null; then
  fail "Canary/GigaAM product-surface contract failed"
fi

# S2 source keys must exist in the enum and in the English map.
for key in \
  settingsLocalModelsRecommendedTitle \
  settingsLocalModelsRecommendedHint \
  settingsLocalModelsAllTitle; do
  if ! grep -qE "^[[:space:]]+case ${key}[[:space:]]*$" "$APPTEXT"; then
    fail "missing AppTextKey case: $key"
  fi
  if ! grep -qF ".${key}:" "$APPTEXT"; then
    fail "missing English/source AppText entry: $key"
  fi
done

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

echo "OK: S2 Settings recommendations, partition, presentation-only, and runtime contracts"
