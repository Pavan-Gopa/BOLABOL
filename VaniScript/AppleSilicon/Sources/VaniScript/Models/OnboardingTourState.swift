import Foundation
import CoreGraphics

public enum BubblePlacement: String, Codable, Sendable {
    case top
    case bottom
    case left
    case right
    case center
}

public struct TourStep: Identifiable, Sendable, Equatable {
    public var id: String { targetSelector }
    public let targetSelector: String
    public let arrowCurveOffset: CGPoint
    public let bubblePlacement: BubblePlacement
    public let titleEN: String
    public let descriptionEN: String
    public let titleRU: String
    public let descriptionRU: String

    public init(
        targetSelector: String,
        arrowCurveOffset: CGPoint,
        bubblePlacement: BubblePlacement,
        titleEN: String,
        descriptionEN: String,
        titleRU: String,
        descriptionRU: String
    ) {
        self.targetSelector = targetSelector
        self.arrowCurveOffset = arrowCurveOffset
        self.bubblePlacement = bubblePlacement
        self.titleEN = titleEN
        self.descriptionEN = descriptionEN
        self.titleRU = titleRU
        self.descriptionRU = descriptionRU
    }

    public func title(for language: String) -> String {
        language.lowercased().hasPrefix("ru") ? titleRU : titleEN
    }

    public func description(for language: String) -> String {
        language.lowercased().hasPrefix("ru") ? descriptionRU : descriptionEN
    }
}

public struct TourSteps {
    public static func steps(for screen: String) -> [TourStep] {
        switch screen {
        case "upload":
            return [
                TourStep(
                    targetSelector: "settings-btn",
                    arrowCurveOffset: CGPoint(x: -30, y: 40),
                    bubblePlacement: .left,
                    titleEN: "Step 1: Settings & API Keys",
                    descriptionEN: "Start here! Click the settings gear icon to configure your API keys (Gemini, OpenAI, Claude) or download offline local models for transcription.",
                    titleRU: "Шаг 1: Настройки и Ключи API",
                    descriptionRU: "Начните отсюда! Нажмите кнопку настроек (шестерёнку), чтобы ввести API-ключи (Gemini, OpenAI) или настроить локальные оффлайн-модели распознавания."
                ),
                TourStep(
                    targetSelector: "workspace-dropzone",
                    arrowCurveOffset: CGPoint(x: 40, y: -30),
                    bubblePlacement: .bottom,
                    titleEN: "Step 2: Drag & Drop Upload",
                    descriptionEN: "Drag and drop any audio or video file here to begin, or click inside the card to browse files from your computer.",
                    titleRU: "Шаг 2: Загрузка файлов",
                    descriptionRU: "Перетащите сюда любой аудио- или видеофайл для начала работы, либо нажмите на карточку для выбора файла с компьютера."
                ),
                TourStep(
                    targetSelector: "workspace-record-card",
                    arrowCurveOffset: CGPoint(x: 0, y: -60),
                    bubblePlacement: .bottom,
                    titleEN: "Step 3: Record Audio",
                    descriptionEN: "No media file ready? Capture system audio (e.g. from browser playback) or a connected microphone directly in VaniScript!",
                    titleRU: "Шаг 3: Запись звука",
                    descriptionRU: "Нет готового файла? Запишите системный звук вашего Mac (например, лекцию из браузера) или подключенный микрофон прямо здесь."
                ),
                TourStep(
                    targetSelector: "workspace-link-card",
                    arrowCurveOffset: CGPoint(x: -40, y: -30),
                    bubblePlacement: .bottom,
                    titleEN: "Step 4: Web URL Import",
                    descriptionEN: "Import media directly from the web! Paste a YouTube or SoundCloud link, and VaniScript will download and prepare the audio for you.",
                    titleRU: "Шаг 4: Импорт по ссылке",
                    descriptionRU: "Вставьте ссылку на YouTube или SoundCloud, и VaniScript автоматически скачает аудиозапись в наилучшем качестве!"
                )
            ]
        case "config":
            return [
                TourStep(
                    targetSelector: "config-metadata",
                    arrowCurveOffset: CGPoint(x: 60, y: 20),
                    bubblePlacement: .right,
                    titleEN: "Step 1: Audio Metadata",
                    descriptionEN: "Fill in the date, location, and lecturer name. VaniScript uses these metadata details for vocabulary alignment and automatic file naming.",
                    titleRU: "Шаг 1: Метаданные аудио",
                    descriptionRU: "Заполните дату, место и имя лектора. VaniScript использует эти данные для автокоррекции терминов и именования файлов при экспорте."
                ),
                TourStep(
                    targetSelector: "target-lang-select",
                    arrowCurveOffset: CGPoint(x: -50, y: -40),
                    bubblePlacement: .top,
                    titleEN: "Step 2: Target Translation",
                    descriptionEN: "Select your target language for translation. If you only want transcription in the original language, choose \"Keep original (Same)\".",
                    titleRU: "Шаг 2: Целевой язык перевода",
                    descriptionRU: "Выберите язык перевода. Для сохранения оригинальной речи без перевода выберите \"Keep original (Same)\"."
                ),
                TourStep(
                    targetSelector: "transcription-model-select",
                    arrowCurveOffset: CGPoint(x: 50, y: -40),
                    bubblePlacement: .top,
                    titleEN: "Step 3: AI Models Selection",
                    descriptionEN: "Select AI models. Use cloud providers (Gemini, OpenAI) for top speed, or download secure offline local Whisper models for 100% privacy.",
                    titleRU: "Шаг 3: Выбор моделей AI",
                    descriptionRU: "Выберите AI-модели. Облачные модели (Gemini, OpenAI) обеспечат скорость, а локальные Whisper-модели — 100% конфиденциальность."
                ),
                TourStep(
                    targetSelector: "start-engine-btn",
                    arrowCurveOffset: CGPoint(x: -40, y: -60),
                    bubblePlacement: .top,
                    titleEN: "Step 4: Launch Engine",
                    descriptionEN: "Ready to go! Click this button to segment your audio file and begin the high-precision transcription and translation workflows.",
                    titleRU: "Шаг 4: Запуск движка",
                    descriptionRU: "Всё настроено! Нажмите эту кнопку, чтобы нарезать аудио и запустить интеллектуальное распознавание."
                )
            ]
        case "review":
            return [
                TourStep(
                    targetSelector: "review-audio-bar",
                    arrowCurveOffset: CGPoint(x: 30, y: 60),
                    bubblePlacement: .bottom,
                    titleEN: "Step 1: Segment Audio Bar",
                    descriptionEN: "Listen to the current segment. Press the \"Spacebar\" on your keyboard to play or pause easily while verifying spelling and wording.",
                    titleRU: "Шаг 1: Аудиоплеер сегмента",
                    descriptionRU: "Прослушивайте текущую фразу. Воспроизведение можно удобно запускать и останавливать клавишей \"Пробел\" для проверки на слух."
                ),
                TourStep(
                    targetSelector: "review-pane-original",
                    arrowCurveOffset: CGPoint(x: 60, y: 40),
                    bubblePlacement: .right,
                    titleEN: "Step 2: Original Transcription",
                    descriptionEN: "This pane displays the speech text transcription. Feel free to type in any corrections directly; they are saved automatically.",
                    titleRU: "Шаг 2: Оригинальный текст",
                    descriptionRU: "Здесь отображается текст распознанной речи. Вы можете править ошибки распознавания прямо в текстовом поле."
                ),
                TourStep(
                    targetSelector: "review-pane-translation",
                    arrowCurveOffset: CGPoint(x: -60, y: 40),
                    bubblePlacement: .left,
                    titleEN: "Step 3: Translation Panel",
                    descriptionEN: "Verify translation side-by-side. You can highlight philosophy terms to add them to your custom VaniScript glossary in one click.",
                    titleRU: "Шаг 3: Перевод и Глоссарий",
                    descriptionRU: "Справа отображается перевод. Выделяйте санскритские философские термины для быстрого добавления в словарь."
                ),
                TourStep(
                    targetSelector: "review-editing-model",
                    arrowCurveOffset: CGPoint(x: 20, y: 50),
                    bubblePlacement: .bottom,
                    titleEN: "Step 4: Choose Editing Model",
                    descriptionEN: "Select which AI model handles text polishing and glossary correction. Choose cloud Gemini for lightning speed, or a local MLX model for 100% privacy.",
                    titleRU: "Шаг 4: Модель редактирования",
                    descriptionRU: "Выберите ИИ-модель для полировки текста и работы глоссария. Используйте облачный Gemini для высокой скорости или локальную MLX-модель для полной приватности."
                ),
                TourStep(
                    targetSelector: "review-view-group",
                    arrowCurveOffset: CGPoint(x: 30, y: 50),
                    bubblePlacement: .bottom,
                    titleEN: "Step 5: View Mode Toggles",
                    descriptionEN: "Customize your editor layout! Switch between seeing only original text (Source), only translated text (Translated), or both side-by-side (Dual View).",
                    titleRU: "Шаг 5: Режимы отображения",
                    descriptionRU: "Настройте внешний вид редактора! Переключайтесь между показом только оригинала (Source), только перевода (Translated) или двух окон вместе (Dual View)."
                ),
                TourStep(
                    targetSelector: "previous-segment-btn",
                    arrowCurveOffset: CGPoint(x: -30, y: -50),
                    bubblePlacement: .top,
                    titleEN: "Step 6: Navigate Segments",
                    descriptionEN: "Want to review an earlier segment? Easily jump back to previous audio chunks using the Previous button before approving and advancing.",
                    titleRU: "Шаг 6: Навигация по сегментам",
                    descriptionRU: "Нужно вернуться назад? Вы можете легко переходить между фрагментами аудио с помощью кнопки \"‹ Previous\" для повторной проверки."
                ),
                TourStep(
                    targetSelector: "approve-next-btn",
                    arrowCurveOffset: CGPoint(x: -40, y: -60),
                    bubblePlacement: .top,
                    titleEN: "Step 7: Approve & Advance",
                    descriptionEN: "Approve the segment and advance! Press Ctrl/Cmd + Enter to quickly save your updates and jump to the next segment.",
                    titleRU: "Шаг 7: Утвердить и продолжить",
                    descriptionRU: "Утвердите проверенный сегмент! Используйте сочетание Ctrl/Cmd + Enter для быстрого перехода к следующей фразе."
                )
            ]
        case "export":
            return [
                TourStep(
                    targetSelector: "export-documents",
                    arrowCurveOffset: CGPoint(x: 50, y: 40),
                    bubblePlacement: .bottom,
                    titleEN: "Step 1: Document Exports",
                    descriptionEN: "Export the reviewed transcript and captions after all chunks are approved. Use TXT, SRT, VTT, or Markdown when you need text delivery instead of video clips.",
                    titleRU: "Шаг 1: Экспорт Документов",
                    descriptionRU: "Экспортируйте проверенную транскрибацию и субтитры после approval всех чанков. TXT, SRT, VTT и Markdown подходят для текстовой выдачи без видеоклипов."
                ),
                TourStep(
                    targetSelector: "shorts-find-moments",
                    arrowCurveOffset: CGPoint(x: 40, y: -40),
                    bubblePlacement: .bottom,
                    titleEN: "Step 2: Find Shorts/Reels Moments",
                    descriptionEN: "Choose how many clips you want, set minimum and maximum length, then ask the selected planning model to search Source, Source + Target, or Target text for fresh moments.",
                    titleRU: "Шаг 2: Поиск моментов для Shorts/Reels",
                    descriptionRU: "Выберите количество клипов, минимальную и максимальную длину, затем отправьте модели Source, Source + Target или Target-текст для поиска новых удачных фрагментов."
                ),
                TourStep(
                    targetSelector: "shorts-choose-clips",
                    arrowCurveOffset: CGPoint(x: -50, y: 30),
                    bubblePlacement: .left,
                    titleEN: "Step 3: Choose Clips",
                    descriptionEN: "Review generated clip cards, compare Source and Target wording, open Details, Replace weak timing, delete misses, and keep only clips you want to export.",
                    titleRU: "Шаг 3: Выбор клипов",
                    descriptionRU: "Проверьте карточки клипов, сравните Source и Target, откройте Details, замените слабые тайминги, удалите лишнее и оставьте только нужные ролики."
                ),
                TourStep(
                    targetSelector: "shorts-edit-clip",
                    arrowCurveOffset: CGPoint(x: -30, y: 40),
                    bubblePlacement: .left,
                    titleEN: "Step 4: Visual Editor",
                    descriptionEN: "Use Edit Clip to open the Visual Editor. There you can sync playback, adjust subtitle blocks, crop and animate the frame, tune captions, and save edits back to the clip card.",
                    titleRU: "Шаг 4: Визуальный редактор",
                    descriptionRU: "Нажмите Edit Clip, чтобы открыть визуальный редактор. Там можно синхронизировать воспроизведение, править блоки субтитров, кадрирование, анимацию, стиль титров и сохранить изменения в карточку."
                ),
                TourStep(
                    targetSelector: "shorts-export-settings",
                    arrowCurveOffset: CGPoint(x: 40, y: -30),
                    bubblePlacement: .top,
                    titleEN: "Step 5: Export Settings",
                    descriptionEN: "Pick format, resolution, and frame rate before rendering. Source-based keeps the source video properties when that is the cleanest choice.",
                    titleRU: "Шаг 5: Настройки экспорта",
                    descriptionRU: "Перед рендером выберите формат, разрешение и частоту кадров. Source-based сохраняет параметры исходного видео, когда это самый аккуратный вариант."
                ),
                TourStep(
                    targetSelector: "shorts-export-actions",
                    arrowCurveOffset: CGPoint(x: -40, y: 30),
                    bubblePlacement: .top,
                    titleEN: "Step 6: Export Ideas or Videos",
                    descriptionEN: "Export ideas JSON/TXT for planning notes, or render selected videos with the native AVFoundation/Metal render pipeline. Clip metadata and captions stay editable later.",
                    titleRU: "Шаг 6: Экспорт идей или видео",
                    descriptionRU: "Экспортируйте идеи в JSON/TXT для заметок или рендерите выбранные видео нативным AVFoundation/Metal-рендерером. Метаданные клипов и субтитры останутся редактируемыми."
                ),
                TourStep(
                    targetSelector: "export-footer-actions",
                    arrowCurveOffset: CGPoint(x: 0, y: -40),
                    bubblePlacement: .top,
                    titleEN: "Step 7: Continue Working",
                    descriptionEN: "Use Back to Chunks to return to reviewed chunks, Sessions to open/import projects, or New Session to start another video without hunting through menus.",
                    titleRU: "Шаг 7: Продолжение работы",
                    descriptionRU: "Back to Chunks возвращает к проверенным чанкам, Sessions открывает проекты и импорт, а New Session запускает новое видео без поиска нужной команды в меню."
                )
            ]
        case "settings":
            return [
                TourStep(
                    targetSelector: "settings-tab-0",
                    arrowCurveOffset: CGPoint(x: -20, y: 40),
                    bubblePlacement: .bottom,
                    titleEN: "Agents",
                    descriptionEN: "Connect trusted MCP clients such as Codex, Claude, Cursor, and Antigravity to the local VaniScript server.",
                    titleRU: "Агенты",
                    descriptionRU: "Подключайте доверенные MCP-клиенты, такие как Codex, Claude, Cursor и Antigravity, к локальному серверу VaniScript."
                ),
                TourStep(
                    targetSelector: "settings-tab-1",
                    arrowCurveOffset: CGPoint(x: -20, y: 40),
                    bubblePlacement: .bottom,
                    titleEN: "API Keys",
                    descriptionEN: "Configure your cloud API keys for Google Gemini, OpenAI, or Anthropic. Cloud models offer maximum processing speed for transcription and translation.",
                    titleRU: "Ключи API",
                    descriptionRU: "Настройте ключи API для Google Gemini, OpenAI или Anthropic. Облачные модели обеспечивают максимальную скорость распознавания и перевода."
                ),
                TourStep(
                    targetSelector: "settings-tab-2",
                    arrowCurveOffset: CGPoint(x: -20, y: 40),
                    bubblePlacement: .bottom,
                    titleEN: "Appearance Options",
                    descriptionEN: "Choose between Dark and Light themes, select your preferred reading font family (JetBrains Mono, Inter, Georgia), and scale the user interface text size.",
                    titleRU: "Оформление и темы",
                    descriptionRU: "Выберите темную или светлую тему, настройте шрифт для чтения (JetBrains Mono, Inter, Georgia) и измените масштаб интерфейса."
                ),
                TourStep(
                    targetSelector: "settings-tab-3",
                    arrowCurveOffset: CGPoint(x: -20, y: 40),
                    bubblePlacement: .bottom,
                    titleEN: "Smart Chunking",
                    descriptionEN: "Configure audio slicing. Choose \"By Silence\" to naturally cut audio at natural speech pauses (recommended) or set fixed duration intervals.",
                    titleRU: "Нарезка аудио (Chunking)",
                    descriptionRU: "Настройте нарезку аудиофайла. Выберите \"By Silence\" для умной нарезки на естественных паузах (рекомендуется) или укажите фиксированный шаг."
                ),
                TourStep(
                    targetSelector: "settings-tab-4",
                    arrowCurveOffset: CGPoint(x: -20, y: 40),
                    bubblePlacement: .bottom,
                    titleEN: "Custom Glossary",
                    descriptionEN: "Add custom vocabulary terms and correct spelling variants (e.g. Sanskrit terms, abbreviations, names) to ensure consistent and accurate AI results.",
                    titleRU: "Словарь терминов",
                    descriptionRU: "Добавляйте сложные термины и варианты их правильного написания (например, санскритские слова, имена, аббревиатуры) для автокоррекции."
                ),
                TourStep(
                    targetSelector: "settings-tab-5",
                    arrowCurveOffset: CGPoint(x: -20, y: 40),
                    bubblePlacement: .bottom,
                    titleEN: "Local AI Models",
                    descriptionEN: "Download offline Whisper models for speech recognition and MLX models for translation and text polishing. Once downloaded, VaniScript works 100% privately and offline.",
                    titleRU: "Локальные модели AI",
                    descriptionRU: "Загрузите оффлайн-модели Whisper для распознавания речи и модели MLX для перевода и полировки. Это позволит работать полностью локально и конфиденциально без интернета."
                ),
                TourStep(
                    targetSelector: "settings-tab-6",
                    arrowCurveOffset: CGPoint(x: -20, y: 40),
                    bubblePlacement: .bottom,
                    titleEN: "AI Prompts Customization",
                    descriptionEN: "Fine-tune system instructions sent to cloud and local MLX models for punctuation alignment, grammar polishing, translation, and summaries.",
                    titleRU: "Настройка промптов",
                    descriptionRU: "Отредактируйте системные инструкции (промпты) для ИИ при расстановке пунктуации, полировке грамматики, переводе и резюмировании."
                ),
                TourStep(
                    targetSelector: "settings-tab-7",
                    arrowCurveOffset: CGPoint(x: -20, y: 40),
                    bubblePlacement: .bottom,
                    titleEN: "Language Defaults",
                    descriptionEN: "Set the default source language of your recordings (or auto-detect) and select the default translation target language.",
                    titleRU: "Языки по умолчанию",
                    descriptionRU: "Задайте язык оригинала по умолчанию (или включите автоопределение) и выберите целевой язык для перевода."
                )
            ]
        case "visualEditor":
            return [
                TourStep(
                    targetSelector: "alignment-lang-toggle",
                    arrowCurveOffset: CGPoint(x: -30, y: 40),
                    bubblePlacement: .bottom,
                    titleEN: "Source / Target Toggle",
                    descriptionEN: "Switch between editing your Source (original) and Target (translation) subtitles.",
                    titleRU: "Выбор языка субтитров",
                    descriptionRU: "Переключаетесь между редактированием оригинальных (Source) и переведённых (Target) субтитров."
                ),
                TourStep(
                    targetSelector: "btn-dl-sync",
                    arrowCurveOffset: CGPoint(x: -30, y: 40),
                    bubblePlacement: .bottom,
                    titleEN: "Bilingual Sync",
                    descriptionEN: "When Sync is enabled, visual styling and keyframes are automatically mirrored between Source and Target languages.",
                    titleRU: "Двуязычная синхронизация",
                    descriptionRU: "При включенной синхронизации визуальные стили и ключевые кадры автоматически копируются между языками."
                ),
                TourStep(
                    targetSelector: "alignment-preview",
                    arrowCurveOffset: CGPoint(x: 40, y: -30),
                    bubblePlacement: .bottom,
                    titleEN: "Video Preview & Panning",
                    descriptionEN: "Watch the video. You can drag and zoom the video inside this frame to set keyframes and follow the lecturer.",
                    titleRU: "Превью и позиционирование видео",
                    descriptionRU: "Вы можете перетаскивать и масштабировать видео внутри этой рамки, чтобы настраивать ключевые кадры следования за спикером."
                ),
                TourStep(
                    targetSelector: "alignment-multitrack",
                    arrowCurveOffset: CGPoint(x: 0, y: -60),
                    bubblePlacement: .top,
                    titleEN: "Captions Timeline",
                    descriptionEN: "Adjust individual word timings! Click and drag words to align them precisely with the audio waveform.",
                    titleRU: "Таймлайн субтитров",
                    descriptionRU: "Настраивайте тайминг отдельных слов! Перетаскивайте и выравнивайте слова по звуковой волне для идеальной синхронизации."
                ),
                TourStep(
                    targetSelector: "alignment-right",
                    arrowCurveOffset: CGPoint(x: -60, y: 40),
                    bubblePlacement: .left,
                    titleEN: "Visual Inspector",
                    descriptionEN: "Customize subtitle fonts, colors, background styles, add logos, text overlays, or extra audio tracks in separate layers.",
                    titleRU: "Инспектор стилей",
                    descriptionRU: "Настраивайте шрифты, цвета, стили фона, добавляйте логотипы, текстовые слои или дополнительные аудиодорожки."
                ),
                TourStep(
                    targetSelector: "alignment-save-btn",
                    arrowCurveOffset: CGPoint(x: -40, y: 40),
                    bubblePlacement: .bottom,
                    titleEN: "Save Edits",
                    descriptionEN: "Make sure to save your edits! Click this button to save your changes and continue refining your clip.",
                    titleRU: "Сохранение изменений",
                    descriptionRU: "Обязательно сохраняйте изменения! Нажмите кнопку \"Save edits\", чтобы записать прогресс."
                )
            ]
        default:
            return []
        }
    }
}
