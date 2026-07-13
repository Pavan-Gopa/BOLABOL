import Foundation

public enum VaniScriptHelpLanguage: String, Sendable {
    case english = "en"
    case russian = "ru"

    public init(rawValueOrDefault value: String?) {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        self = normalized.hasPrefix("ru") ? .russian : .english
    }
}

public struct VaniScriptLocalizedHelpTopic: Equatable, Sendable {
    public let id: String
    public let category: String
    public let screen: String?
    public let title: String
    public let summary: String
    public let requirements: [String]
    public let steps: [String]
    public let troubleshooting: [String]
    public let relatedTopicIDs: [String]
}

public struct VaniScriptContextualHelp: Equatable, Sendable {
    public let screen: String
    public let title: String
    public let summary: String
    public let nextActions: [String]
    public let recommendedTopicIDs: [String]
}

public struct VaniScriptOnboardingChecklist: Equatable, Sendable {
    public let title: String
    public let summary: String
    public let steps: [String]
    public let topicIDs: [String]
}

public enum VaniScriptHelpCatalog {
    public static let topics: [VaniScriptLocalizedHelpTopic] = helpTopics.map { topic in
        topic.localized(.english)
    }

    public static func list(
        category: String? = nil,
        language: VaniScriptHelpLanguage = .english
    ) -> [VaniScriptLocalizedHelpTopic] {
        let normalizedCategory = category?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return helpTopics
            .filter { topic in
                guard let normalizedCategory, !normalizedCategory.isEmpty else { return true }
                return topic.category.lowercased() == normalizedCategory
            }
            .map { $0.localized(language) }
    }

    public static func topic(
        id: String,
        language: VaniScriptHelpLanguage = .english
    ) -> VaniScriptLocalizedHelpTopic? {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return helpTopics.first { $0.id.lowercased() == normalizedID }?.localized(language)
    }

    public static func search(
        query: String,
        language: VaniScriptHelpLanguage = .english,
        limit: Int = 5
    ) -> [VaniScriptLocalizedHelpTopic] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else {
            return Array(list(language: language).prefix(clampedLimit(limit)))
        }

        let queryTokens = Set(tokens(normalizedQuery))
        let ranked = helpTopics.compactMap { topic -> (HelpTopic, Int)? in
            let localized = topic.localized(language)
            let secondary = topic.localized(language == .english ? .russian : .english)
            let title = normalize(localized.title)
            let keywordTokens = Set(tokens(normalize(topic.keywords.joined(separator: " "))))
            let corpus = normalize(
                [
                    localized.title,
                    localized.summary,
                    localized.requirements.joined(separator: " "),
                    localized.steps.joined(separator: " "),
                    localized.troubleshooting.joined(separator: " "),
                    secondary.title,
                    secondary.summary,
                    topic.keywords.joined(separator: " "),
                ].joined(separator: " ")
            )

            var score = 0
            if title == normalizedQuery { score += 1_000 }
            if title.contains(normalizedQuery) { score += 300 }
            if corpus.contains(normalizedQuery) { score += 180 }
            for token in queryTokens where token.count > 1 {
                if keywordTokens.contains(token) { score += 60 }
                if title.contains(token) { score += 30 }
                if corpus.contains(token) { score += 8 }
            }
            guard score > 0 else { return nil }
            return (topic, score)
        }
        .sorted { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0.id < rhs.0.id : lhs.1 > rhs.1
        }

        return ranked.prefix(clampedLimit(limit)).map { $0.0.localized(language) }
    }

    public static func contextualHelp(
        screen: UniversalWorkflowScreen,
        hasSource: Bool,
        hasSession: Bool,
        processingProgress: Double,
        hasShortsPlans: Bool,
        language: VaniScriptHelpLanguage = .english
    ) -> VaniScriptContextualHelp {
        switch screen {
        case .upload:
            return localizedContext(
                screen: screen.rawValue,
                language: language,
                title: ("Start with a source", "Начните с исходного файла"),
                summary: (
                    "Import a local recording, capture audio, or download media from a supported link.",
                    "Импортируйте локальную запись, запишите аудио или загрузите медиа по поддерживаемой ссылке."
                ),
                actions: [
                    ("Click Upload Audio / Video for a file already on this Mac.", "Нажмите Upload Audio / Video, если файл уже находится на этом Mac."),
                    ("Use Record Audio Source for system audio or a microphone.", "Используйте Record Audio Source для системного звука или микрофона."),
                    ("Use Import Link for a supported internet media URL.", "Используйте Import Link для поддерживаемой интернет-ссылки."),
                ],
                topics: ["getting-started", "import-media", "record-audio", "import-link"]
            )
        case .config:
            let readyAction: LocalizedPair = hasSource
                ? ("Confirm the language and models, then click Initialize Engine.", "Проверьте язык и модели, затем нажмите Initialize Engine.")
                : ("Return to Upload and choose a source file first.", "Вернитесь на Upload и сначала выберите исходный файл.")
            return localizedContext(
                screen: screen.rawValue,
                language: language,
                title: ("Configure processing", "Настройте обработку"),
                summary: ("Choose metadata, target language, transcription model, and translation model.", "Выберите метаданные, язык перевода, модель транскрибации и модель перевода."),
                actions: [readyAction],
                topics: ["configure-engine", "manage-models", "process-media"]
            )
        case .processing:
            let percent = Int(max(0, min(1, processingProgress)) * 100)
            return localizedContext(
                screen: screen.rawValue,
                language: language,
                title: ("Processing is running", "Выполняется обработка"),
                summary: ("VaniScript is preparing the transcript and translation. Current progress: \(percent)%.", "VaniScript готовит транскрипт и перевод. Текущий прогресс: \(percent)%."),
                actions: [
                    ("Keep VaniScript open until Review appears.", "Не закрывайте VaniScript до появления экрана Review."),
                    ("If progress fails, open Settings > Models and verify the selected models.", "Если обработка завершается ошибкой, откройте Settings > Models и проверьте выбранные модели."),
                ],
                topics: ["process-media", "manage-models", "troubleshoot-unavailable"]
            )
        case .review:
            let action: LocalizedPair = hasSession
                ? ("Review the current segment, edit text if needed, then click Approve & Next.", "Проверьте текущий сегмент, при необходимости исправьте текст и нажмите Approve & Next.")
                : ("Start a session from Upload before using Review.", "Перед работой в Review запустите сессию через Upload.")
            return localizedContext(
                screen: screen.rawValue,
                language: language,
                title: ("Review and approve the transcript", "Проверьте и утвердите транскрипт"),
                summary: ("Compare the source and translation, listen to the segment, edit cues, and approve completed work.", "Сравнивайте исходный текст и перевод, слушайте сегмент, исправляйте cues и утверждайте готовый результат."),
                actions: [
                    action,
                    ("Use the view controls to show Source, Translation, or Dual mode.", "Используйте переключатель вида для Source, Translation или Dual mode."),
                ],
                topics: ["review-transcript", "edit-cues", "translate", "glossary"]
            )
        case .export:
            let shortsAction: LocalizedPair = hasShortsPlans
                ? ("Select the required clip cards and export ideas or videos.", "Выберите нужные карточки клипов и экспортируйте идеи или видео.")
                : ("In Shorts & Reels, click Find Moments before selecting clips.", "В разделе Shorts & Reels сначала нажмите Find Moments.")
            return localizedContext(
                screen: screen.rawValue,
                language: language,
                title: ("Export documents or create Shorts", "Экспортируйте документы или создайте Shorts"),
                summary: ("Export the reviewed transcript or generate and render short vertical clips.", "Экспортируйте проверенный транскрипт или создайте и отрендерите короткие вертикальные клипы."),
                actions: [
                    ("Use Document export for TXT, SRT, VTT, or Markdown.", "Используйте Document export для TXT, SRT, VTT или Markdown."),
                    shortsAction,
                ],
                topics: ["export-documents", "create-shorts", "visual-editor"]
            )
        case .visualEditor:
            return localizedContext(
                screen: screen.rawValue,
                language: language,
                title: ("Edit the selected clip", "Отредактируйте выбранный клип"),
                summary: ("Adjust crop, timing, subtitles, cuts, background, logo, text, and audio layers.", "Настройте кадрирование, тайминг, субтитры, cuts, фон, логотип, текстовые и аудиодорожки."),
                actions: [
                    ("Preview the clip after each timing or framing change.", "Проверяйте preview после каждого изменения тайминга или кадрирования."),
                    ("Click Save to keep the editor state, then return to Export to render.", "Нажмите Save, чтобы сохранить состояние редактора, затем вернитесь в Export для рендера."),
                ],
                topics: ["visual-editor", "create-shorts"]
            )
        }
    }

    public static func onboardingChecklist(
        language: VaniScriptHelpLanguage = .english
    ) -> VaniScriptOnboardingChecklist {
        switch language {
        case .english:
            return VaniScriptOnboardingChecklist(
                title: "First project checklist",
                summary: "Follow this route from an empty workspace to a reviewed export.",
                steps: [
                    "Open Settings > Models and confirm that the required transcription and translation models are ready.",
                    "On Upload, choose Upload Audio / Video, Record Audio Source, or Import Link.",
                    "On Config, verify metadata, Target Language, Transcription Model, and Translation Model.",
                    "Click Initialize Engine and wait for Review.",
                    "In Review, listen to each segment, correct the source or translation, and click Approve & Next.",
                    "Use glossary actions for recurring names and specialist terms.",
                    "After the last segment, open Export and choose a document format or create Shorts.",
                    "Use the question-mark Help Tour button on any main screen for a visual walkthrough.",
                ],
                topicIDs: ["getting-started", "manage-models", "configure-engine", "review-transcript", "glossary", "export-documents", "create-shorts"]
            )
        case .russian:
            return VaniScriptOnboardingChecklist(
                title: "Чек-лист первого проекта",
                summary: "Следуйте этому маршруту от пустого рабочего пространства до проверенного экспорта.",
                steps: [
                    "Откройте Settings > Models и убедитесь, что нужные модели транскрибации и перевода готовы.",
                    "На экране Upload выберите Upload Audio / Video, Record Audio Source или Import Link.",
                    "На экране Config проверьте метаданные, Target Language, Transcription Model и Translation Model.",
                    "Нажмите Initialize Engine и дождитесь Review.",
                    "В Review прослушивайте каждый сегмент, исправляйте исходный текст или перевод и нажимайте Approve & Next.",
                    "Используйте glossary для повторяющихся имён и специальных терминов.",
                    "После последнего сегмента откройте Export и выберите формат документа или создайте Shorts.",
                    "На любом основном экране нажмите кнопку со знаком вопроса Help Tour для визуальной экскурсии.",
                ],
                topicIDs: ["getting-started", "manage-models", "configure-engine", "review-transcript", "glossary", "export-documents", "create-shorts"]
            )
        }
    }
}

private extension VaniScriptHelpCatalog {
    typealias LocalizedPair = (english: String, russian: String)

    struct HelpTopic: Sendable {
        let id: String
        let category: String
        let screen: String?
        let title: LocalizedPair
        let summary: LocalizedPair
        let requirements: [LocalizedPair]
        let steps: [LocalizedPair]
        let troubleshooting: [LocalizedPair]
        let relatedTopicIDs: [String]
        let keywords: [String]

        func localized(_ language: VaniScriptHelpLanguage) -> VaniScriptLocalizedHelpTopic {
            VaniScriptLocalizedHelpTopic(
                id: id,
                category: category,
                screen: screen,
                title: value(title, language),
                summary: value(summary, language),
                requirements: requirements.map { value($0, language) },
                steps: steps.map { value($0, language) },
                troubleshooting: troubleshooting.map { value($0, language) },
                relatedTopicIDs: relatedTopicIDs
            )
        }
    }

    static func value(_ pair: LocalizedPair, _ language: VaniScriptHelpLanguage) -> String {
        language == .russian ? pair.russian : pair.english
    }

    static func localizedContext(
        screen: String,
        language: VaniScriptHelpLanguage,
        title: LocalizedPair,
        summary: LocalizedPair,
        actions: [LocalizedPair],
        topics: [String]
    ) -> VaniScriptContextualHelp {
        VaniScriptContextualHelp(
            screen: screen,
            title: value(title, language),
            summary: value(summary, language),
            nextActions: actions.map { value($0, language) },
            recommendedTopicIDs: topics
        )
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func tokens(_ value: String) -> [String] {
        value.split(separator: " ").map(String.init)
    }

    static func clampedLimit(_ value: Int) -> Int {
        max(1, min(10, value))
    }

    static func makeTopic(
        id: String,
        category: String,
        screen: UniversalWorkflowScreen? = nil,
        title: LocalizedPair,
        summary: LocalizedPair,
        requirements: [LocalizedPair] = [],
        steps: [LocalizedPair],
        troubleshooting: [LocalizedPair] = [],
        related: [String] = [],
        keywords: [String] = []
    ) -> HelpTopic {
        HelpTopic(
            id: id,
            category: category,
            screen: screen?.rawValue,
            title: title,
            summary: summary,
            requirements: requirements,
            steps: steps,
            troubleshooting: troubleshooting,
            relatedTopicIDs: related,
            keywords: keywords
        )
    }

    static let helpTopics: [HelpTopic] = [
        makeTopic(
            id: "getting-started",
            category: "Getting Started",
            screen: .upload,
            title: ("Create your first project", "Создание первого проекта"),
            summary: ("The normal route is Upload, Config, Processing, Review, then Export.", "Обычный маршрут: Upload, Config, Processing, Review, затем Export."),
            steps: [
                ("Choose or record source media on Upload.", "Выберите или запишите исходное медиа на экране Upload."),
                ("Confirm language and models on Config.", "Проверьте язык и модели на экране Config."),
                ("Click Initialize Engine and wait for Review.", "Нажмите Initialize Engine и дождитесь Review."),
                ("Correct and approve every segment.", "Исправьте и утвердите каждый сегмент."),
                ("Open Export for documents or Shorts.", "Откройте Export для документов или Shorts."),
            ],
            related: ["import-media", "configure-engine", "review-transcript", "export-documents"],
            keywords: ["first project beginner start workflow первый проект начать новичок маршрут"]
        ),
        makeTopic(
            id: "import-media",
            category: "Import",
            screen: .upload,
            title: ("Import an audio or video file", "Импорт аудио- или видеофайла"),
            summary: ("Use a local MP3, WAV, M4A, MP4, MOV, or lecture media file.", "Используйте локальный MP3, WAV, M4A, MP4, MOV или файл лекции."),
            steps: [
                ("Open Upload.", "Откройте Upload."),
                ("Click Upload Audio / Video.", "Нажмите Upload Audio / Video."),
                ("Choose the source file in the macOS file picker.", "Выберите исходный файл в системном окне macOS."),
                ("Wait for Config to open and verify the detected duration and metadata.", "Дождитесь Config и проверьте определённую длительность и метаданные."),
            ],
            troubleshooting: [
                ("If Config does not open, verify that the file exists and uses a supported media format.", "Если Config не открывается, проверьте наличие файла и поддерживаемый формат."),
            ],
            related: ["configure-engine", "import-link", "record-audio"],
            keywords: ["upload file import mp3 wav m4a mp4 mov загрузить файл импорт"]
        ),
        makeTopic(
            id: "import-link",
            category: "Import",
            screen: .upload,
            title: ("Import media from a link", "Импорт медиа по ссылке"),
            summary: ("Download supported internet media and continue through the normal transcription workflow.", "Загрузите поддерживаемое интернет-медиа и продолжите обычный процесс транскрибации."),
            requirements: [
                ("An internet connection and a supported public media URL.", "Нужны интернет-соединение и поддерживаемая публичная ссылка."),
            ],
            steps: [
                ("On Upload, click Import Link.", "На экране Upload нажмите Import Link."),
                ("Paste the complete media URL.", "Вставьте полную ссылку на медиа."),
                ("Start the import and wait until VaniScript opens Config.", "Запустите импорт и дождитесь, когда VaniScript откроет Config."),
            ],
            troubleshooting: [
                ("Private, expired, unsupported, or access-restricted links may fail.", "Приватные, устаревшие, неподдерживаемые или ограниченные ссылки могут не загрузиться."),
            ],
            related: ["import-media", "configure-engine"],
            keywords: ["url youtube soundcloud download link ссылка скачать интернет"]
        ),
        makeTopic(
            id: "record-audio",
            category: "Import",
            screen: .upload,
            title: ("Record an audio source", "Запись источника аудио"),
            summary: ("Capture system audio or a microphone, review it, then send it to transcription.", "Запишите системный звук или микрофон, прослушайте запись и отправьте её на транскрибацию."),
            steps: [
                ("On Upload, click Record Audio Source.", "На экране Upload нажмите Record Audio Source."),
                ("Choose System Audio or Mic / Virtual and select an input when needed.", "Выберите System Audio или Mic / Virtual и при необходимости укажите вход."),
                ("Click Start Recording, then Stop & Review.", "Нажмите Start Recording, затем Stop & Review."),
                ("Listen to the preview and click Save & Continue, or Retake.", "Прослушайте preview и нажмите Save & Continue либо Retake."),
            ],
            troubleshooting: [
                ("Grant the macOS recording permissions requested by VaniScript.", "Предоставьте VaniScript запрошенные macOS разрешения на запись."),
                ("If system audio is unavailable, use a microphone or a virtual input such as BlackHole or Loopback.", "Если системный звук недоступен, используйте микрофон или виртуальный вход, например BlackHole или Loopback."),
            ],
            related: ["configure-engine", "import-media"],
            keywords: ["record microphone system audio capture blackhole loopback запись микрофон системный звук"]
        ),
        makeTopic(
            id: "configure-engine",
            category: "Processing",
            screen: .config,
            title: ("Configure transcription and translation", "Настройка транскрибации и перевода"),
            summary: ("Set metadata, target language, transcription model, translation model, and output formats.", "Укажите метаданные, язык перевода, модели транскрибации и перевода, а также форматы вывода."),
            requirements: [
                ("A source file must already be selected.", "Исходный файл уже должен быть выбран."),
            ],
            steps: [
                ("Check Date, Location, Lecturer, and Interviewer / Participants.", "Проверьте Date, Location, Lecturer и Interviewer / Participants."),
                ("Choose Target Language. Select same to skip translation.", "Выберите Target Language. Укажите same, чтобы не выполнять перевод."),
                ("Choose Transcription Model and, when translating, Translation Model.", "Выберите Transcription Model и, если нужен перевод, Translation Model."),
                ("Click Initialize Engine.", "Нажмите Initialize Engine."),
            ],
            troubleshooting: [
                ("If a model is missing, open Settings > Models and download or locate it.", "Если модель отсутствует, откройте Settings > Models и загрузите либо укажите её расположение."),
            ],
            related: ["manage-models", "process-media"],
            keywords: ["config language provider initialize engine metadata модель язык настройка"]
        ),
        makeTopic(
            id: "manage-models",
            category: "Settings",
            title: ("Install and select local models", "Установка и выбор локальных моделей"),
            summary: ("Models provide local transcription, translation, polishing, planning, and review functions.", "Модели обеспечивают локальную транскрибацию, перевод, полировку, планирование и проверку."),
            steps: [
                ("Open Settings and select Models.", "Откройте Settings и выберите Models."),
                ("Use Download for a supported model, Locate for an existing model, or Scan to detect models on disk.", "Используйте Download для поддерживаемой модели, Locate для существующей модели или Scan для поиска моделей на диске."),
                ("Select the required model in the relevant task section.", "Выберите нужную модель в разделе соответствующей задачи."),
                ("Return to Config and confirm the model selections.", "Вернитесь в Config и проверьте выбранные модели."),
            ],
            troubleshooting: [
                ("A removed or incomplete model cannot be used until it is downloaded or located again.", "Удалённую или неполную модель нельзя использовать, пока она не будет загружена или найдена повторно."),
            ],
            related: ["configure-engine", "troubleshoot-unavailable"],
            keywords: ["models download locate scan whisper mlx модель скачать найти сканировать"]
        ),
        makeTopic(
            id: "process-media",
            category: "Processing",
            screen: .processing,
            title: ("Process the selected media", "Обработка выбранного медиа"),
            summary: ("VaniScript splits the source into segments, transcribes them, and translates when requested.", "VaniScript делит источник на сегменты, транскрибирует их и при необходимости переводит."),
            steps: [
                ("Start from Config with Initialize Engine.", "Запустите обработку из Config кнопкой Initialize Engine."),
                ("Keep the app open while Processing shows progress.", "Не закрывайте приложение, пока Processing показывает прогресс."),
                ("When Review opens, inspect each prepared segment.", "После открытия Review проверьте каждый подготовленный сегмент."),
            ],
            troubleshooting: [
                ("For a failed segment, use Retry or reprocess only that segment from Review.", "Для неудачного сегмента используйте Retry или повторно обработайте только этот сегмент в Review."),
            ],
            related: ["review-transcript", "manage-models"],
            keywords: ["processing progress transcribe segment retry обработка прогресс транскрибация повторить"]
        ),
        makeTopic(
            id: "review-transcript",
            category: "Review",
            screen: .review,
            title: ("Review and approve segments", "Проверка и утверждение сегментов"),
            summary: ("Listen, compare, edit, and approve the source transcript and translation one segment at a time.", "Прослушивайте, сравнивайте, редактируйте и утверждайте исходный текст и перевод по одному сегменту."),
            steps: [
                ("Use the audio bar to play and seek the current segment.", "Используйте аудиопанель для воспроизведения и перемотки текущего сегмента."),
                ("Choose Source, Translation, or Dual view.", "Выберите Source, Translation или Dual view."),
                ("Edit text or timed cues where necessary.", "При необходимости исправьте текст или cues с таймингами."),
                ("Click Approve & Next. On the final segment, click Complete & Export.", "Нажмите Approve & Next. На последнем сегменте нажмите Complete & Export."),
            ],
            related: ["edit-cues", "translate", "glossary", "export-documents"],
            keywords: ["review approve chunk segment dual source translation проверить утвердить сегмент"]
        ),
        makeTopic(
            id: "edit-cues",
            category: "Review",
            screen: .review,
            title: ("Edit text and subtitle cues", "Редактирование текста и subtitle cues"),
            summary: ("Correct words, cue text, and cue timing while reviewing a segment.", "Исправляйте слова, текст cues и их тайминги во время проверки сегмента."),
            steps: [
                ("Open the required segment in Review.", "Откройте нужный сегмент в Review."),
                ("Edit the source or translated text directly, or open the timed cue editor.", "Редактируйте исходный текст или перевод напрямую либо откройте редактор cues с таймингами."),
                ("Keep cue start and end times inside the segment and in chronological order.", "Сохраняйте начало и конец cue внутри сегмента и в хронологическом порядке."),
                ("Listen again before approving the segment.", "Прослушайте сегмент ещё раз перед утверждением."),
            ],
            related: ["review-transcript", "glossary"],
            keywords: ["cue timestamp subtitle edit timing text тайминг субтитры редактировать"]
        ),
        makeTopic(
            id: "translate",
            category: "Translation",
            screen: .review,
            title: ("Create, switch, and polish translations", "Создание, переключение и полировка переводов"),
            summary: ("A project can keep multiple target-language translations and polish selected text.", "Проект может хранить переводы на нескольких языках и полировать выбранный текст."),
            steps: [
                ("In Review, use the translation language control to select or add a language.", "В Review используйте выбор языка перевода, чтобы выбрать или добавить язык."),
                ("Retry translation for a failed segment when needed.", "При необходимости повторите перевод неудачного сегмента."),
                ("Use Polish for selected text or the current translation, then review the revision before approval.", "Используйте Polish для выделенного текста или текущего перевода, затем проверьте результат перед утверждением."),
            ],
            related: ["review-transcript", "glossary", "manage-models"],
            keywords: ["translate language polish retry перевод язык полировка повторить"]
        ),
        makeTopic(
            id: "glossary",
            category: "Translation",
            title: ("Use the glossary for names and terminology", "Использование glossary для имён и терминов"),
            summary: ("Store preferred spellings, variants, translations, categories, and notes for recurring terms.", "Храните предпочтительные написания, варианты, переводы, категории и заметки для повторяющихся терминов."),
            steps: [
                ("Select a misspelled or inconsistent term in Review and choose Add to Glossary.", "Выделите ошибочный или непоследовательный термин в Review и выберите Add to Glossary."),
                ("Add it as a variant of an existing term or create a new term.", "Добавьте его как вариант существующего термина или создайте новый термин."),
                ("Open Settings > Glossary to edit, import, export, sort, or remove entries.", "Откройте Settings > Glossary для редактирования, импорта, экспорта, сортировки или удаления записей."),
                ("Apply glossary corrections to the current chunk or the project, then review the changed text.", "Примените исправления glossary к текущему чанку или проекту, затем проверьте изменённый текст."),
            ],
            related: ["review-transcript", "translate"],
            keywords: ["glossary term variant name spelling translation глоссарий термин имя вариант написание"]
        ),
        makeTopic(
            id: "export-documents",
            category: "Export",
            screen: .export,
            title: ("Export transcript documents", "Экспорт документов транскрипта"),
            summary: ("Export original or translated content as TXT, SRT, VTT, or Markdown.", "Экспортируйте исходный текст или перевод в TXT, SRT, VTT или Markdown."),
            requirements: [
                ("An active reviewed session. Translation exports require an active translation language.", "Нужна активная проверенная сессия. Для экспорта перевода требуется выбранный язык перевода."),
            ],
            steps: [
                ("Open Export, or click Complete & Export after the last segment.", "Откройте Export или нажмите Complete & Export после последнего сегмента."),
                ("In Document export, click the Original or Target button for the required format.", "В Document export нажмите кнопку Original или Target нужного формата."),
                ("Choose the destination in the macOS save dialog.", "Выберите папку назначения в системном окне сохранения macOS."),
            ],
            related: ["review-transcript", "create-shorts"],
            keywords: ["export txt srt vtt markdown subtitles document экспорт документ субтитры"]
        ),
        makeTopic(
            id: "create-shorts",
            category: "Shorts",
            screen: .export,
            title: ("Find and export Shorts", "Поиск и экспорт Shorts"),
            summary: ("Find meaningful moments, choose clips, edit them, and export vertical videos or idea files.", "Найдите содержательные моменты, выберите клипы, отредактируйте и экспортируйте вертикальные видео или файлы идей."),
            steps: [
                ("Open Export and scroll to Shorts & Reels.", "Откройте Export и перейдите к Shorts & Reels."),
                ("Choose clip count and minimum/maximum length, then click a Find Moments language mode.", "Укажите число клипов и минимальную/максимальную длину, затем выберите режим Find Moments."),
                ("Select clip cards. Use Details, Replace, Delete, or Edit when needed.", "Выберите карточки клипов. При необходимости используйте Details, Replace, Delete или Edit."),
                ("Choose format, resolution, and frame rate.", "Выберите формат, разрешение и частоту кадров."),
                ("Click Export ideas JSON/TXT or Export selected videos.", "Нажмите Export ideas JSON/TXT или Export selected videos."),
            ],
            troubleshooting: [
                ("Target-language modes require an available project translation.", "Для режимов на языке перевода в проекте должен быть доступен перевод."),
            ],
            related: ["visual-editor", "export-documents"],
            keywords: ["shorts reels find moments vertical clip export шортс рилс клип вертикальный"]
        ),
        makeTopic(
            id: "visual-editor",
            category: "Shorts",
            screen: .visualEditor,
            title: ("Edit a Short in Visual Editor", "Редактирование Short в Visual Editor"),
            summary: ("Fine-tune framing, subtitles, timing, cuts, graphic layers, and extra audio before render.", "Точно настройте кадрирование, субтитры, тайминг, cuts, графические слои и дополнительное аудио перед рендером."),
            steps: [
                ("On a Shorts card, click Edit.", "На карточке Shorts нажмите Edit."),
                ("Adjust the clip timing and framing while checking the preview.", "Настройте тайминг и кадрирование, проверяя preview."),
                ("Edit subtitle style and segments; add cuts, background, logo, intro/outro, text, or audio tracks as needed.", "При необходимости измените стиль и сегменты субтитров; добавьте cuts, фон, логотип, intro/outro, текстовые или аудиодорожки."),
                ("Click Save, return to Export, select the clip, and render it.", "Нажмите Save, вернитесь в Export, выберите клип и запустите рендер."),
            ],
            related: ["create-shorts"],
            keywords: ["visual editor crop captions cuts logo intro outro text audio редактор кадр логотип титры"]
        ),
        makeTopic(
            id: "projects",
            category: "Projects",
            title: ("Open and manage saved projects", "Открытие и управление сохранёнными проектами"),
            summary: ("Resume previous work from the Projects panel and keep the active project saved.", "Продолжайте предыдущую работу через панель Projects и сохраняйте активный проект."),
            steps: [
                ("In Review, click the folder button labelled Projects.", "В Review нажмите кнопку с папкой Projects."),
                ("Choose a saved project to open it.", "Выберите сохранённый проект для открытия."),
                ("Use the project actions to reveal the source, inspect media information, export a bundle, or delete a project.", "Используйте действия проекта, чтобы показать источник, посмотреть сведения о медиа, экспортировать bundle или удалить проект."),
                ("Use + New Session when you want to leave the current workflow and start another source.", "Используйте + New Session, чтобы выйти из текущего процесса и начать работу с другим источником."),
            ],
            related: ["getting-started", "export-documents"],
            keywords: ["projects saved open resume delete bundle проект открыть продолжить удалить"]
        ),
        makeTopic(
            id: "settings-agents",
            category: "Settings",
            title: ("Connect an MCP agent", "Подключение MCP-агента"),
            summary: ("Enable the local MCP server, choose the preferred agent, and use the generated setup instructions.", "Включите локальный MCP-сервер, выберите предпочтительного агента и используйте созданные инструкции подключения."),
            steps: [
                ("Open Settings > Agents.", "Откройте Settings > Agents."),
                ("Turn on Enable MCP.", "Включите Enable MCP."),
                ("Turn on Allow Write Tools only when the agent may edit the active project.", "Включайте Allow Write Tools только когда агенту разрешено изменять активный проект."),
                ("Choose Preferred Agent and use Copy Setup for that client.", "Выберите Preferred Agent и используйте Copy Setup для этого клиента."),
                ("A green status means the client is currently connected; Active only selects the preferred profile.", "Зелёный статус означает, что клиент сейчас подключён; Active только выбирает предпочтительный профиль."),
            ],
            troubleshooting: [
                ("If the status is Ready, the server is available but that external client is not currently connected.", "Статус Ready означает, что сервер доступен, но внешний клиент сейчас не подключён."),
            ],
            related: ["embedded-chat", "troubleshoot-unavailable"],
            keywords: ["mcp codex agent connected ready enable write tools агент подключить статус"]
        ),
        makeTopic(
            id: "embedded-chat",
            category: "Assistant",
            title: ("Use the VaniScript AI Assistant", "Использование VaniScript AI Assistant"),
            summary: ("Ask how to use VaniScript, inspect the active project, or request an available MCP action directly in the app chat.", "Задавайте вопросы по VaniScript, проверяйте активный проект или просите выполнить доступное MCP-действие прямо в чате приложения."),
            steps: [
                ("Open the AI Assistant panel.", "Откройте панель AI Assistant."),
                ("Select MCP for the connected Codex route or API for the configured provider route.", "Выберите MCP для подключённого Codex или API для настроенного провайдера."),
                ("Ask a concrete question, for example: How do I export SRT?", "Задайте конкретный вопрос, например: Как экспортировать SRT?"),
                ("For edits, enable Allow Write Tools in Settings > Agents and describe the intended change precisely.", "Для изменений включите Allow Write Tools в Settings > Agents и точно опишите нужное действие."),
            ],
            related: ["settings-agents", "getting-started"],
            keywords: ["assistant chat help ask codex mcp api помощник чат спросить помощь"]
        ),
        makeTopic(
            id: "help-tour",
            category: "Getting Started",
            title: ("Open the visual Help Tour", "Запуск визуального Help Tour"),
            summary: ("The question-mark button highlights the important controls on the current workspace.", "Кнопка со знаком вопроса подсвечивает важные элементы текущего рабочего экрана."),
            steps: [
                ("Open the workspace you want to learn.", "Откройте рабочий экран, который хотите изучить."),
                ("Click the question-mark button with the Help Tour tooltip.", "Нажмите кнопку со знаком вопроса и подсказкой Help Tour."),
                ("Follow Next through the highlighted controls, or close the tour at any time.", "Переходите кнопкой Next по подсвеченным элементам или закройте экскурсию в любой момент."),
            ],
            related: ["getting-started", "embedded-chat"],
            keywords: ["help tour onboarding question mark walkthrough помощь обучение экскурсия знак вопроса"]
        ),
        makeTopic(
            id: "troubleshoot-unavailable",
            category: "Troubleshooting",
            title: ("Understand disabled or unavailable actions", "Почему действие недоступно"),
            summary: ("Most disabled actions are missing a source, session, translation, model, selection, permission, or active MCP connection.", "Обычно действие недоступно из-за отсутствия источника, сессии, перевода, модели, выбора, разрешения или активного MCP-подключения."),
            steps: [
                ("Read the status message shown near the affected workspace.", "Прочитайте сообщение статуса рядом с соответствующим рабочим экраном."),
                ("Confirm that a source and active session exist.", "Убедитесь, что существуют исходный файл и активная сессия."),
                ("Check Settings > Models for required local models.", "Проверьте нужные локальные модели в Settings > Models."),
                ("For translated or bilingual actions, select an available translation language.", "Для перевода и двуязычных действий выберите доступный язык перевода."),
                ("For MCP edits, enable Allow Write Tools and confirm that the agent shows Connected.", "Для MCP-изменений включите Allow Write Tools и убедитесь, что агент показывает Connected."),
            ],
            related: ["manage-models", "settings-agents", "embedded-chat"],
            keywords: ["disabled unavailable error ready connected missing неактивно недоступно ошибка отсутствует"]
        ),
    ]
}
