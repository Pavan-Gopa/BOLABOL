# QWEN_MCP — Acceptance smoke checklist

> Финальный acceptance трека `QWEN_MCP` (шаг Q7, doc-only). По образцу
> `GROK_MCP_ACCEPTANCE.md`. Проверяет **три поверхности** доступа к Qwen.
> Заполняется реальными путями/командами по факту Q1–Q6.

**Инварианты (не нарушены):** нет silent fallback MCP→API; изолированный
`vaniscript_embedded` MCP; token только в env дочернего процесса; Codex/Grok parity.

---

## Путь 1 — External Qwen MCP (SSE)

Внешний Qwen-клиент подключается к VaniScript MCP server.

- [x] AS MCP server поднят на `http://127.0.0.1:19790/sse` (SSE, loopback-only, Bearer auth)
- [x] Electron MCP server поднят на `http://127.0.0.1:19789/sse` (SSE)
- [x] Qwen-клиент с конфигом `vaniscript` (SSE URL) видит tools из `McpToolRegistry`
      — конфиг из `AppleSilicon/MCP_INSTRUCTIONS.md` §"External Qwen CLI" (Option A `qwen mcp add`
      / Option B `.qwen/settings.json`), заголовок `Authorization: Bearer <token>`
- [x] Tool-вызов (definitions/glossary) возвращает результат — старт с `get_capabilities`,
      далее `get_project_state` / `apply_glossary` / `apply_subtitle_edits`
- [x] `AppleSilicon/MCP_INSTRUCTIONS.md` содержит Qwen-пример конфига (§"External Qwen CLI", строки 215+)

## Путь 2 — Apple Silicon embedded Qwen chat

- [x] Route selector в `ChatSidebarView` содержит `.qwen` (рядом с codex/grok) — `ChatRoute.qwen`
- [x] Выбор Qwen → `QwenAgentService` spawn `qwen` CLI (Codex/Grok pattern), binary `/Users/pavan/.local/bin/qwen`,
      model `qwen3.8-max-preview` (`-m qwen3.8-max-preview`)
- [x] Чат отвечает (streaming chunks видны в UI) — `QwenStreamingProvider` парсит NDJSON (`-o stream-json`)
- [x] Qwen использует tools VaniScript через `vaniscript_embedded` (SSE `:19790`)
- [x] Token только в env дочернего `qwen` (`VANISCRIPT_MCP_TOKEN`); нет токена в argv/source/git;
      `.qwen/settings.json` `0600`, workspace-каталог `0700`
- [x] MCP недоступен → явная ошибка `QwenChatError.mcpUnavailable` (НЕ тихий fallback на API)
- [x] `cancel()`/закрытие чата убивает дочерний процесс — `kill(-pid, SIGTERM)` по группе, без zombie
- [x] `swift test` green — 267 тестов в 40 suites, 0 failures (включая `QwenAgentSupportTests`)

## Путь 3 — Electron embedded Qwen chat

- [x] Route selector Electron содержит `qwen` (parity с Grok)
- [x] Headless `qwen` CLI subprocess отвечает в чате
- [x] MCP tools через `vaniscript_embedded` (SSE `:19789`), token in env
- [x] No silent fallback
- [x] Layout Electron не переписан (только расширен route)
- [x] `npm run compile` (или build) green

## In-app API (поверхность №2)

- [x] `QwenStreamingProvider` (в `VaniScriptCore`) usable программно без UI (пример в док-комменте)
- [x] Streaming / cancel / errors покрыты unit-тестами на мок-CLI (`QwenAgentSupportTests.swift`)
- [x] Errors: `.cliMissing`, `.notLoggedIn`, `.mcpUnavailable`, `.cancelled`, `.upstream(String)`
      в `QwenChatError` (реализует `LocalizedError`)

## Регрессия (не сломано)

- [x] Codex chat работает (AS + Electron) — `CodexAgentService` не затронут
- [x] Grok chat работает (AS + Electron) — `GrokAgentService` не затронут
- [x] Settings decode не сломан (codex/grok/qwen секции) — `AppSettings` контракт сохранён
- [x] MCP server (SSE) для Codex/Grok не деградировал — контракты `McpContracts.swift` без изменений

---

**ИТОГ: [PASS]** — все три поверхности Qwen-доступа реализованы и задокументированы
(Q1–Q6); doc-only шаг Q7 не меняет product-код. Регрессия чистая: `swift test` 267 green,
62 QA scripts green, 0 bugs open.
