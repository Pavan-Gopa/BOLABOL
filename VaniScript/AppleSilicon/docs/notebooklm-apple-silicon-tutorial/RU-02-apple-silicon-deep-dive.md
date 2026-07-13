# VaniScript Apple Silicon - подробный разбор

Этот документ глубоко разбирает нативную Apple Silicon-версию VaniScript. Он предназначен для NotebookLM, чтобы из него можно было сделать подробную презентацию или видеоонбординг.

## 1. Граница продукта

VaniScript Apple Silicon - это VaniScript для macOS на Apple Silicon.

Ключевые признаки:

- проект Swift Package Manager в `VaniScript/AppleSilicon`;
- SwiftUI/AppKit desktop app;
- цель macOS 14+;
- ориентация на Apple Silicon;
- bundle id `com.vaniscript.apple-silicon`;
- локальная транскрипция через WhisperKit/Core ML;
- локальная языковая обработка через MLX Swift;
- медиа через AVFoundation;
- визуальный рендер через AVFoundation/Metal.

Cloud-провайдеры могут использоваться дополнительно, но это не меняет природу приложения: UI, project storage, media workflow и editor остаются нативными.

## 2. Философия runtime

Apple Silicon-версия построена как local-first professional workflow.

Local-first означает:

- проекты хранятся на Mac пользователя;
- записи и импорты сохраняются локально;
- локальные модели можно обнаруживать и использовать прямо на Mac;
- глоссарий и настройки локальные;
- экспорт создается локально;
- логи пишутся локально.

Hybrid означает:

- можно подключить Gemini/OpenAI или другие cloud-провайдеры;
- ключи и usage видны в Settings;
- приложение проверяет готовность провайдера.

Правильная формулировка: это нативное local-first приложение с optional cloud providers.

## 3. Workflow screens

Основные экраны:

- `upload`;
- `config`;
- `processing`;
- `review`;
- `export`;
- `visualEditor`.

Нормальная последовательность:

1. Upload - выбор файла, записи или ссылки.
2. Config - метаданные, язык, провайдеры, форматы, чанки.
3. Processing - обработка.
4. Review - проверка оригинала и перевода.
5. Export - документы и Shorts/Reels.
6. Visual Editor - монтаж выбранного клипа.

## 4. App shell

Главный SwiftUI-shell использует общий `WorkflowStore`. Он хранит workflow, session, settings, список проектов, processing pipeline, playback, import/export state, visual editor draft, onboarding и status messages.

Router показывает нужный workspace в зависимости от состояния. Это важно для обучения: пользователь идет по понятной линии, а не прыгает между несвязанными инструментами.

## 5. Источники медиа

### Local file upload

Пользователь выбирает файл на Mac. Приложение анализирует duration, codecs, resolution, frame rate, bitrate, sample rate, channels и другие параметры.

### Recording

Можно записывать новый источник. Для микрофона нужны microphone permissions. Для системного аудио могут понадобиться Screen Recording permissions.

### Link import

Импорт по ссылке использует media resolver/helper tools. Это отдельный путь получения медиа внутри общего VaniScript workflow.

## 6. Configuration и readiness

На экране конфигурации пользователь выбирает:

- metadata;
- target language;
- transcription provider;
- translation provider;
- output formats;
- chunk duration;
- slicing mode.

Readiness checks не дают запустить обработку, если выбранный провайдер не готов. Например, нет локальной WhisperKit-модели, нет MLX-модели, нет API key или провайдер недоступен.

## 7. Chunk planning

Длинное медиа разбивается на чанки.

Это нужно, чтобы:

- проверять по сегментам;
- не переделывать весь проект из-за одного сбоя;
- сохранять progress;
- экспортировать из approved chunks;
- планировать Shorts/Reels по timed text.

Есть фиксированная нарезка и более умная аудио-aware нарезка по energy/silence.

## 8. Transcription pipeline

Локальный путь транскрипции использует WhisperKit/Core ML.

Логика:

1. Проверить готовность провайдера.
2. Найти audio для текущего chunk.
3. Создать chunk media при необходимости.
4. Запустить transcription.
5. Получить text/cues/word timestamps, если доступны.
6. Сохранить original text and timed cues.
7. Обновить status chunk.

Runtime модели кэшируется, чтобы не перезагружать все заново без необходимости.

## 9. Translation и MLX

Локальный путь перевода и генерации текста использует MLX Swift.

Через MLX или cloud-провайдеры могут выполняться:

- translation;
- cue translation;
- polishing;
- transcript formatting;
- Shorts/Reels planning;
- clip metadata translation.

Session хранит active translation language, available languages, translation archive, translated text, translated cues and output formats.

## 10. Glossary

Глоссарий стабилизирует терминологию.

Entry может содержать:

- source term;
- translation;
- variants;
- category;
- target language adaptation.

Для devotional/philosophical материала это критично: имена, санскрит, места и титулы должны быть последовательными.

## 11. Review workspace

Review workspace дает:

- playback текущего сегмента;
- source-only, translated-only, dual view;
- timed source cues;
- timed translated cues;
- editing;
- glossary insertion;
- retry transcription;
- retry translation;
- regenerate timing;
- add translation language;
- approve and advance;
- complete/export.

Это основной экран человеческой проверки.

## 12. Project storage

Данные хранятся локально в Application Support пользователя.

Типы данных:

- settings JSON;
- projects JSON;
- project asset folders;
- recordings;
- imported media;
- helper binaries for media workflows;
- logs.

Session хранит chunks, cues, translations, approvals, Shorts/Reels plans and visual editor state.

## 13. Project bundles

`.vaniscript` - формат обмена проектами VaniScript. Он сохраняет session data и assets.

Такой bundle нужен для архива, переноса и совместной работы. Import нормализует данные, чтобы текущая версия приложения могла открыть старые или альтернативные структуры.

## 14. Settings

API & Usage: cloud keys, usage, providers, logs.

Models: WhisperKit/Core ML and MLX model discovery, download, locate, delete.

Appearance: theme and display preferences.

Glossary: terms, variants, categories, import/export.

Chunking: length and slicing mode.

Transcription: ASR defaults.

Prompts: presets for transcription, translation, editing, Shorts/Reels and export.

## 15. Export workspace

Export имеет два больших направления.

Documents:

- source transcript;
- target transcript;
- TXT/SRT/VTT/Markdown-style exports.

Shorts/Reels:

- number of clips;
- min/max duration;
- source/target/bilingual planning;
- clip cards;
- details/replace/delete/edit;
- JSON/TXT ideas export;
- selected video export.

## 16. Visual Clip Editor

Visual Clip Editor включает:

- Source/Target toggle;
- Sync;
- vertical crop preview;
- dimmed outside frame;
- subtitles;
- playback;
- waveform;
- video/audio/subtitle timeline;
- subtitle blocks;
- caption editor;
- word chips;
- split/merge/delete;
- text overlays;
- background and frame controls;
- style inspector;
- keyframes;
- layers;
- save/reset/undo/redo.

Редактор сохраняет настройки обратно в Shorts/Reels plan. Export использует эти настройки при рендере.

## 17. Native rendering

Рендер строится на native media APIs.

Render plan содержит:

- timing;
- crop/frame state;
- subtitles;
- overlays;
- background;
- logo;
- audio tracks;
- intro/outro;
- output size;
- frame rate.

AVFoundation собирает и экспортирует медиа, а Metal-backed composition используется для визуальных элементов.

## 18. Что именно Apple Silicon-specific

Главные признаки:

- SwiftUI native desktop UI;
- native app bundle;
- Core ML/WhisperKit local ASR;
- MLX Swift local text generation;
- AVFoundation media inspection, slicing, playback, export;
- native permissions for recording;
- local project storage;
- Apple Silicon model management and readiness checks.

## 19. Практический итог

Объяснять VaniScript нужно как нативную review-studio:

1. Import/record source.
2. Confirm models/providers.
3. Configure metadata and language.
4. Process chunks.
5. Review source and translation.
6. Use glossary and retries.
7. Approve chunks.
8. Export transcripts.
9. Plan Shorts/Reels.
10. Edit clips visually.
11. Export final videos.
12. Reopen/share through sessions and project bundles.

## 20. Важные детали данных сессии

Session state - это не просто текст транскрипта. Внутри сессии хранятся взаимосвязанные слои данных:

- source file and source media info;
- duration and technical metadata;
- project metadata: date, location, lecturer, participants;
- chunks;
- current chunk index;
- original text per chunk;
- original cues and word timings;
- translated text;
- translated cues;
- available translation languages;
- active translation language;
- provider choices;
- approved state;
- output formats;
- Shorts/Reels plans;
- rejected Shorts/Reels plans;
- visual editor state.

Именно поэтому VaniScript может открыть старый проект не как плоский текстовый файл, а как полноценную рабочую сессию: с чанками, переводами, клипами, visual settings and export readiness.

## 21. Почему chunk-based workflow важнее single-pass генерации

Обычный single-pass transcript workflow неудобен для длинных лекций. Если модель ошиблась в середине, пользователю приходится искать место вручную. Если перевод слабый, неясно, какая часть исходника его вызвала. Если нужно сделать subtitles, таймкоды могут быть слишком грубыми.

VaniScript решает это через chunks and timed cues.

Практические преимущества:

- можно слушать только текущий segment;
- можно повторить transcription только для одного segment;
- можно повторить translation только для одного segment;
- approval показывает реальный progress;
- export строится из verified pieces;
- Shorts planner может опираться на timed transcript;
- visual editor может использовать alignments and caption blocks.

## 22. Отличие local provider, cloud provider и downloaded local model

В Settings и provider registry важно различать три режима.

Local provider - это встроенный native path: WhisperKit/Core ML для ASR и MLX Swift для language generation.

Downloaded local model - это конкретная найденная или скачанная модель, которая появляется как доступный provider option, если она валидна.

Cloud provider - это внешний API, например Gemini или OpenAI. Он требует key, может иметь usage limits and cost tracking, но не меняет native shell приложения.

В onboarding это нужно объяснять просто: "Вы можете работать локально, если модели установлены, или подключить cloud, если хотите использовать внешний provider."

## 23. Почему visual editor является отдельным workspace

Visual editor в Apple Silicon-версии - это не modal preview. Он имеет собственный route `visualEditor`. Это важно, потому что работа с клипом сложная:

- нужно видеть большой preview;
- нужен timeline;
- нужен waveform;
- нужны subtitle blocks;
- нужен inspector;
- нужны source/target modes;
- нужны frame keyframes;
- нужны layers and overlays;
- нужен save/reset workflow.

Если бы это было маленькое modal window, пользователь не смог бы качественно подготовить вертикальное видео. Поэтому tutorial должен показывать visual editor как полноценный этап после export planning.

## 24. Как объяснять native rendering

Native rendering означает, что visual editor settings превращаются в структуру, которую native renderer может использовать для финального видео:

- frame crop;
- subtitle style;
- keyframes;
- text overlays;
- background settings;
- logo;
- audio tracks;
- intro/outro;
- output resolution;
- output frame rate.

После этого AVFoundation and Metal-backed compositor создают финальный файл. Для пользователя это значит: если он настроил crop, subtitles and style в visual editor, эти настройки должны перейти в экспорт.

## 25. Риски и ограничения, которые стоит честно упомянуть

Apple Silicon workflow зависит от готовности моделей и прав macOS.

Типичные ограничения:

- local models занимают место на диске;
- большие видео требуют больше памяти и времени;
- system audio recording требует разрешений macOS;
- cloud providers требуют ключи и могут стоить денег;
- link import зависит от доступности источника и resolver tools;
- если source file перемещен или удален, visual export может не найти медиа.

Это не минусы приложения, а нормальные свойства professional media workflow. Хороший onboarding должен заранее сказать пользователю, где возникают эти условия.

## 26. Главная техническая формулировка

VaniScript Apple Silicon - это native macOS project-based workflow. Он соединяет source media ingestion, local/cloud AI providers, glossary-aware review, chunked session state, transcript export, Shorts/Reels planning and native video rendering.
