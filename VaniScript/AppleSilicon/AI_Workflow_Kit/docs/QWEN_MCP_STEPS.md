# QWEN_MCP — Step cards (Q1–Q7)

> Authoritative architecture: `QWEN_ARCHITECTURE.md`.
> Этот файл: **исполняемые step-карточки** для `STATE.yaml` (track `QWEN_MCP`).
> Эталон parity: `GROK_MCP_STEPS.md`. Acceptance: `QWEN_MCP_ACCEPTANCE.md`.
>
> **Важно:** точные имена файлов провайдеров Codex/Grok в `VaniScriptCore`
> верифицируются на **Q1** через graphify
> (`graphify explain "ChatProvider" --graph "$GRAPH"`). Ниже — ожидаемые пути `[med]`.

## Global quality (каждый coding-шаг)

- Well-commented code per `TEAM_CONTRACT.md` § Comments (role header + why-notes).
- Проект buildable каждый шаг: `swift test` (или `swift build`); Electron `npm run compile`.
- Инварианты `QWEN_ARCHITECTURE.md` §11 — на каждом шаге.
- Токены: Graphify first (MCP `graphify` или CLI `--graph "$GRAPH"`), не дампить дерево.
  `GRAPH=/Users/pavan/Documents/AI Projects/VaniScript/graphify-out/graph.json`

---

## Q1 — Discovery: Qwen CLI + фиксация контракта ChatProvider

### Goal

Исследовать доступный Qwen CLI (binary, auth, MCP-флаги, streaming-формат, model id
для Qwen 3.8 Max-Preview) и зафиксировать реальный контракт `ChatProvider`/route
selector по существующим Codex/Grok провайдерам. **Код продукта не пишем** — только
исследование + ADR + (опционально) тонкий discovery-скрипт.

### Requirements

1. Через graphify найти и описать: `ChatProvider` protocol, `CodexProvider`,
   `GrokProvider`, `ChatRoute` enum, точку spawn CLI, механизм streaming и cancel.
2. Определить Qwen CLI: binary name (`qwen`/`qwen-code`), `qwen login` (OAuth) и/или
   env-токен (`DASHSCOPE_API_KEY`/`QWEN_API_KEY`), флаг MCP-конфига, формат вывода.
3. Проверить доступность model id Qwen 3.8 Max-Preview в этом CLI.
4. Записать ADR в `DECISIONS.md`: выбранный binary, auth-механизм, MCP-флаг,
   streaming-маппинг, точные пути файлов провайдеров.
5. Обновить теги `[med]`→`[high]` в `QWEN_ARCHITECTURE.md` по фактам discovery.

### target_files (Planner/Architect, NO product code)

```yaml
target_files:
  - AI_Workflow_Kit/docs/DECISIONS.md
  - AI_Workflow_Kit/docs/QWEN_ARCHITECTURE.md
  - AI_Workflow_Kit/docs/QWEN_MCP_STEPS.md
```

### Out of scope

- Любой product-код (Q2+).
- Изменение Codex/Grok/MCP server.

### Done

- [ ] ADR в DECISIONS.md фиксирует binary/auth/MCP-флаг/streaming/model id
- [ ] Точные пути провайдеров известны и внесены в карточки Q2/Q6
- [ ] `QWEN_ARCHITECTURE.md` теги обновлены по фактам
- [ ] Verifier approved (doc-only review)

### Rollback

Tag `qwen/pre-Q1`

---

## Q2 — QwenProvider skeleton + embedded chat (Apple Silicon)

### Goal

Добавить `QwenProvider` (CLI subprocess, Codex pattern) в `VaniScriptCore` и
подключить его к route selector `ChatSidebarView` как `.qwen`. Чат с Qwen работает
в AS-клиенте. MCP пока **без** tools (plain chat) — tools подключаются на Q3.

### Requirements

1. `QwenProvider`: реализует `ChatProvider`; spawn `qwen` CLI; streaming chunks;
   `cancel()` (process group); structured errors (`.cliMissing`, `.notLoggedIn`).
2. `ChatRoute` расширяется кейсом `.qwen` (без ломки `.codex`/`.grok`).
3. `ChatSidebarView`: route selector показывает Qwen; выбор запускает `QwenProvider`.
4. Settings decode: `qwen`-секция (model/flags), без ломки Codex/Grok.
5. Unit-тест `QwenProvider` на мок-CLI (инъекция запуска), без реального binary.
6. Токен Qwen — только в env дочернего процесса; проверка login-статуса.

### target_files (Coder) — уточнить пути на Q1 `[med]`

```yaml
target_files:
  - Sources/VaniScriptCore/QwenProvider.swift          # NEW (или рядом с Grok/Codex)
  - Sources/VaniScriptCore/ChatProvider.swift          # route enum + protocol (если есть)
  - Sources/VaniScript/Views/ChatSidebarView.swift     # route selector .qwen
  - Sources/VaniScriptCore/Settings.swift              # qwen-секция decode
  - Tests/VaniScriptCoreTests/QwenProviderTests.swift  # NEW
  - AI_Workflow_Kit/docs/AI/FEEDBACK.md
```

### Out of scope

- MCP tools wiring (Q3).
- Electron (Q4).

### Done

- [ ] `swift test` green (включая новый QwenProviderTests)
- [ ] Чат с Qwen работает в AS (route selector → Qwen → ответ)
- [ ] Токен только в env; нет silent fallback
- [ ] Codex/Grok не сломаны
- [ ] Verifier approved

### Rollback

Tag `qwen/pre-Q2`

---

## Q3 — MCP wiring: Qwen → vaniscript_embedded (tools)

### Goal

Qwen в чате получает доступ к tools VaniScript через изолированный MCP server
(`vaniscript_embedded`, SSE `:19790`). Ephemeral MCP-конфиг на сессию, token в env,
no silent fallback.

### Requirements

1. `QwenProvider.send(..., mcp:)` генерирует **ephemeral** MCP-конфиг (temp dir):
   server `vaniscript_embedded`, SSE URL `http://127.0.0.1:19790/mcp`.
2. Token MCP передаётся в env дочернего `qwen` (`VANISRIPT_MCP_TOKEN`), не в argv/файл.
3. Конфиг передаётся CLI флагом (по факту Q1: `--mcp-config`/env/cwd).
4. Cleanup temp-конфига после сессии (best-effort).
5. При недоступности MCP — ошибка `.mcpUnavailable` (НЕ тихий переход на API).
6. Tools = только `McpToolRegistry` (definitions/glossary/apply); scopes не расширены.
7. Unit-тест: ephemeral config корректен, token не в argv, cleanup работает.

### target_files (Coder) `[med]`

```yaml
target_files:
  - Sources/VaniScriptCore/QwenProvider.swift
  - Sources/VaniScriptCore/McpContracts.swift         # если нужен хелпер конфига
  - Sources/VaniScriptCore/McpSessionConfig.swift      # NEW (если нет) — ephemeral config
  - Tests/VaniScriptCoreTests/QwenProviderTests.swift
  - Tests/VaniScriptCoreTests/QwenMcpConfigTests.swift # NEW
  - AI_Workflow_Kit/docs/AI/FEEDBACK.md
```

### Out of scope

- Electron MCP (Q4).
- External Qwen MCP (Q5).

### Done

- [ ] Qwen в чате вызывает tools VaniScript (definitions/glossary)
- [ ] Ephemeral config + token in env + cleanup — подтверждено тестом
- [ ] No silent fallback (ошибка при недоступном MCP)
- [ ] `swift test` green; Verifier approved

### Rollback

Tag `qwen/pre-Q3`

---

## Q4 — Electron embedded Qwen (parity с Grok)

### Goal

Embedded Qwen в Electron-клиенте через тот же route selector + headless `qwen` CLI
(симметрично Electron embedded Grok из GROK_MCP G6). MCP через SSE `:19789`.

### Requirements

1. Найти точку route selector в Electron через graphify
   (`graphify path "ChatRoute" "GrokProvider" --graph "$GRAPH"` в Electron-скопе).
2. Добавить `qwen` в route selector Electron; headless `qwen` CLI subprocess.
3. MCP wiring в Electron: ephemeral config → `vaniscript_embedded` SSE `:19789`,
   token в env дочернего процесса, no silent fallback.
4. Не переписывать layout Electron — только расширить route (parity с Grok).
5. Smoke: `npm run compile` (или build) green; чат с Qwen в Electron отвечает.

### target_files (Coder) — определить graphify на шаге `[med]`

```yaml
target_files:
  - Electron/src/.../chatRoute.ts        # route selector (уточнить graphify)
  - Electron/src/.../qwenProvider.ts     # NEW (headless qwen CLI)
  - Electron/src/.../mcpConfig.ts        # ephemeral config helper
  - AI_Workflow_Kit/docs/AI/FEEDBACK.md
```

### Out of scope

- Apple Silicon (уже Q2/Q3).
- External Qwen MCP (Q5).

### Done

- [ ] Чат с Qwen работает в Electron (route selector → Qwen)
- [ ] MCP tools доступны через `:19789`, token in env, no fallback
- [ ] `npm run compile` green; layout не переписан
- [ ] Verifier approved

### Rollback

Tag `qwen/pre-Q4`

---

## Q5 — External Qwen MCP (SSE) — опционально

### Goal

Внешний Qwen-агент (любой MCP-клиент) может подключаться к VaniScript MCP server по
SSE (`:19790` AS / `:19789` Electron) — симметрично external Grok MCP (GROK_MCP G6).

### Requirements

1. Документировать/проверить, что существующий MCP server (SSE) доступен внешнему
   Qwen-клиенту (config snippet для `qwen` MCP: server `vaniscript`, SSE URL).
2. Без изменения server-логики (она уже есть от GROK_MCP) — только конфиг-пример + smoke.
3. Если требуется — минимальный фикс CORS/headers (только при необходимости, с ADR).

### target_files (Coder) `[low]`

```yaml
target_files:
  - AppleSilicon/MCP_INSTRUCTIONS.md       # пример конфига для внешнего Qwen
  - AI_Workflow_Kit/docs/DECISIONS.md      # ADR если нужен фикс
  - AI_Workflow_Kit/docs/AI/FEEDBACK.md
```

### Out of scope

- Embedded chat (Q2/Q4 уже).
- Новые tools / scopes.

### Done

- [ ] Внешний Qwen-клиент видит tools VaniScript по SSE
- [ ] MCP_INSTRUCTIONS.md содержит Qwen-пример
- [ ] Verifier approved

### Rollback

Tag `qwen/pre-Q5`

---

## Q6 — In-app API hardening (streaming / cancel / errors + tests)

### Goal

Довести `QwenProvider` API до production-качества: стабильный streaming, корректная
отмена (process group), полный маппинг ошибок, исчерпывающие unit-тесты. Поверхность
№2 (работа через API внутри программы) для стороннего кода.

### Requirements

1. Streaming: backpressure-safe `AsyncThrowingStream<ChatChunk, Error>`; корректный
   finish/throw при обрыве CLI.
2. Cancel: SIGTERM process group; идемпотентный; без zombie-процессов.
3. Errors: `.cliMissing`, `.notLoggedIn`, `.mcpUnavailable`, `.cancelled`, `.upstream(status)`.
4. Public API surface в `VaniScriptCore` для программного использования (без UI).
5. Unit-тесты: streaming happy path, error paths, cancel, login-check, MCP config —
   всё на мок-CLI (без реального binary).
6. Комментарии: role header + why-notes (TEAM_CONTRACT § Comments).

### target_files (Coder) `[med]`

```yaml
target_files:
  - Sources/VaniScriptCore/QwenProvider.swift
  - Sources/VaniScriptCore/ChatProvider.swift
  - Tests/VaniScriptCoreTests/QwenProviderTests.swift
  - Tests/VaniScriptCoreTests/QwenMcpConfigTests.swift
  - AI_Workflow_Kit/docs/AI/FEEDBACK.md
```

### Out of scope

- UI-изменения (только API).
- Electron (Q4).

### Done

- [ ] `swift test` green, покрытие streaming/cancel/errors
- [ ] API usable без UI (пример в док-комменте)
- [ ] Нет zombie-процессов при cancel
- [ ] Verifier approved

### Rollback

Tag `qwen/pre-Q6`

---

## Q7 — Doc-only + acceptance smoke

### Goal

Финальная документация и acceptance-прогон по `QWEN_MCP_ACCEPTANCE.md`. **Без product
фич** — только доки + smoke-чеклист (как GROK_MCP G6).

### Requirements

1. `QWEN_MCP_ACCEPTANCE.md` заполнен реальными путями/командами (по факту Q1–Q6).
2. README / MCP_INSTRUCTIONS обновлены: Qwen как провайдер (AS + Electron + external).
3. Smoke-прогон всех трёх поверхностей (embedded AS, embedded Electron, external MCP).
4. ADR «QWEN_MCP done» в DECISIONS.md.

### target_files (doc-only)

```yaml
target_files:
  - AI_Workflow_Kit/docs/QWEN_MCP_ACCEPTANCE.md
  - AppleSilicon/README.md
  - AppleSilicon/MCP_INSTRUCTIONS.md
  - AI_Workflow_Kit/docs/DECISIONS.md
  - AI_Workflow_Kit/docs/AI/FEEDBACK.md
```

### Done

- [ ] Acceptance smoke пройден (3 поверхности)
- [ ] Доки актуальны
- [ ] ADR «QWEN_MCP done»
- [ ] Verifier approved → `QWEN_DONE`

### Rollback

Tag `qwen/pre-Q7`

