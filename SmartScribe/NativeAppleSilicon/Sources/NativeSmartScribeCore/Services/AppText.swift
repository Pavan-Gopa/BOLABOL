import Foundation

public enum AppTextKey: String, CaseIterable, Sendable {
    case settingsGeneral
    case settingsAPIProviders
    case settingsHotkey
    case settingsLocalModels
    case settingsPolishing
    case settingsPrompts
    case settingsStatistics
    case settingsHelp
    case lastTransactionDetails
    case totalUsageFor
    case promptTokens
    case completionTokens
    case totalTokens
    case selectedModel
    case resetStats
    case noUsageData
    case accessibilityPermission
    case accessibilityTrusted
    case accessibilityNotTrusted
    case accessibilityPermissionDescription
    case requestAccessibilityPermission
    case openAccessibilitySettings
    case refreshPermissionStatus
    case helpWelcomeTitle
    case helpWelcomeBody
    case helpQuickStart
    case helpRecordStep
    case helpVariantsStep
    case helpCopyStep
    case helpRecordingTitle
    case helpHUDStep
    case helpOfflineTranscription
    case helpOfflineModelStep
    case helpOfflineActivateStep
    case helpImportTitle
    case helpImportStep
    case helpTranslateStep
    case helpPolishingProviders
    case helpPolishingProviderStep
    case helpPromptsStep
    case helpHotkeyStep
    case helpPermissionsTitle
    case helpMicrophoneStep
    case helpAccessibilityStep
    case helpPermissionRefreshStep
    case helpPrivacyTitle
    case helpPrivacyLocalStep
    case helpLogsStep
    case theme
    case themeDark
    case themeLight
    case themeSystem
    case appearance
    case uiFontSize
    case scale
    case interfaceLanguage
    case preference
    case overlayHUD
    case position
    case bottomRight
    case bottomLeft
    case bottomCenter
    case topRight
    case topLeft
    case size
    case transparency
    case playSound
    case soundVolume
    case testHUDSounds
    case logLevel
    case level
    case levelError
    case levelWarn
    case levelInfo
    case levelDebug
    case troubleshooting
    case exportSystemLogs
    case resetGeneral
    case logsExported
    case logsExportFailed
    case activeModelLabel
    case noLocalModelSelected
    case transcriptionLanguage
    case autoDetect
    case customCode
    case languageCode
    case resolvedLanguage
    case transcriptionLanguageHint
    case active
    case use
    case selected
    case download
    case retry
    case delete
    case reset
    case downloading
    case downloadInterrupted
    case accuracy
    case speed
    case quality
    case localAISection
    case polishingEngine
    case modelStatus
    case loadTime
    case localPolishingFilesHint
    case polishingModelsSection
    case customPromptsSection
    case prompt
    case promptMustIncludeTranscription
    case charactersCount
    case polishingDisabled
    case quickLocalCleanup
    case localMLXModel
    case polishingDisabledHint
    case quickLocalCleanupHint
    case localMLXModelHint
    case apiPolishingHint
    case globalHotkey
    case enableHotkey
    case shortcut
    case output
    case target
    case mode
    case clipboardMode
    case typeIntoActiveApp
    case textPolishingProviders
    case googleProviderSubtitle
    case openAIProviderSubtitle
    case anthropicProviderSubtitle
    case customProviderSubtitle
    case configured
    case providerName
    case apiKey
    case baseURL
    case textModelField
    case getAPIKey
    case useForPolishing
    case noTranslationProvider
    case untitledNote
    case monoChannel
    case channelsCount
    case noValue
    case chooseLocalPolishingModel
    case idleStatus
    case pendingStatus
    case runningStatus
    case doneStatus
    case failedStatus
    case notes
    case newNote
    case copyAll
    case clearAll
    case clearAllConfirmation
    case clear
    case deleteNote
    case cancel
    case transcriptionModel
    case polishingModel
    case appleSpeech
    case noDownloadedTranscriptionModels
    case settings
    case raw
    case variantOne
    case variantTwo
    case localEngine
    case noNoteSelected
    case createOrSelectNote
    case variant
    case record
    case stopRecording
    case importAudio
    case blankNote
    case translate
    case translateSelectionOrClipboard
    case translateAgain
    case originalText
    case translatedText
    case provider
    case targetLanguage
    case customLanguage
    case close
    case translating
    case translationPlaceholder
    case translationOriginalPlaceholder
    case noTextToTranslate
    case polish
    case copy
    case waitingToTranscribe
    case transcribingWith
    case transcribedWith
    case transcriptionFailed
    case waitingToPolish
    case polishingWith
    case polishedWith
    case polishingFailed
    case noTranscriptYet
    case transcribing
    case noPolishedTextYet
    case waitingToPolishShort
    case polishing
    case noPolishedTextReturned
    case voiceNote
    case blankNoteFallback
    case noTranscriptToPolish
    case emptyPolishingResult
    case unsupportedAudioFormat
    case microphoneAccessDisabled
    case audioInputNoDevice
    case audioInputReady
    case refreshAudioInput
    case audioInputChecking
    case audioSignalActive
    case audioListening
    case couldNotStartRecording
    case recordingStopped
    case missingAudioFileForTranscription
    case whisperReturnedEmptyTranscript
    case speechPermissionDisabled
    case appleSpeechUnavailableForLocale
    case appleSpeechOnDeviceUnavailableForLocale
    case appleSpeechReturnedEmptyTranscript
    case modelDownloadedLoadsOnFirstUse
    case downloadModelBeforePolishing
    case modelRunningInWorker
    case modelCompletedInWorker
    case downloadModelBeforeLoading
    case modelStatusUnavailable
    case polishingDisabledStatus
    case noPreparationRequired
    case chooseLocalPolishingModelShort
    case hotkeyDescription
    case hotkeyTargetLanguage
    case hotkeyPrimaryLabel
    case hotkeyPrimaryDesc
    case hotkeySecondaryLabel
    case hotkeySecondaryDesc
}

public enum AppText {
    public static func localized(
        _ key: AppTextKey,
        language: UILanguagePreference,
        systemLocale: Locale = .current
    ) -> String {
        let locale = language.resolvedLocaleIdentifier(for: systemLocale)
        return translations[locale]?[key] ?? translations["en"]?[key] ?? key.rawValue
    }

    private static let translations: [String: [AppTextKey: String]] = [
        "en": [
            .settingsGeneral: "General",
            .settingsAPIProviders: "API Providers",
            .settingsHotkey: "Hotkey",
            .settingsLocalModels: "Local Models",
            .settingsPolishing: "Polishing",
            .settingsPrompts: "Prompts",
            .settingsStatistics: "Statistics",
            .settingsHelp: "Help",
            .lastTransactionDetails: "Last Transaction Details",
            .totalUsageFor: "Total Usage for %@",
            .promptTokens: "Prompt Tokens",
            .completionTokens: "Completion Tokens",
            .totalTokens: "Total Tokens",
            .selectedModel: "Selected Model",
            .resetStats: "Reset Stats",
            .noUsageData: "No usage data yet.",
            .accessibilityPermission: "Accessibility Permission",
            .accessibilityTrusted: "Granted",
            .accessibilityNotTrusted: "Not granted",
            .accessibilityPermissionDescription: "Required only for Type into Active App. Clipboard mode does not need Accessibility permission.",
            .requestAccessibilityPermission: "Request Permission",
            .openAccessibilitySettings: "Open Accessibility Settings",
            .refreshPermissionStatus: "Refresh Status",
            .helpWelcomeTitle: "Welcome to SmartScribe",
            .helpWelcomeBody: "Effortless dictation and note polishing. Record, transcribe locally, and polish with cloud or local models.",
            .helpQuickStart: "Quick Start",
            .helpRecordStep: "Click Record to capture audio, or use the global hotkey to record into the active app.",
            .helpVariantsStep: "Raw shows the transcript, Variant 1 cleans it up, and Variant 2 rewrites it for maximum clarity.",
            .helpCopyStep: "Use Copy to copy the current text, or Copy All in the sidebar to export every note.",
            .helpRecordingTitle: "Recording & HUD",
            .helpHUDStep: "The Overlay HUD shows recording in red and polishing in green. Drag it once and it will reopen in the same place.",
            .helpOfflineTranscription: "Offline Transcription",
            .helpOfflineModelStep: "Open Settings -> Local Models to download Whisper models and choose a transcription language or Auto detect.",
            .helpOfflineActivateStep: "Click Use on a downloaded model to activate it. If no Whisper model is active, the app falls back to Apple Speech.",
            .helpImportTitle: "Import & Translation",
            .helpImportStep: "Use Import Audio or drag an audio file into the app to transcribe it as a new note.",
            .helpTranslateStep: "Translate can work from selected text, clipboard text, or a short live recording inside the translation window.",
            .helpPolishingProviders: "Polishing Providers",
            .helpPolishingProviderStep: "Choose Polishing Disabled, Quick Local Cleanup, a local MLX model, or an API provider depending on speed and quality needs.",
            .helpPromptsStep: "Variant prompts are in Settings -> Prompts. Variant 1 is light cleanup; Variant 2 is the stronger rewrite.",
            .helpHotkeyStep: "Enable the global hotkey in Settings -> Hotkey and choose Raw, Variant 1, or Variant 2 plus Clipboard or Type into Active App.",
            .helpPermissionsTitle: "Permissions",
            .helpMicrophoneStep: "Microphone access is required for recording inside the app or from the Overlay HUD.",
            .helpAccessibilityStep: "Accessibility access is required only for Type into Active App. Clipboard mode does not need it.",
            .helpPermissionRefreshStep: "If typing into another app stops working, reopen Hotkey settings and refresh the Accessibility status.",
            .helpPrivacyTitle: "Privacy & Troubleshooting",
            .helpPrivacyLocalStep: "Local transcription and local polishing run on-device.",
            .helpLogsStep: "Use Settings -> General -> Export System Logs when something fails and you need a diagnostic file for debugging.",
            .theme: "Theme",
            .themeDark: "Dark",
            .themeLight: "Light",
            .themeSystem: "System",
            .appearance: "Appearance",
            .uiFontSize: "UI Font Size",
            .scale: "Scale",
            .interfaceLanguage: "Interface Language",
            .preference: "Preference",
            .overlayHUD: "Overlay HUD",
            .position: "Position",
            .bottomRight: "Bottom-right",
            .bottomLeft: "Bottom-left",
            .bottomCenter: "Bottom-center",
            .topRight: "Top-right",
            .topLeft: "Top-left",
            .size: "Size",
            .transparency: "Transparency",
            .playSound: "Play sound on start/finish",
            .soundVolume: "Sound Volume",
            .testHUDSounds: "Test HUD Sounds",
            .logLevel: "Log Level",
            .level: "Level",
            .levelError: "Error",
            .levelWarn: "Warn",
            .levelInfo: "Info",
            .levelDebug: "Debug",
            .troubleshooting: "Troubleshooting",
            .exportSystemLogs: "Export System Logs",
            .resetGeneral: "Reset General",
            .logsExported: "Logs exported to file.",
            .logsExportFailed: "Could not export system logs.",
            .activeModelLabel: "Active Model",
            .noLocalModelSelected: "No local model selected",
            .transcriptionLanguage: "Transcription Language",
            .autoDetect: "Auto detect",
            .customCode: "Custom code...",
            .languageCode: "Language code",
            .resolvedLanguage: "Resolved language",
            .transcriptionLanguageHint: "Auto detect is best for mixed speech. Choosing a specific language enables auto-translation: speak in any language and get the result in the selected language.",
            .active: "Active",
            .use: "Use",
            .selected: "Selected",
            .download: "Download",
            .retry: "Retry",
            .delete: "Delete",
            .reset: "Reset",
            .downloading: "Downloading...",
            .downloadInterrupted: "Download interrupted",
            .accuracy: "Accuracy",
            .speed: "Speed",
            .quality: "Quality",
            .localAISection: "Local AI",
            .polishingEngine: "Polishing Engine",
            .modelStatus: "Model Status",
            .loadTime: "Load Time",
            .localPolishingFilesHint: "Use Delete on a model card to remove downloaded local model files from this Mac.",
            .polishingModelsSection: "Polishing Models",
            .customPromptsSection: "Custom Prompts",
            .prompt: "Prompt",
            .promptMustIncludeTranscription: "Prompt must include \(PromptTemplate.transcriptionPlaceholder)",
            .charactersCount: "%d characters",
            .polishingDisabled: "Polishing Disabled",
            .quickLocalCleanup: "Quick Local Cleanup",
            .localMLXModel: "Local MLX Model",
            .polishingDisabledHint: "The app will stop after transcription and keep only the raw text.",
            .quickLocalCleanupHint: "Fast offline cleanup. It fixes spacing, capitalization, punctuation, and simple paragraph structure without using an LLM.",
            .localMLXModelHint: "Runs a downloaded MLX model fully on this Mac for stronger rewriting without sending text to a cloud provider.",
            .apiPolishingHint: "Uses the configured external provider for polishing. This can be stronger, but it sends text to that API.",
            .globalHotkey: "Global Hotkey",
            .hotkeyDescription: "Hotkey + Shift records speech, then translates to the Auto Translation Language configured in Glossary. Hotkey alone keeps auto-detected transcription.",
            .hotkeyTargetLanguage: "Recognition Language",
            .hotkeyPrimaryLabel: "Primary Hotkey",
            .hotkeyPrimaryDesc: "Transcribes speech in auto-detected language.",
            .hotkeySecondaryLabel: "Secondary Hotkey (with Shift)",
            .hotkeySecondaryDesc: "Transcribes speech and translates to the Glossary Auto Translation Language.",
            .enableHotkey: "Enable hotkey",
            .shortcut: "Shortcut",
            .output: "Output",
            .target: "Target",
            .mode: "Mode",
            .clipboardMode: "Copy to Clipboard",
            .typeIntoActiveApp: "Type into Active App",
            .textPolishingProviders: "Text Polishing Providers",
            .googleProviderSubtitle: "Gemini API key and text model for cloud polishing.",
            .openAIProviderSubtitle: "OpenAI-compatible chat completions through api.openai.com.",
            .anthropicProviderSubtitle: "Claude Messages API for polishing.",
            .customProviderSubtitle: "Use providers such as OpenRouter or a private OpenAI-compatible endpoint.",
            .configured: "Configured",
            .providerName: "Provider name",
            .apiKey: "API key",
            .baseURL: "Base URL, e.g. https://openrouter.ai/api/v1",
            .textModelField: "Text model",
            .getAPIKey: "Get API Key",
            .useForPolishing: "Use for Polishing",
            .noTranslationProvider: "No translation provider is available.",
            .untitledNote: "Untitled Note",
            .monoChannel: "mono",
            .channelsCount: "%d channels",
            .noValue: "N/A",
            .chooseLocalPolishingModel: "Choose and download a local polishing model in Settings.",
            .idleStatus: "Idle",
            .pendingStatus: "Pending",
            .runningStatus: "Running",
            .doneStatus: "Done",
            .failedStatus: "Failed",
            .notes: "Notes",
            .newNote: "New Note",
            .copyAll: "Copy All",
            .clearAll: "Clear All",
            .clearAllConfirmation: "Delete all notes?",
            .clear: "Clear",
            .deleteNote: "Delete Note",
            .cancel: "Cancel",
            .transcriptionModel: "Transcription",
            .polishingModel: "Polishing",
            .appleSpeech: "Apple Speech",
            .noDownloadedTranscriptionModels: "No downloaded models",
            .settings: "Settings",
            .raw: "Raw",
            .variantOne: "Variant 1",
            .variantTwo: "Variant 2",
            .localEngine: "local engine",
            .noNoteSelected: "No Note Selected",
            .createOrSelectNote: "Create or select a note to begin.",
            .variant: "Variant",
            .record: "Record",
            .stopRecording: "Stop Recording",
            .importAudio: "Import Audio",
            .blankNote: "Blank",
            .translate: "Translate",
            .translateSelectionOrClipboard: "Translate selection or clipboard text",
            .translateAgain: "Translate Again",
            .originalText: "Original",
            .translatedText: "Translated",
            .provider: "Provider",
            .targetLanguage: "Target Language",
            .customLanguage: "Custom language",
            .close: "Close",
            .translating: "Translating...",
            .translationPlaceholder: "Translation will appear here.",
            .translationOriginalPlaceholder: "Paste or type text to translate.",
            .noTextToTranslate: "No text to translate. Copy text to clipboard or select text in a note and try again.",
            .polish: "Polish",
            .copy: "Copy",
            .waitingToTranscribe: "Waiting to transcribe",
            .transcribingWith: "Transcribing with %@",
            .transcribedWith: "Transcribed with %@",
            .transcriptionFailed: "Transcription failed",
            .waitingToPolish: "Waiting to polish %@",
            .polishingWith: "Polishing %@ with %@",
            .polishedWith: "Polished with %@",
            .polishingFailed: "Polishing failed",
            .noTranscriptYet: "No transcript yet.",
            .transcribing: "Transcribing...",
            .noPolishedTextYet: "No polished text yet.",
            .waitingToPolishShort: "Waiting to polish.",
            .polishing: "Polishing...",
            .noPolishedTextReturned: "No polished text was returned.",
            .voiceNote: "Voice Note",
            .blankNoteFallback: "Blank note",
            .noTranscriptToPolish: "No transcript is available to polish.",
            .emptyPolishingResult: "Polishing returned an empty result.",
            .unsupportedAudioFormat: "This audio format is not supported by the macOS system decoder.",
            .microphoneAccessDisabled: "Microphone access is disabled for SmartScribe.",
            .audioInputNoDevice: "No audio input device is connected. Connect a microphone and refresh.",
            .audioInputReady: "Audio input ready: %@",
            .refreshAudioInput: "Refresh audio input",
            .audioInputChecking: "Checking audio input...",
            .audioSignalActive: "Signal active",
            .audioListening: "Listening",
            .couldNotStartRecording: "Could not start recording: %@",
            .recordingStopped: "Recording stopped: %@",
            .missingAudioFileForTranscription: "No audio file was provided for transcription.",
            .whisperReturnedEmptyTranscript: "WhisperKit returned an empty transcript.",
            .speechPermissionDisabled: "Speech recognition permission is disabled for SmartScribe.",
            .appleSpeechUnavailableForLocale: "Apple Speech is unavailable for %@.",
            .appleSpeechOnDeviceUnavailableForLocale: "On-device Apple Speech recognition is unavailable for %@.",
            .appleSpeechReturnedEmptyTranscript: "Apple Speech returned an empty transcript.",
            .modelDownloadedLoadsOnFirstUse: "%@ is downloaded. Loads automatically on first use.",
            .downloadModelBeforePolishing: "Download %@ before polishing.",
            .modelRunningInWorker: "Running %@ in isolated MLX worker.",
            .modelCompletedInWorker: "%@ completed in isolated MLX worker.",
            .downloadModelBeforeLoading: "Download %@ before loading it.",
            .modelStatusUnavailable: "Model status is not available.",
            .polishingDisabledStatus: "Polishing is disabled.",
            .noPreparationRequired: "No preparation required.",
            .chooseLocalPolishingModelShort: "Choose and download a local polishing model."
        ],
        "ru": [
            .settingsGeneral: "Общие",
            .settingsAPIProviders: "API-провайдеры",
            .settingsHotkey: "Горячая клавиша",
            .settingsLocalModels: "Локальные модели",
            .settingsPolishing: "Доводка",
            .settingsPrompts: "Промпты",
            .settingsStatistics: "Статистика",
            .settingsHelp: "Помощь",
            .lastTransactionDetails: "Последняя операция",
            .totalUsageFor: "Всего использовано для %@",
            .promptTokens: "Токены промпта",
            .completionTokens: "Токены ответа",
            .totalTokens: "Всего токенов",
            .selectedModel: "Выбранная модель",
            .resetStats: "Сбросить статистику",
            .noUsageData: "Статистики пока нет.",
            .accessibilityPermission: "Разрешение Accessibility",
            .accessibilityTrusted: "Выдано",
            .accessibilityNotTrusted: "Не выдано",
            .accessibilityPermissionDescription: "Нужно только для режима печати в активное приложение. Режим буфера обмена не требует Accessibility.",
            .requestAccessibilityPermission: "Запросить разрешение",
            .openAccessibilitySettings: "Открыть настройки Accessibility",
            .refreshPermissionStatus: "Обновить статус",
            .helpWelcomeTitle: "Добро пожаловать в SmartScribe",
            .helpWelcomeBody: "Быстрая диктовка и доводка заметок. Записывайте, транскрибируйте локально и улучшайте текст через облачные или локальные модели.",
            .helpQuickStart: "Быстрый старт",
            .helpRecordStep: "Нажмите Запись, чтобы захватить аудио, или используйте глобальную горячую клавишу для записи сразу в активное приложение.",
            .helpVariantsStep: "Черновик показывает транскрипцию, Вариант 1 делает легкую доводку, а Вариант 2 переписывает текст ради максимальной ясности.",
            .helpCopyStep: "Нажмите Копировать, чтобы скопировать текущий текст, или Копировать все в сайдбаре, чтобы выгрузить все заметки разом.",
            .helpRecordingTitle: "Запись и HUD",
            .helpHUDStep: "Оверлей HUD показывает запись красным, а доводку зеленым. Перетащите его один раз, и дальше он будет открываться в том же месте.",
            .helpOfflineTranscription: "Локальная транскрибация",
            .helpOfflineModelStep: "Откройте Настройки -> Локальные модели, чтобы скачать Whisper-модели и выбрать язык транскрибации или Auto detect.",
            .helpOfflineActivateStep: "Нажмите Использовать у загруженной модели, чтобы активировать ее. Если Whisper-модель не выбрана, приложение использует Apple Speech.",
            .helpImportTitle: "Импорт и перевод",
            .helpImportStep: "Используйте Импорт аудио или просто перетащите аудиофайл в приложение, чтобы создать новую транскрибацию.",
            .helpTranslateStep: "Перевод работает с выделенным текстом, текстом из буфера обмена или короткой записью прямо в окне перевода.",
            .helpPolishingProviders: "Провайдеры доводки",
            .helpPolishingProviderStep: "Выберите Polishing Disabled, Quick Local Cleanup, локальную MLX-модель или API-провайдера в зависимости от нужной скорости и качества.",
            .helpPromptsStep: "Промпты вариантов находятся в Настройки -> Промпты. Вариант 1 — легкая чистка, Вариант 2 — более сильная переработка текста.",
            .helpHotkeyStep: "Включите горячую клавишу в Настройки -> Горячая клавиша и выберите Черновик, Вариант 1 или Вариант 2, а также Clipboard или Type into Active App.",
            .helpPermissionsTitle: "Разрешения",
            .helpMicrophoneStep: "Доступ к микрофону нужен для записи внутри приложения и через Overlay HUD.",
            .helpAccessibilityStep: "Accessibility требуется только для режима Type into Active App. Режим буфера обмена его не требует.",
            .helpPermissionRefreshStep: "Если печать в другое приложение перестала работать, откройте настройки горячей клавиши и обновите статус Accessibility.",
            .helpPrivacyTitle: "Приватность и диагностика",
            .helpPrivacyLocalStep: "Локальная транскрибация и локальная доводка выполняются на устройстве.",
            .helpLogsStep: "Используйте Настройки -> Общие -> Экспортировать системные логи, если что-то сломалось и нужен диагностический файл для отладки.",
            .theme: "Тема",
            .themeDark: "Темная",
            .themeLight: "Светлая",
            .themeSystem: "Системная",
            .appearance: "Оформление",
            .uiFontSize: "Размер шрифта интерфейса",
            .scale: "Масштаб",
            .interfaceLanguage: "Язык интерфейса",
            .preference: "Предпочтение",
            .overlayHUD: "Оверлей",
            .position: "Позиция",
            .bottomRight: "Снизу справа",
            .bottomLeft: "Снизу слева",
            .bottomCenter: "Снизу по центру",
            .topRight: "Сверху справа",
            .topLeft: "Сверху слева",
            .size: "Размер",
            .transparency: "Прозрачность",
            .playSound: "Звук при старте/завершении",
            .soundVolume: "Громкость",
            .testHUDSounds: "Проверить звуки HUD",
            .logLevel: "Уровень логирования",
            .level: "Уровень",
            .levelError: "Ошибки",
            .levelWarn: "Предупреждения",
            .levelInfo: "Информация",
            .levelDebug: "Отладка",
            .troubleshooting: "Диагностика",
            .exportSystemLogs: "Экспортировать системные логи",
            .resetGeneral: "Сбросить общие",
            .logsExported: "Логи экспортированы в файл.",
            .logsExportFailed: "Не удалось экспортировать системные логи.",
            .activeModelLabel: "Активная модель",
            .noLocalModelSelected: "Локальная модель не выбрана",
            .transcriptionLanguage: "Язык транскрибации",
            .autoDetect: "Определять автоматически",
            .customCode: "Свой код...",
            .languageCode: "Код языка",
            .resolvedLanguage: "Итоговый язык",
            .transcriptionLanguageHint: "Auto detect лучше подходит для смешанной речи. Выбор конкретного языка включает автоперевод: говорите на любом языке, а результат будет на выбранном.",
            .active: "Активна",
            .use: "Использовать",
            .selected: "Выбрана",
            .download: "Скачать",
            .retry: "Повторить",
            .delete: "Удалить",
            .reset: "Сбросить",
            .downloading: "Загрузка...",
            .downloadInterrupted: "Загрузка прервана",
            .accuracy: "Точность",
            .speed: "Скорость",
            .quality: "Качество",
            .localAISection: "Локальный AI",
            .polishingEngine: "Движок доводки",
            .modelStatus: "Статус модели",
            .loadTime: "Время загрузки",
            .localPolishingFilesHint: "Используйте кнопку Удалить у карточки модели, чтобы убрать скачанные локальные файлы с этого Mac.",
            .polishingModelsSection: "Модели доводки",
            .customPromptsSection: "Пользовательские промпты",
            .prompt: "Промпт",
            .promptMustIncludeTranscription: "Промпт должен содержать \(PromptTemplate.transcriptionPlaceholder)",
            .charactersCount: "%d символов",
            .polishingDisabled: "Доводка отключена",
            .quickLocalCleanup: "Быстрая локальная чистка",
            .localMLXModel: "Локальная MLX-модель",
            .polishingDisabledHint: "После транскрибации приложение остановится и оставит только исходный текст.",
            .quickLocalCleanupHint: "Быстрая офлайн-чистка. Исправляет пробелы, заглавные буквы, пунктуацию и простую разбивку на абзацы без использования LLM.",
            .localMLXModelHint: "Запускает скачанную MLX-модель полностью на этом Mac для более сильной доводки без отправки текста в облако.",
            .apiPolishingHint: "Использует настроенного внешнего провайдера для доводки. Обычно это мощнее, но текст уходит в соответствующий API.",
            .globalHotkey: "Глобальная горячая клавиша",
            .hotkeyDescription: "Комбинация с Shift записывает речь, затем переводит на язык Auto Translation из вкладки Glossary. Обычное нажатие оставляет транскрибацию с автоопределением.",
            .hotkeyTargetLanguage: "Язык распознавания",
            .hotkeyPrimaryLabel: "Основное сочетание",
            .hotkeyPrimaryDesc: "Транскрибирует речь на исходном языке (автоопределение).",
            .hotkeySecondaryLabel: "Сочетание с Shift",
            .hotkeySecondaryDesc: "Транскрибирует речь и переводит её на язык Auto Translation из глоссария.",
            .enableHotkey: "Включить горячую клавишу",
            .shortcut: "Сочетание клавиш",
            .output: "Вывод",
            .target: "Цель",
            .mode: "Режим",
            .clipboardMode: "Копировать в буфер обмена",
            .typeIntoActiveApp: "Печатать в активное приложение",
            .textPolishingProviders: "Провайдеры текстовой доводки",
            .googleProviderSubtitle: "Gemini API key и текстовая модель для облачной доводки.",
            .openAIProviderSubtitle: "OpenAI-совместимые chat completions через api.openai.com.",
            .anthropicProviderSubtitle: "Claude Messages API для доводки текста.",
            .customProviderSubtitle: "Используйте провайдеры вроде OpenRouter или собственный OpenAI-совместимый endpoint.",
            .configured: "Настроено",
            .providerName: "Имя провайдера",
            .apiKey: "API key",
            .baseURL: "Base URL, например https://openrouter.ai/api/v1",
            .textModelField: "Текстовая модель",
            .getAPIKey: "Получить API key",
            .useForPolishing: "Использовать для доводки",
            .noTranslationProvider: "Нет доступного провайдера перевода.",
            .untitledNote: "Без названия",
            .monoChannel: "моно",
            .channelsCount: "%d канала(ов)",
            .noValue: "Н/Д",
            .chooseLocalPolishingModel: "Выберите и скачайте локальную модель доводки в настройках.",
            .idleStatus: "Ожидание",
            .pendingStatus: "В очереди",
            .runningStatus: "В работе",
            .doneStatus: "Готово",
            .failedStatus: "Ошибка",
            .notes: "Заметки",
            .newNote: "Новая заметка",
            .copyAll: "Копировать все",
            .clearAll: "Очистить все",
            .clearAllConfirmation: "Удалить все заметки?",
            .clear: "Очистить",
            .deleteNote: "Удалить заметку",
            .cancel: "Отмена",
            .transcriptionModel: "Транскрибация",
            .polishingModel: "Доводка",
            .appleSpeech: "Apple Speech",
            .noDownloadedTranscriptionModels: "Нет загруженных моделей",
            .settings: "Настройки",
            .raw: "Черновик",
            .variantOne: "Вариант 1",
            .variantTwo: "Вариант 2",
            .localEngine: "локальный движок",
            .noNoteSelected: "Заметка не выбрана",
            .createOrSelectNote: "Создайте или выберите заметку, чтобы начать.",
            .variant: "Вариант",
            .record: "Запись",
            .stopRecording: "Остановить запись",
            .importAudio: "Импорт аудио",
            .blankNote: "Бланк",
            .translate: "Перевести",
            .translateSelectionOrClipboard: "Перевести выделение или текст из буфера",
            .translateAgain: "Перевести снова",
            .originalText: "Оригинал",
            .translatedText: "Перевод",
            .provider: "Провайдер",
            .targetLanguage: "Целевой язык",
            .customLanguage: "Свой язык",
            .close: "Закрыть",
            .translating: "Перевод...",
            .translationPlaceholder: "Перевод появится здесь.",
            .translationOriginalPlaceholder: "Вставьте или введите текст для перевода.",
            .noTextToTranslate: "Нет текста для перевода. Скопируйте текст в буфер или выделите текст в заметке и попробуйте снова.",
            .polish: "Довести",
            .copy: "Копировать",
            .waitingToTranscribe: "Ожидание транскрибации",
            .transcribingWith: "Транскрибация через %@",
            .transcribedWith: "Транскрибировано через %@",
            .transcriptionFailed: "Транскрибация не удалась",
            .waitingToPolish: "Ожидание доводки %@",
            .polishingWith: "Доводка %@ через %@",
            .polishedWith: "Доведено через %@",
            .polishingFailed: "Доводка не удалась",
            .noTranscriptYet: "Транскрипции пока нет.",
            .transcribing: "Транскрибация...",
            .noPolishedTextYet: "Доведенного текста пока нет.",
            .waitingToPolishShort: "Ожидание доводки.",
            .polishing: "Доводка...",
            .noPolishedTextReturned: "Модель не вернула доведенный текст.",
            .voiceNote: "Голосовая заметка",
            .blankNoteFallback: "Пустая заметка",
            .noTranscriptToPolish: "Нет транскрипции для доводки.",
            .emptyPolishingResult: "Доводка вернула пустой результат.",
            .unsupportedAudioFormat: "Этот аудиоформат не поддерживается системным декодером macOS.",
            .microphoneAccessDisabled: "Для SmartScribe отключён доступ к микрофону.",
            .audioInputNoDevice: "Устройство аудиоввода не подключено. Подключите микрофон и обновите статус.",
            .audioInputReady: "Аудиоввод готов: %@",
            .refreshAudioInput: "Обновить аудиоввод",
            .audioInputChecking: "Проверка аудиоввода...",
            .audioSignalActive: "Сигнал есть",
            .audioListening: "Слушаю",
            .couldNotStartRecording: "Не удалось начать запись: %@",
            .recordingStopped: "Запись остановлена: %@",
            .missingAudioFileForTranscription: "Аудиофайл для транскрибации не был передан.",
            .whisperReturnedEmptyTranscript: "WhisperKit вернул пустую транскрипцию.",
            .speechPermissionDisabled: "Для SmartScribe отключено разрешение на распознавание речи.",
            .appleSpeechUnavailableForLocale: "Apple Speech недоступен для %@.",
            .appleSpeechOnDeviceUnavailableForLocale: "Локальное распознавание Apple Speech недоступно для %@.",
            .appleSpeechReturnedEmptyTranscript: "Apple Speech вернул пустую транскрипцию.",
            .modelDownloadedLoadsOnFirstUse: "%@ скачана. Она автоматически загрузится при первом использовании.",
            .downloadModelBeforePolishing: "Сначала скачайте %@, а потом запускайте доводку.",
            .modelRunningInWorker: "%@ выполняется в отдельном MLX worker.",
            .modelCompletedInWorker: "%@ завершила работу в отдельном MLX worker.",
            .downloadModelBeforeLoading: "Сначала скачайте %@, а потом загружайте её.",
            .modelStatusUnavailable: "Статус модели недоступен.",
            .polishingDisabledStatus: "Доводка отключена.",
            .noPreparationRequired: "Подготовка не требуется.",
            .chooseLocalPolishingModelShort: "Выберите и скачайте локальную модель доводки."
        ],
        "es": [
            .settingsGeneral: "General",
            .settingsAPIProviders: "Proveedores API",
            .settingsHotkey: "Atajo",
            .settingsLocalModels: "Modelos locales",
            .settingsPolishing: "Pulido",
            .settingsStatistics: "Estadísticas",
            .settingsHelp: "Ayuda",
            .theme: "Tema",
            .themeDark: "Oscuro",
            .themeLight: "Claro",
            .themeSystem: "Sistema",
            .interfaceLanguage: "Idioma de la interfaz",
            .overlayHUD: "HUD superpuesto",
            .notes: "Notas",
            .copyAll: "Copiar todo",
            .clearAll: "Borrar todo",
            .clear: "Limpiar",
            .cancel: "Cancelar",
            .settings: "Ajustes",
            .raw: "Raw",
            .variantOne: "Variante 1",
            .variantTwo: "Variante 2",
            .record: "Grabar",
            .stopRecording: "Detener grabación",
            .importAudio: "Importar audio",
            .blankNote: "En blanco",
            .translate: "Traducir",
            .translateAgain: "Traducir de nuevo",
            .originalText: "Texto original",
            .translatedText: "Texto traducido",
            .provider: "Proveedor",
            .targetLanguage: "Idioma de destino",
            .close: "Cerrar",
            .translating: "Traduciendo...",
            .polish: "Pulir",
            .copy: "Copiar",
            .noNoteSelected: "No hay ninguna nota seleccionada",
            .createOrSelectNote: "Crea o selecciona una nota para empezar.",
            .helpWelcomeTitle: "Bienvenido a SmartScribe",
            .helpQuickStart: "Inicio rápido"
        ],
        "de": [
            .settingsGeneral: "Allgemein",
            .settingsAPIProviders: "API-Anbieter",
            .settingsHotkey: "Hotkey",
            .settingsLocalModels: "Lokale Modelle",
            .settingsPolishing: "Nachbearbeitung",
            .settingsStatistics: "Statistik",
            .settingsHelp: "Hilfe",
            .theme: "Thema",
            .themeDark: "Dunkel",
            .themeLight: "Hell",
            .themeSystem: "System",
            .interfaceLanguage: "Sprache der Oberfläche",
            .overlayHUD: "Overlay-HUD",
            .notes: "Notizen",
            .copyAll: "Alles kopieren",
            .clearAll: "Alles löschen",
            .clear: "Leeren",
            .cancel: "Abbrechen",
            .settings: "Einstellungen",
            .raw: "Rohtext",
            .variantOne: "Variante 1",
            .variantTwo: "Variante 2",
            .record: "Aufnehmen",
            .stopRecording: "Aufnahme stoppen",
            .importAudio: "Audio importieren",
            .blankNote: "Leer",
            .translate: "Übersetzen",
            .translateAgain: "Erneut übersetzen",
            .originalText: "Originaltext",
            .translatedText: "Übersetzter Text",
            .provider: "Anbieter",
            .targetLanguage: "Zielsprache",
            .close: "Schließen",
            .translating: "Übersetzen...",
            .polish: "Überarbeiten",
            .copy: "Kopieren",
            .noNoteSelected: "Keine Notiz ausgewählt",
            .createOrSelectNote: "Erstelle oder wähle eine Notiz, um zu beginnen.",
            .helpWelcomeTitle: "Willkommen bei SmartScribe",
            .helpQuickStart: "Schnellstart"
        ],
        "fr": [
            .settingsGeneral: "Général",
            .settingsAPIProviders: "Fournisseurs API",
            .settingsHotkey: "Raccourci",
            .settingsLocalModels: "Modèles locaux",
            .settingsPolishing: "Retouche",
            .settingsStatistics: "Statistiques",
            .settingsHelp: "Aide",
            .theme: "Thème",
            .themeDark: "Sombre",
            .themeLight: "Clair",
            .themeSystem: "Système",
            .interfaceLanguage: "Langue de l’interface",
            .overlayHUD: "HUD superposé",
            .notes: "Notes",
            .copyAll: "Tout copier",
            .clearAll: "Tout effacer",
            .clear: "Effacer",
            .cancel: "Annuler",
            .settings: "Réglages",
            .raw: "Brut",
            .variantOne: "Variante 1",
            .variantTwo: "Variante 2",
            .record: "Enregistrer",
            .stopRecording: "Arrêter l’enregistrement",
            .importAudio: "Importer l’audio",
            .blankNote: "Vierge",
            .translate: "Traduire",
            .translateAgain: "Traduire à nouveau",
            .originalText: "Texte original",
            .translatedText: "Texte traduit",
            .provider: "Fournisseur",
            .targetLanguage: "Langue cible",
            .close: "Fermer",
            .translating: "Traduction...",
            .polish: "Retoucher",
            .copy: "Copier",
            .noNoteSelected: "Aucune note sélectionnée",
            .createOrSelectNote: "Créez ou sélectionnez une note pour commencer.",
            .helpWelcomeTitle: "Bienvenue dans SmartScribe",
            .helpQuickStart: "Démarrage rapide"
        ],
        "it": [
            .settingsGeneral: "Generale",
            .settingsAPIProviders: "Provider API",
            .settingsHotkey: "Hotkey",
            .settingsLocalModels: "Modelli locali",
            .settingsPolishing: "Rifinitura",
            .settingsStatistics: "Statistiche",
            .settingsHelp: "Aiuto",
            .theme: "Tema",
            .themeDark: "Scuro",
            .themeLight: "Chiaro",
            .themeSystem: "Sistema",
            .interfaceLanguage: "Lingua dell’interfaccia",
            .overlayHUD: "HUD sovrapposto",
            .notes: "Note",
            .copyAll: "Copia tutto",
            .clearAll: "Cancella tutto",
            .clear: "Cancella",
            .cancel: "Annulla",
            .settings: "Impostazioni",
            .raw: "Grezzo",
            .variantOne: "Variante 1",
            .variantTwo: "Variante 2",
            .record: "Registra",
            .stopRecording: "Interrompi registrazione",
            .importAudio: "Importa audio",
            .blankNote: "Vuoto",
            .translate: "Traduci",
            .translateAgain: "Traduci di nuovo",
            .originalText: "Testo originale",
            .translatedText: "Testo tradotto",
            .provider: "Provider",
            .targetLanguage: "Lingua di destinazione",
            .close: "Chiudi",
            .translating: "Traduzione...",
            .polish: "Rifinisci",
            .copy: "Copia",
            .noNoteSelected: "Nessuna nota selezionata",
            .createOrSelectNote: "Crea o seleziona una nota per iniziare.",
            .helpWelcomeTitle: "Benvenuto in SmartScribe",
            .helpQuickStart: "Avvio rapido"
        ],
        "pt": [
            .settingsGeneral: "Geral",
            .settingsAPIProviders: "Provedores API",
            .settingsHotkey: "Atalho",
            .settingsLocalModels: "Modelos locais",
            .settingsPolishing: "Refinamento",
            .settingsStatistics: "Estatísticas",
            .settingsHelp: "Ajuda",
            .theme: "Tema",
            .themeDark: "Escuro",
            .themeLight: "Claro",
            .themeSystem: "Sistema",
            .interfaceLanguage: "Idioma da interface",
            .overlayHUD: "HUD sobreposto",
            .notes: "Notas",
            .copyAll: "Copiar tudo",
            .clearAll: "Limpar tudo",
            .clear: "Limpar",
            .cancel: "Cancelar",
            .settings: "Configurações",
            .raw: "Bruto",
            .variantOne: "Variante 1",
            .variantTwo: "Variante 2",
            .record: "Gravar",
            .stopRecording: "Parar gravação",
            .importAudio: "Importar áudio",
            .blankNote: "Em branco",
            .translate: "Traduzir",
            .translateAgain: "Traduzir novamente",
            .originalText: "Texto original",
            .translatedText: "Texto traduzido",
            .provider: "Provedor",
            .targetLanguage: "Idioma de destino",
            .close: "Fechar",
            .translating: "Traduzindo...",
            .polish: "Refinar",
            .copy: "Copiar",
            .noNoteSelected: "Nenhuma nota selecionada",
            .createOrSelectNote: "Crie ou selecione uma nota para começar.",
            .helpWelcomeTitle: "Bem-vindo ao SmartScribe",
            .helpQuickStart: "Início rápido"
        ],
        "zh": [
            .settingsGeneral: "常规",
            .settingsAPIProviders: "API 提供商",
            .settingsHotkey: "快捷键",
            .settingsLocalModels: "本地模型",
            .settingsPolishing: "润色",
            .settingsStatistics: "统计",
            .settingsHelp: "帮助",
            .theme: "主题",
            .themeDark: "深色",
            .themeLight: "浅色",
            .themeSystem: "系统",
            .interfaceLanguage: "界面语言",
            .overlayHUD: "叠加 HUD",
            .notes: "笔记",
            .copyAll: "全部复制",
            .clearAll: "全部清除",
            .clear: "清除",
            .cancel: "取消",
            .settings: "设置",
            .raw: "原始",
            .variantOne: "变体 1",
            .variantTwo: "变体 2",
            .record: "录音",
            .stopRecording: "停止录音",
            .importAudio: "导入音频",
            .blankNote: "空白",
            .translate: "翻译",
            .translateAgain: "再次翻译",
            .originalText: "原文",
            .translatedText: "译文",
            .provider: "提供商",
            .targetLanguage: "目标语言",
            .close: "关闭",
            .translating: "翻译中...",
            .polish: "润色",
            .copy: "复制",
            .noNoteSelected: "未选择笔记",
            .createOrSelectNote: "创建或选择一条笔记以开始。",
            .helpWelcomeTitle: "欢迎使用 SmartScribe",
            .helpQuickStart: "快速开始"
        ],
        "ja": [
            .settingsGeneral: "一般",
            .settingsAPIProviders: "API プロバイダ",
            .settingsHotkey: "ホットキー",
            .settingsLocalModels: "ローカルモデル",
            .settingsPolishing: "仕上げ",
            .settingsStatistics: "統計",
            .settingsHelp: "ヘルプ",
            .theme: "テーマ",
            .themeDark: "ダーク",
            .themeLight: "ライト",
            .themeSystem: "システム",
            .interfaceLanguage: "インターフェイス言語",
            .overlayHUD: "オーバーレイ HUD",
            .notes: "ノート",
            .copyAll: "すべてコピー",
            .clearAll: "すべて消去",
            .clear: "クリア",
            .cancel: "キャンセル",
            .settings: "設定",
            .raw: "Raw",
            .variantOne: "バリアント 1",
            .variantTwo: "バリアント 2",
            .record: "録音",
            .stopRecording: "録音を停止",
            .importAudio: "音声を読み込む",
            .blankNote: "空白",
            .translate: "翻訳",
            .translateAgain: "もう一度翻訳",
            .originalText: "元のテキスト",
            .translatedText: "翻訳後のテキスト",
            .provider: "プロバイダ",
            .targetLanguage: "対象言語",
            .close: "閉じる",
            .translating: "翻訳中...",
            .polish: "仕上げる",
            .copy: "コピー",
            .noNoteSelected: "ノートが選択されていません",
            .createOrSelectNote: "開始するにはノートを作成するか選択してください。",
            .helpWelcomeTitle: "SmartScribe へようこそ",
            .helpQuickStart: "クイックスタート"
        ],
        "ko": [
            .settingsGeneral: "일반",
            .settingsAPIProviders: "API 제공업체",
            .settingsHotkey: "단축키",
            .settingsLocalModels: "로컬 모델",
            .settingsPolishing: "다듬기",
            .settingsStatistics: "통계",
            .settingsHelp: "도움말",
            .theme: "테마",
            .themeDark: "다크",
            .themeLight: "라이트",
            .themeSystem: "시스템",
            .interfaceLanguage: "인터페이스 언어",
            .overlayHUD: "오버레이 HUD",
            .notes: "메모",
            .copyAll: "모두 복사",
            .clearAll: "모두 지우기",
            .clear: "지우기",
            .cancel: "취소",
            .settings: "설정",
            .raw: "Raw",
            .variantOne: "변형 1",
            .variantTwo: "변형 2",
            .record: "녹음",
            .stopRecording: "녹음 중지",
            .importAudio: "오디오 가져오기",
            .blankNote: "빈 메모",
            .translate: "번역",
            .translateAgain: "다시 번역",
            .originalText: "원문",
            .translatedText: "번역문",
            .provider: "제공업체",
            .targetLanguage: "대상 언어",
            .close: "닫기",
            .translating: "번역 중...",
            .polish: "다듬기",
            .copy: "복사",
            .noNoteSelected: "선택된 메모가 없습니다",
            .createOrSelectNote: "시작하려면 메모를 만들거나 선택하세요.",
            .helpWelcomeTitle: "SmartScribe에 오신 것을 환영합니다",
            .helpQuickStart: "빠른 시작"
        ],
        "ar": [
            .settingsGeneral: "عام",
            .settingsAPIProviders: "مزودو API",
            .settingsHotkey: "اختصار",
            .settingsLocalModels: "النماذج المحلية",
            .settingsPolishing: "تنقيح",
            .settingsStatistics: "الإحصاءات",
            .settingsHelp: "المساعدة",
            .theme: "السمة",
            .themeDark: "داكن",
            .themeLight: "فاتح",
            .themeSystem: "النظام",
            .interfaceLanguage: "لغة الواجهة",
            .overlayHUD: "HUD عائم",
            .notes: "الملاحظات",
            .copyAll: "نسخ الكل",
            .clearAll: "مسح الكل",
            .clear: "مسح",
            .cancel: "إلغاء",
            .settings: "الإعدادات",
            .raw: "خام",
            .variantOne: "الإصدار 1",
            .variantTwo: "الإصدار 2",
            .record: "تسجيل",
            .stopRecording: "إيقاف التسجيل",
            .importAudio: "استيراد الصوت",
            .blankNote: "فارغ",
            .translate: "ترجمة",
            .translateAgain: "ترجمة مرة أخرى",
            .originalText: "النص الأصلي",
            .translatedText: "النص المترجم",
            .provider: "المزوّد",
            .targetLanguage: "اللغة الهدف",
            .close: "إغلاق",
            .translating: "جارٍ الترجمة...",
            .polish: "تنقيح",
            .copy: "نسخ",
            .noNoteSelected: "لا توجد ملاحظة محددة",
            .createOrSelectNote: "أنشئ ملاحظة أو اختر واحدة للبدء.",
            .helpWelcomeTitle: "مرحبًا بك في SmartScribe",
            .helpQuickStart: "بدء سريع"
        ],
        "hi": [
            .settingsGeneral: "सामान्य",
            .settingsAPIProviders: "API प्रदाता",
            .settingsHotkey: "हॉटकी",
            .settingsLocalModels: "स्थानीय मॉडल",
            .settingsPolishing: "संवारना",
            .settingsStatistics: "आंकड़े",
            .settingsHelp: "सहायता",
            .theme: "थीम",
            .themeDark: "डार्क",
            .themeLight: "लाइट",
            .themeSystem: "सिस्टम",
            .interfaceLanguage: "इंटरफ़ेस भाषा",
            .overlayHUD: "ओवरले HUD",
            .notes: "नोट्स",
            .copyAll: "सब कॉपी करें",
            .clearAll: "सब साफ़ करें",
            .clear: "साफ़ करें",
            .cancel: "रद्द करें",
            .settings: "सेटिंग्स",
            .raw: "रॉ",
            .variantOne: "वेरिएंट 1",
            .variantTwo: "वेरिएंट 2",
            .record: "रिकॉर्ड",
            .stopRecording: "रिकॉर्डिंग रोकें",
            .importAudio: "ऑडियो आयात करें",
            .blankNote: "खाली",
            .translate: "अनुवाद करें",
            .translateAgain: "फिर से अनुवाद करें",
            .originalText: "मूल पाठ",
            .translatedText: "अनूदित पाठ",
            .provider: "प्रदाता",
            .targetLanguage: "लक्ष्य भाषा",
            .close: "बंद करें",
            .translating: "अनुवाद हो रहा है...",
            .polish: "संवारें",
            .copy: "कॉपी",
            .noNoteSelected: "कोई नोट चयनित नहीं है",
            .createOrSelectNote: "शुरू करने के लिए एक नोट बनाएँ या चुनें।",
            .helpWelcomeTitle: "SmartScribe में आपका स्वागत है",
            .helpQuickStart: "त्वरित शुरुआत"
        ]
    ]
}
