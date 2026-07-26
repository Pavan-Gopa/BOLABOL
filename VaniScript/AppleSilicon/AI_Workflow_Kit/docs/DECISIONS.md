# DECISIONS — VaniScript multi-agent program

## D-2026-07-13 — Orchestration model

- Roles mirror **AuraSplitter / KirtanSplitter** `AI_Workflow_Kit`.
- Orchestrator: **Grok**. Implementation: **Hy3/Coder**. Verification: **Gemini 3.5 Flash**.
- File bus only: `STATE.yaml` + `FEEDBACK.md`.
- **Git checkpoint before every step and after every approved step** (commit + tag + push when possible).

## D-2026-07-13 — Product scope

1. **GROK_MCP first** (AS + Electron functional Grok).
2. **UI_AS second** — visual density **Apple Silicon only** (user override: no Electron redesign in this program).
3. Embedded Grok = CLI subprocess (Codex pattern), auth via `grok login`, no silent API fallback.
4. Isolation: ephemeral project MCP config; token in env only.

## D-2026-07-13 — Git root

- Workspace git root is `AI Projects/`.
- Checkpoint script scopes adds to `VaniScript/AppleSilicon/**` (and Electron when step says so).
- If remote push is DISABLED, local commit+tag is still mandatory; human pushes when able.

## D-2026-07-14 — GROK_MCP acceptance

- G6 is doc-only (no product features). Smoke checklist lives in `GROK_MCP_ACCEPTANCE.md`.
- Three accepted paths: (1) external Grok MCP via SSE — AS `19790`, Electron `19789`; (2) AS embedded chat for **Codex and Grok**; (3) Electron embedded Grok via the chat route selector + headless `grok` CLI.
- Invariants unchanged: no silent MCP→API fallback; isolated `vaniscript_embedded` MCP; token in child env only; Codex/Grok parity.

## D-2026-07-25 — QWEN_MCP track (Qwen 3.8 Max-Preview)

- Новый трек **QWEN_MCP** (Q1–Q7 → `QWEN_DONE`): Qwen 3.8 Max-Preview как первый класс
  AI-провайдера VaniScript. Три поверхности: (1) embedded chat в запущенном CLI-клиенте,
  (2) in-app API внутри `VaniScriptCore`, (3) MCP integration (Qwen → изолированный
  `vaniscript_embedded` MCP server).
- Архитектура: `QWEN_ARCHITECTURE.md` (accuracy tags `[high]/[med]/[low]`). Шаги:
  `QWEN_MCP_STEPS.md`. Acceptance: `QWEN_MCP_ACCEPTANCE.md`.
- **Наследует инварианты GROK_MCP:** embedded = CLI subprocess (Codex pattern);
  auth via `qwen login` / env token в дочернем процессе; **no silent MCP→API fallback**;
  изолированный ephemeral MCP config; parity с Codex/Grok; переиспользуем существующий
  MCP server (AS `:19790` / Electron `:19789`, SSE).
- **Открытые вопросы** (верифицируются на Q1 discovery): точный Qwen CLI binary и его
  MCP/auth-флаги, имя env-токена, формат streaming-вывода, model id Qwen 3.8 Max-Preview.
- **QA gate** введён для coding-шагов (Q2–Q6): advance только после approve **и** QA green.
- **Graphify** подключён как dev-инструмент для экономии токенов (граф `VaniScript/graphify-out/graph.json`,
  MCP server `graphify` в Cline). Не product-код.

## D-2026-07-25 — Workflow kit upgrade (QA + Graphify + kick-шаблоны)

- Добавлены роли **Architect/Planner** (on-demand, Qwen 3.8 Max) и **QA Script Engineer**.
- QA-контур: `QA/` (run_all.sh, manifest.json, COVERAGE.md, build-gate + MCP smoke скрипты),
  триаж багов через оркестратора (product-фиксы — **только Coder**).
- Kick-шаблоны для чистых агентов: `KICK_CODER.md`, `KICK_REVIEWER.md`, `KICK_QA.md`.
- Comments-bar (TEAM_CONTRACT § Comments) + REVIEW_TEMPLATE §4 — обязательная читаемость кода.
- Graphify first: агенты запрашивают граф вместо bulk-grep/дампа дерева.

## D-2026-07-25 — Q1 Discovery: Qwen CLI (verified)

**Binary:** `/Users/pavan/.local/bin/qwen` (v0.20.0, "Qwen Code"). `[high]`

**Auth:** OpenAI-compatible. `~/.qwen/settings.json` → `env.BAILIAN_TOKEN_PLAN_API_KEY`.
Также `DASHSCOPE_API_KEY` в env. `qwen auth` — removed (не используется).
Для embedded: токен передаётся **только в env дочернего процесса**. `[high]`

**MCP:** `qwen mcp add <name> <url> --transport sse --header "Authorization: Bearer <token>" --scope project --trust`.
Изоляция: `--scope project` + ephemeral workspace (аналог Grok `--cwd`).
`--safe-mode` отключает все кастомизации (для troubleshooting). `[high]`

**Streaming:** `-o stream-json` → NDJSON:
- `{"type":"system","subtype":"init",...}` — инициализация (model, tools, session_id)
- `{"type":"assistant","message":{"content":[{"type":"text","text":"..."}]}}` — ответ
- `{"type":"result","subtype":"success","result":"...","usage":{...}}` — финал
Парсер: `QwenAgentOutputParser` (аналог `GrokAgentOutputParser`). `[high]`

**Model:** `qwen3.8-max-preview` через `-m qwen3.8-max-preview`. `[high]`

**Non-interactive:** `-p "prompt"` или `--prompt-file <path>`. `[high]`

**CLI differences from Grok:**
- Нет глобального `--trust` (trust per-MCP-server via `mcp add --trust`)
- Нет `--cwd` (изоляция через `--scope project` + ephemeral config)
- `--output-format stream-json` (не `streaming-json` как у Grok)
- NDJSON формат отличается: `assistant.message.content[].text` vs Grok `{"type":"text","data":"..."}`

**Точные пути провайдеров (verified):**
- `Sources/VaniScript/Services/GrokAgentService.swift` — эталон для QwenAgentService
- `Sources/VaniScriptCore/GrokAgentSupport.swift` — эталон для QwenAgentSupport
- `Sources/VaniScript/Views/ChatSidebarView.swift` — route selector (ChatRoute enum, sendMessage)
- `Sources/VaniScriptCore/McpContracts.swift` — McpClientProfileID (добавить .qwen)
- `Sources/VaniScriptCore/AppSettings.swift` — settings (добавить qwenChatModelID, qwenChatReasoningEffort)

## Open

- ~~Qwen CLI binary/auth/MCP-флаги/streaming-формат/model id — верифицировать на Q1.~~ **DONE (D-2026-07-25 Q1)**

## D-2026-07-25-Q5 — External Qwen MCP access (doc-only)

- **Тип:** DOC-ONLY. Никаких изменений кода (Swift/JS/TS/Python не трогаем). `[high]`
- **Суть:** Документирован подключение **внешнего** Qwen CLI (запущенного вручную в
  терминале, не embedded) к VaniScript MCP server и использование его tools.
- **SSE endpoint:** `http://127.0.0.1:19789/sse` (Electron build). Native AS build — `19790`
  (см. Security Model в `AppleSilicon/MCP_INSTRUCTIONS.md`). `[high]`
- **Auth:** Bearer token (тот же, что у embedded чата) в заголовке `Authorization`:
  `Bearer <YOUR_TOKEN>`. Сервер также принимает `x-vaniscript-mcp-token`. `[high]`
- **No CORS changes needed:** сервер биндится на loopback и отвергает non-loopback `Origin`;
  localhost-клиенты работают как есть. `[high]`
- **Доки обновлены:** `AppleSilicon/MCP_INSTRUCTIONS.md` (секция «External Qwen CLI») и
  `Electron/MCP_INSTRUCTIONS.md` (секция «7. Qwen (external CLI)»). Оба варианта:
  `qwen mcp add ... --transport sse --header "Authorization: Bearer <token>" --scope project --trust`
  и эквивалентный `.qwen/settings.json`. `[high]`
- **Smoke (static, без запуска Qwen):** endpoint `19789/sse` присутствует в
  `Electron/electron/main.js` (`.listen(19789, '127.0.0.1')`); Bearer-auth middleware
  `isMcpAuthorized` проверяет `authorization` header (`bearer ` + token); CORS разрешает
  только loopback origins. `[high]`
- **Out of scope:** embedded chat (done Q2/Q4), новые tools/scopes, изменение логики MCP
  server, изменение CORS. `[high]`

## D-2026-07-26-Q7 — QWEN_MCP track complete

- **Тип:** DOC-ONLY. Финальный ADR трека QWEN_MCP.
- **Итог:** Все 3 поверхности Qwen-доступа реализованы и задокументированы:
  1. External Qwen MCP (SSE) — Q5
  2. Apple Silicon embedded Qwen chat — Q2/Q3/Q6
  3. Electron embedded Qwen chat — Q4
  + In-app API (VaniScriptCore) — Q6
- **Шаги:** Q1 (discovery) → Q2 (AS skeleton) → Q3 (MCP wiring) →
  Q4 (Electron) → Q5 (external) → Q6 (API hardening) → Q7 (doc/acceptance).
- **Тесты:** 267 unit tests, 62 QA scripts, 0 bugs open.
- **Инварианты соблюдены:** no silent fallback, token env-only,
  vaniscript_embedded isolated, Codex/Grok parity.
- **Статус:** QWEN_MCP → QWEN_DONE.

## D-2026-07-26-API_USAGE — Реорганизация вкладки «API & Usage» (Apple Silicon)

- **Контекст:** Вкладка `API & Usage` (SettingsView → `apiKeysTab`) в Apple Silicon
  версии недоделана относительно Electron-эталона. Подтверждено в коде:
  (1) все провайдерские карточки (Gemini/OpenAI/Anthropic/Custom) развёрнуты всегда —
  нет единого выбора провайдера; (2) «Text Model» — `ReadOnlyRow` с захардкоженными
  значениями (`gemini-2.5-flash`, `gpt-4o-mini / whisper-1`, `claude-3-5-sonnet`) в
  `ActiveCloud*Provider.resolve()`; (3) **статистика пустая, т.к. `settings.usage`
  нигде не пишется** — движки `CloudAudioTranscriptionEngine`/`CloudTextTranslationEngine`
  не парсят token-счётчики из API-ответов и не вызывают запись (в Electron есть
  `trackUsage()` в `src/services/storage.ts`, в Swift аналога нет); (4) отсутствуют
  cloud-провайдеры Qwen / OpenRouter / Ollama Cloud; (5) нет реального баланса
  (нет даже в Electron — там локальная оценка по токенам).
- **Решение:** Новый трек **API_USAGE** (A1–A8 → `API_USAGE_DONE`), **только Apple Silicon**.
  1. **Единый dropdown провайдеров** в фиксированном порядке (утверждён Human):
     `Google Gemini → OpenAI → Anthropic → Qwen → OpenRouter → Ollama Cloud → Custom`.
     Карточка настроек показывается **только для выбранного** провайдера (снижение
     когнитивной нагрузки — требование Human «чем проще, тем лучше»).
  2. **Карточка провайдера:** ключ + кнопка **Get API Key** (существующий `ApiKeyInputRow`)
     + **бейдж валидности** (Checking / Valid / Invalid) + **автоподтягивание моделей**
     в dropdown (после валидного ключа) + выбор модели + бюджет. Новая фича, улучшает
     и Swift, и Electron.
  3. **Запись usage** (чинит пустую статистику): парсинг token-счётчиков из ответов
     Gemini (`usageMetadata.promptTokenCount/candidatesTokenCount`) и OpenAI-compatible
     (`usage.prompt_tokens/completion_tokens`), возврат из движков, запись в
     `settings.usage` через `WorkflowStore` (аналог Electron `trackUsage`).
  4. **Статистика по эталону Electron** (`SettingsModal.tsx` tab 7): Last Transaction
     Details (с бейджем модели) + сводка Transcribing / Translation-Editing → модель +
     per-model карточки (`N transactions · Prompt · Completion · Total · Audio min ·
     Estimated spent · Estimated remaining`) + дисклеймер «Cost is an estimate…» +
     Reset Statistics.
  5. **Реальный баланс — адаптером, только где провайдер отдаёт** (OpenRouter:
     `GET /api/v1/credits` + `GET /api/v1/key`). Где не отдаёт — локальная estimated
     spent (как сейчас). Ollama Cloud — плановые лимиты (биллинг по GPU-времени, не $).
  6. **Custom** = существующий `CustomCloudProvider` (механизм полон), просто перенос
     в новый dropdown-поток.
- **Альтернативы (отвергнуты):**
  - *Оставить развёрнутые карточки* — отвергнуто: когнитивная нагрузка, требование Human.
  - *Локальный сервер (автодетект Ollama/LM Studio/llama.cpp, «установи Ollama»)* —
    **отвергнуто явно (Human):** уход от любых локальных установок внешних программ.
    Всё облачное = облачные API-ключи. Локальные модели = только встроенные рекомендованные
    (WhisperKit/MLX), скачиваются кнопкой внутри приложения — **вне скоупа этого трека**.
    Ollama в dropdown = **только облако** (`https://ollama.com`, мастер-ключ, `/api/tags`).
  - *Реальный баланс для всех провайдеров* — отвергнуто: не все отдают (Anthropic/Gemini
    не дают $-баланс по ключу); честно показываем estimate там, где реального нет.
  - *LightLLM и подобные self-hosted* — отвергнуто: требуют установки/администрирования,
    противоречит требованию простоты.
- **Риски / ограничения:**
  - Qwen/OpenRouter/Ollama имеют разные аудио-возможности → тумблер «Use for Transcribing»
    показывается **честно** только где реально есть аудио-модель; иначе только Translation.
  - Ollama Cloud биллинг по GPU-времени в рамках плана (Free/Pro/Max), сессионные/недельные
    лимиты — «$-баланс как в OpenRouter» для него невозможен, не вводим в заблуждение.
  - Migration: новые поля settings через `decodeIfPresent` (не ломаем существующий decode).
  - Endpoints новых провайдеров (Qwen DashScope OpenAI-compatible, OpenRouter, Ollama Cloud)
    верифицируются на A1/A5; до тех пор теги `[med]`.
- **Точность:** структура и точки интеграции `[high]` (подтверждено в коде);
  endpoints/возможности новых провайдеров `[med]` (верификация на A1/A5);
  точные model id и формат баланса `[med]`.
- **Компаньон-доки:** `API_USAGE_ARCHITECTURE.md` (спек), `API_USAGE_STEPS.md` (A1–A8).
- **Scope guard:** только Apple Silicon (`Sources/**`, `Tests/**`); Electron не трогаем
  (parity-улучшение Swift-side, Electron redesign вне программы — DECISIONS D-2026-07-13).



## D-2026-07-26-A1 — API_USAGE A1: data-model foundation + endpoint discovery

- **Status:** Implemented (awaiting verification).
- **Context:** Первый шаг трека API_USAGE. Нужен единый источник правды о cloud-провайдерах
  и migration-safe расширение модели данных под новых провайдеров и per-model статистику,
  без изменения UI/движков.
- **Decision:**
  1. Новый `Sources/VaniScriptCore/CloudProviderCatalog.swift`: `CloudProviderDescriptor`
     (id, label, getApiKeyURL, modelsEndpoint, capabilities, defaultTextModel,
     defaultAudioModel, balanceKind) + фиксированный порядок
     `[gemini, openai, anthropic, qwen, openrouter, ollama-cloud, custom]` + `providerDisplayName(_:)`.
     Вспомогательные типы: `ModelsEndpoint`, `CloudProviderCapabilities`, `BalanceKind`.
  2. `AppSettings`: новые поля §6.3 (`geminiTextModel`/`openaiTextModel` с дефолтом текущего
     хардкода; `qwen*`/`openrouter*`/`ollamaCloud*` ключи/модели/бюджеты). Все через
     `decodeIfPresent` — старые settings читаются без миграции.
  3. `ProviderUsage`: `lastModel`, `lastTransactionAt` (опциональны, `decodeIfPresent`;
     добавлен явный `init(from:)` для явного контракта миграции).
  4. Unit-тест `AppSettingsCloudFieldsTests`: legacy-decode → дефолты; round-trip; порядок каталога.
- **Endpoint discovery (A1, curl без ключей):**
  - OpenRouter `GET /api/v1/models` → HTTP 200; `GET /api/v1/key` → HTTP 401 (жив, нужен Bearer).
  - Ollama Cloud `GET https://ollama.com/api/tags` → HTTP 200.
  - Qwen DashScope `GET .../compatible-mode/v1/models` (intl + cn) → HTTP 401 (жив, нужен Bearer).
  - Теги `[med]`→`[high]` обновлены в `API_USAGE_ARCHITECTURE.md` §7/§9.
- **Out of scope (A1):** UI, запись usage (A2), валидация/списки моделей (A4), баланс (A7),
  движки. Точные model id / аудио-capabilities новых провайдеров уточняются на A5 (пока
  дефолты-заглушки в каталоге).
- **Verification:** `swift build` + `swift test` — 273 tests, 41 suites, GREEN.

## D-2026-07-26-A2 — API_USAGE A2: usage recording (fixes empty statistics)

- **Status:** Implemented (awaiting verification).
- **Context:** Движки делали HTTP-запросы, но не извлекали token-счётчики; `settings.usage`
  никогда не писался → статистика всегда пустая. A2 добавляет запись usage без изменения
  UI и без ломания транскрипции/перевода (best-effort, инвариант §14.4).
- **Decision:**
  1. Новый `Sources/VaniScriptCore/UsageRecorder.swift` — чистый, тестируемый слой:
     - `TokenUsage(inputTokens, outputTokens)` (+`+`, `isEmpty`).
     - `record(into:providerId:model:delta:audioMinutes:now:)` — агрегатор по ключу
       `providerId:model` (§6.2): инкремент sessions/input/output/audio + обновление
       `last*`. No-op когда нет ни токенов, ни аудио (best-effort — нет пустых записей).
     - `parseGeminiUsage(from:)` (`usageMetadata.promptTokenCount`/`candidatesTokenCount`)
       и `parseOpenAIUsage(from:)` (`usage.prompt_tokens`/`completion_tokens`). Парсеры
       вынесены в Core (а не в app-target движки) чтобы быть тестируемыми из
       `VaniScriptCoreTests`; любой сбой декода/отсутствие usage → `nil` (не бросают).
  2. **Движки возвращают токены:**
     - `CloudAudioTranscriptionEngine`: `CloudAudioTranscriptionResult.usage: TokenUsage?`;
       парсинг из Gemini/OpenAI ответов, проброс в результат.
     - `CloudTextTranslationEngine`: actor-аккумулятор + `takeLastUsage()`; каждый
       `generate*` складывает распарсенный delta (несколько HTTP-вызовов в одной
       операции суммируются), стор считывает и сбрасывает один раз после операции.
       Выбран аккумулятор (а не смена типа возврата `translate`) чтобы не менять
       десятки вызовов и не ломать MLX-движок с той же сигнатурой (минимальный diff).
  3. **`WorkflowStore` пишет `settings.usage`:** приватный best-effort
     `recordCloudTranslationUsage(from:provider:)` вызывается после каждого успешного
     облачного перевода/шортс-планирования (`reviewCloudEngine`/`shortsCloudEngine`).
     `normalizedUsageProviderId` маппит `gemini-cloud`→`gemini`, `gpt-cloud`→`openai`
     (совместимо с ключами `estimateCost` для A6).
- **Scope note:** облачная транскрипция вызывается из `NativeProcessingPipeline`
  (не в `target_files` A2). Движок уже **возвращает** `usage` в результате; проводка
  записи транскрипции в settings — когда pipeline попадёт в scope (A5/A6). Требование
  A2 «движок возвращает токены» выполнено; запись через WorkflowStore покрывает переводы.
- **Out of scope (A2):** UI статистики (A6), новые провайдеры в движках (A5), баланс (A7).
- **Verification:** `swift build` + `swift test` — 287 tests, 42 suites, GREEN (14 новых
  в `UsageRecorderTests`).

## D-2026-07-26-A5 — API_USAGE A5: Qwen / OpenRouter / Ollama Cloud full integration

- **Status:** Implemented (awaiting verification).
- **Context:** A3 оставил Qwen/OpenRouter/Ollama Cloud карточками-заглушками ("coming
  soon"). A5 превращает их в рабочих провайдеров: ключ → валидация/модели (A4) →
  Translation. Транскрипция — честно off (нет верифицированного аудио-API).
- **Decision:**
  1. **`CloudChatRouter` в `ProviderRegistry.swift` (Core).** Чистый слой routing
     (`CloudChatRoute`: providerID/label/model/apiKey/endpoint/headers), тестируемый
     из `VaniScriptCoreTests` без сети/ключей. Движки (app target) делегируют ему.
  2. **Endpoints (все OpenAI-compatible chat/completions, Bearer):** `[high]`
     - Qwen: `https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions`
       (тот же DashScope compatible-mode base, что и CloudModelCatalog, A1 verified).
     - OpenRouter: `https://openrouter.ai/api/v1/chat/completions`.
     - Ollama Cloud: `{ollamaCloudBaseUrl|https://ollama.com}/v1/chat/completions` —
       выбран OpenAI-compatible `/v1` вместо нативного `/api/chat`, чтобы все три
       провайдера шли через ОДИН request/response/usage-парсер
       (`generateOpenAICompatible`, рефакторинг бывшего `generateOpenAI`; gpt-cloud
       поведение 1:1). Trailing slashes у base URL нормализуются.
  3. **Provider ids = catalog ids** (`qwen`/`openrouter`/`ollama-cloud`, БЕЗ суффикса
     `-cloud` как у legacy `gemini-cloud`): `normalizedUsageProviderId` в WorkflowStore
     пропускает их без remap → usage-ключи `providerId:model` (§8) корректны без
     правки WorkflowStore (вне target_files A5).
  4. **ProviderRegistry:** translation-опции при непустом ключе (паттерн gemini/gpt);
     transcription-опции — data-driven по `capabilities.supportsTranscription`
     (сегодня все три `false` → опций нет; включение = флип флага в каталоге).
  5. **Capabilities (честно):** transcription у Qwen/OpenRouter/Ollama Cloud НЕ
     заявляется — у Qwen ASR-модели (qwen-audio) не верифицированы через
     compatible-mode, OpenRouter/Ollama Cloud не дают STT endpoint. UI-тумблер
     "Use for Transcribing" виден, но disabled + tooltip/пояснение.
     `CloudAudioTranscriptionEngine.resolve` намеренно без новых кейсов.
  6. **UI:** `comingSoonCard` заменён generic `cloudProviderCard` (key +
     `CloudKeyModelRow` + budget slider где есть поле + Base URL для Ollama +
     честные toggles). Ollama budget-слайдера нет (plan-based, A7).
- **Scope note:** проводка записи usage транскрипции через NativeProcessingPipeline
  по-прежнему deferred — новые провайдеры не транскрибируют, переводы пишутся через
  существующий A2-путь (`recordCloudTranslationUsage`), который автоматически
  покрывает новые ids.
- **Out of scope (A5):** stats UI (A6), реальный баланс (A7), локальные модели, MCP.
- **Verification:** `swift build` + `swift test` — 320 tests, 46 suites, GREEN
  (+12 новых: `ProviderRegistryCloudTests`, `CloudProviderRoutingTests`).

---

## D-2026-07-26-A7 — Real balance adapter (OpenRouter first)

- **Context:** §11 — показывать реальный баланс/лимиты только там, где провайдер их
  отдаёт; иначе честный Estimated spent без фейковых «$». Ленивая загрузка + кэш +
  тихий fallback.
- **Decision:**
  1. **`CloudBalanceService` (NEW, VaniScriptCore, actor):** protocol `BalanceProvider`
     `{ func fetchBalance(apiKey:) async throws -> BalanceInfo }`; enum
     `BalanceInfo` = `.usd(remaining:total:)` / `.planLimits(label:detail:)` / `.unavailable`.
     Сеть инжектится через `CloudHTTPFetcher` (reuse из CloudModelCatalog A4) → парсеры
     тестируются на моках, без реальных запросов/ключей.
  2. **OpenRouter (`.openrouterCredits`) — фактические формы ответа (verified A7):**
     - `GET https://openrouter.ai/api/v1/credits` (Bearer) →
       `{ "data": { "total_credits": Double, "total_usage": Double } }`.
     - `GET https://openrouter.ai/api/v1/key` (Bearer) →
       `{ "data": { "limit": Double?, "limit_remaining": Double?, "usage": Double,
       "is_free_tier": Bool, ... } }` (`limit`/`limit_remaining` = null → безлимитный ключ).
     - Маппинг: `accountRemaining = total_credits − total_usage`; если у ключа задан
       per-key cap, берём `min(accountRemaining, limit_remaining)` (никогда не завышаем
       остаток). `total` = `limit` ключа, иначе `total_credits`. Показ: «$X remaining /
       $Y limit» (как Cline CLI).
  3. **Ollama Cloud (`.ollamaPlan`):** публичного $-/plan-эндпоинта баланса нет →
     честная подпись «Plan-based (GPU time)» (никаких фейковых «$»). Если API
     впоследствии отдаст plan-лимиты — прокидываются в `.planLimits(detail:)`.
  4. **Honesty guard:** для `.none`/`.estimated` (Gemini/OpenAI/Anthropic/Qwen/Custom)
     сервис ВООБЩЕ не ходит в сеть и возвращает `.unavailable` (провайдер-маппинг = nil).
     Любая сетевая/парс-ошибка → тихий `.unavailable` (без crash, UI на Estimated).
  5. **Кэш:** in-memory TTL (default 60s) по provider id; Refresh (`force: true`)
     обходит кэш. Session-only, ничего не персистится, ключи не логируются.
  6. **UI:** `CloudBalanceRow` (module-visible, в SettingsView) — строка баланса +
     Refresh + ProgressView; рендерится только для real-balance kinds. Provider cards
     (`cloudProviderCard`) и `UsageStatisticsView` (секция `realBalanceSection`, только
     провайдеры с ключом) переиспользуют её.
- **Out of scope (A7):** баланс для Gemini/Anthropic/Qwen (нет API) — только Estimated;
  запись usage (A2), stats layout (A6), A8 docs/acceptance.
- **Verification:** `swift build` OK; `swift test` — 331 tests / 47 suites GREEN
  (+ suite `CloudBalanceService (A7)`: парсеры credits/key, маппинг per-key cap, Ollama
  plan, guard `.estimated`/`.none` no-fetch, quiet fallback, TTL cache, force refresh).


## D-2026-07-26-A8 — API_USAGE done (doc-only acceptance)

- **Status:** Implemented (awaiting verification). Закрывает трек `API_USAGE` (A1–A8).
- **Context:** Все product-фичи трека закрыты на A1–A7 (каталог/данные, запись usage,
  dropdown+карточки, валидация+модели, интеграция Qwen/OpenRouter/Ollama Cloud,
  статистика UI, реальный баланс). A8 — финальная документация + acceptance smoke,
  без изменений product-кода (как GROK_MCP G6 / QWEN_MCP Q7).
- **Decision:**
  1. **`API_USAGE_ACCEPTANCE.md` (NEW):** чеклист по 5 поверхностям вкладки
     «API & Usage» с реальными путями/командами по факту A1–A7; smoke-команды;
     регрессионная секция; итог [PASS].
  2. **`AppleSilicon/README.md`:** новая секция «Cloud Providers & the API & Usage
     tab» — провайдеры в порядке каталога (вкл. Qwen/OpenRouter/Ollama Cloud),
     5 поверхностей, honesty-принципы (§14.5/§14.6), ссылка на ACCEPTANCE.
  3. Product-код (Swift/JS/TS) не тронут — diff только в docs (target_files A8).
- **Smoke (A8):** `swift build` green; `swift test` — **331 tests / 47 suites PASS**
  (без сети/реальных ключей — моки). Инварианты §14 соблюдены; QA A7: 133 PASS /
  0 FAIL, bugs_open: 0.
- **Outcome:** после approve Verifier → `API_USAGE_DONE`, tag `apiusage/A8-done`.


## D-2026-07-27-CLOUD_PROVIDER_STABILIZATION — Endpoint profiles, model capabilities and role policy

- **Status:** Architecture accepted for planning; implementation not started.
- **Context:** После закрытия `API_USAGE` Human предоставил native UI evidence
  (`OBS-001…OBS-005`):
  1. Qwen Token Plan key не проходит validation;
  2. generic `Use for Translation` наблюдается как no-op;
  3. OpenRouter transcription заблокирован provider-wide, хотя audio support
     зависит от выбранной модели/route;
  4. model picker не показывает context и input/output price;
  5. Anthropic/Custom присутствуют в Settings, но не имеют полного workflow routing.
- **Decision:**
  1. Новый ограниченный Apple Silicon track:
     `CLOUD_PROVIDER_STABILIZATION`.
  2. Credential kind, billing plan и region становятся first-class
     `CloudEndpointProfile`. Один resolver обслуживает key validation, model
     discovery и runtime URLs. Для Qwen минимальный подтверждённый набор:
     Pay-as-you-go International и Token Plan Singapore.
  3. Human’s requirement «универсально» означает: один выбранный Qwen
     credential/profile доступен API translation/editing и embedded Qwen CLI.
     Provider secret передаётся child process только через environment; MCP token,
     config, tools, scopes и no-silent-fallback invariant не меняются.
  4. `CloudModel` расширяется до source-attributed model descriptor с optional
     context, price, modalities и transcription route kind. Неизвестные значения
     не подменяются нулями. Token Plan Credits не маркируются как PAYG USD.
  5. Provider-wide `supportsTranscription` больше не является достаточным
     основанием. Settings, `ProviderRegistry`, workflow synchronization и runtime
     preflight используют одну pure `ProviderRolePolicy`.
  6. UI может включить роль только если policy подтверждает credential/profile,
     selected/effective model и реализованный executable route. Disabled role
     остаётся видимой с точной причиной.
  7. Anthropic получает нативный Messages API translation adapter; Custom —
     ограниченный явно выбранным OpenAI-compatible text protocol. Audio для них
     не заявляется.
  8. OpenRouter transcription добавляется только per-model через подтверждённый
     dedicated STT или audio-input text-output route.
  9. Существующие `UsageRecorder`, `CloudBalanceService`, provider/usage ids и
     migration-safe settings сохраняются; они не создаются заново.
- **Supersedes narrow API_USAGE assumptions:**
  - D-2026-07-26-A5 пункт «OpenRouter не даёт STT endpoint» больше не считается
    актуальным provider-wide утверждением.
  - Один общий DashScope endpoint недостаточен для всех Qwen key/billing profiles.
  - Наличие provider в Settings не считается доказательством runtime integration.
- **Evidence gate:** точный source-level root cause `OBS-002` остаётся `UNKNOWN`;
  CPS-01 обязан перевести его в `VERIFIED` до product fix.
- **Scope guard:** Apple Silicon only; Electron, MCP protocol/scopes, local
  WhisperKit/MLX, Codex/Grok, usage aggregation и balance вне трека.
- **Documents:** `CLOUD_PROVIDER_STABILIZATION_ARCHITECTURE.md`,
  `CLOUD_PROVIDER_STABILIZATION_STEPS.md`.
