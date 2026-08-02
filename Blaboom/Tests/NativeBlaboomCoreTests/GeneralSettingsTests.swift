import Foundation
import NativeBlaboomCore
import Testing

@Test
func generalSettingsMatchElectronGeneralDefaults() {
    let settings = GeneralSettings()

    #expect(settings.theme == .dark)
    #expect(settings.uiScale == 1)
    #expect(settings.uiLanguage == .system)
    #expect(settings.overlay.position == .bottomCenter)
    #expect(settings.overlay.lastOrigin == nil)
    #expect(settings.overlay.scale == 1)
    #expect(settings.overlay.capsuleOpacity == 0.32)
    #expect(settings.overlay.soundEnabled == true)
    #expect(settings.overlay.volume == 1)
    #expect(settings.overlay.style == .capsule)
    #expect(settings.overlay.styleOrigins.isEmpty)
    #expect(settings.logLevel == .warn)
}

@Test
func generalSettingsDefaultSpeechLanguagesMatchCanonicalDefaults() {
    let settings = GeneralSettings()

    // Structural equality: the blob default equals the canonical fresh-install
    // default computed the same way, regardless of the machine's locale.
    #expect(settings.speechLanguages == UserSpeechLanguages())
    #expect(settings.speechLanguages == UserSpeechLanguages.makeDefaults())
    #expect(!settings.speechLanguages.primaryLanguageCode.isEmpty)
    #expect(!settings.speechLanguages.additionalLanguageCode.isEmpty)
}

@Test
func generalSettingsCarriesExplicitSpeechLanguagesPair() {
    let pair = UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "en")
    let settings = GeneralSettings(speechLanguages: pair)

    #expect(settings.speechLanguages == pair)
    #expect(settings.speechLanguages.primaryLanguageCode == "ru")
    #expect(settings.speechLanguages.additionalLanguageCode == "en")
}

@Test
func generalSettingsSpeechLanguagesRoundTripThroughCodable() throws {
    let pair = UserSpeechLanguages(primaryLanguageCode: "hi", additionalLanguageCode: "en")
    let settings = GeneralSettings(theme: .light, speechLanguages: pair)

    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(GeneralSettings.self, from: data)

    #expect(decoded.speechLanguages == pair)
    #expect(decoded.theme == .light)
}

@Test
func generalSettingsDecodesLegacyPayloadWithoutSpeechLanguagesKey() throws {
    let data = Data("""
    {
      "theme": "dark",
      "uiScale": 1,
      "uiLanguage": "system",
      "hasCompletedOnboarding": false,
      "textScale": 1,
      "textFont": "system",
      "isAutoArchiveCleanupEnabled": true,
      "maxSavedAudioRecordings": 50
    }
    """.utf8)

    let settings = try JSONDecoder().decode(GeneralSettings.self, from: data)

    // Legacy payload: the pair falls back to canonical fresh-install defaults;
    // the store layer then runs best-effort migration on top (B1).
    #expect(settings.speechLanguages == UserSpeechLanguages())
    #expect(settings.maxSavedAudioRecordings == 50)
}

@Test
func generalSettingsNormalizeKeepsSpeechLanguagesPair() {
    var settings = GeneralSettings(speechLanguages: UserSpeechLanguages(
        primaryLanguageCode: "ru",
        additionalLanguageCode: "en"
    ))

    settings.normalize()

    #expect(settings.speechLanguages.primaryLanguageCode == "ru")
    #expect(settings.speechLanguages.additionalLanguageCode == "en")
}

@Test
func generalSettingsNormalizeSliderRanges() {
    var settings = GeneralSettings()
    settings.uiScale = 2
    settings.overlay.scale = 0.1
    settings.overlay.capsuleOpacity = 2
    settings.overlay.volume = 4

    settings.normalize()

    #expect(settings.uiScale == 1.4)
    #expect(settings.overlay.scale == 0.8)
    #expect(settings.overlay.capsuleOpacity == 1)
    #expect(settings.overlay.volume == 2)
}

@Test
func overlaySettingsDecodeLegacyPayloadWithoutOpacity() throws {
    let data = Data("""
    {
      "position": "bottom-center",
      "scale": 1.2,
      "soundEnabled": true,
      "volume": 0.05
    }
    """.utf8)

    let settings = try JSONDecoder().decode(OverlayHUDSettings.self, from: data)

    #expect(settings.capsuleOpacity == 0.32)
    #expect(settings.volume == 0.1)
    #expect(settings.style == .capsule)
    #expect(settings.styleOrigins.isEmpty)
}

@Test
func overlaySettingsRememberAnIndependentOriginForEveryStyle() throws {
    var settings = OverlayHUDSettings()
    let capsuleOrigin = OverlayHUDOrigin(x: 120, y: 48)
    let techOrigin = OverlayHUDOrigin(x: 812, y: 620)
    let verticalOrigin = OverlayHUDOrigin(x: 35, y: 410)

    settings.setOrigin(capsuleOrigin, for: .capsule)
    settings.setOrigin(techOrigin, for: .tech)
    settings.setOrigin(verticalOrigin, for: .vertical)

    #expect(settings.origin(for: .capsule) == capsuleOrigin)
    #expect(settings.origin(for: .tech) == techOrigin)
    #expect(settings.origin(for: .vertical) == verticalOrigin)
    #expect(settings.lastOrigin == capsuleOrigin)

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(OverlayHUDSettings.self, from: encoded)
    #expect(decoded.origin(for: .capsule) == capsuleOrigin)
    #expect(decoded.origin(for: .tech) == techOrigin)
    #expect(decoded.origin(for: .vertical) == verticalOrigin)
}

@Test
func overlaySettingsUseLegacyOriginOnlyForClassicStyle() {
    let legacyOrigin = OverlayHUDOrigin(x: 240, y: 80)
    let settings = OverlayHUDSettings(lastOrigin: legacyOrigin)

    #expect(settings.origin(for: .capsule) == legacyOrigin)
    #expect(settings.origin(for: .tech) == nil)
    #expect(settings.origin(for: .vertical) == nil)
}

@Test
func overlayPositionSupportsBottomCenter() {
    #expect(OverlayPosition.allCases.contains(.bottomCenter))
    #expect(OverlayPosition.bottomCenter.displayName == "Bottom-center")
}

@Test
func uiLanguagePreferenceResolvesSystemLocalesLikeElectron() {
    #expect(UILanguagePreference.system.resolvedLocaleIdentifier(for: Locale(identifier: "ru_RU")) == "ru")
    #expect(UILanguagePreference.system.resolvedLocaleIdentifier(for: Locale(identifier: "pt_BR")) == "pt")
    #expect(UILanguagePreference.system.resolvedLocaleIdentifier(for: Locale(identifier: "nl_NL")) == "en")
    #expect(UILanguagePreference.japanese.resolvedLocaleIdentifier(for: Locale(identifier: "ru_RU")) == "ja")
}

@Test
func appTextUsesSelectedRussianLanguage() {
    #expect(AppText.localized(.settingsGeneral, language: .russian) == "Общие")
    #expect(AppText.localized(.copy, language: .russian) == "Копировать")
    #expect(AppText.localized(.settingsGeneral, language: .system, systemLocale: Locale(identifier: "ru_RU")) == "Общие")
}

@Test
func helpGuideCoversCurrentProductSurface() {
    let hero = AppText.localized(.helpHeroSubtitle, language: .english)
    #expect(hero.contains("Whisper") || hero.lowercased().contains("dictate"))

    let start = AppText.localized(.helpStart2, language: .english)
    #expect(start.contains("Local Models") || start.contains("Whisper"))
    #expect(start.contains("Full") || start.contains("Large"))

    let languageControl = AppText.localized(.helpHUDControlLanguage, language: .english)
    #expect(languageControl.contains("A"))
    #expect(languageControl.contains("E") || languageControl.contains("English"))

    let leftA = AppText.localized(.helpHUDLeftA, language: .english)
    #expect(leftA.contains("A") && leftA.lowercased().contains("auto"))
    let leftLetter = AppText.localized(.helpHUDLeftLetter, language: .english)
    #expect(leftLetter.contains("E") && leftLetter.contains("English"))
    let leftTap = AppText.localized(.helpHUDLeftTap, language: .english)
    #expect(leftTap.lowercased().contains("tap") || leftTap.contains("A"))

    let rightR = AppText.localized(.helpHUDRightR, language: .english)
    #expect(rightR.contains("R") && rightR.lowercased().contains("raw"))
    let rightCycle = AppText.localized(.helpHUDRightCycle, language: .english)
    #expect(rightCycle.contains("1") && rightCycle.contains("2"))

    let drag = AppText.localized(.helpHUDDrag, language: .english)
    #expect(drag.lowercased().contains("drag") || drag.lowercased().contains("move"))
    let size = AppText.localized(.helpHUDSize, language: .english)
    #expect(size.lowercased().contains("size") || size.contains("General"))
    let sound = AppText.localized(.helpHUDSound, language: .english)
    #expect(sound.lowercased().contains("sound"))

    let targetControl = AppText.localized(.helpHUDControlTarget, language: .english)
    #expect(targetControl.contains("R") && targetControl.contains("1") && targetControl.contains("2"))

    let englishNote = AppText.localized(.helpLangEnglishNote, language: .english)
    #expect(englishNote.contains("Whisper"))
    #expect(englishNote.contains("Full") || englishNote.lowercased().contains("translate"))

    let otherNote = AppText.localized(.helpLangOtherNote, language: .english)
    #expect(otherNote.contains("LLM") || otherNote.contains("MLX"))

    let providers = AppText.localized(.helpCloudProviders, language: .english)
    #expect(providers.contains("Google"))
    #expect(providers.contains("OpenRouter"))
    #expect(providers.contains("Qwen"))
    #expect(providers.contains("Custom"))

    let openRouter = AppText.localized(.helpCloudOpenRouter, language: .english)
    #expect(openRouter.lowercased().contains("balance"))

    // Floating translation + dual hotkeys (recent product surface)
    let floatHotkey = AppText.localized(.helpHotkeySecondary, language: .english)
    #expect(floatHotkey.contains("Option+~") || floatHotkey.lowercased().contains("translation"))
    #expect(!floatHotkey.contains("Alt+"))
    let helpPrimary = AppText.localized(.helpHotkeyPrimary, language: .english)
    #expect(helpPrimary.contains("Option+S"))
    #expect(!helpPrimary.contains("Alt+"))
    let floatCapture = AppText.localized(.helpFloatCapture, language: .english)
    #expect(floatCapture.contains("Command-C") || floatCapture.lowercased().contains("clipboard"))
    let favorites = AppText.localized(.helpCloudFavorites, language: .english)
    #expect(favorites.contains("★") || favorites.lowercased().contains("favorite"))
    let multiKeys = AppText.localized(.helpCloudKeys, language: .english)
    #expect(multiKeys.contains("10") || multiKeys.lowercased().contains("key"))
    #expect(!AppText.localized(.helpModeFloatTitle, language: .russian).isEmpty)

    let clear = AppText.localized(.helpPrivacyClear, language: .english)
    #expect(clear.contains("Clear All") || clear.lowercased().contains("permanently"))

    #expect(AppText.localized(.helpHeroTitle, language: .russian).contains("Blaboom"))
    #expect(!AppText.localized(.helpStartTitle, language: .russian).isEmpty)
    #expect(!AppText.localized(.helpHUDControlLanguage, language: .russian).isEmpty)

    // Legacy keys still resolve for partial locales / older references
    #expect(!AppText.localized(.helpQuickStart, language: .english).isEmpty)
    #expect(!AppText.localized(.helpLogsStep, language: .english).isEmpty)
}

@Test
func settingsAndTranslationCopyUsesSharedLocalizedText() {
    #expect(AppText.localized(.globalHotkey, language: .english) == "Global Hotkey")
    #expect(AppText.localized(.enableHotkey, language: .english) == "Enable hotkey")
    #expect(AppText.localized(.textPolishingProviders, language: .english) == "Text Polishing Providers")
    #expect(AppText.localized(.useForPolishing, language: .english) == "Use for Polishing")
    #expect(AppText.localized(.noTranslationProvider, language: .english) == "No translation provider is available.")
    #expect(AppText.localized(.globalHotkey, language: .russian) == "Глобальная горячая клавиша")
    #expect(AppText.localized(.textPolishingProviders, language: .russian) == "Провайдеры текстовой доводки")
    #expect(AppText.localized(.untitledNote, language: .english) == "Untitled Note")
    #expect(AppText.localized(.voiceNote, language: .english) == "Voice Note")
    #expect(AppText.localized(.blankNoteFallback, language: .russian) == "Пустая заметка")
    #expect(AppText.localized(.monoChannel, language: .english) == "mono")
    #expect(AppText.localized(.channelsCount, language: .russian) == "%d канала(ов)")
    #expect(AppText.localized(.noTranscriptToPolish, language: .english) == "No transcript is available to polish.")
    #expect(AppText.localized(.unsupportedAudioFormat, language: .russian) == "Этот аудиоформат не поддерживается системным декодером macOS.")
}

@Test
func appTextCoversTranscriptionAndModelPreparationFallbacks() {
    #expect(
        AppText.localized(.missingAudioFileForTranscription, language: .english)
            == "No audio file was provided for transcription."
    )
    #expect(
        AppText.localized(.modelDownloadedLoadsOnFirstUse, language: .english)
            == "%@ is downloaded. Loads automatically on first use."
    )
    #expect(
        AppText.localized(.modelDownloadedLoadsOnFirstUse, language: .russian)
            == "%@ скачана. Она автоматически загрузится при первом использовании."
    )
    #expect(
        AppText.localized(.audioInputNoDevice, language: .english)
            == "No audio input device is connected. Connect a microphone and refresh."
    )
    #expect(
        AppText.localized(.audioInputNoDevice, language: .russian)
            == "Устройство аудиоввода не подключено. Подключите микрофон и обновите статус."
    )
}

@Test
func appTextProvidesPrimaryInterfaceTranslationsForAllSupportedLocales() {
    let keys: [AppTextKey] = [
        .settingsGeneral,
        .settingsPolishing,
        .settingsHelp,
        .theme,
        .interfaceLanguage,
        .overlayHUD,
        .notes,
        .record,
        .stopRecording,
        .importAudio,
        .translate,
        .originalText,
        .translatedText,
        .copy,
        .polish,
        .raw,
        .variantOne,
        .variantTwo,
        .noNoteSelected,
        .createOrSelectNote
    ]
    let languages: [UILanguagePreference] = [
        .spanish, .german, .french, .italian, .portuguese,
        .chinese, .japanese, .korean, .arabic, .hindi
    ]

    for language in languages {
        for key in keys {
            let value = AppText.localized(key, language: language)
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(value != key.rawValue)
        }
    }

    #expect(AppText.localized(.settingsGeneral, language: .spanish) == "General")
    #expect(AppText.localized(.record, language: .german) == "Aufnehmen")
    #expect(AppText.localized(.translate, language: .french) == "Traduire")
    #expect(AppText.localized(.copy, language: .italian) == "Copia")
    #expect(AppText.localized(.settingsHelp, language: .portuguese) == "Ajuda")
    #expect(AppText.localized(.record, language: .chinese) == "录音")
    #expect(AppText.localized(.translate, language: .japanese) == "翻訳")
    #expect(AppText.localized(.notes, language: .korean) == "메모")
    #expect(AppText.localized(.copy, language: .arabic) == "نسخ")
    #expect(AppText.localized(.settingsGeneral, language: .hindi) == "सामान्य")
}
