import Foundation
import NativeSmartScribeCore
import Testing

/// Guards the onboarding ↔ AppText key synchronisation. The welcome tour
/// (`OnboardingView`) is built entirely from `onboarding*` keys; a previous
/// iteration referenced keys that did not exist in `AppTextKey`, which broke
/// the build and left the tour unlocalised. These tests lock the contract:
/// every onboarding key must resolve to a real, non-empty translation in all
/// 12 supported languages (never the raw-key fallback).
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
  #expect(concreteLanguages.count == 12, "Expected 12 concrete UI languages")

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
  // These three keys were added to support the tour UI. Verify they did not
  // silently fall back to English in non-English locales (i.e. that a real
  // translation exists per language).
  let newKeys: [AppTextKey] = [
    .onboardingWelcomeTitle,
    .onboardingPermissionsGrant,
    .onboardingGlossaryExplanation,
    .onboardingGlossaryCreate,
    .onboardingGlossaryCreated,
  ]

  let english = UILanguagePreference.english
  for language in [UILanguagePreference.russian, .chinese, .arabic, .hindi] {
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
  ]

  for key in usedByTour {
    let value = AppText.localized(key, language: .english)
    #expect(value != key.rawValue, "Tour key \(key.rawValue) has no English translation")
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
