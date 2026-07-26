# Implementation Handoff → Verification (A2)

Шаг: **A2 — Запись использования (чинит пустую статистику)**. Роль: Implementation Engineer (Hy3).
Статус: `implementation.status = waiting_review`. Pre-tag `apiusage/pre-A2` подтверждён.

**Что сделано (target_files):**
- `Sources/VaniScriptCore/UsageRecorder.swift` (NEW) — `TokenUsage`, чистый `record(...)`
  (ключ `providerId:model`, инкремент sessions/input/output/audio + `last*`, no-op без
  сигнала), парсеры `parseGeminiUsage`/`parseOpenAIUsage` (lenient → `nil`).
- `Sources/VaniScript/Services/CloudAudioTranscriptionEngine.swift` (MODIFY) — результат
  `CloudAudioTranscriptionResult.usage: TokenUsage?`; парсинг из Gemini/OpenAI ответов.
- `Sources/VaniScript/Services/CloudTextTranslationEngine.swift` (MODIFY) — actor-аккумулятор
  usage + `takeLastUsage()`; парсинг в `generateGemini`/`generateOpenAI`.
- `Sources/VaniScript/Stores/WorkflowStore.swift` (MODIFY) — best-effort
  `recordCloudTranslationUsage(...)` после всех облачных переводов/шортс-операций;
  `normalizedUsageProviderId` (`gemini-cloud`→`gemini`, `gpt-cloud`→`openai`).
- `Tests/VaniScriptCoreTests/UsageRecorderTests.swift` (NEW) — 14 тестов (record/last*/
  per-model/best-effort/парсеры/round-trip/TokenUsage).
- `AI_Workflow_Kit/docs/DECISIONS.md` — ADR `D-2026-07-26-A2`.

**Verify:** `swift build` OK; `swift test` — **287 tests / 42 suites GREEN**.

**Инварианты §14:** decode `AppSettings` не тронут (1); Codex/Grok/Qwen/MCP/локальные модели
не тронуты (2); только облачные API (3); запись usage best-effort — не фейлит операцию (4);
нет ключей в коде/логах (7); buildable/testable (8); diff только в target_files (9);
essential comments добавлены (10).

**Scope note (важно для ревью):** облачная транскрипция вызывается из
`NativeProcessingPipeline` (вне target_files A2). Движок уже **возвращает** `usage`, но
запись транскрипции в `settings.usage` через WorkflowStore не проведена (нужна проводка в
pipeline — предложено на A5/A6). Запись переводов полностью функциональна. Требование A2
«движок возвращает токены» выполнено для обоих движков.

**Не делал:** `review.status`, инкремент `current_step`, post-tag — по контракту.
Зови оркестратора / Gemini на ревью.

---

# Verification Report (Verification Engineer)

Проверяемый шаг: **A2 — Запись использования (чинит пустую статистику)**
Требования шага: `API_USAGE_STEPS.md` (§A2), `API_USAGE_ARCHITECTURE.md` (§8, §14)
Роль: Verification Engineer (Gemini 3.6 Flash)

---

### 1. Сборка и интеграция
- **Собирается / тестируется ли проект после этих изменений?**
  Да. `swift test` выполнен успешно — **287 tests в 42 suites GREEN** (за 0.155 сек). Все 14 новых unit-тестов в `UsageRecorderTests` прошли.
- **Не нарушают ли изменения Codex/Grok/Qwen, MCP server, AppSettings decode?**
  Нет. Не затрагивались Codex/Grok/Qwen, MCP server и локальные модели (MLX/WhisperKit). `AppSettings` decode проверяется отдельной suite тестов, совместимость сохранена.

### 2. Логика и соответствие плану
- **Выполнены ли все требования текущего шага?**
  Да.
  1. `UsageRecorder.swift` создан в `VaniScriptCore`: содержит `TokenUsage`, чистую функцию `record(...)` с составным ключом `providerId:model`, lenient-парсеры `parseGeminiUsage` и `parseOpenAIUsage` (возвращают `nil` при отсутствии/ошибке usage block).
  2. `CloudAudioTranscriptionEngine`: расширен `CloudAudioTranscriptionResult` полем `usage: TokenUsage?`; парсятся токены из ответов Gemini и OpenAI-compatible API.
  3. `CloudTextTranslationEngine`: добавлен actor-isolated accumulator `accumulatedUsage` и метод `takeLastUsage()`, который атомарно считывает и сбрасывает накопленный usage после операций перевода/планирования шортсов.
  4. `WorkflowStore`: добавлен метод `recordCloudTranslationUsage`, вызываемый после всех облачных переводов и генераций шортсов. Использован `normalizedUsageProviderId` (`gemini-cloud` → `gemini`, `gpt-cloud` → `openai`) для совместимости с `estimateCost`.
  5. `UsageRecorderTests.swift`: 14 тестов полностью покрывают `UsageRecorder` (инкремент, `last*`, per-model ключи, no-op при пустом/nil `delta`, парсеры Gemini/OpenAI и JSON round-trip).
  6. ADR `D-2026-07-26-A2` добавлен в `DECISIONS.md`.
- **Оценка Scope Note по транскрипции (NativeProcessingPipeline):**
  Принято / DEFERRED OK. Движок `CloudAudioTranscriptionEngine` полностью выполнил требование шага A2 ("возвращает TokenUsage"). Файл `NativeProcessingPipeline.swift` не входил в `target_files` A2, поэтому проводка вызова `record` для транскрипции оправданно отложена до шагов A5/A6, когда pipeline попадет в scope.
- **Соблюдены ли target_files?**
  Да. Изменения выполнены строго в пределах разрешенных `target_files`:
  - `Sources/VaniScriptCore/UsageRecorder.swift` (NEW)
  - `Sources/VaniScript/Services/CloudAudioTranscriptionEngine.swift` (MODIFY)
  - `Sources/VaniScript/Services/CloudTextTranslationEngine.swift` (MODIFY)
  - `Sources/VaniScript/Stores/WorkflowStore.swift` (MODIFY)
  - `Tests/VaniScriptCoreTests/UsageRecorderTests.swift` (NEW)
  - `AI_Workflow_Kit/docs/DECISIONS.md` (MODIFY)
  - `AI_Workflow_Kit/docs/AI/FEEDBACK.md` (MODIFY)

### 3. Безопасность и контракты
- **Best-effort контракт (§14.4):**
  Выполнено. При отсутствии или ошибке парсинга `usage` операция перевода/транскрипции не фейлится. `record` является no-op если `delta` равен `nil` или пуст и `audioMinutes == 0`.
- **Хардкод ключей / логгирование секретов:**
  Ключи и секреты отсутствуют в исходниках и логах.

### 4. Комментарии и читаемость (TEAM_CONTRACT § Comments)
- **Role headers и Why-notes:**
  Все новые и измененные модули (`UsageRecorder.swift`, `CloudAudioTranscriptionEngine.swift`, `CloudTextTranslationEngine.swift`, `WorkflowStore.swift`, `UsageRecorderTests.swift`) содержат качественные role headers, ссылки на §8 / §14 архитектуры и развернутые why-notes для non-obvious логики (например, почему parsers вынесены в Core, почему использован accumulator в translation engine и почему delta сбрасывается с `defer`).

---

**ИТОГОВЫЙ СТАТУС:** [APPROVED]
