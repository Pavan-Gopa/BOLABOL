# Verification Report (Verification Engineer)

Проверяемый шаг: **A6 — Статистика использования (UI, эталон Electron tab 7)**
Требования шага: `API_USAGE_STEPS.md` (§A6), `API_USAGE_ARCHITECTURE.md` (§10, §14)
Роль: Verification Engineer (Gemini 3.6 Flash)

---

### 1. Сборка и тесты
- **Собирается и проходит ли тестовый прогон проект после изменений?**
  Да. `swift build` прошёл успешно. `swift test` выполнен успешно — **320 tests в 46 suites PASS** (за 0.122 сек).

### 2. Логика и соответствие требованиям A6
- **Компонент UsageStatisticsView:**
  Создан новый `UsageStatisticsView.swift` в `Sources/VaniScript/Views/`, реализующий вкладку статистики в парадигме Electron `SettingsModal.tsx` tab 7:
  1. **Last Transaction Details:** Отображает запись с максимальным `lastTransactionAt` (ISO-8601), бейдж `lastModel` (с fallback на название провайдера), а также метрики `Prompt tokens`, `Completion tokens`, `Total tokens`.
  2. **Active Providers Summary:** Сводка `Transcribing` и `Translation / Editing` отображает человекочитаемые имена активных провайдеров через `CloudProviderCatalog.providerDisplayName` с нормализацией legacy engine ID (`gemini-cloud` → Gemini, `gpt-cloud` → OpenAI) и поддержкой локальных движков.
  3. **Per-model Cards:** Карточки генерируются по каждому ключу `providerId:model` из `settings.usage`. Каждая карточка содержит бейдж `N transactions`, сетку из 6 метрик (`Prompt / input tokens`, `Completion tokens`, `Total tokens`, `Audio min`, `Estimated spent`, `Estimated remaining`).
  4. **Точный Дисклеймер:** Текст `Cost is an estimate based on locally counted text tokens; provider billing can differ.` соответствует эталонной строке из Electron **точь-в-точь**.
  5. **Reset Statistics:** Кнопка сброса выполняет `settings.usage = [:]`, очищая всю сохраненную статистику.
  6. **Empty State:** При отсутствии записей отображается «No usage recorded yet.».
- **Интеграция в SettingsView:**
  Старая секция «Cloud Usage Statistics» и мёртвые функции/типы (`estimateCost`, `formatTokens`, `StatItem`, `BudgetBar`) удалены из `SettingsView.swift`. В `apiKeysTab` корректно подключён `UsageStatisticsView()`. Секция выбора провайдера (`apiKeysTab`) и карточки провайдеров (`ProviderCardView`) сохранены без нарушения их работоспособности.
- **Инварианты и Scope:**
  - Изменения затрагивают исключительно UI (UI only): логика движков, `ProviderRegistry`, `UsageRecorder` и `AppSettings` не менялись.
  - Сетевые вызовы реального баланса отсутствуют (отложено до A7).
  - Изменения ограничены разрешёнными `target_files` (`SettingsView.swift`, `UsageStatisticsView.swift`, `FEEDBACK.md`).
  - Оговорки кодера в HANDOFF (QA скрипты старой секции устарели by design; бейдж lastModel как superset) проверены и признаны корректными.

### 3. Качество кода и комментарии
- `UsageStatisticsView.swift` снабжен подробным role header, ссылками на эталон Electron tab 7 и маркерами `// A6:` в соответствии с `TEAM_CONTRACT.md` § Comments.

---

**ИТОГОВЫЙ СТАТУС:** [APPROVED]

---

# Verification Report (Verification Engineer)

Проверяемый шаг: **A5 — Полноценная интеграция Qwen / OpenRouter / Ollama Cloud**
Требования шага: `API_USAGE_STEPS.md` (§A5), `API_USAGE_ARCHITECTURE.md` (§7, §14)
Роль: Verification Engineer (Gemini 3.6 Flash)

---

### 1. Сборка и тесты
- **Собирается и проходит ли тестовый прогон проект после изменений?**
  Да. `swift test` выполнен успешно — **320 tests в 46 suites PASS** (проведен самостоятельный прогон, +12 новых unit-тестов в `ProviderRegistryCloudTests` и `CloudProviderRoutingTests`).

### 2. Логика и соответствие требованиям A5
- **Маршрутизация и endpoints:**
  Создан `CloudChatRouter` (`CloudChatRoute`) в `VaniScriptCore` для изоляции логики построения URL/заголовков и тестов без сети/ключей. Endpoints:
  - Qwen: DashScope compatible-mode (`/compatible-mode/v1/chat/completions`) + Bearer.
  - OpenRouter: `/api/v1/chat/completions` + Bearer.
  - Ollama Cloud: `{base}/v1/chat/completions` (OpenAI-compatible) + Bearer, с нормализацией base URL.
- **ProviderRegistry и доступность:**
  Опции перевода (`qwen`, `openrouter`, `ollama-cloud`) отдаются при наличии непустого ключа в `AppSettings`. Опции транскрипции фильтруются честно на основе `capabilities.supportsTranscription` (для всех трех провайдеров сейчас `false`, поэтому опции транскрипции не добавляются).
- **Движки перевода и транскрипции:**
  `CloudTextTranslationEngine` рефакторен с выносом общей логики в `generateOpenAICompatible`, извлекающей токены через `UsageRecorder.parseOpenAIUsage`. `CloudAudioTranscriptionEngine` намеренно оставлен без новых кейсов (честная индикация, отсутствие мертвых кейсов).
- **Интерфейс пользователя (SettingsView):**
  Заглушка "coming soon" заменена на `cloudProviderCard` с полями ключа (`ApiKeyInputRow`), выбора модели (`CloudKeyModelRow` из A4), слайдера бюджета (Qwen/OpenRouter), Base URL (Ollama) и честными тумблерами. Тумблер Transcribing отключен с поясняющим подсказкой/текстом (`supportsTranscription == false`).
- **Соблюдение инвариантов и рамок шага (Scope):**
  - Отсутствуют переработка UI статистики (A6) и реальный баланс (A7).
  - Использованы только разрешенные `target_files` (с переносом `CloudChatRouter` в `ProviderRegistry.swift` для тестируемости).
  - API-ключи передаются только в заголовках, отсутствуют в исходном коде и логах.
  - Codex / Grok / embedded Qwen / MCP сервер не затронуты и проходят все тесты.
  - Оговорки кодера (transcription pipeline deferral, catalog base url for Ollama models) обоснованы и приняты.

### 3. Качество кода и комментарии
- Все новые и измененные файлы содержат подробные role-headers, why-комментарии и пояснения к логике маршрутизации в соответствии с `TEAM_CONTRACT.md` § Comments.

---

**ИТОГОВЫЙ СТАТУС:** [APPROVED]

---

# Verification Report (Verification Engineer)

Проверяемый шаг: **A4 — Валидация ключа (бейдж) + автоподтягивание моделей**
Требования шага: `API_USAGE_STEPS.md` (§A4), `API_USAGE_ARCHITECTURE.md` (§9, §14)
Роль: Verification Engineer (Gemini 3.6 Flash)

---

### 1. Сборка и тесты
- **Собирается и проходит ли тестовый прогон проект после изменений?**
  Да. `swift test` выполнен успешно — **308 tests в 44 suites PASS** (включая 15 тестов в `CloudModelCatalog parsers (A4)` и 9 тестов в `CloudKeyValidator (A4)`).

### 2. Логика и соответствие требованиям A4
- **Бейдж валидности ключа:**
  Реализован `CloudKeyValidator` со статусами `.idle`, `.checking`, `.valid`, `.invalid(reason)`. В UI (`CloudKeyModelRow`) корректно отображаются бейджи Checking, ● Valid, ● Invalid (с `help(reason)` подсказкой).
- **Автоподтягивание и каталог моделей:**
  Реализован `CloudModelCatalog` (actor) с чистыми парсерами для OpenAI/Gemini/Ollama/Anthropic endpoints, фильтрацией пустых значений и дедупликацией. В UI при валидном ключе загружается `Picker` моделей; при ошибке/пустом списке или по кнопке `square.and.pencil` включается editable combo (`TextField` + кнопка `Retry`).
- **Безопасность и хэширование:**
  Кэш моделей сессионный (`cache[cacheKey]`), ключ кэша формируется через `keyFingerprint` (`String(key.hashValue, radix: 16)`). Исходный API-ключ не персистится и не логгируется.
- **Запись в AppSettings и fallback:**
  Выбранные модели сохраняются в `settings.geminiTextModel` и `settings.openaiTextModel`. Метод `resolve()` в `ActiveCloudTranscriptionProvider` и `ActiveCloudTranslationProvider` использует выбранную модель, а при пустом значении корректно возвращает прежний захардкоженный дефолт (`gemini-2.5-flash` / `gpt-4o-mini`).
- **Соблюдение инвариантов и рамок шага (Scope):**
  - Отсутствует роутинг движков для Qwen/OpenRouter/Ollama (A5).
  - Секция статистики не перерабатывалась (A6).
  - Изменения строго в рамках `target_files` (с допустимым in-file helper `CloudKeyModelRow` внутри `SettingsView.swift`).
  - Оговорки кодера (OpenAI transcription на whisper-1, Anthropic read-only) полностью обоснованы и приняты.

### 3. Качество кода и комментарии
- Все новые и измененные файлы содержат подробные role-headers, why-комментарии и пояснения к асинхронной логике / кэшированию в соответствии с `TEAM_CONTRACT.md` § Comments.

---

**ИТОГОВЫЙ СТАТУС:** [APPROVED]

---

# Implementation Handoff → Verification (A4)

Шаг: **A4 — Валидация ключа (бейдж) + автоподтягивание моделей**. Роль: Implementation Engineer (Coder).
Статус: `implementation.status = waiting_review`, `next_actor = orchestrator`. Pre-tag `apiusage/pre-A4` подтверждён.

**Проверка (green):**
- `swift build` → `Build complete!` (0 ошибок).
- `swift test` → **308 tests в 44 suites PASS**, включая новые suites
  `CloudModelCatalog parsers (A4)` и `CloudKeyValidator (A4)`.

**Что сделано (target_files):**
- `Sources/VaniScriptCore/CloudModelCatalog.swift` (NEW):
  - `CloudModel` (id), `CloudModelCatalog` actor с `listModels(descriptor:apiKey:baseURL:useCache:)`.
  - In-memory session cache (не персистится); ключ кэша = provider id + необратимый
    хэш ключа + baseURL → секрет не хранится (§14.3), смена ключа сбрасывает кэш.
  - Чистые публичные парсеры `parse(data:endpoint:provider:)` для OpenAI-compatible
    (`data[].id`), Gemini (`models[].name`, strip `models/`), Ollama (`models[].name`),
    Anthropic (`data[].id`); де-дуп с сохранением порядка + фильтр пустых.
  - Публичный `listRequest(descriptor:apiKey:baseURL:)` — строит per-provider запрос
    (Gemini `?key=`, OpenAI/Qwen/OpenRouter Bearer, Anthropic `x-api-key`+version,
    Ollama `{base}/api/tags` Bearer); custom/none → nil.
  - Сеть инъектируется через `CloudHTTPFetcher` (default `CloudHTTP.live` на URLSession)
    → тесты гоняют парсеры/actor на моках без реальной сети.
- `Sources/VaniScriptCore/CloudKeyValidator.swift` (NEW):
  - `CloudKeyValidationStatus` = `idle/checking/valid/invalid(reason)`.
  - `validate(descriptor:apiKey:baseURL:)` переиспользует `listRequest` (успешный
    models-list == valid ключ, §9.1); пустой ключ → `.idle`; провайдеры без листинга
    (custom) → `.valid`; сетевые ошибки → `.invalid` (не бросает).
  - Чистый `status(forHTTPStatus:)`: 2xx→valid, 401/403→invalid, 429→valid (throttle),
    прочее non-2xx→invalid(HTTP code). Debounce живёт в UI (task cancellation).
- `Sources/VaniScript/Views/SettingsView.swift` (MODIFY):
  - Новый file-private `CloudKeyModelRow` заменил `ReadOnlyRow "Text Model"` в
    Gemini/OpenAI карточках: бейдж Checking/● Valid/● Invalid + при valid автозагрузка
    моделей → `Picker` (с сохранением уже выбранного id) + кнопка ручного ввода;
    при ошибке/пустом списке → editable combo (free-text) + `Retry`.
  - Валидация/загрузка в `.task(id: apiKey)` с 500ms debounce (отмена задачи = дедуп).
  - Выбор пишется в `settings.geminiTextModel` / `settings.openaiTextModel` через
    существующий `binding(_:)`. Anthropic оставлен на `ReadOnlyRow` (нет settings-поля
    и engine-роутинга для него — вне scope A4; см. ниже).
- `Sources/VaniScript/Services/CloudAudioTranscriptionEngine.swift` (MODIFY):
  - `resolve()` Gemini использует `settings.geminiTextModel` (fallback = старый хардкод
    `gemini-2.5-flash`). OpenAI транскрипция — это whisper-1 (audio-модель, не text),
    хардкод оставлен до A5 (audio-picker).
- `Sources/VaniScript/Services/CloudTextTranslationEngine.swift` (MODIFY):
  - `resolve()` Gemini/OpenAI используют settings-модели (fallback = `gemini-2.5-flash`
    / `gpt-4o-mini`) через `resolvedModel(_:fallback:)`.
- `Tests/VaniScriptCoreTests/CloudModelCatalogTests.swift` (NEW): парсеры (OpenAI/
  Gemini/Ollama), де-дуп, ошибки, request-builder (auth per provider), actor listModels
  на моке + кэш-хит, non-2xx → throw.
- `Tests/VaniScriptCoreTests/CloudKeyValidatorTests.swift` (NEW): маппинг статусов +
  async validate (idle/valid/invalid/network-error/custom) на моке.

**Инварианты (§14):** AppSettings decode не менялся (модели уже добавлены в A1,
migration-safe); Codex/Grok/Qwen/MCP не затронуты; ключей в source/логах нет
(кэш-ключ — необратимый хэш); дефолт модели = старый хардкод при пустых settings.

**Out of scope (не делалось):** A5 (qwen/openrouter/ollama engine routing), A6 (stats UI),
A7 (balance). Anthropic model picker (нет settings-поля/движка) — вне A4.

---

# Verification Report (Verification Engineer)

Проверяемый шаг: **A3 — UI reorg: единый dropdown провайдеров + условные карточки**
Требования шага: `API_USAGE_STEPS.md` (§A3), `API_USAGE_ARCHITECTURE.md` (§7, §14)
Роль: Verification Engineer (Gemini 3.6 Flash)

---

### 1. Сборка и интеграция
- **Собирается ли проект после этих изменений?**
  Да. `swift build` выполнен успешно (`Build complete! (12.66s)`).
- **Соблюдены ли инварианты §14 (Codex/Grok/Qwen, MCP server, AppSettings decode)?**
  Да. Не затрагивались Codex/Grok/Qwen, MCP server и `AppSettings` decode. Статистика в секции «Cloud Usage Statistics» оставлена без изменений (территория A6).

### 2. Логика и соответствие требованиям A3
- **Выполнены ли все требования текущего шага?**
  Да:
  1. `apiKeysTab`: Вся секция реорганизована под единый `Picker` провайдера (`selectedProviderId` со значением по умолчанию `CloudProviderCatalog.geminiID`).
  2. Порядок провайдеров берется из `CloudProviderCatalog.providers` (фиксированный порядок каталога A1).
  3. Для `Custom` отображается `customProvidersSection` (существующий механизм добавления/удаления провайдеров 1:1).
  4. Для остальных провайдеров рендерится карточка `ProviderCardView(descriptor:)`.
  5. Gemini/OpenAI/Anthropic: ключи, бюджет и тумблеры привязки к транскрипции/переводу работают 1:1 с сохраненным поведением. Выбор модели отображается как `ReadOnlyRow`.
  6. Qwen / OpenRouter / Ollama Cloud: реализована заглушка «ключ + coming soon note» с записью ключей в соответствующие поля `AppSettings` (`qwenApiKey`, `openrouterApiKey`, `ollamaCloudApiKey`).
- **Соблюдены ли target_files?**
  Да. Изменения выполнены строго в `Sources/VaniScript/Views/SettingsView.swift` (включая in-file helper `ProviderCardView`) и документации `FEEDBACK.md` / `STATE.yaml`. Изменения out-of-scope (A4/A5/A6) отсутствуют.

### 3. Комментарии и читаемость
- Все добавленные компоненты (`ProviderCardView`, `customProvidersSection`) снабжены роли/why-комментариями и соответствуют TEAM_CONTRACT.

---

**ИТОГОВЫЙ СТАТУС:** [APPROVED]

---

# Implementation Handoff → Verification (A3)

Шаг: **A3 — UI reorg: единый dropdown провайдеров + условные карточки**. Роль: Implementation Engineer (Coder).
Статус: `implementation.status = waiting_review`, `next_actor = verification`. Pre-tag `apiusage/pre-A3` подтверждён.

**Что сделано (target_files):**
- `Sources/VaniScript/Views/SettingsView.swift` (MODIFY):
  - Добавлен `@State private var selectedProviderId = CloudProviderCatalog.geminiID`.
  - `apiKeysTab`: всегда-развёрнутые секции Gemini/OpenAI/Anthropic/Custom заменены на
    одну секцию «Cloud Provider» с `Picker` по `CloudProviderCatalog.providers`
    (фиксированный порядок каталога) + условный рендер: `Custom` → `customProvidersSection`,
    иначе → `ProviderCardView(descriptor:)`.
  - Секция «Cloud Usage Statistics» (территория A6) оставлена **без изменений**.
  - Логика Custom-провайдеров (список + форма добавления + `addCustomProvider()`) вынесена
    1:1 в новый computed var `customProvidersSection` (механизм не менялся).
- `ProviderCardView` реализован **внутри SettingsView.swift** (разрешено брифом
  «или внутри SettingsView») — отдельный файл не создавался, т.к. карточка
  переиспользует file-private строки (`ApiKeyInputRow`, `ReadOnlyRow`, `SliderRow`,
  `SettingsSection`, `SettingsSmallButtonStyle`), которые остаются private.
  - Gemini/OpenAI: ключ + `ReadOnlyRow` модели (dropdown → A4) + `SliderRow` бюджета +
    тумблеры Transcribing/Translation и бейджи — поведение **1:1** (те же engine-id
    `gemini-cloud`/`gpt-cloud`/`coreml-whisperkit`/`mlx-native`, те же budget keyPath).
  - Anthropic: ключ + `ReadOnlyRow` модели — 1:1.
  - Qwen/OpenRouter/Ollama Cloud: заглушка «ключ + coming soon» (ключи пишутся в
    существующие `qwenApiKey`/`openrouterApiKey`/`ollamaCloudApiKey`; полное — A5).
  - «Get API Key» URL теперь берётся из `descriptor.getApiKeyURL` (single source of
    truth каталога A1).

**Verify:** `swift build` → **Build complete!** (только pre-existing deprecation warnings
в несвязанном `VisualClipEditorView.swift`).

**Инварианты §14:** `AppSettings` decode не тронут (migration-safe); Codex/Grok/Qwen/MCP/
локальные модели не тронуты; изменения только в UI `apiKeysTab`; нет ключей/токенов в
исходниках/логах; buildable. Diff только в target_files (`SettingsView.swift` + этот
FEEDBACK).

**Out of scope (не делал):** валидация ключа / dropdown моделей (A4); логика новых
провайдеров в движках (A5); статистика UI (A6); UsageRecorder / cloud engines / WorkflowStore.
`review.status` / `current_step` / post-tag не трогал.

Готово. Скажи оркестратору: **статус** (Kick ревьюеру выдаёт только Orchestrator).

---

# Implementation Handoff → Verification (A2)

Шаг: **A2 — Запись использования (чинит пустую статистику)**. Роль: Implementation Engineer (Hy3).
Статус: `implementation.status = waiting_review`. Pre-tag `apiusage/pre-A2` подтверждён.

**Что сделано (target_files):**
- `Sources/VaniScriptCore/UsageRecorder.swift` (NEW) — `TokenUsage`, чистый `record(...)`
  (ключ `providerId:model`, инкремент sessions/input/output/audio + `last*`, no-op без
  сигнала), парсеры `parseGeminiUsage`/`parseOpenAIUsage` (lenient → `nil`).
- `Sources/VaniScript/Services/CloudAudioTranscriptionEngine.swift` (MODIFY) — результат
  `CloudAudioTranscriptionResult.usage: TokenUsage?`; парсинг из Gemini/OpenAI ответов.
- `Sources/VaniScript/Services/CloudTextTranslationEngine.swift` (MODIFY) — actor-аккумулятор
  usage + `takeLastUsage()`; парсинг в `generateGemini`/`generateOpenAI`.
- `Sources/VaniScript/Stores/WorkflowStore.swift` (MODIFY) — best-effort
  `recordCloudTranslationUsage(...)` после всех облачных переводов/шортс-операций;
  `normalizedUsageProviderId` (`gemini-cloud`→`gemini`, `gpt-cloud`→`openai`).
- `Tests/VaniScriptCoreTests/UsageRecorderTests.swift` (NEW) — 14 тестов (record/last*/
  per-model/best-effort/парсеры/round-trip/TokenUsage).
- `AI_Workflow_Kit/docs/DECISIONS.md` — ADR `D-2026-07-26-A2`.

**Verify:** `swift build` OK; `swift test` — **287 tests / 42 suites GREEN**.

**Инварианты §14:** decode `AppSettings` не тронут (1); Codex/Grok/Qwen/MCP/локальные модели
не тронуты (2); только облачные API (3); запись usage best-effort — не фейлит операцию (4);
нет ключей в коде/логах (7); buildable/testable (8); diff только в target_files (9);
essential comments добавлены (10).

**Scope note (важно для ревью):** облачная транскрипция вызывается из
`NativeProcessingPipeline` (вне target_files A2). Движок уже **возвращает** `usage`, но
запись транскрипции в `settings.usage` через WorkflowStore не проведена (нужна проводка в
pipeline — предложено на A5/A6). Запись переводов полностью функциональна. Требование A2
«движок возвращает токены» выполнено для обоих движков.

**Не делал:** `review.status`, инкремент `current_step`, post-tag — по контракту.
Зови оркестратора / Gemini на ревью.

---

# Verification Report (Verification Engineer)

Проверяемый шаг: **A2 — Запись использования (чинит пустую статистику)**
Требования шага: `API_USAGE_STEPS.md` (§A2), `API_USAGE_ARCHITECTURE.md` (§8, §14)
Роль: Verification Engineer (Gemini 3.6 Flash)

---

### 1. Сборка и интеграция
- **Собирается / тестируется ли проект после этих изменений?**
  Да. `swift test` выполнен успешно — **287 tests в 42 suites GREEN** (за 0.155 сек). Все 14 новых unit-тестов в `UsageRecorderTests` прошли.
- **Не нарушают ли изменения Codex/Grok/Qwen, MCP server, AppSettings decode?**
  Нет. Не затрагивались Codex/Grok/Qwen, MCP server и локальные модели (MLX/WhisperKit). `AppSettings` decode проверяется отдельной suite тестов, совместимость сохранена.

### 2. Логика и соответствие плану
- **Выполнены ли все требования текущего шага?**
  Да.
  1. `UsageRecorder.swift` создан в `VaniScriptCore`: содержит `TokenUsage`, чистую функцию `record(...)` с составным ключом `providerId:model`, lenient-парсеры `parseGeminiUsage` и `parseOpenAIUsage` (возвращают `nil` при отсутствии/ошибке usage block).
  2. `CloudAudioTranscriptionEngine`: расширен `CloudAudioTranscriptionResult` полем `usage: TokenUsage?`; парсятся токены из ответов Gemini и OpenAI-compatible API.
  3. `CloudTextTranslationEngine`: добавлен actor-isolated accumulator `accumulatedUsage` и метод `takeLastUsage()`, который атомарно считывает и сбрасывает накопленный usage после операций перевода/планирования шортсов.
  4. `WorkflowStore`: добавлен метод `recordCloudTranslationUsage`, вызываемый после всех облачных переводов и генераций шортсов. Использован `normalizedUsageProviderId` (`gemini-cloud` → `gemini`, `gpt-cloud` → `openai`) для совместимости с `estimateCost`.
  5. `UsageRecorderTests.swift`: 14 тестов полностью покрывают `UsageRecorder` (инкремент, `last*`, per-model ключи, no-op при пустом/nil `delta`, парсеры Gemini/OpenAI и JSON round-trip).
  6. ADR `D-2026-07-26-A2` добавлен в `DECISIONS.md`.
- **Оценка Scope Note по транскрипции (NativeProcessingPipeline):**
  Принято / DEFERRED OK. Движок `CloudAudioTranscriptionEngine` полностью выполнил требование шага A2 ("возвращает TokenUsage"). Файл `NativeProcessingPipeline.swift` не входил в `target_files` A2, поэтому проводка вызова `record` для транскрипции оправданно отложена до шагов A5/A6, когда pipeline попадет в scope.
- **Соблюдены ли target_files?**
  Да. Изменения выполнены строго в пределах разрешенных `target_files`:
  - `Sources/VaniScriptCore/UsageRecorder.swift` (NEW)
  - `Sources/VaniScript/Services/CloudAudioTranscriptionEngine.swift` (MODIFY)
  - `Sources/VaniScript/Services/CloudTextTranslationEngine.swift` (MODIFY)
  - `Sources/VaniScript/Stores/WorkflowStore.swift` (MODIFY)
  - `Tests/VaniScriptCoreTests/UsageRecorderTests.swift` (NEW)
  - `AI_Workflow_Kit/docs/DECISIONS.md` (MODIFY)
  - `AI_Workflow_Kit/docs/AI/FEEDBACK.md` (MODIFY)

### 3. Безопасность и контракты
- **Best-effort контракт (§14.4):**
  Выполнено. При отсутствии или ошибке парсинга `usage` операция перевода/транскрипции не фейлится. `record` является no-op если `delta` равен `nil` или пуст и `audioMinutes == 0`.
- **Хардкод ключей / логгирование секретов:**
  Ключи и секреты отсутствуют в исходниках и логах.

### 4. Комментарии и читаемость (TEAM_CONTRACT § Comments)
- **Role headers и Why-notes:**
  Все новые и измененные модули (`UsageRecorder.swift`, `CloudAudioTranscriptionEngine.swift`, `CloudTextTranslationEngine.swift`, `WorkflowStore.swift`, `UsageRecorderTests.swift`) содержат качественные role headers, ссылки на §8 / §14 архитектуры и развернутые why-notes для non-obvious логики (например, почему parsers вынесены в Core, почему использован accumulator в translation engine и почему delta сбрасывается с `defer`).

---

**ИТОГОВЫЙ СТАТУС:** [APPROVED]

---

# HANDOFF — A5 (Coder → Orchestrator)

**Step:** A5 — Полноценная интеграция Qwen / OpenRouter / Ollama Cloud.
**Status:** IMPLEMENTED, `swift test` GREEN — 320 tests / 46 suites (было 308/44).

## Что сделано
1. **`ProviderRegistry.swift`:** translation-опции `qwen`/`openrouter`/`ollama-cloud`
   при сохранённом ключе (паттерн gemini/gpt); transcription — data-driven по
   `capabilities.supportsTranscription` (честно: сегодня опций нет). Новый core-слой
   **`CloudChatRouter`/`CloudChatRoute`** (endpoint+headers+model+key) — в Core ради
   тестируемости из VaniScriptCoreTests (единственный test target).
2. **`CloudTextTranslationEngine.swift`:** `resolve` default-кейс → CloudChatRouter;
   `generateOpenAI` рефакторен в общий `generateOpenAICompatible(url:headers:)`
   (gpt-cloud 1:1). Qwen=DashScope compatible-mode `/v1/chat/completions`,
   OpenRouter=`/api/v1/chat/completions`, Ollama Cloud=`{base}/v1/chat/completions`.
   Usage через `parseOpenAIUsage` (A2) работает для всех трёх автоматически.
3. **Usage ids:** engine/registry ids = catalog ids → `normalizedUsageProviderId`
   пропускает без remap; WorkflowStore НЕ трогался (вне target_files).
4. **`CloudAudioTranscriptionEngine.swift`:** намеренно без новых кейсов (why-коммент):
   у всех трёх `supportsTranscription == false` — честная индикация, без мёртвого кода.
5. **`SettingsView.swift`:** "coming soon" заменён на generic `cloudProviderCard`:
   ApiKeyInputRow + CloudKeyModelRow (валидация+модели A4) + budget slider
   (Qwen/OpenRouter) + Base URL (Ollama) + toggles. Transcribing — disabled +
   tooltip + поясняющий текст; Translation доступен всем при ключе.
6. **Тесты (моки, без сети/ключей):** `ProviderRegistryCloudTests` (5) +
   `CloudProviderRoutingTests` (7): gating по ключу, honest transcription, URL/headers,
   model fallback/override, base-URL нормализация, nil-mapping.
7. **ADR `D-2026-07-26-A5`** в DECISIONS.md (endpoints/capabilities/ids решения).

## Замечания для ревью
- Transcription usage pipeline (A2 defer) остаётся deferred: новые провайдеры не
  транскрибируют, `NativeProcessingPipeline` вне target_files A5.
- CloudKeyModelRow для Ollama использует дефолтный base каталога (https://ollama.com)
  для списка моделей — как в A4; кастомный base влияет на chat-endpoint (router).
- target_files соблюдены строго; ключи только в headers, не в логах/исходниках.

**next_actor: orchestrator**

---

# HANDOFF — A6 (Coder → Orchestrator)

**Step:** A6 — Статистика использования (UI, эталон Electron tab 7).
**Status:** IMPLEMENTED, `swift build` GREEN, `swift test` GREEN — 320 tests / 46 suites.

## Что сделано
1. **`Sources/VaniScript/Views/UsageStatisticsView.swift` (NEW):** секция статистики
   в парадигме Electron SettingsModal.tsx tab 7 («Cloud API Usage»):
   - **Last Transaction Details** — запись с максимальным `lastTransactionAt`
     (ISO-8601, сортируется лексикографически), бейдж `lastModel` (fallback —
     display name провайдера), ячейки Prompt / Completion / Total tokens
     (`lastInputTokens` / `lastOutputTokens`).
   - **Summary-карточка:** Transcribing / Translation & Editing — display name
     активных провайдеров. Legacy engine ids нормализуются (`gemini-cloud`→gemini,
     `gpt-cloud`→openai), локальные движки — «Local Whisper (Core ML)» / «Local MLX»,
     остальные — `CloudProviderCatalog.providerDisplayName` (A5 ids = catalog ids).
   - **Per-model карточки** по каждому ключу `settings.usage`
     (`providerId:model`, UsageRecorder.usageKey): заголовок «Provider · model»,
     бейдж «N transactions», грид 6 метрик — Prompt/input, Completion, Total,
     Audio min, Estimated spent (estimateCost), Estimated remaining
     (`max(0, budget − spent)` или «—» при budget == 0). Порядок: новые сверху.
   - **Дисклеймер EXACT:** «Cost is an estimate based on locally counted text
     tokens; provider billing can differ.» (на каждой карточке, как в Electron).
   - **Reset Statistics** → `settings.usage = [:]` (прежнее поведение сброса).
   - Пустое состояние: «No usage recorded yet.»
2. **`SettingsView.swift`:** старая секция «Cloud Usage Statistics» удалена и
   заменена на `UsageStatisticsView()` в `apiKeysTab`; ставшие мёртвыми приватные
   `estimateCost`/`formatTokens` и `StatItem`/`BudgetBar` удалены (A6-комментарии
   оставлены на местах). Остальной apiKeysTab (A3 dropdown/карточки) не тронут.
3. **Pricing:** локальные ставки gemini/openai/anthropic и custom-провайдеров
   перенесены 1:1 из старого `estimateCost`; qwen/openrouter/ollama без локального
   прайса → $0.0000 (real balance — A7). Budget lookup: gemini/openai/qwen/openrouter
   BudgetUsd + `budgetLimitUsd` кастомных провайдеров.

## Инварианты (§14)
- UI only: engines/registry/UsageRecorder/AppSettings не тронуты; decode не менялся.
- Данные только из `settings.usage` (A2/A5); никакой network/real balance (A7).
- Нет ключей в исходниках; Codex/Grok/Qwen/MCP не тронуты.
- Comments: role header + why-notes, `// A6:` маркеры.

## Замечания для ревью / QA
- QA-скрипты `a3_stats_section_unchanged.sh` / `a4_no_a6_stats_rewrite.sh` проверяют
  наличие старой секции «Cloud Usage Statistics» — теперь устарели by design
  (A6 её заменяет), потребуют обновления манифеста QA.
- Бейдж Last Transaction показывает `lastModel` (у нас есть per-model данные),
  Electron показывал provider name — считаю это superset эталона; fallback на
  provider name сохранён.

**next_actor: orchestrator**
