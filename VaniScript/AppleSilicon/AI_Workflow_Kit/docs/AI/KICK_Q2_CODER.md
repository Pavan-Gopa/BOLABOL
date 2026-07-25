# Kick: Q2 — QwenProvider skeleton + embedded chat (Apple Silicon)

> **Оркестратор:** Cline. **Трек:** QWEN_MCP. **Шаг:** Q2 (первый coding-шаг).
> **Pre-checkpoint:** `qwen/pre-Q2` (tag существует).
> **Working directory:** `cd "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon"`

---

## System Prompt (вставь как роль / system prompt кодеру)

```
Ты — Implementation Engineer (Coder) проекта VaniScript (Apple Silicon).

## Проект (кратко)
VaniScript — macOS-приложение (Swift 6 / SwiftUI, AppleSilicon/) для транскрипции,
перевода и экспорта лекций. AI-провайдеры (Codex, Grok) встраиваются как CLI
subprocess. Локальный MCP server (SSE) на порту AS:19790, изолированный
`vaniscript_embedded`. Контракты: Sources/VaniScriptCore/McpContracts.swift.

## Твоя роль
- Пишешь product-код ТОЛЬКО в target_files (указаны ниже).
- НЕ делаешь работу из будущих шагов (Q3+ = MCP wiring, Q4 = Electron).
- НЕ переписываешь UI/layout — только расширяешь (parity с Codex/Grok).
- Без fake telemetry / фейковых состояний.
- Комментарии: role header у новых модулей (1-5 строк: слой, роль, must-not,
  invariants) + why у неочевидной логики. Inline: // Q2: по шагу.
- Английский предпочтителен в коде.

## Инварианты (QWEN_MCP)
- Embedded = CLI subprocess (Codex/Grok pattern).
- Token только в env дочернего процесса; нет токенов в argv/source/git.
- No silent fallback MCP chat → API (явная ошибка).
- vaniscript_embedded изолирован; scopes/tools не расширены.
- Codex/Grok path, MCP server, settings decode не сломаны.

## Правила
- Diff только в target_files.
- Buildable каждый шаг: swift test (или swift build).
- Токены: Graphify first — MCP "graphify" или CLI:
  graphify query|explain|path --graph "/Users/pavan/Documents/AI Projects/VaniScript/graphify-out/graph.json"
  НЕ дампить дерево без graphify. НЕ читать весь репо.

## Сдача
1. Заполни FEEDBACK.md §1-4 (build/commands, step compliance, invariants, comments).
2. Поставь implementation.status: waiting_review, next_actor: verification.
3. Скажи Human: «зови ревью».
```
---

## Task (вставь как задание / user prompt кодеру)

```
## Шаг: Q2 — QwenProvider skeleton + embedded chat (Apple Silicon)

### Цель
Добавить QwenProvider (CLI subprocess, Codex/Grok pattern) в VaniScript и подключить
к route selector ChatSidebarView как .qwen. Чат с Qwen работает в AS-клиенте.
MCP tools wiring — на Q3 (НЕ делать сейчас). Plain chat only.

### Target files (ТОЛЬКО эти)
- Sources/VaniScript/Services/QwenAgentService.swift          # NEW
- Sources/VaniScriptCore/QwenAgentSupport.swift               # NEW
- Sources/VaniScriptCore/McpContracts.swift                   # add .qwen to McpClientProfileID
- Sources/VaniScriptCore/AppSettings.swift                    # add qwenChatModelID
- Sources/VaniScript/Views/ChatSidebarView.swift              # route selector .qwen + qwenModelMenu
- Sources/VaniScript/Views/SettingsView.swift                 # Qwen agent option in Agents tab
- Tests/VaniScriptCoreTests/QwenAgentSupportTests.swift       # NEW
- AI_Workflow_Kit/docs/AI/FEEDBACK.md

### Что уже есть (НЕ делать заново)

Эталон Grok (зеркалить 1:1):
- GrokAgentService.swift: enum GrokAgentService { static func send(history:settings:) }
  GrokChatHistoryItem, GrokAgentResponse, GrokAgentError
  Spawn: Process() -> grok --trust --prompt-file --output-format streaming-json --model --cwd
  Isolation: ephemeral workspace + .grok/config.toml
  Token: VANISCRIPT_MCP_TOKEN в child env only
  GrokOutputCollector actor -> GrokAgentOutputParser.parse()

- GrokAgentSupport.swift: GrokChatModelOption, GrokChatModelCatalog, GrokAgentRun, GrokAgentOutputParser

- ChatSidebarView.swift: ChatRoute enum (mcp/gemini), sendMessage() dispatch по mcpPreferredAgentID,
  agentModelMenu, executeGrokRequest/executeCodexRequest

- McpContracts.swift: McpClientProfileID enum (antigravity, claudeCode, claudeDesktop, codex, cursor, grok)

- AppSettings.swift: mcpPreferredAgentID, grokChatModelID, grokChatReasoningEffort (lines ~255-259)

### Qwen CLI — verified facts (Q1 Discovery)

Binary: /Users/pavan/.local/bin/qwen (v0.20.0, "Qwen Code")
Spawn: qwen -p "<prompt>" -o stream-json -m qwen3.8-max-preview --safe-mode
  --safe-mode отключает hooks/extensions/MCP (изоляция для plain chat на Q2)
Model: qwen3.8-max-preview через -m
Auth: токен в env дочернего процесса (DASHSCOPE_API_KEY / BAILIAN_TOKEN_PLAN_API_KEY)

Streaming NDJSON (-o stream-json):
  {"type":"system","subtype":"init","session_id":"...","model":"qwen3.8-max-preview"}
  {"type":"assistant","message":{"content":[{"type":"text","text":"Hello!"}]}}
  {"type":"result","subtype":"success","result":"Hello!","usage":{...}}
  Парсер: assistant.message.content[].text + result.result как fallback

CLI differences from Grok (ВАЖНО):
- НЕТ --trust (trust per-MCP via mcp add --trust)
- НЕТ --cwd (изоляция через --safe-mode)
- --output-format stream-json (НЕ streaming-json)
- NDJSON: assistant.message.content[].text (НЕ {"type":"text","data":"..."})
- НЕТ --reasoning-effort

### Что сделать

1. QwenAgentSupport.swift (VaniScriptCore, NEW):
   - QwenChatModelOption (id, displayName, shortName, description) — БЕЗ reasoningEfforts
   - QwenChatModelCatalog: qwen38MaxPreviewID = "qwen3.8-max-preview", options, normalizedModelID(), displayLabel()
   - QwenAgentRun (runID, responseText, toolNames, errorMessage)
   - QwenAgentOutputParser: NDJSON parse (assistant.message.content[].text, result.result, session_id)
   - Role header: "Q2: Qwen CLI output parsing and model catalog for embedded chat."

2. QwenAgentService.swift (VaniScript/Services, NEW):
   - Зеркалить GrokAgentService: QwenChatHistoryItem, QwenAgentResponse, QwenAgentError
   - enum QwenAgentService { static func send(history:settings:) async throws -> QwenAgentResponse }
   - Spawn: Process() -> qwen -p "<prompt>" -o stream-json -m <modelID> --safe-mode
   - Prompt: system instruction + conversation (suffix 12, bound 16k) — аналог Grok
   - Token: VANISCRIPT_MCP_TOKEN в child env (для будущего Q3)
   - QwenOutputCollector actor -> QwenAgentOutputParser.parse()
   - Executable: which qwen / PATH search
   - Role header: "Q2: Embedded Qwen chat — CLI subprocess, Codex/Grok pattern."

3. McpContracts.swift: case qwen, displayName "Qwen", symbolName "brain.head.profile"

4. AppSettings.swift: var qwenChatModelID: String (default: QwenChatModelCatalog.defaultModelID)
   CodingKeys + init(from:) + encode(to:) — по аналогии с grokChatModelID
   НЕ добавлять qwenChatReasoningEffort

5. ChatSidebarView.swift:
   - sendMessage(): обработка McpClientProfileID.qwen.rawValue
   - executeQwenRequest(history:) — аналог executeGrokRequest
   - agentModelMenu: qwenModelMenu (без reasoning)
   - selectQwenModel(_:)
   - Guard: "Codex, Grok, or Qwen"

6. SettingsView.swift: Qwen в Agents tab (picker + model menu, без reasoning)

7. QwenAgentSupportTests.swift (NEW):
   - QwenAgentOutputParser.parse() с fixture NDJSON
   - QwenChatModelCatalog.normalizedModelID() (valid, invalid, empty)
   - QwenChatModelCatalog.displayLabel()

### Проверка (обязательно green)
  cd "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon"
  swift test    # или swift build

### Сдача
FEEDBACK.md §1-4, waiting_review -> «зови ревью».
```

---

Токены: Graphify first — MCP server "graphify" tools, или CLI:
graphify query|explain|path --graph "/Users/pavan/Documents/AI Projects/VaniScript/graphify-out/graph.json"
Skill: VaniScript/.agents/skills/graphify/SKILL.md. Не дампить дерево без graphify.
