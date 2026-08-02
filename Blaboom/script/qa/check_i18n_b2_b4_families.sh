#!/usr/bin/env bash
# i18n families (B2 onboarding, B3 settings pair, B4 helpBilingual, helpLang/helpHUD):
# every key must exist in EVERY one of the 15 locale maps inside AppText.swift.
# This is a structural complement to the runtime guards (SettingsLocalizationTests
# / OnboardingLocalizationTests / AppTextFullCoverageTests): those resolve via
# AppText.localized, this proves the literal per-locale dictionary entries exist.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

APPTEXT="Sources/NativeBlaboomCore/Services/AppText.swift"
[ -f "$APPTEXT" ] || { echo "FAIL: $APPTEXT not found"; exit 1; }

LOCALES=(en ru es de fr it pt zh ja ko ar hi uk tr pl)

# B2 onboarding (plan §6.1), B3 settings pair (§7.1), B4 help bilingual (§8.1),
# helpLang*/helpHUD* updated per §8.2.
FAMILIES=(
  onboardingPrimaryLanguageTitle onboardingPrimaryLanguageHint onboardingPrimaryLanguageBody
  onboardingAdditionalLanguageTitle onboardingAdditionalLanguageHint onboardingAdditionalLanguageBody
  onboardingAdditionalSameAsPrimary
  languagePairSectionTitle primaryLanguage primaryLanguageHint
  additionalLanguage additionalLanguageHint additionalSameAsPrimary languagePairEngineNote
  helpBilingualTitle helpBilingualIntro helpBilingualPrimary helpBilingualAdditional
  helpBilingualNotAlwaysOutput helpBilingualWhere helpBilingualOnboarding helpBilingualSettingsPath
  helpBilingualCanary helpBilingualHUD helpBilingualAutoEngines helpBilingualPolishNote
  helpLangIntro helpLangAuto helpLangForced helpLangEnglishNote helpLangOtherNote helpLangWhere
  helpHUDLeftA helpHUDLeftLetter helpHUDLeftTap helpHUDControlLanguage
)

FAILED=0
for key in "${FAMILIES[@]}"; do
  # One dictionary entry per locale: ".key: " must appear exactly once per map.
  count=$(grep -cE "^[[:space:]]*\.${key}:" "$APPTEXT" || true)
  if [ "$count" -ne 15 ]; then
    echo "FAIL: ${key} appears $count times (expected 15 — one per locale map)"
    FAILED=1
  fi
done

if [ "$FAILED" -ne 0 ]; then
  echo "FAIL: i18n family coverage broken (B2/B3/B4 + helpLang/helpHUD × 15 locales)"
  exit 1
fi

echo "OK: $((${#FAMILIES[@]})) B2–B4/helpLang/helpHUD keys present in all 15 locale maps"
