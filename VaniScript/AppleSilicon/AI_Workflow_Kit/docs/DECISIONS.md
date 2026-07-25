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
