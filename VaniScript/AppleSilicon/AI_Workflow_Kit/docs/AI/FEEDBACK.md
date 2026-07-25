# Шаблон проверки (Verification Template)

Проверяемый шаг: Q6 — In-app API hardening (streaming / cancel / errors + tests)
Требования шага: `QWEN_MCP_STEPS.md` (§Q6)

---

### 1. Сборка и интеграция
- **Собирается / тестируется ли проект после этих изменений?** Да. `swift test` в `VaniScript/AppleSilicon` полностью успешен: 267 тестов в 40 suites прошли без ошибок (0 failures).
- **Проверка App Store compliance:** `grep -ci electron MCP_INSTRUCTIONS.md` -> 0. Тест `AppStoreNativeComplianceTests` полностью green.
- **Не нарушают ли изменения Codex/Grok path, MCP server, settings decode?** Нет. `CodexAgentService` и `GrokAgentService` не затронуты. MCP сервер и настройки сохраняют прежние контракты.

### 2. Логика и соответствие плану
- **Выполнены ли все требования текущего шага (Q6)?** Да.
  - **Streaming:** Реализован `AsyncThrowingStream<QwenChatChunk, Error>` в `QwenStreamingProvider`. Стримит текстовые фрагменты (`.text`), вызовы инструментов (`.toolUse`) и завершающий результат (`.done(QwenAgentRun)`).
  - **Cancel:** Метод `cancel()` посылает `SIGTERM` всей группе процессов (`kill(-pid, SIGTERM)`) и `process.terminate()` в качестве fallback. Идемпотентен, исключает появление процессов-зомби.
  - **Errors:** Объявлен enum `QwenChatError` со всеми требуемыми кейсами (`.cliMissing`, `.notLoggedIn`, `.mcpUnavailable`, `.cancelled`, `.upstream(String)`) и реализацией `LocalizedError`.
  - **Public API surface:** `QwenStreamingProvider`, `QwenChatProvider`, `QwenChatChunk`, `QwenChatError`, `QwenChatHistoryItem` и общие CLI-хелперы вынесены в `VaniScriptCore`. API полностью пригодно для программного использования без UI.
  - **Unit-тесты:** В `QwenAgentSupportTests.swift` добавлены тесты на `QwenChatChunk`, `QwenChatError`, `QwenChatHistoryItem` и идемпотентность `cancel()`.
- **Задокументированное отклонение:** Вынос `QwenStreamingProvider` и общих хелперов в `VaniScriptCore` вместо `VaniScript` (app target) технически обоснован: SwiftPM запрещает импорт executable-таргетов в тестовые библиотеки (`VaniScriptCoreTests`). `QwenAgentService.send()` в app-слое остался работоспособным.
- **Нет ли самодеятельности?** Нет. UI не изменен, Q7 (документация/акцептанс) не затронут, MCP server / tools не расширялись.
- **Соблюдены ли target_files?** Да, изменения внесены строго в целевые файлы из списка `STATE.yaml`.

### 3. Безопасность и контракты
- **Нет ли хардкода MCP token / API keys?** Нет. Токен авторизации передается исключительно через `process.environment` (`VANISCRIPT_MCP_TOKEN`).
- **Нет ли silent fallback MCP chat → API?** Нет. Если MCP выключен или не готов, выбрасывается `QwenChatError.mcpUnavailable`.
- **Isolated MCP / scopes не ослаблены?** Нет. Эфемерный конфиг пишется в директорию воркспейса с правами `0o700`, файл настроек `.qwen/settings.json` имеет права `0o600`. Разрешен только сервер `vaniscript_embedded`.
- **Thread safety & cancellation:** Синхронизация состояния `QwenStreamingProvider` выполнена через `OSAllocatedUnfairLock` (async-safe Swift 6 strict concurrency lock).

### 4. Комментарии и читаемость (TEAM_CONTRACT § Comments)
- **Role headers:** Присутствуют во всех вынесенных публичных типах и `QwenStreamingProvider` с описанием ответственности слоя, ограничений и инвариантов.
- **Why-комментарии:** Размещены `// Q6:` комментарии, объясняющие причину отмены через группу процессов `kill(-pid, SIGTERM)`, использование `OSAllocatedUnfairLock` вместо `NSLock`, маппинг `notLoggedIn` по выводу stderr и регистрацию процесса до запуска.
- **Язык:** Документирование кода выполнено на английском языке.

### 5. Конкретный список правок (не требуется)
Отсутствуют. Реализация Q6 полностью соответствует всем критериям качества и безопасности.

---

**ИТОГОВЫЙ СТАТУС:** APPROVED
