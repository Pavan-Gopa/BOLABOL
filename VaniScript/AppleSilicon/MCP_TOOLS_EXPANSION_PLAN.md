# VaniScript MCP Tools Expansion Plan

## 1. Цель

Расширить MCP-интерфейс VaniScript с текущих 9 инструментов до полноценного
набора управления приложением из встроенного чата. Целевой каталог этого плана:

- 9 существующих инструментов;
- 111 новых инструментов;
- 120 инструментов после завершения всех этапов.

Это не означает, что все 120 определений нужно всегда отправлять агенту.
Инструменты должны быть разделены на группы и выдаваться клиенту в зависимости
от разрешений и доступного состояния проекта. Это уменьшит контекст, повысит
точность выбора инструмента и не даст агенту случайно вызвать опасную операцию.

## 2. Что уже реализовано

Текущий MCP-контур предоставляет:

1. `get_project_state`
2. `get_subtitle_style`
3. `get_shorts_plans`
4. `update_chunk_text`
5. `approve_chunk`
6. `update_subtitle_style`
7. `update_cue_timestamps`
8. `align_translation_timings`
9. `reprocess_chunk`

Сильные стороны текущей реализации:

- сервер доступен только через loopback;
- доступ защищён bearer token;
- секреты провайдеров не входят в снимок проекта;
- read-only режим действительно скрывает изменяющие инструменты;
- индексы валидируются как конечные целые числа;
- после изменений проект сохраняется.

Текущие ограничения:

- `WorkflowStore.executeMcpTool` станет слишком большим при добавлении десятков
  команд;
- права делятся только на `read` и `write`, чего недостаточно для файлов,
  сетевых операций, моделей и удаления данных;
- `get_project_state` возвращает крупный непагинированный снимок;
- большинство команд обращаются к чанку по хрупкому `chunkIndex`;
- нет общей модели долгих заданий, прогресса, отмены и истории результатов;
- нет optimistic concurrency, поэтому агент может перезаписать более свежую
  пользовательскую правку;
- часть Visual Editor живёт в локальном состоянии SwiftUI view и пока не может
  безопасно вызываться из MCP;
- файловые команды используют системные панели, что не подходит для фонового
  вызова агентом.

## 3. Обязательная архитектура перед массовым расширением

### 3.1. Стабильные идентификаторы

Каждый проект, чанк, cue, Shorts plan, дорожка и блок должен приниматься по
стабильному ID. В ответах одновременно возвращаются:

- `id` — стабильный идентификатор для следующего MCP-вызова;
- `displayNumber` — человеческий номер, например `5`;
- `arrayIndex` — только диагностическое поле.

Существующие команды с `chunkIndex` сохраняются для совместимости, но получают
поддержку `chunkId` и помечаются устаревающими. Это устраняет путаницу между
видимым «Chunk 5» и индексом `4`.

### 3.2. Сервисный слой

MCP не должен напрямую имитировать нажатия SwiftUI-кнопок. Нужны общие сервисы,
которыми пользуются и интерфейс, и MCP:

- `ProjectCommandService`
- `WorkflowCommandService`
- `TranscriptCommandService`
- `TranslationCommandService`
- `GlossaryCommandService`
- `ShortsCommandService`
- `VisualEditorCommandService`
- `ExportCommandService`
- `ModelCommandService`

`WorkflowStore` остаётся координатором состояния, а регистрация, валидация и
исполнение MCP-команд выносятся из одного большого `switch`.

### 3.3. Права доступа

Вместо одного переключателя `Allow Write Tools` нужны отдельные scopes:

1. `Read Project` — чтение состояния, поиск, проверки.
2. `Edit Project` — текст, тайминги, glossary, параметры Shorts.
3. `Run Processing` — транскрибация, перевод, reprocess, AI-polish.
4. `Files & Export` — импорт файлов, создание экспортов, reveal.
5. `Network & Models` — URL import и загрузка моделей.
6. `Destructive Actions` — удаление проектов, моделей и монтажных элементов.

По умолчанию разрешаются только `Read Project` и явно включённый пользователем
`Edit Project`. Остальные scopes включаются отдельно.

### 3.4. Долгие задания

Транскрибация, перевод всех чанков, генерация Shorts, рендер, импорт URL и
загрузка моделей должны немедленно возвращать `jobId`. Общий формат задания:

- `status`: `queued`, `running`, `succeeded`, `failed`, `cancelled`;
- `progress`: число от 0 до 1;
- `stage` и безопасное пользовательское сообщение;
- `startedAt`, `updatedAt`, `finishedAt`;
- структурированный результат или ошибка;
- возможность `cancel_job` для отменяемых операций.

### 3.5. Защита изменений

Каждая изменяющая команда должна поддерживать:

- `expectedRevision` — отказ при устаревшем состоянии;
- `requestId` — идемпотентность повторного запроса;
- `dryRun` — предварительный расчёт затронутых сущностей;
- `changeSetId` — запись в журнале изменений;
- атомарное сохранение проекта после успешной транзакции.

Удаление проекта, модели или массовая замена требуют двух шагов:
сначала `dryRun`, затем вызов с короткоживущим `confirmationToken`.

### 3.6. Безопасность файлов и секретов

- MCP никогда не читает и не возвращает API keys, MCP token и пароли.
- Агент не получает произвольный доступ ко всей файловой системе.
- Импорт разрешается только для пользовательски выбранного файла, security
  scoped bookmark или заранее разрешённой папки.
- Экспорт принимает `destinationId`, полученный после выбора папки
  пользователем, а не произвольный путь.
- URL import проверяет схему, размер, тип контента, redirects и локальные адреса.
- Логи очищаются от токенов, ключей, полного Authorization header и приватных
  путей, если они не нужны для диагностики.

### 3.7. Ответы и ошибки

Крупные списки получают `limit`, `cursor`, `hasMore` и `fields`. Ошибки должны
иметь стабильные коды, например:

- `NO_ACTIVE_PROJECT`
- `ENTITY_NOT_FOUND`
- `STALE_REVISION`
- `PERMISSION_DENIED`
- `CONFIRMATION_REQUIRED`
- `VALIDATION_FAILED`
- `JOB_ALREADY_RUNNING`
- `PROVIDER_NOT_READY`

## 4. Каталог новых инструментов

### A. Состояние, задания и аудит — 8

1. `get_capabilities` — доступные группы, permissions и ограничения.
2. `get_ui_state` — активный экран, выделение, выбранный чанк и редактор.
3. `get_processing_status` — текущая стадия pipeline и прогресс.
4. `list_jobs` — список фоновых заданий с пагинацией.
5. `get_job` — подробный статус одного задания.
6. `cancel_job` — отмена поддерживаемого задания.
7. `get_change_history` — журнал агентских и пользовательских изменений.
8. `validate_active_project` — целостность проекта и список проблем.

### B. Проекты и исходные медиа — 11

1. `list_projects`
2. `get_project_summary`
3. `open_project`
4. `save_project`
5. `reset_session`
6. `import_media_file`
7. `import_media_url`
8. `get_source_media_info`
9. `import_project_bundle`
10. `export_project_bundle`
11. `delete_project`

`delete_project` относится к destructive scope. Импорт URL относится к network
scope. Импорт и экспорт bundle используют разрешённые пользователем locations.

### C. Workflow и обработка — 6

1. `get_workflow_config`
2. `update_workflow_config`
3. `start_processing`
4. `cancel_processing`
5. `retry_failed_chunks`
6. `select_chunk`

Конфигурация включает source/target language, providers, formats и параметры
chunking, но не секреты провайдеров.

### D. Транскрипт и Review — 13

1. `list_chunks`
2. `get_chunk`
3. `get_chunk_cues`
4. `get_unrecognized_fragments`
5. `search_transcript`
6. `replace_transcript_text`
7. `batch_update_chunk_text`
8. `update_cue_text`
9. `insert_cue`
10. `delete_cue`
11. `split_cue`
12. `merge_cues`
13. `batch_approve_chunks`

Массовая замена сначала возвращает preview: совпадения, контекст и число
затрагиваемых чанков. Агент не должен делать blind global replace.

### E. Перевод и редактирование — 9

1. `list_translation_languages`
2. `select_translation_language`
3. `add_translation_language`
4. `remove_translation_language`
5. `translate_chunk`
6. `translate_cue`
7. `translate_pending_chunks`
8. `retry_chunk_translation`
9. `polish_translation`

`polish_translation` принимает область (`selection`, `cue`, `chunk`, `project`)
и всегда сохраняет исходную версию в change history.

### F. Glossary — 9

1. `list_glossary_entries`
2. `search_glossary`
3. `create_glossary_entry`
4. `update_glossary_entry`
5. `delete_glossary_entry`
6. `apply_glossary_entry`
7. `apply_glossary_all`
8. `import_glossary`
9. `export_glossary`

Применение поддерживает scope `currentChunk`, `selectedChunks` или `project` и
сначала показывает количество замен.

### G. Shorts planning — 11

1. `generate_shorts_plans`
2. `get_shorts_plan`
3. `create_shorts_plan`
4. `update_shorts_plan`
5. `update_shorts_timing`
6. `remove_shorts_plan`
7. `list_rejected_shorts_plans`
8. `restore_shorts_plan`
9. `translate_shorts_plans`
10. `validate_shorts_plan`
11. `open_visual_editor`

Проверка плана выявляет выход за duration, пустые титры, конфликт cuts, слишком
короткие/длинные клипы и отсутствие обязательных дорожек.

### H. Visual Editor — 16

1. `get_visual_editor_state`
2. `update_clip_details`
3. `update_clip_timing`
4. `manage_timeline_cut`
5. `manage_subtitle_segment`
6. `set_frame_keyframes`
7. `clear_frame_keyframes`
8. `update_visual_background`
9. `update_visual_logo`
10. `update_intro_outro`
11. `set_visual_sync`
12. `manage_text_track`
13. `manage_text_block`
14. `manage_audio_track`
15. `save_visual_editor`
16. `update_visual_subtitle_style`

Команды `manage_*` используют строгий `action` enum (`create`, `update`,
`delete`; для субтитров также `split`, `merge`) и типизированные payloads. Это
сохраняет полный функционал, не раздувая список ещё на 20 почти одинаковых
CRUD-команд.

До реализации этой группы операции split/merge/cuts/tracks следует вынести из
локального состояния `VisualClipEditorView` в `VisualEditorCommandService`.

### I. Playback и export — 10

1. `get_playback_state`
2. `play_chunk`
3. `pause_playback`
4. `seek_playback`
5. `list_export_options`
6. `validate_export`
7. `export_transcript`
8. `export_shorts_ideas`
9. `export_shorts_videos`
10. `reveal_export`

Экспорт видео возвращает `jobId`. `validate_export` выполняет preflight моделей,
FFmpeg/рендера, исходного файла, duration, разрешения и места назначения.

### J. Settings, providers, prompts и models — 13

1. `get_safe_settings`
2. `update_safe_settings`
3. `list_providers`
4. `select_provider`
5. `list_prompt_presets`
6. `get_prompt`
7. `update_prompt`
8. `reset_prompt`
9. `get_model_status`
10. `scan_local_models`
11. `download_model`
12. `locate_model`
13. `remove_model`

Ни один settings-инструмент не возвращает и не принимает API keys. Ключи
остаются только в защищённом пользовательском интерфейсе/Keychain. Загрузка и
удаление моделей требуют отдельных scopes; удаление требует подтверждения.

### K. Help & Onboarding — 5

1. `list_help_topics` — категории и доступные темы справки.
2. `get_help_topic` — подробная инструкция с последовательностью действий.
3. `search_help` — поиск релевантных инструкций по вопросу пользователя.
4. `get_contextual_help` — помощь с учётом текущего экрана и состояния проекта.
5. `get_onboarding_checklist` — пользовательский путь от первого запуска до
   готового экспорта.

Справка должна описывать реальные элементы интерфейса и точные переходы:
какой экран открыть, какую кнопку нажать, какие предварительные условия нужны,
почему команда может быть недоступна и что делать дальше. Ответы возвращаются
на языке запроса, а названия кнопок сохраняются такими, как они показаны в UI.

Help tools доступны в read-only режиме. Для вопроса о текущем проекте
`get_contextual_help` использует только безопасный снимок состояния и никогда
не возвращает ключи, токены или приватные настройки.

## 5. Порядок реализации

### Этап 0. MCP Foundation

- типизированный registry и отдельные tool handlers;
- scopes вместо бинарного read/write;
- стабильные entity IDs и project revision;
- общий `McpJobManager`;
- change history, dry-run и confirmation tokens;
- пагинация и стабильные error codes;
- tool annotations: read-only, destructive, idempotent, open-world;
- тесты на утечку секретов, права, stale revision и path traversal.

Результат: безопасная основа, на которой добавление инструментов не превращает
`WorkflowStore` в неуправляемый switch.

### Этап 1. Ежедневная работа с текстом

Реализовать группы A, C, D, E, F и K. Это самый полезный первый релиз: агент сможет
искать и исправлять текст, управлять cues, переводить, полировать, применять
glossary, повторять неудачные чанки, утверждать результат и давать новым
пользователям пошаговую помощь по приложению.

### Этап 2. Проекты, медиа и export

Реализовать группы B и I. Сначала безопасные read/open/save/export операции,
затем URL import и destructive actions. Убрать зависимость MCP от `NSOpenPanel`
и `NSSavePanel` через пользовательские destination grants.

### Этап 3. Shorts planning

Реализовать группу G, включая job progress, проверку результата и восстановление
отклонённых планов.

### Этап 4. Visual Editor

Сначала создать `VisualEditorCommandService` и перевести UI на него. После этого
реализовать группу H, единый undo/redo журнал и визуальный preflight перед
сохранением или экспортом.

### Этап 5. Settings, prompts и models

Реализовать группу J. Операции с моделями включать только после тестов загрузки,
отмены, checksum, нехватки места, удаления активной модели и восстановления.

### Этап 6. End-to-end hardening

- contract tests каждого JSON schema;
- happy path и ключевые ошибки каждого handler;
- тесты MCP initialize, tools/list, tools/call и cancellation;
- параллельные вызовы и stale-revision конфликты;
- перезапуск приложения во время job;
- восстановление проекта после неудачного сохранения;
- реальные сценарии встроенного Codex-чата;
- проверка, что UI и MCP дают одинаковый результат;
- документация с примерами команд и permissions.

## 6. Как не перегрузить агента 120 инструментами

В Agents settings нужны включаемые группы:

- `Core & Review`
- `Help & Onboarding`
- `Translation & Glossary`
- `Projects & Files`
- `Shorts`
- `Visual Editor`
- `Models & System`

`get_capabilities` всегда доступен. Остальные определения фильтруются по scopes,
наличию активного проекта и включённым группам. При смене состояния сервер
отправляет `notifications/tools/list_changed`, если клиент это поддерживает.

Дополнительно стоит использовать MCP resources для чтения больших данных:

- `vaniscript://project/active`
- `vaniscript://project/active/chunks`
- `vaniscript://project/active/chunks/{chunkId}`
- `vaniscript://project/active/shorts/{planId}`

Инструменты выполняют действия, а resources отдают крупный контекст. Так агенту
не нужно каждый раз получать весь проект через `get_project_state`.

## 7. Целевые пользовательские сценарии

### Исправление транскрипта

> Найди все варианты написания имени, покажи совпадения, добавь правильную форму
> в glossary, примени её ко всему проекту, повторно переведи затронутые чанки и
> покажи изменения перед утверждением.

### Полный перевод и экспорт

> Переведи все ещё не переведённые чанки на русский, выровняй тайминги, найди
> пустые cues, исправь ошибки, утверди готовые чанки и экспортируй SRT и DOCX.

### Создание Shorts

> Найди пять самостоятельных фрагментов длительностью 35–60 секунд, подготовь
> заголовки и hooks, открой лучший план, добавь логотип и intro, проверь cuts и
> запусти вертикальный экспорт.

### Управление проектами

> Открой последний незавершённый проект, покажи проблемные чанки, повтори только
> неудачные операции и сохрани диагностический отчёт.

## 8. Definition of Done для каждого этапа

Этап считается завершённым только когда:

1. Все tool schemas типизированы и документированы.
2. Нет секретов в arguments, results, logs и test fixtures.
3. Read-only клиент не может изменить состояние обходным способом.
4. Destructive команда требует preview и confirmation token.
5. Долгая команда возвращает job и корректно сообщает progress/error/cancel.
6. Повтор с тем же `requestId` не дублирует действие.
7. Неверный ID, тип, диапазон и stale revision дают стабильную ошибку.
8. Изменение атомарно сохраняется и отражается в UI без перезапуска.
9. Есть unit, contract и end-to-end тесты.
10. Свежая сборка запускается, а сценарий проверяется через реальный MCP-клиент.

## 9. Рекомендуемый первый инкремент

Не начинать с файлов и Visual Editor. Первый production-инкремент:

1. MCP Foundation.
2. Полный Help & Onboarding: `list_help_topics`, `get_help_topic`, `search_help`,
   `get_contextual_help`, `get_onboarding_checklist`.
3. `get_capabilities`, `get_processing_status`, `list_jobs`, `get_job`,
   `cancel_job`, `get_change_history`, `validate_active_project`.
4. Stable `chunkId`/`cueId` и revision для существующих 9 инструментов.
5. `list_chunks`, `get_chunk`, `get_chunk_cues`, `search_transcript`,
   `replace_transcript_text`, `update_cue_text`, `split_cue`, `merge_cues`,
   `batch_approve_chunks`.
6. `translate_chunk`, `translate_pending_chunks`, `polish_translation`.
7. Полный безопасный glossary CRUD и apply preview.

После этого встроенный агент сможет выполнять основную редакторскую работу
полностью, а дальнейшие группы будут добавляться без переделки безопасности и
контрактов.
