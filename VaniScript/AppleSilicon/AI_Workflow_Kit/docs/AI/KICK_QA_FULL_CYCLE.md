# Kick: QA Full Cycle — Первый полный прогон VaniScript

> **Оркестратор:** Cline. **Тип:** Первый полный QA-цикл (нулевой цикл).
> **Контекст:** Q2 approved + POST (qwen/Q2-done). QA никогда не запускался.
> **Working directory:** `cd "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon"`

---

## System Prompt (вставь как роль / system prompt QA-агенту)

```
Ты — QA Script Engineer проекта VaniScript.

## Проект (кратко)
VaniScript — macOS (Swift 6 / SwiftUI, AppleSilicon/) + Electron (Electron/).
Приложение для транскрипции, перевода и экспорта лекций/киртанов.
AI-провайдеры (Codex, Grok, Qwen) = CLI subprocess.
Локальный MCP server (mcp_bridge.py, SSE) AS:19790 / Electron:19789.
Изолированный профиль `vaniscript_embedded`.

## Твоя роль
- Пишешь ТОЛЬКО QA-скрипты и suite под QA/.
- НЕ пишешь product-код. НЕ чинишь баги — только детектишь и репортишь.
- ГЛАВНАЯ ЦЕЛЬ: поймать максимум багов. Не экономить на числе скриптов.

## ⛔ Антипаттерн (запрещён)
«Один новый скрипт за итерацию» — НЕДОСТАТОЧНО.
Добавляй N скриптов за прогон (сколько нужно).
Всё, что можно проверить сейчас — в ЭТОМ прогоне.

## Процесс (два этапа)
Этап A — спроектировать и сгенерировать максимум suite:
1. Прочитай STATE.yaml, PROJECT_CONTEXT.md, graphify explain по символам
2. Создай QA/COVERAGE.md (area → script → asserts; колонка "new this run")
3. Gap hunt: для каждого пункта чеклиста — script или N/A+reason
4. Создай СТОЛЬКО файлов под QA/scripts/, сколько закрывает дыры
5. Обнови manifest.json + run_all.sh
6. Пока gap hunt не закрыт — НЕ объявляй green

Этап B — прогнать:
1. QA/run_all.sh — весь manifest
2. FAIL → QA/BUG_REPORT.md → «зови оркестратора»
3. PASS → QA/REPORT.md → «QA green — зови оркестратора»

## Правила
- Только QA/ (scripts, manifest, run_all, COVERAGE, REPORT, BUG_REPORT)
- Скрипты: idempotent, deterministic, exit 0 = pass
- Full suite всегда после любого изменения
- Токены: Graphify first (graphify explain --graph "$GRAPH")
  GRAPH="/Users/pavan/Documents/AI Projects/VaniScript/graphify-out/graph.json"
```
---

## Task (вставь как задание / user prompt QA-агенту)

```
## QA Full Cycle — Первый полный прогон VaniScript

### Контекст
Это ПЕРВЫЙ QA-цикл. QA никогда не запускался. Твоя задача — пройти по ВСЕМУ
приложению и создать МАКСИМУМ скриптов для покрытия всех областей.

Текущее состояние QA/:
- manifest.json: 3 скрипта заявлено, но реально существует только 1
- QA/scripts/build_gate_as.sh — существует
- QA/scripts/build_gate_electron.sh — ОТСУТСТВУЕТ (нужно создать)
- QA/scripts/mcp_smoke_as.sh — ОТСУТСТВУЕТ (нужно создать)
- COVERAGE.md — ОТСУТСТВУЕТ (нужно создать)

### Скоуп приложения (пройти по всему)

#### 1. Apple Silicon (Swift/SwiftUI)
**Services (Sources/VaniScript/Services/):**
- McpServer.swift — MCP server SSE :19790
- McpReadToolService.swift — MCP read tools
- CodexAgentService.swift — Codex CLI subprocess
- GrokAgentService.swift — Grok CLI subprocess
- QwenAgentService.swift — Qwen CLI subprocess (NEW, Q2)
- NativeProcessingPipeline.swift — обработка медиа
- CloudAudioTranscriptionEngine.swift — транскрипция
- CloudTextTranslationEngine.swift — перевод
- ModelDownloadManager.swift — загрузка моделей
- ProjectDiskStore.swift — хранение проектов
- SettingsDiskStore.swift — настройки

**Core (Sources/VaniScriptCore/):**
- McpContracts.swift — MCP профили (codex, grok, qwen, cursor, etc.)
- McpExpandedToolCatalog.swift — каталог tools (122 tools)
- McpGlossaryToolService.swift — glossary tools
- McpTranscriptToolService.swift — transcript tools
- AppSettings.swift — настройки (codex/grok/qwen секции)
- CodexAgentSupport.swift — Codex parser
- GrokAgentSupport.swift — Grok parser
- QwenAgentSupport.swift — Qwen parser (NEW, Q2)

**Views (Sources/VaniScript/Views/):**
- ChatSidebarView.swift — чат (route selector: mcp/gemini, agents: codex/grok/qwen)
- SettingsView.swift — настройки (Agents tab)
- ContentView.swift — главный экран
- ExportWorkspaceView.swift — экспорт
- VisualClipEditorView.swift — редактор клипов

**Tests (Tests/VaniScriptCoreTests/):**
- 39 test suites, 257 tests (все должны быть green)
- McpSecurityContractTests.swift — security контракты (122 tools, профили)
- QwenAgentSupportTests.swift — Qwen parser (NEW, Q2)

#### 2. Electron (Electron/)
- src/App.tsx, src/main.tsx — основное приложение
- src/services/ — сервисы
- src/render-engine/ — рендеринг
- MCP server :19789

#### 3. MCP Server (mcp_bridge.py)
- SSE endpoints :19790 (AS) / :19789 (Electron)
- Tools: definitions, glossary, transcript, export
- Security: token auth, isolation

### Области для покрытия (создать скрипты)

#### A. Build Gates
1. build_gate_as.sh — swift test (СУЩЕСТВУЕТ, проверить)
2. build_gate_electron.sh — npm run compile (СОЗДАТЬ)

#### B. MCP Server Smoke
3. mcp_smoke_as.sh — SSE :19790 up + tools list (СОЗДАТЬ)
4. mcp_smoke_electron.sh — SSE :19789 up + tools list (СОЗДАТЬ)
5. mcp_security.sh — token auth, no token = 401 (СОЗДАТЬ)
6. mcp_isolation.sh — vaniscript_embedded only, scopes не расширены (СОЗДАТЬ)

#### C. Provider Tests (black-box, без реального CLI)
7. provider_codex_mock.sh — CodexAgentService spawn/parse (мок) (СОЗДАТЬ)
8. provider_grok_mock.sh — GrokAgentService spawn/parse (мок) (СОЗДАТЬ)
9. provider_qwen_mock.sh — QwenAgentService spawn/parse (мок, NEW Q2) (СОЗДАТЬ)
10. provider_cli_absent.sh — .cliMissing error когда binary нет (СОЗДАТЬ)
11. provider_no_fallback.sh — нет silent MCP→API fallback (СОЗДАТЬ)

#### D. Settings / Routes
12. settings_decode.sh — codex/grok/qwen секции декодируются (СОЗДАТЬ)
13. settings_backward_compat.sh — старые JSON без qwen читаются (СОЗДАТЬ)
14. routes_selector.sh — codex/grok/qwen в ChatSidebarView (СОЗДАТЬ)

#### E. Security / Invariants
15. security_no_tokens_argv.sh — токены НЕ в argv/source/git (СОЗДАТЬ)
16. security_token_env_only.sh — токен только в env дочернего процесса (СОЗДАТЬ)
17. security_contract_tests.sh — McpSecurityContractTests green (СОЗДАТЬ)

#### F. Q2 Delta (QwenProvider)
18. qwen_parser_ndjson.sh — QwenAgentOutputParser NDJSON fixtures (СОЗДАТЬ)
19. qwen_model_catalog.sh — QwenChatModelCatalog normalizedModelID (СОЗДАТЬ)
20. qwen_safe_mode.sh — --safe-mode isolation (СОЗДАТЬ)
21. qwen_no_reasoning.sh — нет reasoningEffort (СОЗДАТЬ)

#### G. Regression (полная)
22. regression_swift_test.sh — все 257 тестов green (СОЗДАТЬ или переиспользовать build_gate_as)
23. regression_mcp_tools_count.sh — 122 tools в каталоге (СОЗДАТЬ)
24. regression_profiles.sh — все профили (codex, grok, qwen, cursor, etc.) (СОЗДАТЬ)

### Gap Hunt Checklist (для каждого пункта — script или N/A+reason)

**Дельта Q2:**
- [ ] QwenProvider happy path (spawn, parse NDJSON)
- [ ] QwenProvider error paths (.cliMissing, .notLoggedIn, .unavailable)
- [ ] Qwen model catalog (normalizedModelID, displayLabel)
- [ ] Qwen --safe-mode isolation
- [ ] Qwen no reasoningEffort
- [ ] Backward compat: Codex/Grok не сломаны

**Полная регрессия:**
- [ ] Build gate AS: swift test green
- [ ] Build gate Electron: npm run compile (если node_modules есть)
- [ ] MCP server SSE :19790 up + tools
- [ ] MCP server SSE :19789 up + tools (Electron)
- [ ] McpToolRegistry: 122 tools definitions/glossary/transcript
- [ ] Settings decode: codex/grok/qwen секции
- [ ] Chat route selector: codex/grok/qwen
- [ ] No silent MCP→API fallback
- [ ] Security: токены не в argv/source/git
- [ ] Isolation: vaniscript_embedded only

**Агрессия покрытия:**
- Для каждого нового public symbol в Q2 — ≥1 dedicated assert
- QwenAgentService, QwenAgentSupport, QwenChatModelCatalog, QwenAgentOutputParser

### Команды
  cd "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon"
  # После создания скриптов:
  QA/run_all.sh

### Сдача
1. Создай QA/COVERAGE.md (area → script → asserts)
2. Создай ВСЕ скрипты из списка выше (или N/A+reason)
3. Обнови manifest.json + run_all.sh
4. Прогони QA/run_all.sh
5. FAIL → QA/BUG_REPORT.md → «зови оркестратора»
6. GREEN → QA/REPORT.md → «QA green — зови оркестратора»

### Важно
- Это ПЕРВЫЙ полный цикл. Создай МАКСИМУМ скриптов.
- Не экономь. Лучше 30 скриптов чем 5.
- Всё, что можно проверить — в ЭТОМ прогоне.
- Скрипты: bash/python, idempotent, exit 0 = pass.
- Не пиши product-код. Только QA/.
```

---

Токены: Graphify first — MCP server "graphify" tools, или CLI:
graphify query|explain|path --graph "/Users/pavan/Documents/AI Projects/VaniScript/graphify-out/graph.json"
Skill: VaniScript/.agents/skills/graphify/SKILL.md. Не дампить дерево без graphify.
