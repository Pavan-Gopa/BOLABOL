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


