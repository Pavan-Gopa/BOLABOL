# Шаблон проверки (Verification Template)

Проверяемый шаг: Q2 — QwenProvider skeleton + embedded chat (Apple Silicon)
Требования шага: `QWEN_MCP_STEPS.md` (§Q2)

---

### 1. Сборка и интеграция
- **Собирается / тестируется ли проект после этих изменений?** Да. `swift test` выполнен успешно в `VaniScript/AppleSilicon` (257 тестов в 39 suites прошли без ошибок).
- **Не нарушают ли изменения Codex/Grok path, MCP server, settings decode?** Нет. `CodexAgentService` и `GrokAgentService` не затронуты. `qwenChatModelID` декодируется с фоллбеком на `defaultModelID` через `decodeIfPresent`, старые JSON-настройки сохраняются.

### 2. Логика и соответствие плану
- **Выполнены ли все требования текущего шага (Q2)?** Да.
  - Добавлен `QwenAgentSupport.swift` с каталогом моделей (`qwen3.8-max-preview`) и парсером NDJSON stream-json.
  - Добавлен `QwenAgentService.swift` для спавна CLI `qwen -p <prompt> -o stream-json -m <modelID> --safe-mode`.
  - В `McpContracts.swift` добавлен профиль `.qwen`.
  - В `AppSettings.swift` добавлено поле `qwenChatModelID`.
  - В `ChatSidebarView.swift` интегрирован маршрут `.qwen` и селектор моделей `qwenModelMenu`.
  - В `SettingsView.swift` добавлена секция "Embedded Qwen Chat" в вкладке Agents.
  - Добавлены модульные тесты в `QwenAgentSupportTests.swift` на парсинг фикстур NDJSON.
- **Нет ли самодеятельности (Q3+ MCP wiring, Q4 Electron)?** Нет. Использован `--safe-mode`, MCP инструменты и интеграция с `vaniscript_embedded` отложены до Q3.
- **Соблюдены ли target_files?** Да, target_files соблюдены. Отклонение по `McpSecurityContractTests.swift` обосновано: 1) добавлен "Qwen" в ожидаемый список профилей из-за `CaseIterable`, 2) актуализация количества инструментов со 120 до 122 отражает предсуществующий дрейф каталога на HEAD.

### 3. Безопасность и контракты
- **Нет ли хардкода MCP token / API keys?** Нет. Токен передается строго в `environment` дочернего процесса (`VANISCRIPT_MCP_TOKEN`).
- **Нет ли silent fallback MCP chat → API?** Нет. При ошибках генерируются явные `QwenAgentError` (`.mcpUnavailable`, `.qwenNotInstalled`, `.launchFailed`, `.unavailable`, `.noResponse`).
- **Isolated MCP / scopes не ослаблены?** Нет. Флаг `--safe-mode` изолирует сессию.
- **(QWEN_MCP) Token только в env дочернего процесса?** Да. `setupText` ссылается на `$VANISCRIPT_MCP_TOKEN` без инлайн-значения токена.

### 4. Комментарии и читаемость (TEAM_CONTRACT § Comments)
- **Role headers:** Присутствуют в `QwenAgentSupport.swift` и `QwenAgentService.swift` с описанием слоя, ответственности, ограничений и инвариантов.
- **Why-комментарии:** Включены инлайн-комментарии `// Q2:` объясняющие причину использования `--safe-mode`, отсутствие `reasoningEffort` у Qwen, структуру парсера NDJSON и обновления контрактных тестов.

### 5. Конкретный список правок (не требуется)
Отсутствуют. Код соответствует всем критериям Q2.

---

**ИТОГОВЫЙ СТАТУС:** APPROVED

---

## Q3 — MCP wiring: Qwen → vaniscript_embedded (tools)

**СТАТУС:** DONE — `swift test` green (261 tests, 40 suites).

### Что сделано
- `QwenAgentService.swift`: убран `--safe-mode`; добавлен `writeIsolatedMcpConfig(workspaceURL:port:)`,
  вызываемый в `send()` до spawn; prompt теперь содержит MCP tool-инструкции (mirror Grok);
  best-effort cleanup эфемерного `.qwen/` конфига после сессии; role header/комментарии Q2 → Q3.
- `QwenMcpConfig.swift` (NEW, VaniScriptCore): чистый билдер `.qwen/settings.json` —
  server `vaniscript_embedded`, SSE `http://127.0.0.1:<port>/sse`, header
  `Authorization: Bearer ${VANISCRIPT_MCP_TOKEN}`, `trust: true`. Тестируемый без spawn.
- `McpContracts.swift`: обновлён qwen `setupText` (SSE + `--scope project --trust`, token via env).
- Тесты: `QwenMcpConfigTests.swift` (NEW) — server name/URL/port, token via env only (no secret inlined),
  валидный JSON и no silent fallback инварианты.

### Формат конфига Qwen CLI (verified)
`qwen mcp add ... --scope project` пишет `.qwen/settings.json` с ключом `mcpServers`.
Env substitution `${VANISCRIPT_MCP_TOKEN}` сохраняется дословно → секрет не попадает в файл.

### Безопасность
- Token только в env дочернего процесса; в argv и в `settings.json` — только `${VANISCRIPT_MCP_TOKEN}`.
- No silent fallback: `.mcpUnavailable` при `mcpConfiguration.canStart == false`.
- Изоляция: project-scope MCP в 0o700 workspace, единственный разрешённый server — `vaniscript_embedded`.
