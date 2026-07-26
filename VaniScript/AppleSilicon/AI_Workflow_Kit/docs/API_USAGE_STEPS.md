# API_USAGE — Step cards (A1–A8)

> Authoritative architecture: `API_USAGE_ARCHITECTURE.md`.
> ADR: `DECISIONS.md` → `D-2026-07-26-API_USAGE`.
> Этот файл: **исполняемые step-карточки** для `STATE.yaml` (track `API_USAGE`).
> Эталон UI статистики: `Electron/src/components/SettingsModal.tsx` (tab 7) +
> `Electron/src/services/storage.ts` (`trackUsage`).
>
> **Scope:** только Apple Silicon (`Sources/**`, `Tests/**`). Electron не трогаем.
> Точные пути/сигнатуры верифицируются через graphify на соответствующем шаге.

## Global quality (каждый coding-шаг)

- Well-commented code per `TEAM_CONTRACT.md` § Comments (role header + why-notes).
- Проект buildable каждый шаг: `swift build` (и `swift test` где есть тесты).
- Инварианты `API_USAGE_ARCHITECTURE.md` §14 — на каждом шаге.
- Токены: Graphify first (`GRAPH=/Users/pavan/Documents/AI Projects/VaniScript/graphify-out/graph.json`),
  не дампить дерево.
- Новые поля `AppSettings` — только через `decodeIfPresent` (migration-safe).
- Ключи/токены — только в settings/keychain; никогда в логах/исходниках/git.

---

## A1 — Discovery + data model (фундамент)

### Goal

Зафиксировать модель данных и каталог облачных провайдеров как единый источник правды.
Расширить `AppSettings`/`ProviderUsage` под новых провайдеров и per-model статистику.
**UI и движки на этом шаге не меняем** — только данные + ADR + верификация endpoints.

### Requirements

1. Через graphify подтвердить пути: `AppSettings.swift`, `ProviderRegistry.swift`,
   `SettingsView.swift` (`apiKeysTab`), `CloudAudioTranscriptionEngine.swift`,
   `CloudTextTranslationEngine.swift`, `WorkflowStore.swift` (точки вызова движков).
2. Новый `Sources/VaniScriptCore/CloudProviderCatalog.swift`:
   `CloudProviderDescriptor` (id, label, getApiKeyURL, modelsEndpoint, capabilities,
   defaultTextModel, defaultAudioModel, balanceKind) + фиксированный порядок
   `[gemini, openai, anthropic, qwen, openrouter, ollama-cloud, custom]` +
   `providerDisplayName(id)`.
3. Расширить `ProviderUsage`: `lastModel: String?`, `lastTransactionAt: String?`
   (опционально, `decodeIfPresent`).
4. Расширить `AppSettings`: поля §6.3 (qwen/openrouter/ollama ключи+модели+бюджеты,
   `geminiTextModel`/`openaiTextModel` с дефолтом текущего хардкода). `CodingKeys`,
   `init`, `init(from:)` — migration-safe.
5. Верифицировать (curl/доки, без product-кода) endpoints моделей/валидации/баланса
   для новых провайдеров; обновить теги `[med]`→`[high]` в `API_USAGE_ARCHITECTURE.md`.
6. Unit-тест: decode старых settings (без новых полей) → дефолты; encode/decode round-trip.

### target_files (Coder)

```yaml
target_files:
  - Sources/VaniScriptCore/CloudProviderCatalog.swift        # NEW
  - Sources/VaniScriptCore/AppSettings.swift                 # MODIFY
  - Tests/VaniScriptCoreTests/AppSettingsCloudFieldsTests.swift  # NEW
  - AI_Workflow_Kit/docs/DECISIONS.md                        # ADR discovery
  - AI_Workflow_Kit/docs/API_USAGE_ARCHITECTURE.md           # теги
  - AI_Workflow_Kit/docs/AI/FEEDBACK.md
```

### Out of scope

- UI (A3+), запись usage (A2), движки (A2/A5), валидация/модели (A4).

### Done

- [ ] `CloudProviderCatalog` с фиксированным порядком провайдеров
- [ ] `AppSettings`/`ProviderUsage` расширены, decode старых settings green
- [ ] `swift build` + `swift test` green
- [ ] Endpoints верифицированы, теги обновлены, ADR discovery
- [ ] Verifier approved

### Rollback

Tag `apiusage/pre-A1`

---

## A2 — Запись использования (чинит пустую статистику)

### Goal

Движки начинают извлекать token-счётчики из API-ответов и возвращать их; `WorkflowStore`
пишет агрегированную статистику в `settings.usage` через новый чистый `UsageRecorder`.
После этого шага данные для статистики реально накапливаются.

### Requirements

1. Новый `Sources/VaniScriptCore/UsageRecorder.swift`: чистая `record(into:providerId:
   model:delta:audioMinutes:)` (§8.2), ключ `providerId:model`. Без сайд-эффектов.
2. `CloudAudioTranscriptionEngine` / `CloudTextTranslationEngine`: парсинг usage
   (Gemini `usageMetadata.*`; OpenAI-compatible `usage.*`); результат расширяется на
   `TokenUsage(input:output:)` (опционально; `nil` если API не вернул).
3. `WorkflowStore`: после успешной транскрипции/перевода — `updateSettings {
   UsageRecorder.record(...) }`. Best-effort: ошибка парсинга usage не фейлит операцию.
4. Расширить `estimateCost`/pricing на новых провайдеров (для A6) — подготовка данных.
5. Unit-тесты: `UsageRecorder` (инкремент, last*, per-model ключ), парсеры usage
   (Gemini JSON, OpenAI JSON, отсутствие usage → nil).

### target_files (Coder)

```yaml
target_files:
  - Sources/VaniScriptCore/UsageRecorder.swift               # NEW
  - Sources/VaniScript/Services/CloudAudioTranscriptionEngine.swift   # MODIFY
  - Sources/VaniScript/Services/CloudTextTranslationEngine.swift      # MODIFY
  - Sources/VaniScript/Stores/WorkflowStore.swift            # MODIFY
  - Tests/VaniScriptCoreTests/UsageRecorderTests.swift       # NEW
  - Tests/VaniScriptTests/CloudUsageParsingTests.swift       # NEW
  - AI_Workflow_Kit/docs/AI/FEEDBACK.md
```

### Out of scope

- UI статистики (A6), новые провайдеры в движках (A5), баланс (A7).

### Done

- [ ] Движки возвращают `TokenUsage`, `WorkflowStore` пишет `settings.usage`
- [ ] `UsageRecorder` + парсеры покрыты тестами, `swift test` green
- [ ] Ошибка usage не фейлит транскрипцию/перевод
- [ ] Verifier approved

### Rollback

Tag `apiusage/pre-A2`

---

## A3 — UI reorg: единый dropdown провайдеров + условные карточки

### Goal

Заменить всегда-развёрнутые секции Gemini/OpenAI/Anthropic/Custom на **один** dropdown
«Provider» (фиксированный порядок) и рендер **только карточки выбранного** провайдера.
Поведение существующих провайдеров (ключ/бюджет/тумблеры) сохраняется 1:1, но в
компактном виде. Новые провайдеры (Qwen/OpenRouter/Ollama) пока как карточки-заглушки
с полем ключа (полная интеграция — A5).

### Requirements

1. Рефакторинг `apiKeysTab` (`SettingsView.swift:385-678`): `@State selectedProviderId`
   (дефолт `gemini`), `Picker` по `CloudProviderCatalog.orderedDescriptors`.
2. Новый `ProviderCardView` (в `SettingsView.swift` или отдельном файле): рендерит
   карточку по `CloudProviderDescriptor` + ключ/бюджет/тумблеры из существующей логики.
   Переиспользуем `ApiKeyInputRow`, `SliderRow`, бейджи Transcribing/Translation.
3. Для Gemini/OpenAI/Anthropic — существующая логика (ключ/бюджет/тумблеры), модель
   пока `ReadOnlyRow` (dropdown моделей — A4). Для Qwen/OpenRouter/Ollama — заглушка
   «ключ + скоро» (полное — A5). Custom — существующий список `customCloudProviders`
   (перенос в поток, механизм не меняем).
4. Секция статистики пока остаётся как есть (перестройка — A6); не ломать.
5. Без изменения поведения сохранения settings.

### target_files (Coder)

```yaml
target_files:
  - Sources/VaniScript/Views/SettingsView.swift             # MODIFY (apiKeysTab)
  - Sources/VaniScript/Views/ProviderCardView.swift         # NEW (опц., иначе внутри SettingsView)
  - AI_Workflow_Kit/docs/AI/FEEDBACK.md
```

### Out of scope

- Валидация ключа / dropdown моделей (A4), логика новых провайдеров (A5), статистика (A6).

### Done

- [ ] Один dropdown провайдеров, карточка только для выбранного
- [ ] Gemini/OpenAI/Anthropic/Custom работают как раньше (ключ/бюджет/тумблеры)
- [ ] `swift build` green, существующее поведение не сломано
- [ ] Verifier approved

### Rollback

Tag `apiusage/pre-A3`

---

## A4 — Валидация ключа (бейдж) + автоподтягивание моделей

### Goal

В карточке провайдера: бейдж валидности ключа (Checking/Valid/Invalid) и dropdown моделей
с автоподтягиванием после валидного ключа (editable combo + Retry как fallback). Заменяет
`ReadOnlyRow` «Text Model» на реальный выбор модели.

### Requirements

1. Новый `Sources/VaniScriptCore/CloudKeyValidator.swift`: статусы
   `idle/checking/valid/invalid(reason)`, стратегия по провайдерам (§9.1), debounce.
2. Новый `Sources/VaniScriptCore/CloudModelCatalog.swift`: `listModels(provider,apiKey)`
   поверх endpoints (§9.2); кэш в памяти сессии.
3. `ProviderCardView`: бейдж валидности; при valid → автозагрузка моделей → `Picker`
   (editable combo при ошибке) + `Retry`; выбор модели → `settings.<provider>…Model`.
4. Выбранная модель пробрасывается в `ActiveCloud*Provider.resolve()` (вместо хардкода)
   для Gemini/OpenAI — подготовка к A5 (поведение не ломать: дефолт = старый хардкод).
5. Unit-тесты: парсеры списков моделей (OpenAI `/v1/models`, Gemini `/v1beta/models`,
   Ollama `/api/tags`), маппинг статусов валидации. Сеть — мок.

### target_files (Coder)

```yaml
target_files:
  - Sources/VaniScriptCore/CloudKeyValidator.swift          # NEW
  - Sources/VaniScriptCore/CloudModelCatalog.swift          # NEW
  - Sources/VaniScript/Views/ProviderCardView.swift         # MODIFY
  - Sources/VaniScript/Views/SettingsView.swift             # MODIFY (при необходимости)
  - Sources/VaniScript/Services/CloudAudioTranscriptionEngine.swift   # MODIFY (resolve model)
  - Sources/VaniScript/Services/CloudTextTranslationEngine.swift      # MODIFY (resolve model)
  - Tests/VaniScriptCoreTests/CloudModelCatalogTests.swift  # NEW
  - Tests/VaniScriptCoreTests/CloudKeyValidatorTests.swift  # NEW
  - AI_Workflow_Kit/docs/AI/FEEDBACK.md
```

### Out of scope

- Полная логика Qwen/OpenRouter/Ollama в движках (A5), статистика (A6), баланс (A7).

### Done

- [ ] Бейдж валидности ключа работает (Checking/Valid/Invalid)
- [ ] Модели автоподтягиваются, выбираются, пишутся в settings; editable fallback + Retry
- [ ] `swift build` + `swift test` green
- [ ] Verifier approved

### Rollback

Tag `apiusage/pre-A4`

---

## A5 — Полноценная интеграция Qwen / OpenRouter / Ollama Cloud

### Goal

Превратить карточки-заглушки Qwen/OpenRouter/Ollama Cloud в рабочие облачные провайдеры:
ключ → валидация → модели → использование для Translation (и Transcribing, где реально
есть аудио). Расширить `ProviderRegistry` и движки через OpenAI-compatible endpoints.
**Честная индикация возможностей** (тумблер Transcribing только где есть аудио).

### Requirements

1. `ProviderRegistry`: добавить cloud-опции `qwen` / `openrouter` / `ollama-cloud`
   (transcription/translation) при наличии ключа — по образцу gemini/gpt.
2. `ActiveCloudTranscriptionProvider.resolve` / `ActiveCloudTranslationProvider.resolve`:
   кейсы для новых провайдеров (base URL + модель из settings + ключ). OpenAI-compatible
   для Qwen (DashScope `compatible-mode`)/OpenRouter; Ollama Cloud — нативный `/api/chat`
   или OpenAI-compatible `/v1` (по факту discovery A1).
3. Движки: маршрутизация запросов по провайдеру (endpoints/заголовки). Qwen/OpenRouter —
   OpenAI-compatible chat/completions + (где есть) audio. Ollama Cloud — Bearer + `/api/...`.
4. Тумблер «Use for Transcribing» показывается только при
   `capabilities.supportsTranscription` (иначе disabled + пояснение). Translation — всем.
5. Запись usage (§8) работает и для новых провайдеров (ключ `providerId:model`).
6. Unit-тесты: resolve новых провайдеров, построение запросов (URL/headers), маппинг
   ошибок. Сеть — мок. Реальные ключи не используются.

### target_files (Coder)

```yaml
target_files:
  - Sources/VaniScriptCore/ProviderRegistry.swift           # MODIFY
  - Sources/VaniScript/Services/CloudAudioTranscriptionEngine.swift   # MODIFY
  - Sources/VaniScript/Services/CloudTextTranslationEngine.swift      # MODIFY
  - Sources/VaniScript/Views/ProviderCardView.swift         # MODIFY (тумблеры по capabilities)
  - Tests/VaniScriptCoreTests/ProviderRegistryCloudTests.swift        # NEW
  - Tests/VaniScriptTests/CloudProviderRoutingTests.swift             # NEW
  - AI_Workflow_Kit/docs/DECISIONS.md                       # ADR: endpoints/capabilities по факту
  - AI_Workflow_Kit/docs/AI/FEEDBACK.md
```

### Out of scope

- Статистика UI (A6), реальный баланс (A7), локальные модели, MCP.

### Done

- [ ] Qwen/OpenRouter/Ollama Cloud: ключ → модели → translation работают
- [ ] Transcribing доступен только где есть аудио (честно)
- [ ] `ProviderRegistry` отдаёт новых провайдеров; usage пишется
- [ ] `swift build` + `swift test` green; ADR по endpoints
- [ ] Verifier approved

### Rollback

Tag `apiusage/pre-A5`

---

## A6 — Статистика использования (UI, эталон Electron tab 7)

### Goal

Перестроить секцию статистики вкладки `API & Usage` по эталону Electron: Last Transaction
Details (с бейджем модели), сводка Transcribing/Translation → модель, per-model карточки
(N transactions · Prompt · Completion · Total · Audio min · Estimated spent · Estimated
remaining), дисклеймер, Reset. Данные — из `settings.usage` (заполнено на A2/A5).

### Requirements

1. Новый `UsageStatisticsView` (в `SettingsView.swift` или отдельном файле) по
   `SettingsModal.tsx:1209-1263`.
2. Last Transaction Details: запись с max `lastTransactionAt`; бейдж `lastModel`;
   Prompt/Completion/Total tokens.
3. Сводка: `Transcribing → providerDisplayName(transcriptionProvider)`,
   `Translation / Editing → providerDisplayName(translationProvider)`.
4. Per-model карточки по записям `usage`: бейдж `N transactions`, grid метрик,
   `Estimated spent` (`estimateCost`), `Estimated remaining` (`max(0, budget-spent)` или `—`).
5. Дисклеймер дословно: «Cost is an estimate based on locally counted text tokens;
   provider billing can differ.»
6. Reset Statistics — существующий `settings.usage = [:]`.
7. Убрать старую секцию «Cloud Usage Statistics» (заменена новой). Поведение Reset сохранить.

### target_files (Coder)

```yaml
target_files:
  - Sources/VaniScript/Views/SettingsView.swift             # MODIFY (stats section)
  - Sources/VaniScript/Views/UsageStatisticsView.swift      # NEW (опц.)
  - AI_Workflow_Kit/docs/AI/FEEDBACK.md
```

### Out of scope

- Реальный баланс (A7), запись данных (A2/A5 уже), новые провайдеры (A5).

### Done

- [ ] Статистика совпадает по смыслу с Electron tab 7 (все блоки)
- [ ] Last Transaction + per-model карточки + дисклеймер + Reset работают
- [ ] `swift build` green
- [ ] Verifier approved

### Rollback

Tag `apiusage/pre-A6`

---

## A7 — Реальный баланс (адаптер, OpenRouter first)

### Goal

Показывать **реальный** баланс/лимиты там, где провайдер их отдаёт (OpenRouter: credits/key;
Ollama Cloud: плановые лимиты). Где не отдаёт — только локальная `Estimated spent` с
дисклеймером (никаких фейковых «$»). Ленивая загрузка + кэш + тихий fallback.

### Requirements

1. Новый `Sources/VaniScriptCore/CloudBalanceService.swift`: `BalanceProvider` protocol,
   `BalanceInfo` (`.usd` / `.planLimits` / `.unavailable`) (§11).
2. OpenRouter: `GET /api/v1/credits` + `GET /api/v1/key` (Bearer) → остаток/лимит USD.
3. Ollama Cloud: плановые лимиты, если API отдаёт; иначе подпись «Plan-based (GPU time)».
4. `ProviderCardView` + `UsageStatisticsView`: строка баланса по `balanceKind`; Refresh;
   кэш на короткий TTL; ошибка → fallback на estimated.
5. Для `.none`/`.estimated` провайдеров реальный баланс НЕ запрашивается и не показывается.
6. Unit-тесты: парсеры ответов баланса (OpenRouter credits/key), маппинг в `BalanceInfo`,
   fallback. Сеть — мок.

### target_files (Coder)

```yaml
target_files:
  - Sources/VaniScriptCore/CloudBalanceService.swift        # NEW
  - Sources/VaniScript/Views/ProviderCardView.swift         # MODIFY
  - Sources/VaniScript/Views/UsageStatisticsView.swift      # MODIFY (или SettingsView)
  - Tests/VaniScriptCoreTests/CloudBalanceServiceTests.swift        # NEW
  - AI_Workflow_Kit/docs/DECISIONS.md                       # ADR: формат баланса по факту
  - AI_Workflow_Kit/docs/AI/FEEDBACK.md
```

### Out of scope

- Баланс для провайдеров без API отдачи (Gemini/Anthropic/Qwen) — не реализуем.
- Запись usage (A2), статистика (A6), новые провайдеры (A5).

### Done

- [ ] OpenRouter показывает реальный остаток/лимит; Ollama — плановые лимиты
- [ ] Где баланса нет — только estimated + дисклеймер
- [ ] Ленивая загрузка, кэш, тихий fallback; `swift test` green
- [ ] Verifier approved

### Rollback

Tag `apiusage/pre-A7`

---

## A8 — Doc-only + acceptance smoke

### Goal

Финальная документация и acceptance-прогон. **Без product-фич** — только доки + smoke
(как GROK_MCP G6 / QWEN_MCP Q7). ADR «API_USAGE done».

### Requirements

1. `API_USAGE_ACCEPTANCE.md`: чеклист по всем 5 поверхностям (dropdown, карточка+валидация+
   модели, запись usage, статистика, баланс) с реальными путями/командами по факту A1–A7.
2. README Apple Silicon обновлён: новые провайдеры (Qwen/OpenRouter/Ollama Cloud),
   описание вкладки API & Usage.
3. Smoke: `swift build` + `swift test` green; ручной прогон UI по чеклисту (без реальных
   ключей — мок/описание); инварианты §14 соблюдены.
4. ADR «API_USAGE done» в `DECISIONS.md`.

### target_files (doc-only)

```yaml
target_files:
  - AI_Workflow_Kit/docs/API_USAGE_ACCEPTANCE.md            # NEW
  - AppleSilicon/README.md                                  # MODIFY
  - AI_Workflow_Kit/docs/DECISIONS.md                       # ADR done
  - AI_Workflow_Kit/docs/AI/FEEDBACK.md
```

### Out of scope

- Любой product-код (все фичи завершены на A1–A7).

### Done

- [ ] Acceptance smoke пройден (5 поверхностей)
- [ ] Доки актуальны (README, ACCEPTANCE)
- [ ] ADR «API_USAGE done»
- [ ] Verifier approved → `API_USAGE_DONE`

### Rollback

Tag `apiusage/pre-A8`