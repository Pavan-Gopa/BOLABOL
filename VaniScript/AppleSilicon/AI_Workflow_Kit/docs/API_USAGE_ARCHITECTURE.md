# VaniScript — API & Usage Tab Reorganization: Architectural Specification

> Архитектурный план реорганизации вкладки **«API & Usage»** в Apple Silicon версии
> VaniScript: (1) единый dropdown облачных провайдеров с условными карточками,
> (2) валидация ключа + автоподтягивание моделей, (3) запись использования (чинит
> пустую статистику), (4) статистика по эталону Electron, (5) реальный баланс где
> провайдер отдаёт. Добавляются cloud-провайдеры **Qwen / OpenRouter / Ollama Cloud**.
>
> **Track:** `API_USAGE` (шаги A1–A8, карточки в `API_USAGE_STEPS.md`).
> **Status:** Accepted design, not yet implemented.
> **Companion docs:** `API_USAGE_STEPS.md`, `DECISIONS.md` (D-2026-07-26-API_USAGE),
> `PROJECT_CONTEXT.md`. Эталон UI статистики: `Electron/src/components/SettingsModal.tsx`
> (tab 7) + `Electron/src/services/storage.ts` (`trackUsage`).

**Accuracy tags:** `[high]` подтверждено в кодовой базе; `[med]` направление
зафиксировано, деталь верифицируется на шаге; `[low]` открыто/некритично.

---

## 1. Цель и scope

Привести вкладку `API & Usage` (Apple Silicon) к законченному, простому для
пользователя виду (parity+ с Electron) и добавить недостающих облачных провайдеров.

**Пять поверхностей:**

1. **Единый выбор провайдера** — dropdown в фиксированном порядке (утверждён Human):
   `Google Gemini → OpenAI → Anthropic → Qwen → OpenRouter → Ollama Cloud → Custom`.
   Карточка настроек рендерится **только для выбранного**. `[high]`
2. **Карточка провайдера** — ключ + `Get API Key` + бейдж валидности + dropdown моделей
   (автоподтягивание после валидного ключа) + выбор модели + бюджет. `[high]`
3. **Запись использования** — парсинг token-счётчиков из API-ответов и запись в
   `settings.usage` (сейчас не пишется → статистика пустая). `[high]`
4. **Статистика** — Last Transaction Details + сводка Transcribing/Translation +
   per-model карточки + дисклеймер + Reset (эталон Electron tab 7). `[high]`
5. **Реальный баланс** — адаптер, только где провайдер отдаёт (OpenRouter first). `[med]`

**Non-goals (этот трек):**
- Любые **локальные** серверы/движки (Ollama/LM Studio/llama.cpp локально, «установи
  Ollama») — **явно отвергнуто Human**. Ollama здесь = **только облако**.
- Локальные модели (WhisperKit/MLX, скачивание кнопкой) — уже существуют, **не трогаем**.
- MCP — отдельный механизм, **не трогаем**.
- Electron UI — **не трогаем** (D-2026-07-13: Electron redesign вне программы).
- Embedded CLI-чат Codex/Grok/Qwen (трек QWEN_MCP закрыт) — не трогаем.

## 2. Принципы

1. **Простота прежде всего (Human).** Один dropdown → одна карточка. Никаких развёрнутых
   списков всех провайдеров сразу. Продвинутый пользователь не блокируется: модели
   можно ввести вручную (editable combo), если автозагрузка недоступна. `[high]`
2. **Только облако.** Все провайдеры в dropdown — облачные API по ключу. Никаких внешних
   локальных установок. `[high]`
3. **Честная индикация возможностей.** Тумблер «Use for Transcribing» показывается только
   где у провайдера реально есть аудио-модель; иначе только Translation/Editing. Реальный
   баланс — только где провайдер отдаёт; иначе локальная оценка с дисклеймером. `[high]`
4. **Переиспользуем существующее.** `ApiKeyInputRow`, `SliderRow`, `SettingsSection`,
   `CustomCloudProvider`, `ProviderRegistry`, `estimateCost` — не переписываем, расширяем. `[high]`
5. **Migration-safe settings.** Новые поля `AppSettings` через `decodeIfPresent` с
   дефолтами; существующий decode/encode не ломаем. `[high]`
6. **Статистика = данные сначала, UI потом.** Сначала запись usage (A2), потом UI (A6).
   Без записи UI показывал бы нули (текущий баг). `[high]`
7. **Buildable каждый шаг** (`swift build` / `swift test`); diff только в `target_files`. `[high]`

## 3. Топология (to-be)

```
┌────────────────────────── SettingsView → apiKeysTab ──────────────────────────┐
│  Provider Picker (единый dropdown)                                              │
│   [ Google Gemini ▾ ]  ← Gemini | OpenAI | Anthropic | Qwen | OpenRouter |      │
│                           Ollama Cloud | Custom                                 │
│        │  (рендер только для выбранного)                                        │
│        ▼                                                                        │
│  ┌─ ProviderCardView(selected) ──────────────────────────────────────────┐     │
│  │  ApiKeyInputRow  (ключ + Get API Key)            [● Valid] badge       │     │
│  │  Model Picker    (авто: CloudModelCatalog.listModels)  [▾ model]       │     │
│  │  Budget SliderRow ($0…200)                                             │     │
│  │  [Use for Transcribing] [Use for Translation]  (честно по capabilities)│     │
│  │  Balance row: real (OpenRouter) | estimated | plan limits (Ollama)     │     │
│  └────────────────────────────────────────────────────────────────────────┘     │
│                                                                                 │
│  UsageStatisticsView (эталон Electron tab 7)                                    │
│   • Last Transaction Details (badge: model) Prompt/Completion/Total tokens      │
│   • Summary: Transcribing → model · Translation/Editing → model                 │
│   • Per-model cards: N transactions · Prompt · Completion · Total · Audio min · │
│       Estimated spent · Estimated remaining                                     │
│   • «Cost is an estimate based on locally counted tokens; billing can differ.»  │
│   • [Reset Statistics]                                                          │
└─────────────────────────────────────────────────────────────────────────────────┘
        │ reads/writes                       │ reads
        ▼                                    ▼
  WorkflowStore (settings.usage)      VaniScriptCore
   ▲  writes via UsageRecorder         ├─ CloudProviderCatalog   [NEW A1]
   │                                    ├─ CloudModelCatalog      [NEW A4]
   │                                    ├─ CloudKeyValidator      [NEW A4]
   │                                    ├─ CloudBalanceService    [NEW A7]
   │                                    ├─ ProviderRegistry       [EXTEND A5]
   │                                    └─ AppSettings/ProviderUsage [EXTEND A1/A2]
   │
  CloudAudioTranscriptionEngine ─┐  (Services/, парсят usage из ответов, A2)
  CloudTextTranslationEngine ────┘  → возвращают TokenUsage → UsageRecorder
```

## 4. Текущее состояние (as-is, подтверждено) `[high]`

| Факт | Где | Вывод |
|------|-----|-------|
| `apiKeysTab` рендерит секции Gemini/OpenAI/Anthropic/Custom все сразу | `SettingsView.swift:385-678` | Нет dropdown провайдеров |
| «Text Model» = `ReadOnlyRow` с хардкодом | `SettingsView.swift:418,485,529` | Модель не выбирается |
| Модели захардкожены в `resolve()` | `CloudAudioTranscriptionEngine.swift:8-34`, `CloudTextTranslationEngine.swift:8-34` | `gemini-2.5-flash`/`whisper-1`/`gpt-4o-mini` |
| `settings.usage` пишется только в `= [:]` (reset) | `SettingsView.swift:667` | **Статистика не собирается** |
| Движки не парсят token-счётчики | grep `usageMetadata`/`prompt_tokens` → 0 в движках | Нет данных для статистики |
| `ProviderUsage`: sessions/input/output/audioMinutes/lastUsed/lastInput/lastOutput | `AppSettings.swift:162-188` | База есть; нет per-model и lastModel |
| `CustomCloudProvider` полон (baseUrl/key/model/pricing/budget) | `AppSettings.swift:189-218` | Custom переиспользуем |
| `ProviderRegistry` — центральный реестр cloud/local | `ProviderRegistry.swift` | Точка расширения A5 |
| `WorkflowStore` владеет `reviewCloudEngine`/`shortsCloudEngine`, вызывает `.translate` | `WorkflowStore.swift:118-121,1235+` | Точка записи usage |
| Эталон статистики Electron | `SettingsModal.tsx:1209-1263`, `storage.ts:163-183` (`trackUsage`) | Переносим 1:1 по смыслу |
| Реального баланса нет даже в Electron | grep `/api/v1/credits` → 0 | Новая фича (A7) |

## 5. Целевой UI-флоу (user journey)

1. Пользователь открывает Settings → **API & Usage**. Видит **один** dropdown «Provider».
2. Выбирает, напр., **Google Gemini** → появляется **только** карточка Gemini.
3. Вставляет ключ → бейдж меняется `Checking… → ● Valid` (зелёный) или `● Invalid` (красный).
4. При валидном ключе **автоподтягиваются модели** → dropdown моделей наполняется.
   Пользователь выбирает модель (или вводит вручную, если авто недоступно).
5. (Опционально) задаёт бюджет слайдером. Нажимает «Use for Transcribing/Translation».
6. Ниже — блок **статистики**: последняя транзакция (модель + токены), сводка активных
   провайдеров, per-model карточки (всего/последнее, estimated spent/remaining).
7. Для **OpenRouter** дополнительно виден **реальный баланс** (credits/key). Для
   остальных — локальная оценка с дисклеймером. Для **Ollama Cloud** — плановые лимиты.

## 6. Модель данных (расширения) `[high]`

### 6.1 `ProviderUsage` — расширяем (без ломки существующих полей)

Текущие поля остаются (`sessions, inputTokens, outputTokens, audioMinutes, lastUsed,
lastInputTokens, lastOutputTokens`). Добавляем:

- `lastModel: String?` — модель последней транзакции (для бейджа «Last Transaction»).
- `lastTransactionAt: String?` — ISO-время последней транзакции (сортировка latest).

Все новые поля — опциональны, `decodeIfPresent`, дефолт `nil`. Старые settings-файлы
читаются без миграции.

### 6.2 Per-model статистика

Эталон Electron считает статистику **per provider** (`usage[providerId]`). Скриншот
Human показывает **per model** (карточки `qwen3.7-max`, `qwen3.6-plus`). Решение:
**ключ usage = составной `providerId:model`** (напр. `qwen:qwen3.7-max`), плюс
агрегация по провайдеру на лету для сводки. Это даёт и per-model карточки, и per-provider
сводку, и «последнее использование» (сортировка по `lastTransactionAt`). `[med]` —
точная схема ключа фиксируется на A2 (совместимость с существующими `gemini`/`openai`/
`anthropic` ключами, которые пишет Electron-style; на AS они сейчас пустые, миграция не нужна).

### 6.3 `AppSettings` — новые поля (cloud-провайдеры) `[high]`

Добавляем (все `decodeIfPresent`, дефолты пустые/нулевые):

| Поле | Тип | Назначение |
|------|-----|-----------|
| `qwenApiKey` | `String` | Qwen (DashScope) cloud-ключ |
| `qwenCloudModel` | `String` | выбранная модель Qwen |
| `qwenBudgetUsd` | `Double` | бюджет Qwen |
| `openrouterApiKey` | `String` | OpenRouter-ключ |
| `openrouterModel` | `String` | выбранная модель OpenRouter |
| `openrouterBudgetUsd` | `Double` | бюджет OpenRouter |
| `ollamaCloudApiKey` | `String` | Ollama Cloud мастер-ключ |
| `ollamaCloudModel` | `String` | выбранная модель Ollama Cloud |
| `ollamaCloudBaseUrl` | `String` | дефолт `https://ollama.com` |

`geminiKey/openaiKey/anthropicKey` и `geminiBudgetUsd/openaiBudgetUsd` — **существуют**,
используем как есть. Для Gemini/OpenAI добавляем поля выбранной модели
(`geminiTextModel`, `openaiTextModel`) с дефолтом = текущий хардкод
(`gemini-2.5-flash`, `gpt-4o-mini`), чтобы не сломать поведение. `[high]`

### 6.4 `CodingKeys` / `init` / `decode`

Каждое новое поле: `case` в `CodingKeys`, параметр `init` с дефолтом, присваивание,
`decodeIfPresent` в `init(from:)`. Существующий encode/decode не меняется. `[high]`

## 7. Каталог облачных провайдеров (`CloudProviderCatalog`) `[med]`

Новый тип в `VaniScriptCore` — единый источник правды о провайдерах для UI и движков.
Убирает хардкод из `resolve()` и `SettingsView`.

```
struct CloudProviderDescriptor {
  let id: String                 // "gemini" | "openai" | "anthropic" | "qwen" |
                                 // "openrouter" | "ollama-cloud" | "custom"
  let label: String              // "Google Gemini", "OpenAI", ...
  let getApiKeyURL: String       // для кнопки Get API Key
  let modelsEndpoint: ModelsEndpoint   // как тянуть список моделей (см. §9)
  let capabilities: Capabilities // supportsTranscription / supportsTranslation /
                                 // supportsRealBalance
  let defaultTextModel: String   // fallback если автозагрузка недоступна
  let defaultAudioModel: String? // для транскрипции (whisper-1 и т.п.)
  let balanceKind: BalanceKind   // .none | .openrouterCredits | .ollamaPlan | .estimated
}
```

**Порядок в dropdown (утверждён Human, фиксированный):**
`gemini, openai, anthropic, qwen, openrouter, ollama-cloud, custom`. `[high]`

**Capabilities (честная индикация):** `[med]` — верифицируется на A5
- Gemini: transcription ✅ (мультимодальный `generateContent` с audio), translation ✅, balance ❌.
- OpenAI: transcription ✅ (`/v1/audio/transcriptions`, whisper), translation ✅, balance ❌.
- Anthropic: transcription ❌ (только текст), translation ✅, balance ❌.
- Qwen: transcription ⚠️ (аудио-модели есть, но формат верифицируется), translation ✅, balance ❌.
- OpenRouter: transcription ⚠️ (зависит от маршрутизируемой модели), translation ✅, balance ✅.
- Ollama Cloud: transcription ⚠️ (зависит от модели), translation ✅, balance → plan limits.
- Custom: определяется пользователем (существующий `CustomCloudProvider`).

Где `supportsTranscription == false` — тумблер «Use for Transcribing» **скрыт/disabled**
с пояснением. Это и есть «честная индикация». `[high]`

## 8. Конвейер записи использования (чинит пустую статистику) `[high]`

**Проблема:** движки делают HTTP, но не извлекают и не возвращают token-счётчики;
`settings.usage` не пишется. **Решение — 3 слоя:**

1. **Парсинг в движках.** `CloudAudioTranscriptionEngine` / `CloudTextTranslationEngine`
   извлекают usage из ответа:
   - Gemini: `usageMetadata.promptTokenCount` / `candidatesTokenCount` / `totalTokenCount`.
   - OpenAI-compatible (OpenAI/Qwen/OpenRouter/Ollama): `usage.prompt_tokens` /
     `completion_tokens` / `total_tokens`.
   Движок возвращает расширенный результат: текст/cues **+ `TokenUsage(input, output)`**.
   Если API не вернул счётчики — `nil` (не фейлим запрос; статистика просто не инкрементится).

2. **`UsageRecorder` (новый, `VaniScriptCore`).** Чистая, тестируемая функция-агрегатор
   (аналог Electron `trackUsage`):
   ```
   static func record(into usage: inout [String: ProviderUsage],
                      providerId: String, model: String,
                      delta: TokenUsage?, audioMinutes: Double)
   ```
   Ключ = `providerId:model` (§6.2). Инкрементит sessions/input/output/audio,
   обновляет `lastUsed/lastInput/lastOutput/lastModel/lastTransactionAt`. Идемпотентна
   по структуре, без сайд-эффектов (чистая для unit-тестов).

3. **Запись в `WorkflowStore`.** Точки вызова движков (`WorkflowStore.swift:1235+`,
   `1371+`, `1477+`, `3528+` и транскрипция) после успешного ответа вызывают
   `store.updateSettings { UsageRecorder.record(into: &$0.usage, ...) }`.
   `updateSettings` уже персистит settings (существующий механизм). `[high]`

**Инвариант:** запись usage не должна фейлить основную операцию (транскрипцию/перевод).
Ошибка парсинга usage → лог, операция успешна. `[high]`

## 9. Валидация ключа + автоподтягивание моделей `[med]`

### 9.1 `CloudKeyValidator` (новый, `VaniScriptCore`)

Лёгкая проверка ключа без тяжёлых запросов. Статусы: `idle / checking / valid / invalid(reason)`.
Стратегия по провайдерам (верифицируется на A4):
- Gemini: `GET https://generativelanguage.googleapis.com/v1beta/models?key=…` → 200 = valid.
- OpenAI: `GET https://api.openai.com/v1/models` + `Authorization: Bearer …` → 200.
- Anthropic: `GET https://api.anthropic.com/v1/models` + `x-api-key` + `anthropic-version`.
- Qwen: OpenAI-compatible `GET {dashscope}/compatible-mode/v1/models` + Bearer.
- OpenRouter: `GET https://openrouter.ai/api/v1/models` + Bearer (или `/api/v1/key`).
- Ollama Cloud: `GET https://ollama.com/api/tags` + `Authorization: Bearer …`.

Валидация запускается по потере фокуса/паузе ввода ключа (debounce), не на каждый символ.
Бейдж в UI: серый `Checking…`, зелёный `● Valid`, красный `● Invalid`. `[high]` (UX),
`[med]` (точные endpoints).

### 9.2 `CloudModelCatalog` (новый, `VaniScriptCore`)

`listModels(provider, apiKey) async throws -> [CloudModel]`. Единый интерфейс поверх
разных endpoints:
- OpenAI-compatible (OpenAI/Qwen/OpenRouter): `GET /v1/models` → `data[].id`.
- Ollama Cloud: `GET /api/tags` → `models[].name`.
- Gemini: `GET /v1beta/models` → `models[].name` (strip `models/`).
- Anthropic: `GET /v1/models` → `data[].id`.

**Поведение dropdown моделей (гибрид, по решению Architect):**
1. Ключ валиден → автозагрузка → dropdown наполняется актуальным модельным рядом.
2. Автозагрузка упала/пуста → **editable combo**: пользователь вводит model id вручную
   (продвинутый пользователь не блокируется) + кнопка `Retry`.
3. Кэш последних моделей в памяти сессии (не персистим), чтобы не дёргать API повторно.
4. Выбор модели → пишем в `settings.<provider>…Model` → Save (автосохранение settings).

Это снижает когнитивную нагрузку (обычный пользователь просто выбирает из списка) и не
блокирует эксперта. `[high]` (UX-решение), `[med]` (форматы ответов).

## 10. Статистика использования (UI, эталон Electron tab 7) `[high]`

Перенос 1:1 по смыслу из `SettingsModal.tsx:1209-1263`. Компонент `UsageStatisticsView`
(новый, в `SettingsView.swift` или отдельном файле). Данные — из `settings.usage`
(заполняется через §8). Состав:

1. **Last Transaction Details** — карточка последней транзакции: бейдж с моделью
   (`lastModel`), Prompt / Completion / Total tokens (`lastInputTokens`,
   `lastOutputTokens`, сумма). Берётся запись с максимальным `lastTransactionAt`.
2. **Сводка активных провайдеров** — `Transcribing → <providerDisplayName(transcriptionProvider)>`,
   `Translation / Editing → <providerDisplayName(translationProvider)>`. Переиспользуем
   бейджи Transcribing/Translation из текущего `apiKeysTab`.
3. **Per-model карточки** — для каждой записи `usage`: бейдж `N transactions`,
   grid: Prompt/input · Completion · Total · Audio min · Estimated spent · Estimated
   remaining. `Estimated spent` = существующая `estimateCost(...)` (расширяем на новых
   провайдеров через pricing из `CloudProviderCatalog`/`CustomCloudProvider`).
   `Estimated remaining` = `max(0, budget - spent)` (если бюджет задан, иначе `—`).
4. **Дисклеймер** под каждой карточкой: «Cost is an estimate based on locally counted
   text tokens; provider billing can differ.» (дословно из Electron).
5. **Reset Statistics** — destructive-кнопка, `settings.usage = [:]` (существует).

`providerDisplayName` маппит id → человекочитаемое имя (Gemini → «Google Gemini 2.5 Flash»
и т.д., как в Electron `providerDisplayName`). `[high]`

## 11. Реальный баланс (адаптер, только где отдаёт) `[med]`

**Новая фича** (нет даже в Electron). `CloudBalanceService` (новый, `VaniScriptCore`)
с protocol `BalanceProvider`:

```
protocol BalanceProvider { func fetchBalance(apiKey: String) async throws -> BalanceInfo }
enum BalanceInfo { case usd(remaining: Double, total: Double?)
                   case planLimits(label: String, detail: String)
                   case unavailable }
```

- **OpenRouter** (`balanceKind == .openrouterCredits`): `GET https://openrouter.ai/api/v1/credits`
  + `GET /api/v1/key` (Bearer) → реальные кредиты/лимиты в USD. Показываем как в Cline CLI:
  «остаток $X / лимит $Y». `[med]` (точный формат ответа верифицируется на A7).
- **Ollama Cloud** (`.ollamaPlan`): $-баланса нет (биллинг по GPU-времени плана). Показываем
  плановые лимиты, если API отдаёт; иначе подпись «Plan-based (GPU time)». Не вводим в
  заблуждение «$ как в OpenRouter». `[med]`
- **Остальные** (`.none`/`.estimated`): реального баланса нет → показываем только локальную
  `Estimated spent` (§10) с дисклеймером. Никаких фейковых «$». `[high]`

Баланс тянется лениво (при открытии карточки провайдера / по кнопке Refresh), с кэшем на
короткий TTL, без блокировки UI. Ошибка → тихий fallback на estimated. `[high]`

## 12. Mapping на шаги (подробно — `API_USAGE_STEPS.md`)

| Шаг | Цель | Поверхность | Зависит от |
|-----|------|-------------|-----------|
| **A1** | Discovery + data model: `CloudProviderCatalog`, расширения `AppSettings`/`ProviderUsage`, ADR | фундамент | — |
| **A2** | Запись usage: парсинг token-счётчиков в движках + `UsageRecorder` + вызовы в `WorkflowStore` + тесты | №3 (данные) | A1 |
| **A3** | UI reorg: единый dropdown провайдеров + условные карточки (рефакторинг `apiKeysTab`) | №1 | A1 |
| **A4** | `CloudKeyValidator` (бейдж) + `CloudModelCatalog` (автоподтягивание моделей, editable combo) | №2 | A3 |
| **A5** | Полноценная интеграция Qwen/OpenRouter/Ollama Cloud: ключи/модели/движки/`ProviderRegistry`, честные capabilities | №1,№2 | A4 |
| **A6** | `UsageStatisticsView` (эталон Electron tab 7) поверх данных A2 | №4 | A2, A5 |
| **A7** | `CloudBalanceService`: реальный баланс OpenRouter (+plan Ollama), fallback estimated | №5 | A5 |
| **A8** | Doc-only + acceptance smoke, ADR «API_USAGE done» | — | A6, A7 |

Порядок: **A1 → A2 → A3 → A4 → A5 → A6 → A7 → A8**. Каждый шаг buildable
(`swift build`/`swift test`), diff только в `target_files`.

## 13. Open questions / risks

| # | Вопрос | Тег | Где решается |
|---|--------|-----|--------------|
| 1 | Qwen DashScope OpenAI-compatible base URL и model id (аудио-возможности) | `[med]` | A1/A5 |
| 2 | OpenRouter endpoints `/api/v1/credits`, `/api/v1/key`, формат ответа баланса | `[med]` | A7 |
| 3 | Ollama Cloud: отдаёт ли API плановые лимиты; формат `/api/tags` с Bearer | `[med]` | A5/A7 |
| 4 | Anthropic: есть ли `/v1/models` для валидации/списка (vs messages ping) | `[med]` | A4 |
| 5 | Точная схема ключа per-model usage и совместимость с Electron-ключами | `[med]` | A2 |
| 6 | Какие модели Qwen/OpenRouter реально поддерживают аудио для транскрипции | `[med]` | A5 |
| 7 | Pricing-таблица для новых провайдеров (для estimated spent) | `[low]` | A6 |

**Риски:**
- Разные форматы ответов моделей → парсеры изолированы по провайдерам, фейл одного не
  ломает других. `[high]`
- Автозагрузка моделей требует сети → обязателен editable-fallback + Retry (§9.2). `[high]`
- Ollama Cloud не даёт $-баланс → явно не показываем «$», только plan/estimated. `[high]`

## 14. Инварианты (проверяются ревьюером каждый шаг)

1. Существующий decode/encode `AppSettings` не сломан (старые settings читаются).
2. Codex/Grok/Qwen embedded-чат, MCP server, локальные модели (WhisperKit/MLX) не тронуты.
3. Никаких локальных серверов/внешних установок (только облачные API по ключу).
4. Запись usage не фейлит транскрипцию/перевод (best-effort).
5. Тумблер Transcribing показан только где есть аудио-возможность (честная индикация).
6. Реальный $-баланс показан только где провайдер отдаёт; иначе estimated + дисклеймер.
7. Нет ключей/токенов в исходниках, логах, git; ключи только в settings/keychain.
8. Проект buildable/testable каждый шаг (`swift build` / `swift test`).
9. Diff только в `target_files` шага.
10. Well-commented code per `TEAM_CONTRACT.md` § Comments (role header + why-notes).