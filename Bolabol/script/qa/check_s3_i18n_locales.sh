#!/usr/bin/env bash
# S3 structural localization contract: S3 keys and the existing S1 language
# steps must appear exactly once in each of the 15 concrete locale maps.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

APPTEXT="Sources/NativeBolabolCore/Services/AppText.swift"
LOCALES=(en ru es de fr it pt zh ja ko ar hi uk tr pl)

S3_KEYS=(
  onboardingModelsTitle
  onboardingModelsHint
  onboardingModelsRecommended
  onboardingModelsBestMatch
  onboardingModelsChangeLater
  settingsLocalModelsRecommendedTitle
  settingsLocalModelsRecommendedHint
  settingsLocalModelsAllTitle
)

# S1 language-step regression set: interface language, primary language, and
# additional language copy, including their change-later/footer strings.
S1_KEYS=(
  onboardingChooseLanguageTitle
  onboardingChooseLanguageHint
  onboardingLanguageNote
  onboardingPrimaryLanguageTitle
  onboardingPrimaryLanguageHint
  onboardingPrimaryLanguageBody
  onboardingAdditionalLanguageTitle
  onboardingAdditionalLanguageHint
  onboardingAdditionalLanguageBody
  onboardingAdditionalSameAsPrimary
)

FAILED=0

fail() {
  echo "FAIL: $1"
  FAILED=1
}

if [ ! -f "$APPTEXT" ]; then
  echo "FAIL: $APPTEXT not found"
  exit 1
fi

map_block() {
  local locale="$1"
  awk -v locale="$locale" '
    index($0, "\"" locale "\": [") > 0 { in_map = 1; next }
    in_map && $0 ~ /^[[:space:]]*"[a-z][a-z]"[[:space:]]*:[[:space:]]*\[/ { exit }
    in_map { print }
  ' "$APPTEXT"
}

check_family() {
  local locale="$1"
  local block="$2"
  local family_name="$3"
  shift 3

  for key in "$@"; do
    local count
    count="$(printf '%s\n' "$block" | grep -cE "^[[:space:]]*\.${key}:" || true)"
    if [ "$count" -ne 1 ]; then
      fail "$family_name key $key appears $count times in the $locale map (expected exactly 1)"
      continue
    fi

    # Keep the S3 strings free of the old forced-target/output framing. The
    # Swift tests cover runtime resolution; this check is source-map scoped.
    if [ "$family_name" = "S3" ]; then
      local entry forbidden
      entry="$(printf '%s\n' "$block" | grep -E "^[[:space:]]*\.${key}:" || true)"
      forbidden="$(printf '%s\n' "$entry" | grep -iE 'target[[:space:]]+always|target[[:space:]]+output|always[[:space:]]+output|always[[:space:]]+force|force[[:space:]]+output' || true)"
      if [ -n "$forbidden" ]; then
        fail "$family_name key $key uses forbidden target/output terminology in $locale"
      fi
    fi
  done
}

for locale in "${LOCALES[@]}"; do
  locale_count="$(grep -cE "^[[:space:]]*\"${locale}\"[[:space:]]*:[[:space:]]*\[" "$APPTEXT" || true)"
  if [ "$locale_count" -ne 1 ]; then
    fail "locale $locale map appears $locale_count times (expected exactly 1)"
    continue
  fi

  block="$(map_block "$locale")"
  if [ -z "$block" ]; then
    fail "locale $locale map could not be isolated"
    continue
  fi

  check_family "$locale" "$block" S3 "${S3_KEYS[@]}"
  check_family "$locale" "$block" S1 "${S1_KEYS[@]}"
done

if [ "$FAILED" -ne 0 ]; then
  echo "FAIL: S3 locale-map coverage is incomplete"
  exit 1
fi

echo "OK: ${#S3_KEYS[@]} S3 keys + ${#S1_KEYS[@]} S1 language-step keys present exactly once in all ${#LOCALES[@]} locale maps"
