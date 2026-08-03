#!/usr/bin/env bash
# S1c structural contract for the dynamic local-model onboarding screen.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

ONBOARDING="Sources/NativeBolabol/Views/OnboardingView.swift"
APPTEXT="Sources/NativeBolabolCore/Services/AppText.swift"
RANKING="Sources/NativeBolabolCore/Models/OnboardingModelRecommendation.swift"
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

require_adjacent() {
  local anchor="$1"
  local expected="$2"
  if ! grep -A1 -F "$anchor" "$ONBOARDING" | grep -qF "$expected"; then
    fail "$anchor must dispatch to $expected"
  fi
}

require_file "$ONBOARDING"
require_file "$APPTEXT"
require_file "$RANKING"

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

# Keep the eight onboarding screens in the product order.
if ! grep -qE '^[[:space:]]*private let totalSteps = 8[[:space:]]*$' "$ONBOARDING"; then
  fail "onboarding must keep exactly eight steps"
fi
require_adjacent 'case 0:' 'languageStep'
require_adjacent 'case 1:' 'primaryLanguageStep'
require_adjacent 'case 2:' 'additionalLanguageStep'
require_adjacent 'case 3:' 'localModelsStep'
require_adjacent 'case 4:' 'permissionsStep'
require_adjacent 'case 5:' 'modesStep'
require_adjacent 'case 6:' 'glossaryStep'
require_adjacent 'default:' 'themeStep'

# S1c has one and only one UI call site, with the current speech pair and store.
top_three_calls="$(grep -cE 'OnboardingModelRecommendation[.]topThree[[:space:]]*[(]' "$ONBOARDING" || true)"
if [ "$top_three_calls" -ne 1 ]; then
  fail "OnboardingView must contain exactly one topThree UI call (found $top_three_calls)"
fi

top_three_block="$(grep -A5 -E 'OnboardingModelRecommendation[.]topThree[[:space:]]*[(]' "$ONBOARDING" || true)"
for argument in \
  'primary: settingsStore.speechLanguages.primaryLanguageCode' \
  'additional: settingsStore.speechLanguages.additionalLanguageCode' \
  'available: transcriptionModelStore.models'; do
  if [[ "$top_three_block" != *"$argument"* ]]; then
    fail "topThree call is missing required argument: $argument"
  fi
done

# Keep ranking ownership in the pure helper and prevent arbitrary new call sites.
while IFS= read -r line; do
  [ -n "$line" ] || continue
  if [[ "$line" == *"$RANKING"* ]]; then
    continue
  fi
  if [[ "$line" == Sources/NativeBolabol/Views/OnboardingView.swift:* ]]; then
    continue
  fi
  fail "S1c ranking symbol appears outside the helper or onboarding view: $line"
done < <(grep -RIn --include='*.swift' -E 'OnboardingModelRecommendation|\.topThree\(' Sources || true)

# Cards must be computed from the helper result, not cached in SwiftUI state or
# padded with fixed slots/placeholders when catalog entries are unavailable.
if ! grep -qF 'private var onboardingModels: [TranscriptionModelDescriptor]' "$ONBOARDING"; then
  fail "onboardingModels must remain a computed descriptor list"
fi
if grep -nE '@(State|StateObject|SceneStorage|AppStorage)[^[:cntrl:]]*onboardingModels|onboardingModels[[:space:]]*=[[:space:]]*' "$ONBOARDING"; then
  fail "onboarding model cards must not use stale state/cache"
fi
if ! grep -qF 'ForEach(Array(onboardingModels.enumerated()), id: \.element.id)' "$ONBOARDING"; then
  fail "local-model cards must enumerate the computed onboardingModels result"
fi
if grep -nEi 'preferred[[:alnum:]_]*(id|model)|modelIDs?[[:space:]]*=[^=]|(gigaam|canary|whisperkit|parakeet)-|placeholder|emptyModel|modelSlot|0\.\.<[[:space:]]*3' "$ONBOARDING"; then
  fail "OnboardingView contains hard-coded model ranking or placeholder slots"
fi

# Only slot zero owns the Recommended badge and Best Match subtitle.
slot_zero_blocks="$(grep -A4 -E '^[[:space:]]*if slot == 0[[:space:]]*\{[[:space:]]*$' "$ONBOARDING" || true)"
for key in onboardingModelsRecommended onboardingModelsBestMatch; do
  count="$(grep -cF ".${key}" "$ONBOARDING" || true)"
  if [ "$count" -ne 1 ]; then
    fail "$key must be referenced exactly once"
  elif [[ "$slot_zero_blocks" != *".${key}"* ]]; then
    fail "$key must be rendered only inside the slot == 0 branch"
  fi
done
if ! grep -qF 'else if let badge = model.badge' "$ONBOARDING"; then
  fail "non-first cards must retain their descriptor badges"
fi

# Next/Skip must not require a downloaded model or mutate backend/active model
# when the user makes no explicit card selection.
if grep -nE 'step[[:space:]]*(==|!=)[[:space:]]*3|\.disabled[[:space:]]*\([^)]*step|step[^[:cntrl:]]*disabled' "$ONBOARDING"; then
  fail "Next must not be blocked through a step == 3 model-download gate"
fi
finish_block="$(grep -A7 -E '^[[:space:]]*private func finish\(\)' "$ONBOARDING" || true)"
if [[ "$finish_block" == *"activeModelID"* || "$finish_block" == *"setBackend"* || "$finish_block" == *"transcriptionModelStore"* || "$finish_block" == *"activate("* || "$finish_block" == *"download("* ]]; then
  fail "finish must not change backend or activeModelID without an explicit model action"
fi

# Preserve the existing store-backed Download, Retry, Use, progress, and error
# states instead of introducing a second model-management path.
for needle in \
  'transcriptionModelStore.download(model)' \
  'transcriptionModelStore.activate(model)' \
  'settingsStore.text(.download)' \
  'settingsStore.text(.retry)' \
  'settingsStore.text(.use)' \
  'installation.status == .downloading' \
  'installation.status == .failed'; do
  if ! grep -qF "$needle" "$ONBOARDING"; then
    fail "existing store action/state is missing: $needle"
  fi
done

# S1c adds source keys only; runtime integrations and Python remain forbidden.
for key in \
  onboardingModelsTitle \
  onboardingModelsHint \
  onboardingModelsRecommended \
  onboardingModelsBestMatch \
  onboardingModelsChangeLater; do
  if ! grep -qE "^[[:space:]]+case ${key}[[:space:]]*$" "$APPTEXT"; then
    fail "missing AppTextKey case: $key"
  fi
  if ! grep -qF ".${key}:" "$APPTEXT"; then
    fail "missing AppText English/source map entry: $key"
  fi
done

if grep -nEi '^import (CoreML|FluidAudio|WhisperKit|MLX|Python)|Process\(|executableURL|launchPath|TranscriptionEngine|EngineStore|CoreMLEngine|GigaAM|Canary' "$ONBOARDING"; then
  fail "OnboardingView contains new ASR runtime/engine wiring"
fi
if grep -nE 'transcriptionStep|cloudSetup|backendButton|transcriptionSetupIsReady|saveGoogleAPIKey|polishingEngineStore' "$ONBOARDING"; then
  fail "obsolete cloud/engine onboarding setup remains in the S1c screen"
fi

# Reuse the repo-wide runtime guards so this step cannot silently introduce
# Python or Canary/GigaAM product integration.
if ! bash script/qa/check_no_python_in_sources.sh >/dev/null; then
  fail "Python runtime contract failed"
fi
if ! bash script/qa/check_no_canary_product.sh >/dev/null; then
  fail "Canary/GigaAM product-surface contract failed"
fi

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

echo "OK: S1c dynamic onboarding model cards and no-runtime contracts"
