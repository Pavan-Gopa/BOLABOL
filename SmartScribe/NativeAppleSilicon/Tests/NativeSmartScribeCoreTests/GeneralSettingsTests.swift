import Foundation
import NativeSmartScribeCore
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
    #expect(settings.logLevel == .warn)
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
func helpTextExplainsCoreWorkflowsMoreExplicitly() {
    #expect(
        AppText.localized(.helpRecordStep, language: .english)
            == "Click Record to capture audio, or use the global hotkey to record into the active app."
    )
    #expect(
        AppText.localized(.helpVariantsStep, language: .english)
            == "Raw shows the transcript, Variant 1 cleans it up, and Variant 2 rewrites it for maximum clarity."
    )
    #expect(
        AppText.localized(.helpOfflineModelStep, language: .english)
            == "Open Settings -> Local Models to download Whisper models and choose a transcription language or Auto detect."
    )
    #expect(
        AppText.localized(.helpPolishingProviderStep, language: .english)
            == "Choose Polishing Disabled, Quick Local Cleanup, a local MLX model, or an API provider depending on speed and quality needs."
    )
    #expect(
        AppText.localized(.helpLogsStep, language: .english)
            == "Use Settings -> General -> Export System Logs when something fails and you need a diagnostic file for debugging."
    )
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
