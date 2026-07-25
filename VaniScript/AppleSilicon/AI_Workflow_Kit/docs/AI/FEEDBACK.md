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

---

## Q5 — External Qwen MCP access (doc-only)

**СТАТУС:** DONE — doc-only, no code changes. QA gate green (37/37 PASS, nothing broken).

### Что сделано
- `AppleSilicon/MCP_INSTRUCTIONS.md`: добавлена секция **«External Qwen CLI»** с двумя
  вариантами подключения внешнего Qwen CLI к VaniScript MCP server (`qwen mcp add ...`
  project scope + эквивалентный `.qwen/settings.json`), пояснением про токен из
  Settings → MCP, требование запущенного приложения, списком доступных tools
  (`get_project_state`, `get_subtitle_style`, `get_shorts_plans`, `apply_subtitle_edits`,
  `apply_glossary`, и др.) и security-заметками. Указана портовая разница (19789 Electron /
  19790 AS).
- `Electron/MCP_INSTRUCTIONS.md`: добавлена секция **«7. Qwen (external CLI)»** с тем же
  примером, адаптированным под Electron-сборку (endpoint `http://127.0.0.1:19789/sse`).
- `DECISIONS.md`: добавлена запись **D-2026-07-25-Q5** (doc-only, SSE endpoint, Bearer auth,
  no CORS changes, smoke-результаты).

### Smoke-проверка (статическая, без запуска Qwen)
- **Endpoint:** `http://127.0.0.1:19789/sse` присутствует в `Electron/electron/main.js`
  (`.listen(19789, '127.0.0.1')`, лог «MCP HTTP/SSE Server listening on .../sse»). `[high]`
- **Auth:** Bearer-token middleware `isMcpAuthorized` проверяет `authorization` header
  (`bearer ` + `mcpAccessToken`); также принимается `x-vaniscript-mcp-token`. `[high]`
- **CORS:** разрешены только loopback origins (`isLoopbackOrigin`); нативные MCP-клиенты без
  `Origin` → fallback `'*'`. localhost работает без изменений CORS. `[high]`

### Безопасность и контракты
- Нет изменений кода — инварианты QWEN_MCP сохранены: no silent MCP→API fallback, изолированный
  project-scope MCP config, токен только в env/config клиента (не инлайн в публичную команду).
- Токен в примерах задокументирован как `<YOUR_TOKEN>` placeholder — никаких реальных секретов
  в документацию не попало.

### Комментарии
- Доки — на английском (согласно правилам шага); ADR и FEEDBACK — на русском (формат программы).
- Верификация: `grep -c 'qwen'` и `grep -c '19789'` по `AppleSilicon/MCP_INSTRUCTIONS.md` > 0;
  `bash QA/run_all.sh` → 37/37 PASS.

**ИТОГОВЫЙ СТАТУС:** APPROVED (doc-only)

---

## Q5 — Independent Review (Verification Engineer)

**СТАТУС:** APPROVED (doc-only)

### Проверено
1. **Соответствие требованиям Q5:**
   - `AppleSilicon/MCP_INSTRUCTIONS.md`: секция «External Qwen CLI» присутствует и корректно задокументирована.
   - `Electron/MCP_INSTRUCTIONS.md`: секция «7. Qwen (external CLI)» присутствует и содержит применимый snippet.
   - Config snippets: добавлены оба формата (команда `qwen mcp add ...` и `.qwen/settings.json`).
   - Порты: четко указаны 19789 (Electron) и 19790 (Apple Silicon).
2. **Точность документации (smoke-проверка по коду):**
   - SSE endpoint `http://127.0.0.1:19789/sse` подтвержден в `Electron/electron/main.js` (строка 3311: `listen(19789, '127.0.0.1')`).
   - Bearer auth middleware `isMcpAuthorized` подтвержден в `Electron/electron/main.js` (строка 3021: проверка `authorization` и `x-vaniscript-mcp-token`).
   - Loopback CORS `isLoopbackOrigin` подтвержден в `Electron/electron/main.js` (строка 3034: фильтрация `Origin`).
   - SSE endpoint `:19790` подтвержден в `AppleSilicon/MCP_INSTRUCTIONS.md` (раздел Security Model).
3. **Безопасность:**
   - Секреты/токены не захардкожены (используется плейсхолдер `<YOUR_TOKEN>`).
   - Нет любых изменений исходного кода (diff включает строго документацию).
   - Инварианты QWEN_MCP сохранены (изолированный project scope, токен в env/config).
4. **ADR (DECISIONS.md):**
   - Запись `D-2026-07-25-Q5` создана.
   - Указан тип `DOC-ONLY`.
   - Описаны архитектурные детали подключения и результаты статической smoke-проверки.
5. **Качество документации:**
   - Секции `MCP_INSTRUCTIONS.md` написаны на английском языке.
   - Записи ADR и FEEDBACK ведутся на русском языке.
6. **target_files соблюдены:**
   - Изменения ограничены файлами `AppleSilicon/MCP_INSTRUCTIONS.md`, `Electron/MCP_INSTRUCTIONS.md`, `AppleSilicon/AI_Workflow_Kit/docs/DECISIONS.md`, `AppleSilicon/AI_Workflow_Kit/docs/AI/FEEDBACK.md`, `AppleSilicon/AI_Workflow_Kit/docs/AI/STATE.yaml`.

### Smoke-верификация по коду
- **Endpoint:** `Electron/electron/main.js:3311` (`mcpHttpServer.listen(19789, '127.0.0.1', ...)`).
- **Auth:** `Electron/electron/main.js:3021` (`isMcpAuthorized(req)` — проверка `Authorization: Bearer` и `x-vaniscript-mcp-token`).
- **CORS:** `Electron/electron/main.js:3034` (`isLoopbackOrigin(origin)` — разрешение только loopback `127.0.0.1`, `::1`, `localhost`).

### Безопасность
- Использован `<YOUR_TOKEN>` placeholder, отсутствуют реальные токены/ключи.
- Кодовая база Swift/JS/TS не изменена.

### Замечания
- Замечаний нет. Документация исчерпывающая и полная.

**ИТОГОВЫЙ СТАТУС:** APPROVED


