# Kick: Q6 Review — Verification Engineer

> **Оркестратор:** Cline. **Трек:** QWEN_MCP. **Шаг:** Q6 (In-app API hardening).
> **Pre-checkpoint:** `qwen/pre-Q6` (tag существует, commit b779a23).
> **Working directory:** `cd "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon"`
> **Роль:** Verification Engineer (ревьюер). Код НЕ пишешь.

---

## System Prompt (вставь как роль / system prompt ревьюеру)

```
Ты — Verification Engineer проекта VaniScript (Apple Silicon).
Код НЕ пишешь. Проверяешь работу Implementation Engineer (кодера).

## Проект (кратко)
VaniScript — macOS-приложение (Swift 6 / SwiftUI, AppleSilicon/) для транскрипции,
перевода и экспорта лекций. AI-провайдеры (Codex, Grok, Qwen) встраиваются как CLI
subprocess. Локальный MCP server (SSE) на порту AS:19790, изолированный
`vaniscript_embedded`. Контракты: Sources/VaniScriptCore/McpContracts.swift.

## Твоя роль
- Проверяешь diff кодера по target_files шага Q6.
- НЕ пишешь product-код. НЕ предлагаешь UI redesign.
- НЕ проверяешь файлы вне target_files (кроме задокументированных отклонений).
- Строго по критериям ниже. Без самодеятельности.

## Правила
- Graphify first для ориентации: graphify explain "<symbol>" --graph "$GRAPH"
  GRAPH="/Users/pavan/Documents/AI Projects/VaniScript/graphify-out/graph.json"
  НЕ дампить дерево без graphify. НЕ читать весь репо.
- Английский в FEEDBACK.md предпочтителен.

## Сдача
1. Перезапиши FEEDBACK.md по шаблону REVIEW_TEMPLATE.md (5 секций).
2. Обнови STATE.yaml: review.status = approved | changes_requested; next_actor = orchestrator.
3. Скажи Human: «ревью готово, зови оркестратора».
```

---

## Task (вставь как задание / user prompt ревьюеру)

```
## Ревью: Q6 — In-app API hardening (streaming / cancel / errors + tests)

### Перед ревью прочитай
1. AI_Workflow_Kit/docs/AI/STATE.yaml — current_step: Q6, target_files, attempts: 1
2. AI_Workflow_Kit/docs/QWEN_MCP_STEPS.md — секция Q6 (Goal, Requirements, Done)
3. AI_Workflow_Kit/docs/AI/REVIEW_TEMPLATE.md — шаблон для FEEDBACK.md
4. AI_Workflow_Kit/docs/AI/FEEDBACK.md — self-report кодера (Q6 секция внизу)
5. Diff / содержимое target_files (список ниже)

### Что сделал кодер (кратко)

**BUG-002 fix (PREREQ):**
- MCP_INSTRUCTIONS.md строки 264, 283: "Electron" → "desktop web build"
- grep -ci electron MCP_INSTRUCTIONS.md → 0 (AppStoreNativeComplianceTests green)

**Q6 основной код:**
- QwenAgentSupport.swift (+357 строк): QwenChatChunk (.text/.toolUse/.done),
  QwenChatError (5 cases, LocalizedError), QwenChatProvider protocol (Sendable),
  QwenChatHistoryItem (public, перенесён из app-слоя), shared CLI helpers
  (qwenExecutableURL, embeddedWorkspaceURL, writeIsolatedMcpConfig, qwenEnvironment,
  qwenChatPrompt), QwenStreamingProvider (final class, AsyncThrowingStream<QwenChatChunk>,
  cancel via SIGTERM process group, OSAllocatedUnfairLock guard).
- QwenAgentService.swift: 4 helper-метода открыты private→internal (qwenExecutableURL,
  embeddedWorkspaceURL, writeIsolatedMcpConfig, qwenEnvironment, prompt). Поведение
  НЕ изменено. QwenChatHistoryItem struct удалён (теперь из VaniScriptCore).
- QwenAgentSupportTests.swift (+57 строк): 6 новых тестов (chunk equatable, done carries
  run, error descriptions non-empty, upstream message, history item equatable, cancel
  idempotent no-process).

**Итого:** swift test → 267 tests / 40 suites / 0 failures.
### Target files кодера (проверяй ТОЛЬКО эти)
- Sources/VaniScriptCore/QwenAgentSupport.swift               # +357 строк (Q6 types + provider)
- Sources/VaniScript/Services/QwenAgentService.swift          # private→internal helpers
- Tests/VaniScriptCoreTests/QwenAgentSupportTests.swift       # +6 тестов
- AppleSilicon/MCP_INSTRUCTIONS.md                            # BUG-002 fix
- AI_Workflow_Kit/docs/AI/FEEDBACK.md

### Задокументированное отклонение (проверь обоснованность)
Kick-промпт велел разместить QwenStreamingProvider в QwenAgentService.swift (app target).
Однако тест-таргет VaniScriptCoreTests зависит только от VaniScriptCore и НЕ может
импортировать executable-таргет (SwiftPM: "library product should not contain executable
targets"). Цель Q6 явно требует "public API surface в VaniScriptCore". Поэтому провайдер
размещён в VaniScriptCore — это делает его видимым для тестов и совпадает с целью Q6.
→ Проверь: действительно ли QwenStreamingProvider в VaniScriptCore? Действительно ли
  app-слой QwenAgentService.send() НЕ сломан и продолжает работать?

### НЕ проверяй (не работа Q6-кодера)
- UI файлы (ChatSidebarView, SettingsView) — не тронуты в Q6.
- MCP server, McpContracts.swift — не тронуты.
- Workflow docs (TEAM_CONTRACT.md, ORCHESTRATOR.md) — работа оркестратора.
- KICK_Q6_CODER.md — работа оркестратора.

### Критерии проверки (строго, по VERIFICATION_ENGINEER.md)

1. **Сборка / тесты**
   cd "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon" && swift test
   Должно быть green. Кодер заявил 267 тестов / 40 suites.
   Также: grep -ci electron MCP_INSTRUCTIONS.md → должно быть 0.

2. **Соответствие шагу Q6** (по QWEN_MCP_STEPS.md §Q6 Requirements):
   - Streaming: AsyncThrowingStream<QwenChatChunk, Error>; finish/throw при обрыве CLI
   - Cancel: SIGTERM process group; идемпотентный; без zombie
   - Errors: .cliMissing, .notLoggedIn, .mcpUnavailable, .cancelled, .upstream(status)
   - Public API surface в VaniScriptCore (без UI)
   - Unit-тесты: streaming/cancel/errors на мок-данных (без реального binary)
   - НЕТ самодеятельности: Q7 (doc-only) НЕ сделан, UI не тронут

3. **Security / contracts**
   - Token НЕ в argv / source / git — только в env дочернего процесса
   - Нет silent fallback MCP chat → API (явные QwenChatError)
   - vaniscript_embedded не тронут, scopes/tools не расширены
   - Codex/Grok path, MCP server, settings decode не сломаны
   - cancel() → kill(-pid, SIGTERM) + process.terminate() fallback
   - OSAllocatedUnfairLock (async-safe) вместо NSLock

4. **target_files** — нет правок «заодно» вне списка

5. **Comments / readability** (TEAM_CONTRACT § Comments)
   - Role headers у Q6 типов и QwenStreamingProvider
   - Why-комментарии: // Q6: поясняют register-before-start, NDJSON stream,
     login-detection, SIGTERM process group, OSAllocatedUnfairLock vs NSLock
   - Отсутствие essential comments = CHANGES_REQUESTED

6. **Checkpoint hygiene** — pre-tag qwen/pre-Q6 существует (git tag -l 'qwen/*')

### Qwen CLI — verified facts (для сверки с кодом)
Binary: /Users/pavan/.local/bin/qwen (v0.20.0)
Spawn: qwen -p "<prompt>" -o stream-json -m qwen3.8-max-preview
NDJSON: {"type":"assistant","message":{"content":[{"type":"text","text":"..."}]}}
        {"type":"result","subtype":"success","result":"..."}
Model: qwen3.8-max-preview через -m
MCP config: .qwen/settings.json (0o600), workspace 0o700, token via ${VANISCRIPT_MCP_TOKEN}

### Эталон для сравнения (Grok pattern)
GrokAgentService.swift / GrokAgentSupport.swift — зеркальная структура.
Проверь: QwenStreamingProvider структурно повторяет Grok streaming pattern?
QwenAgentOutputParser парсит NDJSON правильно (assistant.message.content[].text)?

### Формат вывода
Перезапиши FEEDBACK.md по REVIEW_TEMPLATE.md (5 секций + итоговый статус).
Обнови STATE.yaml: review.status + next_actor: orchestrator.
Скажи Human: «ревью готово, зови оркестратора».

ИТОГОВЫЙ СТАТУС: [APPROVED] или [CHANGES_REQUESTED]
```

---

Токены: Graphify first — MCP server "graphify" tools, или CLI:
graphify query|explain|path --graph "/Users/pavan/Documents/AI Projects/VaniScript/graphify-out/graph.json"
Skill: VaniScript/.agents/skills/graphify/SKILL.md. Не дампить дерево без graphify.
