# QWEN_MCP — Acceptance smoke checklist

> Финальный acceptance трека `QWEN_MCP` (шаг Q7, doc-only). По образцу
> `GROK_MCP_ACCEPTANCE.md`. Проверяет **три поверхности** доступа к Qwen.
> Заполняется реальными путями/командами по факту Q1–Q6.

**Инварианты (не нарушены):** нет silent fallback MCP→API; изолированный
`vaniscript_embedded` MCP; token только в env дочернего процесса; Codex/Grok parity.

---

## Путь 1 — External Qwen MCP (SSE)

Внешний Qwen-клиент подключается к VaniScript MCP server.

- [ ] AS MCP server поднят на `http://127.0.0.1:19790/mcp` (SSE)
- [ ] Electron MCP server поднят на `http://127.0.0.1:19789/mcp` (SSE)
- [ ] Qwen-клиент с конфигом `vaniscript` (SSE URL) видит tools из `McpToolRegistry`
- [ ] Tool-вызов (definitions/glossary) возвращает результат
- [ ] `AppleSilicon/MCP_INSTRUCTIONS.md` содержит Qwen-пример конфига

## Путь 2 — Apple Silicon embedded Qwen chat

- [ ] Route selector в `ChatSidebarView` содержит `.qwen` (рядом с codex/grok)
- [ ] Выбор Qwen → `QwenProvider` spawn `qwen` CLI (Codex pattern)
- [ ] Чат отвечает (streaming chunks видны в UI)
- [ ] Qwen использует tools VaniScript через `vaniscript_embedded` (SSE `:19790`)
- [ ] Token только в env дочернего `qwen`; нет токена в argv/конфиге открыто
- [ ] MCP недоступен → явная ошибка `.mcpUnavailable` (НЕ тихий fallback на API)
- [ ] `cancel()`/закрытие чата убивает дочерний процесс (нет zombie)
- [ ] `swift test` green (включая QwenProviderTests / QwenMcpConfigTests)

## Путь 3 — Electron embedded Qwen chat

- [ ] Route selector Electron содержит `qwen` (parity с Grok)
- [ ] Headless `qwen` CLI subprocess отвечает в чате
- [ ] MCP tools через `vaniscript_embedded` (SSE `:19789`), token in env
- [ ] No silent fallback
- [ ] Layout Electron не переписан (только расширен route)
- [ ] `npm run compile` (или build) green

## In-app API (поверхность №2)

- [ ] `QwenProvider` usable программно без UI (пример в док-комменте)
- [ ] Streaming / cancel / errors покрыты unit-тестами на мок-CLI
- [ ] Errors: `.cliMissing`, `.notLoggedIn`, `.mcpUnavailable`, `.cancelled`

## Регрессия (не сломано)

- [ ] Codex chat работает (AS + Electron)
- [ ] Grok chat работает (AS + Electron)
- [ ] Settings decode не сломан (codex/grok/qwen секции)
- [ ] MCP server (SSE) для Codex/Grok не деградировал

---

**ИТОГ:** [PASS] / [FAIL] — при FAIL список блокеров → `FEEDBACK.md` → «зови оркестратора».
