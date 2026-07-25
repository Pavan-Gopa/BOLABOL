# VaniScript — Qwen 3.8 Max-Preview Integration: Architectural Specification

> Архитектурный план внедрения **Qwen 3.8 Max-Preview** как первого класса
> AI-провайдера VaniScript: (1) embedded chat в запущенном CLI-клиенте,
> (2) работа через API внутри программы, (3) интеграция с MCP (Qwen использует
> tools VaniScript через изолированный `vaniscript_embedded` MCP server).
> План наследует проверенные инварианты трека **GROK_MCP** (Codex pattern).
>
> **Track:** `QWEN_MCP` (шаги Q1–Q7, карточки в `QWEN_MCP_STEPS.md`).
> **Status:** Accepted design, not yet implemented.
> **Companion docs:** `QWEN_MCP_STEPS.md`, `QWEN_MCP_ACCEPTANCE.md`,
> `GROK_MCP_STEPS.md` (эталон parity), `PROJECT_CONTEXT.md`.

**Accuracy tags:** `[high]` подтверждено в кодовой базе; `[med]` направление
зафиксировано, деталь верифицируется на шаге; `[low]` открыто/некритично.

---

## 1. Цель и scope

Дать VaniScript третьего embedded-провайдера — **Qwen 3.8 Max-Preview** — наравне
с Codex и Grok, с тремя поверхностями доступа:

1. **Embedded chat** — пользователь общается с Qwen прямо в чате VaniScript при
   запущенном CLI-клиенте (route selector в ChatSidebarView, parity с Grok). `[high]`
2. **In-app API** — Qwen доступен программно внутри `VaniScriptCore` через общий
   `ChatProvider`-интерфейс (стриминг, отмена, ошибки), без UI. `[high]`
3. **MCP integration** — Qwen CLI подключается к локальному MCP server VaniScript
   (`vaniscript_embedded`) и вызывает tools (definitions/glossary) как часть диалога. `[high]`

**Non-goals (этот трек):** UI redesign (трек UI_AS закрыт); изменения export
pipeline / редактора; замена Codex/Grok — только **добавление** Qwen рядом (parity).

## 2. Принципы (наследуют GROK_MCP, DECISIONS D-2026-07-13/14)

1. **Embedded = CLI subprocess (Codex pattern).** Qwen живёт как дочерний процесс
   CLI (`qwen`/`qwen-code`), а не как in-process SDK. `[med]` — точный binary и его
   флаги верифицируются на Q1 (discovery).
2. **Auth via CLI login, token в env только дочернего процесса.** Аналог `grok login`
   → `qwen login` (OAuth) ИЛИ env-токен. Никаких токенов в argv/исходниках. `[med]`
3. **No silent fallback MCP chat → API.** Если MCP-путь не сконфигурирован/упал —
   явная ошибка пользователю, не тихий переход на прямой API. `[high]`
4. **Isolated MCP.** Qwen получает **ephemeral** MCP-конфиг только на
   `vaniscript_embedded`; scopes/tools не расширяются «заодно». `[high]`
5. **Parity с Codex/Grok.** Один и тот же `ChatProvider`-контракт; route selector
   расширяется значением `qwen`, а не переписывается. `[high]`
6. **Переиспользуем существующий MCP server.** Порты AS `19790` / Electron `19789`
   (SSE) уже подняты GROK_MCP — Qwen подключается к ним же. `[high]`

## 3. Топология

```
┌──────────────────────────── VaniScript ────────────────────────────┐
│  ChatSidebarView (route selector: codex | grok | qwen)             │
│        │                                                           │
│        ▼                                                           │
│  VaniScriptCore: ChatProvider protocol                             │
│   ├─ CodexProvider   (CLI subprocess)        [existing]            │
│   ├─ GrokProvider    (CLI subprocess)        [existing]            │
│   └─ QwenProvider    (CLI subprocess)        [NEW — Q2/Q6]         │
│        │  spawn `qwen` with:                                       │
│        │   - ephemeral MCP config → vaniscript_embedded            │
│        │   - token in child env only                               │
│        ▼                                                           │
│  Local MCP server (mcp_bridge.py)  AS:19790 / Electron:19789 (SSE) │
│   └─ McpToolRegistry: definitions / glossary tools   [existing]    │
└────────────────────────────────────────────────────────────────────┘
        ▲ external Qwen MCP (opt, Q5)    ▲ in-app API (Q6)
        │ SSE client → :19790/:19789     │ VaniScriptCore public surface
```

## 4. QwenProvider — in-app API (поверхность №2)

**Слой:** `VaniScriptCore` (Swift). **Роль:** единая точка доступа к Qwen для UI и
кода; владеет lifecycle CLI-процесса, стримингом, отменой, маппингом ошибок.
**Must-not:** хранить токены; делать silent fallback; расширять MCP scopes.

Контракт (уточняется по существующему `ChatProvider` на Q1): `[med]`

```swift
// Ориентировочно — сверить с реальным протоколом Codex/Grok провайдеров.
protocol ChatProvider {
    var id: ChatRoute { get }            // .codex | .grok | .qwen
    func send(_ prompt: String, mcp: McpSessionConfig?)
        -> AsyncThrowingStream<ChatChunk, Error>
    func cancel()
}
```

Требования: streaming chunks (token-by-token) как у Grok/Codex; structured errors
(`.notLoggedIn`, `.cliMissing`, `.mcpUnavailable`, `.cancelled`); `cancel()` убивает
дочерний процесс (process group); unit-тестируемость через инъекцию «как запускать
CLI», чтобы тесты не требовали реального `qwen` binary. `[high]`

## 5. MCP integration (поверхность №3)

Qwen CLI умеет читать MCP-конфиг. На сессию чата VaniScript генерирует **ephemeral**
конфиг (temp file), указывающий на локальный MCP server:

- transport: **SSE** (как external Grok MCP), URL `http://127.0.0.1:19790/mcp` (AS)
  или `:19789` (Electron). `[high]` — порты уже заняты GROK_MCP.
- server name: `vaniscript_embedded` (изолированно). `[high]`
- tools: только из `McpToolRegistry` (definitions/glossary/apply). Не расширяем. `[high]`
- token: передаётся **в env дочернего процесса** (`VANISRIPT_MCP_TOKEN`), не в argv,
  не в файл конфига в открытом виде. `[high]`
- lifecycle: конфиг создаётся перед `send()`, удаляется после (best-effort cleanup). `[high]`

**No silent fallback:** если MCP server не отвечает — `QwenProvider` кидает
`.mcpUnavailable`, UI показывает явную ошибку. Прямой API-вызов в обход MCP —
запрещён для чат-пути. `[high]`

## 6. Auth (поверхность доступа)

- **CLI login (предпочтительно):** `qwen login` (OAuth) — токен хранит сам CLI в своём
  keychain/config; VaniScript его не читает и не логирует. `[med]`
- **Env token (fallback для CI/headless):** `DASHSCOPE_API_KEY` / `QWEN_API_KEY`
  передаётся **только в env дочернего процесса**. `[med]` — точное имя переменной и
  механизм auth верифицируются на Q1.
- Запрещено: токены в argv, в исходниках, в git, в ephemeral MCP-конфиге открыто. `[high]`
- Проверка «залогинен ли» — отдельная лёгкая команда/флаг CLI (как у Grok), чтобы UI
  мог показать «Qwen: not logged in → run `qwen login`». `[med]`

## 7. Isolation и безопасность

- **Ephemeral MCP config** на сессию, в temp-директории (не в репо, не вUserData). `[high]`
- **Scope guard:** Qwen видит только `vaniscript_embedded`; никаких дополнительных
  MCP-серверов в его конфиге. `[high]`
- **Token in child env only:** родительский процесс VaniScript не держит токен Qwen в
  своей памяти дольше необходимого; в дочерний — через env при spawn. `[high]`
- **Process hygiene:** `cancel()`/закрытие чата → SIGTERM process group дочернего CLI. `[high]`
- Ревьюер (Verification) проверяет эти инварианты на каждом Q-шаге (REVIEW_TEMPLATE §3). `[high]`

## 8. Parity с Codex/Grok и Electron

- **Apple Silicon (Swift):** `QwenProvider` в `VaniScriptCore`; route selector
  `ChatSidebarView` расширяется кейсом `.qwen` (иконка/подпись в стиле Grok). `[high]`
- **Electron (TS):** embedded Qwen через тот же route selector + headless `qwen` CLI
  (parity с Electron embedded Grok из GROK_MCP G6). `[med]` — точная точка в
  Electron-коде определяется на Q4 через graphify.
- **Settings decode:** добавляется `qwen`-секция (model, flags) без ломки существующих
  Codex/Grok настроек. `[high]`
- **External Qwen MCP (опционально, Q5):** внешний Qwen-агент может подключаться к
  VaniScript MCP по SSE (`:19790`/`:19789`) — симметрично external Grok MCP. `[low]`

## 9. Mapping на шаги (подробно — `QWEN_MCP_STEPS.md`)

| Шаг | Цель | Поверхность |
|-----|------|-------------|
| **Q1** | Discovery: Qwen CLI binary/auth/MCP-флаги; фиксация контракта `ChatProvider` | — (исследование + ADR) |
| **Q2** | `QwenProvider` skeleton + embedded chat (AS), route selector `.qwen` | №1, №2 |
| **Q3** | MCP wiring: ephemeral config → `vaniscript_embedded`, token in env, no-fallback | №3 |
| **Q4** | Electron embedded Qwen (parity с Grok) | №1 |
| **Q5** | External Qwen MCP (SSE) — опционально | №3 (внешний) |
| **Q6** | In-app API hardening: streaming/cancel/errors + unit tests | №2 |
| **Q7** | Doc-only + acceptance smoke (`QWEN_MCP_ACCEPTANCE.md`) | — |

## 10. Open questions / risks

| # | Вопрос | Тег | Где решается |
|---|--------|-----|--------------|
| 1 | Точный Qwen CLI binary (`qwen` vs `qwen-code`) и его MCP/auth-флаги | `[med]` | Q1 discovery |
| 2 | Имя env-переменной токена (`DASHSCOPE_API_KEY`/`QWEN_API_KEY`) | `[med]` | Q1 |
| 3 | Как CLI читает ephemeral MCP config (флаг `--mcp-config` / env / cwd) | `[med]` | Q1/Q3 |
| 4 | Streaming-формат вывода CLI (SSE/NDJSON/plain) для маппинга в `ChatChunk` | `[med]` | Q2 |
| 5 | Доступность Qwen 3.8 Max-Preview в выбранном CLI (model id) | `[med]` | Q1 |
| 6 | Точка route selector в Electron | `[med]` | Q4 (graphify) |

## 11. Инварианты (проверяются ревьюером каждый шаг)

1. Нет токенов в argv / исходниках / git / ephemeral-конфиге открыто.
2. Нет silent fallback MCP chat → API.
3. `vaniscript_embedded` изолирован; scopes/tools не расширены.
4. Codex/Grok path, MCP server, settings decode не сломаны.
5. Проект buildable/testable каждый шаг (`swift test` / `swift build`; Electron `npm run compile`).
6. Diff только в `target_files` шага.


