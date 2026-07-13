# Сценарий для NotebookLM - VaniScript Apple Silicon

Использовать как основной русский сценарий для генерации видео. Тон: спокойный, практичный, tutorial/onboarding. Аудитория - новый пользователь, которому нужно понять полный путь в нативной Apple Silicon-версии.

## Название

VaniScript Apple Silicon: от лекции к транскрипту, переводу и Shorts

## Длина

10-14 минут.

## Глава 1 - Что это за приложение

Визуал: `screenshots/01-upload-workspace.png`

Текст:

Добро пожаловать в VaniScript Apple Silicon. Это VaniScript для macOS на Apple Silicon.

Приложение предназначено для длинных аудио и видео: лекций, классов, интервью и devotional-записей. Пользователь загружает источник, настраивает модели и язык, обрабатывает материал по чанкам, проверяет оригинал и перевод, а затем экспортирует документы или создает вертикальные клипы.

Акцент на экране:

- native Apple Silicon;
- local-first workflow;
- transcription, translation, review, export, clips.

## Глава 2 - Начинаем с источника

Визуал: `screenshots/02-upload-workspace-clean.png`

Текст:

Первый экран - Upload. Здесь новичок выбирает, откуда взять материал.

Upload Audio / Video - для файла на Mac. Record Audio Source - для записи нового источника. Import Link - для импорта по ссылке.

Для первого проекта лучше выбрать локальный файл. Так пользователь сразу увидит основной workflow VaniScript без сетевых проблем.

## Глава 3 - Настройки провайдеров

Визуал: `screenshots/03-settings-api-usage.png`

Текст:

Перед серьезной обработкой нужно открыть Settings. Раздел API & Usage показывает cloud-провайдеры, ключи, usage и logs.

VaniScript может работать локально, через cloud или гибридно. Но даже если используется Gemini или OpenAI, это все равно native Apple Silicon app. Интерфейс, storage, review и export остаются нативными.

## Глава 4 - Локальные модели

Визуал: `screenshots/04-settings-models.png`

Текст:

Models - ключевой экран Apple Silicon-версии. Локальная транскрипция использует WhisperKit/Core ML. Локальный перевод и text generation используют MLX Swift.

Если модель не установлена или не найдена, приложение не должно начинать обработку. Оно проверяет готовность провайдера. Пользователь может scan, locate, download или выбрать другой provider.

## Глава 5 - Глоссарий

Визуал: `screenshots/05-settings-glossary.png`

Текст:

Глоссарий нужен для последовательности терминов. Для devotional и philosophical материала это особенно важно: имена, санскритские слова, места, титулы и традиционные термины должны быть стабильными.

Пользователь добавляет source term, translation, variants and category. Во время review можно добавлять новые термины.

## Глава 6 - Промпты

Визуал: `screenshots/06-settings-prompts.png`

Текст:

Prompts показывают, что VaniScript можно адаптировать. Здесь есть шаблоны для transcription, translation, editing, Shorts/Reels and export.

Новичок может оставить defaults. Опытный пользователь может настроить стиль, точность терминов и формат результата.

## Глава 7 - Sessions

Визуал: `screenshots/08-sessions-sidebar-real-project.png`

Текст:

Каждая большая работа становится сессией. В Sessions sidebar видно проект, source media, chunks, progress, target language and export action.

Это важно для длинных лекций. Можно закрыть приложение, вернуться позже, перейти к нужному чанку и продолжить.

## Глава 8 - Review в Dual View

Визуал: `screenshots/10-review-dual-mode.png`

Текст:

Review workspace - сердце приложения. В Dual View слева оригинал, справа русский перевод. Оба текста разбиты на timed cues.

Пользователь слушает текущий сегмент, сверяет смысл, исправляет ошибки, добавляет термины в glossary и подтверждает чанк. Если нужно, можно повторить transcription, regenerate timings или retry translation.

Главная идея: VaniScript не просит слепо доверять модели. Он дает человеку удобное место для проверки.

## Глава 9 - Экспорт документов

Визуал: `screenshots/12-export-workspace.png`

Текст:

После проверки пользователь переходит в Export. Верхняя часть экрана отвечает за документы: original and target TXT, SRT, VTT and Markdown.

Экспорт строится из reviewed session. Все исправления, glossary decisions и approved cues переходят в итоговый файл.

## Глава 10 - Shorts/Reels

Визуал: `screenshots/12-export-workspace.png`

Текст:

В этом же экране VaniScript может планировать Shorts и Reels. Пользователь выбирает количество клипов, минимальную и максимальную длину, язык: Source, Target или Source + Target.

После этого появляются карточки клипов: title, timing, duration, summary, category and actions. Клип можно открыть в визуальном редакторе.

## Глава 11 - Visual Clip Editor

Визуал: `screenshots/13-visual-editor.png`

Текст:

Visual Clip Editor превращает выбранный момент в вертикальный клип. В этом NotebookLM-safe скриншоте исходное видео заменено нейтральной графикой, но интерфейс всё равно показывает vertical crop, caption overlay area, waveform, subtitle timeline and inspector.

Справа находится inspector. Здесь настраиваются style, frame animation, font, size, outline, shadow, box, opacity, zoom, pan and keyframes.

Когда пользователь нажимает Save edits, настройки сохраняются в render plan клипа.

## Глава 12 - Финальный экспорт

Визуал: `screenshots/12-export-workspace.png`

Текст:

Вернувшись в Export, пользователь выбирает MP4 или MOV, resolution and frame rate. Затем экспортирует selected videos.

Итоговый путь завершен: один длинный source file превратился в проверенный transcript, перевод, subtitles and vertical clips.

## Финальный текст

VaniScript Apple Silicon - это нативная review-studio, а не просто кнопка транскрипции. Сильная сторона приложения в полном пути: source media, model configuration, glossary consistency, timed review, document export, Shorts/Reels planning and visual clip editing.

Для первого проекта безопасный путь такой: загрузить локальный файл, проверить модели, обработать по чанкам, пройти Review в Dual View, экспортировать документы, а затем создать клипы из утвержденного текста.

Финальный экран:

VaniScript Apple Silicon
Native transcription, translation, review and clip export for macOS.

## Дополнительная раскадровка для NotebookLM

Если NotebookLM делает не просто короткий обзор, а полноценный video tutorial, можно использовать расширенную структуру.

### Сцена A - Orientation

Визуал: `screenshots/01-upload-workspace.png`

Текст ведущего:

"Сначала важно понять, что VaniScript Apple Silicon - это единый рабочий процесс внутри macOS app: source media, local models, review, export and visual editing."

На экране выделить:

- Upload;
- guided tour;
- Apple Silicon framing.

### Сцена B - Three input paths

Визуал: `screenshots/02-upload-workspace-clean.png`

Текст ведущего:

"У пользователя есть три входа. Первый - файл. Второй - запись. Третий - ссылка. Для обучения лучше начинать с файла, потому что это самый стабильный и понятный путь."

На экране выделить:

- Upload Audio / Video;
- Record Audio Source;
- Import Link.

### Сцена C - Why settings matter

Визуал: `screenshots/03-settings-api-usage.png`

Текст ведущего:

"Перед обработкой нужно понять, чем именно будет работать приложение. Если вы хотите cloud workflow, здесь добавляются API keys. Если вы хотите local-first workflow, убедитесь, что локальные модели готовы."

### Сцена D - Local model confidence

Визуал: `screenshots/04-settings-models.png`

Текст ведущего:

"Apple Silicon-версия раскрывается через локальные модели. WhisperKit/Core ML отвечает за локальную транскрипцию, MLX Swift - за локальный перевод и генерацию текста. Если модель не найдена, обработка не должна стартовать случайно."

### Сцена E - Glossary as quality control

Визуал: `screenshots/05-settings-glossary.png`

Текст ведущего:

"Для devotional-контента glossary - это не украшение. Это механизм точности. Он помогает одинаково писать имена, санскритские термины, места, титулы и философские понятия."

### Сцена F - Prompt presets

Визуал: `screenshots/06-settings-prompts.png`

Текст ведущего:

"Prompts позволяют адаптировать поведение VaniScript. Новичок может не трогать их сразу. Но если у вас есть особый стиль перевода или терминология, этот раздел становится важным."

### Сцена G - Saved sessions

Визуал: `screenshots/08-sessions-sidebar-real-project.png`

Текст ведущего:

"Каждая большая работа сохраняется как session. Здесь видно исходный файл, progress, chunks and export. Это значит, что длинную лекцию не нужно проходить за один раз."

### Сцена H - Human review

Визуал: `screenshots/10-review-dual-mode.png`

Текст ведущего:

"Review - главный экран качества. Слева оригинал, справа перевод. Пользователь слушает сегмент, правит текст, сверяет смысл, добавляет glossary terms и подтверждает только проверенный chunk."

### Сцена I - Export is based on approval

Визуал: `screenshots/12-export-workspace.png`

Текст ведущего:

"Экспорт появляется после review. Поэтому документы и субтитры строятся не из сырого ответа модели, а из проверенной сессии."

### Сцена J - From long lecture to clips

Визуал: `screenshots/12-export-workspace.png`

Текст ведущего:

"Тот же экран помогает найти короткие моменты для Shorts and Reels. Пользователь выбирает количество клипов, длину и язык, а VaniScript создает карточки с timing, title and summary."

### Сцена K - Visual editor

Визуал: `screenshots/13-visual-editor.png`

Текст ведущего:

"Здесь выбранный момент превращается в вертикальное видео. В этом safe-кадре вместо исходного видео показана нейтральная графика, но структура редактора видна полностью: crop frame, captions area, waveform, subtitle blocks and inspector. Пользователь может настроить style, frame, subtitles and keyframes."

### Сцена L - Closing

Визуал: снова `screenshots/13-visual-editor.png` или `screenshots/12-export-workspace.png`

Текст ведущего:

"В итоге VaniScript Apple Silicon закрывает полный цикл: long-form media in, reviewed transcript out, translated subtitles out, and optional vertical clips out. Это нативный Apple Silicon workflow для серьезной работы с лекциями и devotional media."

## Короткий вариант voiceover для финального слайда

"VaniScript Apple Silicon объединяет транскрипцию, перевод, human review, glossary consistency, document export and visual clip editing. Главное - не пропускать review. Именно там модельный черновик превращается в качественный материал для публикации, архива или видео."
