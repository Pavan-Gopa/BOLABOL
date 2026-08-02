import Foundation
import NativeBlaboomCore
import Testing

/// Full localization contract: every AppTextKey resolves for every concrete UI language.
private let concreteLanguages: [UILanguagePreference] = UILanguagePreference.allCases.filter {
  $0 != .system
}

@Test
func everyAppTextKeyResolvesNonEmptyInEnglish() {
  var missing: [String] = []
  for key in AppTextKey.allCases {
    let value = AppText.localized(key, language: .english)
    if value.isEmpty || value == key.rawValue {
      missing.append(key.rawValue)
    }
  }
  #expect(missing.isEmpty, "English missing translations for: \(missing.prefix(20))")
}

@Test
func everyAppTextKeyResolvesNonEmptyInRussian() {
  var missing: [String] = []
  for key in AppTextKey.allCases {
    let value = AppText.localized(key, language: .russian)
    if value.isEmpty || value == key.rawValue {
      missing.append(key.rawValue)
    }
  }
  #expect(missing.isEmpty, "Russian missing translations for: \(missing.prefix(20))")
}

@Test
func everyAppTextKeyResolvesInEveryConcreteLanguage() {
  // Full cartesian product: keys × languages. Collect failures instead of
  // exploding into thousands of individual #expect failures.
  var failures: [String] = []
  for language in concreteLanguages {
    for key in AppTextKey.allCases {
      let value = AppText.localized(key, language: language)
      if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        failures.append("\(language.rawValue):\(key.rawValue)=empty")
      } else if value == key.rawValue {
        failures.append("\(language.rawValue):\(key.rawValue)=fallback")
      }
    }
  }
  #expect(
    failures.isEmpty,
    "Localization gaps (\(failures.count)): \(failures.prefix(30).joined(separator: ", "))"
  )
}

@Test
func appTextKeyCountIsLargeEnoughForProductSurface() {
  // Guard against accidental deletion of large localization blocks.
  #expect(AppTextKey.allCases.count >= 400)
  #expect(concreteLanguages.count == 15)
}

@Test
func appTextSettingsTabLabelsExistForAllTabs() {
  let tabKeys: [AppTextKey] = [
    .settingsGeneral,
    .settingsAPIProviders,
    .settingsHotkey,
    .settingsGlossary,
    .settingsPolishing,
    .settingsHelp,
  ]
  for language in concreteLanguages {
    for key in tabKeys {
      let value = AppText.localized(key, language: language)
      #expect(!value.isEmpty)
      #expect(value != key.rawValue)
    }
  }
}

@Test
func appTextNoteWorkspaceLabelsExist() {
  let keys: [AppTextKey] = [
    .raw, .variantOne, .variantTwo, .notes, .record, .stopRecording,
    .importAudio, .translate, .polish, .copy, .untitledNote, .voiceNote,
  ]
  for language in [.english, .russian, .chinese, .arabic] as [UILanguagePreference] {
    for key in keys {
      #expect(AppText.localized(key, language: language) != key.rawValue)
    }
  }
}

@Test
func appTextHUDHelpKeysDocumentControls() {
  let english = UILanguagePreference.english
  #expect(AppText.localized(.helpHUDControlLanguage, language: english).contains("A"))
  #expect(AppText.localized(.helpHUDControlTarget, language: english).contains("R"))
  #expect(AppText.localized(.helpHUDRightCycle, language: english).contains("1"))
  let body = AppText.localized(.helpModeHotkeyBody, language: english).lowercased()
  #expect(body.contains("scroll") || body.contains("provider"))
}

@Test
func appTextSystemLocaleResolutionFallsBackToEnglishForUnknown() {
  #expect(
    UILanguagePreference.system.resolvedLocaleIdentifier(
      for: Locale(identifier: "xx_YY")
    ) == "en"
  )
}

@Test
func appTextBilingualHelpKeysExistAndDocumentLanguages() {
  let english = UILanguagePreference.english
  let title = AppText.localized(.helpBilingualTitle, language: english)
  let intro = AppText.localized(.helpBilingualIntro, language: english)
  #expect(!title.isEmpty && title != AppTextKey.helpBilingualTitle.rawValue)
  #expect(!intro.isEmpty && intro != AppTextKey.helpBilingualIntro.rawValue)
  #expect(intro.lowercased().contains("primary"))
}

