import Foundation
import NativeBlaboomCore
import Testing

/// Guards the onboarding ↔ AppText key synchronisation. The welcome tour
/// (`OnboardingView`) is built entirely from `onboarding*` keys; a previous
/// iteration referenced keys that did not exist in `AppTextKey`, which broke
/// the build and left the tour unlocalised. These tests lock the contract:
/// every onboarding key must resolve to a real, non-empty translation in all
/// 15 supported languages (never the raw-key fallback).
private let onboardingKeys: [AppTextKey] = AppTextKey.allCases.filter {
  $0.rawValue.hasPrefix("onboarding")
}

/// The concrete UI languages the app ships translations for (excludes `.system`,
/// whose resolution depends on the host environment).
private let concreteLanguages: [UILanguagePreference] = UILanguagePreference.allCases.filter {
  $0 != .system
}

@Test
func everyOnboardingKeyIsLocalizedInEveryLanguage() {
  #expect(!onboardingKeys.isEmpty, "Expected onboarding keys to exist in AppTextKey")
  #expect(concreteLanguages.count == 15, "Expected 15 concrete UI languages")

  for language in concreteLanguages {
    for key in onboardingKeys {
      let value = AppText.localized(key, language: language)
      #expect(
        !value.isEmpty,
        "Onboarding key \(key.rawValue) resolved to an empty string for \(language.rawValue)"
      )
      #expect(
        value != key.rawValue,
        "Onboarding key \(key.rawValue) fell back to its raw key for \(language.rawValue)"
      )
    }
  }
}

@Test
func newlyAddedOnboardingKeysAreActuallyTranslated() {
  // These keys were added to support the tour UI. Verify they did not
  // silently fall back to English in non-English locales (i.e. that a real
  // translation exists per language). B5 (plan §9): the B2 speech-language
  // steps are real 15-locale strings — they must differ from the EN source
  // in every non-EN locale, never fall back.
  let newKeys: [AppTextKey] = [
    .onboardingWelcomeTitle,
    .onboardingPermissionsGrant,
    .onboardingGlossaryExplanation,
    .onboardingGlossaryCreate,
    .onboardingGlossaryCreated,
    // B2 — primary + additional speech-language steps (plan §6.1)
    .onboardingPrimaryLanguageTitle, .onboardingPrimaryLanguageHint,
    .onboardingPrimaryLanguageBody, .onboardingAdditionalLanguageTitle,
    .onboardingAdditionalLanguageHint, .onboardingAdditionalLanguageBody,
    .onboardingAdditionalSameAsPrimary,
  ]

  let english = UILanguagePreference.english
  // B5 (Tester): iterate ALL 14 non-EN concrete languages — a 4-locale
  // sample (ru/zh/ar/hi) could miss a silent EN fallback in es/de/fr/it/pt/
  // ja/ko/uk/tr/pl. Independently verified: 0 identical-to-EN across 14.
  for language in concreteLanguages where language != english {
    for key in newKeys {
      let localized = AppText.localized(key, language: language)
      let englishValue = AppText.localized(key, language: english)
      #expect(
        localized != key.rawValue,
        "New onboarding key \(key.rawValue) missing for \(language.rawValue)"
      )
      #expect(
        localized != englishValue,
        "New onboarding key \(key.rawValue) fell back to English for \(language.rawValue)"
      )
    }
  }
}

@Test
func onboardingKeysUsedByWelcomeTourAllExist() {
  // The exact set of keys referenced by OnboardingView. If any of these is
  // ever removed from AppTextKey the tour stops compiling; this list also
  // documents the contract and fails loudly if a key loses all translations.
  let usedByTour: [AppTextKey] = [
    .onboardingWelcomeTitle, .onboardingChooseLanguageTitle, .onboardingChooseLanguageHint,
    .onboardingLanguageNote,
    .onboardingHowToTranscribe, .onboardingLocalTitle, .onboardingLocalBody,
    .onboardingCloudTitle, .onboardingCloudBody,
    .onboardingSetupTitle, .onboardingSetupLocalBody, .onboardingSetupCloudBody,
    .onboardingOpenSettings,
    .onboardingPermissionsTitle, .onboardingPermissionsBody,
    .onboardingMicrophone, .onboardingAccessibility, .onboardingPermissionsGrant,
    .onboardingModesTitle, .onboardingModesBody,
    .onboardingGlossaryTitle, .onboardingGlossaryBody, .onboardingGlossaryExplanation,
    .onboardingGlossaryCreate, .onboardingGlossaryCreated,
    .onboardingThemeTitle, .onboardingThemeBody,
    .onboardingBack, .onboardingNext, .onboardingGetStarted, .onboardingSkip, .onboardingShowTour,
    // B2 — primary + additional speech-language steps (plan §6.1).
    .onboardingPrimaryLanguageTitle, .onboardingPrimaryLanguageHint, .onboardingPrimaryLanguageBody,
    .onboardingAdditionalLanguageTitle, .onboardingAdditionalLanguageHint, .onboardingAdditionalLanguageBody,
    .onboardingAdditionalSameAsPrimary,
  ]

  for key in usedByTour {
    let value = AppText.localized(key, language: .english)
    #expect(value != key.rawValue, "Tour key \(key.rawValue) has no English translation")
  }
}

/// B2 — keys added for the primary + additional speech-language steps
/// (plan §6.1, §9.4). Full 15-locale maps landed in B5; EN remains the
/// authoritative source.
private let b2SpeechLanguageKeys: [AppTextKey] = [
  .onboardingPrimaryLanguageTitle,
  .onboardingPrimaryLanguageHint,
  .onboardingPrimaryLanguageBody,
  .onboardingAdditionalLanguageTitle,
  .onboardingAdditionalLanguageHint,
  .onboardingAdditionalLanguageBody,
  .onboardingAdditionalSameAsPrimary,
]

@Test
func onboardingSpeechLanguageKeysResolveInEnglish() {
  // B2 requires real EN strings for the new keys — never the raw-key fallback.
  for key in b2SpeechLanguageKeys {
    let value = AppText.localized(key, language: .english)
    #expect(!value.isEmpty, "B2 key \(key.rawValue) has no English translation")
    #expect(
      value != key.rawValue,
      "B2 key \(key.rawValue) fell back to its raw key in English"
    )
  }
}

@Test
func onboardingAndSettingsSameAsPrimaryCopyMatch() {
  // B3 — the Settings "Same as primary" control describes the same policy as
  // the onboarding step (plan §6.2, §7.1): additional mirrors primary; it is
  // never framed as a forced output language. The two surfaces share wording.
  let onboarding = AppText.localized(.onboardingAdditionalSameAsPrimary, language: .english)
  let settings = AppText.localized(.additionalSameAsPrimary, language: .english)
  #expect(!onboarding.isEmpty && onboarding != AppTextKey.onboardingAdditionalSameAsPrimary.rawValue)
  #expect(!settings.isEmpty && settings != AppTextKey.additionalSameAsPrimary.rawValue)
  #expect(onboarding == settings)
}

@Test
func onboardingSpeechLanguageCopyAvoidsTargetAlwaysOutputTerminology() {
  // Plan §3.1 / §6.2: additional is a second language the user often uses —
  // never a "target" / "always output" language. Check every locale a user
  // could see (EN fallback included).
  for language in concreteLanguages {
    for key in b2SpeechLanguageKeys {
      let value = AppText.localized(key, language: language).lowercased()
      #expect(!value.contains("target always"))
      #expect(!value.contains("target output"))
      #expect(!value.contains("always output"))
    }
  }
}

@Test
func onboardingGlossaryExplanationAvoidsInternalTerminology() {
  for language in concreteLanguages {
    let explanation = AppText.localized(.onboardingGlossaryExplanation, language: language)
      .lowercased()
    #expect(!explanation.contains("json"))
    #expect(!explanation.contains("hud"))
    #expect(!explanation.contains("hotkey"))
  }
}
