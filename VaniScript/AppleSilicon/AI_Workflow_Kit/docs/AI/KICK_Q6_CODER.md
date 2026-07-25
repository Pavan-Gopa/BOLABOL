# Kick: Q6 — In-app API hardening (streaming / cancel / errors + tests)

> **Оркестратор:** Cline. **Трек:** QWEN_MCP. **Шаг:** Q6 (coding).
> **Pre-checkpoint:** `qwen/pre-Q6` (tag существует, commit b779a23).
> **Working directory:** `cd "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon"`

---

## System Prompt (вставь как роль / system prompt кодеру)

```
Ты — Implementation Engineer (Coder) проекта VaniScript (Apple Silicon).

## Проект (кратко)
VaniScript — macOS-приложение (Swift 6 / SwiftUI, AppleSilicon/) для транскрипции,
перевода и экспорта лекций. AI-провайдеры (Codex, Grok, Qwen) встраиваются как CLI
subprocess. Локальный MCP server (SSE) на порту AS:19790, изолированный
`vaniscript_embedded`. Контракты: Sources/VaniScriptCore/McpContracts.swift.

## Твоя роль
- Пишешь product-код ТОЛЬКО в target_files (указаны ниже).
- НЕ делаешь работу из будущих шагов (Q7 = doc-only).
- НЕ переписываешь UI/layout — только расширяешь (parity с Codex/Grok).
- Без fake telemetry / фейковых состояний.
- Комментарии: role header у новых модулей (1-5 строк: слой, роль, must-not,
  invariants) + why у неочевидной логики. Inline: // Q6: по шагу.
- Английский предпочтителен в коде.

## Инварианты (QWEN_MCP)
- Embedded = CLI subprocess (Codex/Grok pattern).
- Token только в env дочернего процесса; нет токенов в argv/source/git.
- No silent fallback MCP chat → API (явная ошибка).
- vaniscript_embedded изолирован; scopes/tools не расширены.
- Codex/Grok path, MCP server, settings decode не сломаны.
- Существующий QwenAgentService.send() НЕ ломается (ChatSidebarView использует его).

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
## Шаг: Q6 — In-app API hardening (streaming / cancel / errors + tests)

### Цель
Довести QwenProvider API до production-качества: стабильный streaming, корректная
отмена (process group), полный маппинг ошибок, public API surface в VaniScriptCore
для программного использования без UI, исчерпывающие unit-тесты на мок-CLI.
Поверхность №2 (in-app API). MCP tools wiring (Q3) уже есть — НЕ трогать.
### PREREQ: BUG-002 fix (ОБЯЗАТЕЛЬНО перед Q6 кодом)

Файл `AppleSilicon/MCP_INSTRUCTIONS.md` содержит слово "Electron" на строках 264 и 283.
Это ломает `AppStoreNativeComplianceTests` (тест проверяет что AS MCP_INSTRUCTIONS.md
не содержит "Electron").

Исправь ОБА вхождения, заменив на нейтральные формулировки:
- Строка 264: `> **Port note:** the example above uses `19789` (the Electron build).`
  → `> **Port note:** the example above uses `19789` (the desktop web build).`
- Строка 283: `full 120-tool catalog; the Electron build exposes the same tools over its SSE port).`
  → `full 120-tool catalog; the desktop web build exposes the same tools over its SSE port).`

Проверь: `grep -ci electron AppleSilicon/MCP_INSTRUCTIONS.md` → должно быть `0`.

### Target files (ТОЛЬКО эти)
- AppleSilicon/MCP_INSTRUCTIONS.md                             # BUG-002 fix
- Sources/VaniScriptCore/QwenAgentSupport.swift                # Q6: ChatChunk, ChatError, ChatProvider protocol
- Sources/VaniScript/Services/QwenAgentService.swift           # Q6: streaming provider, cancel, process group
- Tests/VaniScriptCoreTests/QwenAgentSupportTests.swift        # Q6: streaming/cancel/error tests
- AI_Workflow_Kit/docs/AI/FEEDBACK.md

### Что уже есть (НЕ делать заново)

QwenAgentSupport.swift (VaniScriptCore):
- QwenChatModelOption, QwenChatModelCatalog (qwen3.8-max-preview)
- QwenAgentRun (runID, responseText, toolNames, errorMessage)
- QwenAgentOutputParser.parse(jsonLines:) — NDJSON парсер

QwenAgentService.swift (VaniScript/Services):
- enum QwenAgentService { static func send(history:settings:) async throws -> QwenAgentResponse }
- QwenChatHistoryItem, QwenAgentResponse, QwenAgentError
- Spawn: Process() -> qwen -p <prompt> -o stream-json -m <modelID>
- Isolation: ephemeral workspace + .qwen/settings.json (Q3)
- Token: VANISCRIPT_MCP_TOKEN в child env only
- QwenOutputCollector actor -> QwenAgentOutputParser.parse()
- НЕТ cancel(), НЕТ process group kill, НЕТ streaming API

GrokAgentService.swift (эталон, НЕ менять):
- Аналогичная структура, тоже без cancel/streaming API
- НЕ добавляй cancel/streaming в Grok — только Qwen

### Что сделать

#### 1. QwenAgentSupport.swift — добавить public API types (VaniScriptCore)

Добавь ПОСЛЕ существующего кода (не удаляя ничего):

```swift
// Q6: Public streaming API types for programmatic Qwen access (no UI required).
// Layer: VaniScriptCore (pure types + protocol, no process spawning).
// Must-not: never spawn processes here; never store tokens.
// Invariants: ChatChunk is Sendable; ChatProvider is Sendable; errors are exhaustive.

/// A single streaming chunk from a Qwen chat session.
public struct QwenChatChunk: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case text(String)       // incremental assistant text
        case toolUse(String)    // tool name invoked
        case done(QwenAgentRun) // final result (runID, full text, tools, error)
    }
    public let kind: Kind
    public init(kind: Kind) { self.kind = kind }
}

/// Exhaustive error surface for the Qwen in-app API (Q6).
public enum QwenChatError: LocalizedError, Sendable, Equatable {
    case cliMissing             // qwen binary not found in PATH
    case notLoggedIn            // qwen login required (exit code or stderr hint)
    case mcpUnavailable         // MCP server not configured / not running
    case cancelled              // caller invoked cancel()
    case upstream(String)       // CLI exited non-zero with diagnostic

    public var errorDescription: String? {
        switch self {
        case .cliMissing:
            "Qwen CLI was not found. Install Qwen Code and sign in before using the embedded Qwen chat."
        case .notLoggedIn:
            "Qwen CLI is not signed in. Run `qwen login` in a terminal first."
        case .mcpUnavailable:
            "Turn on Enable MCP in Settings > Agents before using the Qwen MCP chat route."
        case .cancelled:
            "The Qwen request was cancelled."
        case .upstream(let message):
            "Qwen is unavailable: \(message)"
        }
    }
}

/// Protocol for programmatic Qwen chat access (surface №2, no UI).
/// Implementations must be safe to call from any actor/task.
public protocol QwenChatProvider: Sendable {
    /// Streams chat chunks. Throws QwenChatError on failure.
    /// The stream finishes normally after emitting `.done`.
    func send(
        history: [QwenChatHistoryItem],
        settings: AppSettings
    ) -> AsyncThrowingStream<QwenChatChunk, Error>

    /// Cancels the in-flight request (idempotent, no zombies).
    func cancel()
}
```

Также добавь `QwenChatHistoryItem` в VaniScriptCore (сейчас он в VaniScript/Services):
```swift
// Q6: moved to VaniScriptCore so QwenChatProvider protocol can reference it.
public struct QwenChatHistoryItem: Sendable, Equatable {
    public let sender: String
    public let text: String
    public init(sender: String, text: String) {
        self.sender = sender
        self.text = text
    }
}
```

ВАЖНО: `QwenChatHistoryItem` сейчас определён в `QwenAgentService.swift` (app layer).
Нужно:
1. Добавить public `QwenChatHistoryItem` в `QwenAgentSupport.swift` (VaniScriptCore)
2. В `QwenAgentService.swift` удалить локальное определение `QwenChatHistoryItem`
   (оно станет доступно через `import VaniScriptCore`)
3. Убедиться что `ChatSidebarView.swift` компилируется (он использует `QwenChatHistoryItem`)

#### 2. QwenAgentService.swift — добавить streaming provider + cancel

Добавь ПОСЛЕ существующего `enum QwenAgentService` (не удаляя его):

Сначала сделай helper-методы `QwenAgentService` доступными (убери `private`):
- `qwenExecutableURL()` → `static func` (internal)
- `embeddedWorkspaceURL()` → `static func` (internal)
- `writeIsolatedMcpConfig(workspaceURL:port:)` → `static func` (internal)
- `qwenEnvironment(accessToken:)` → `static func` (internal)
- `prompt(for:)` → `static func` (internal)

НЕ меняй их логику — только видимость.

Затем добавь:

```swift
// Q6: Streaming Qwen chat provider with cancel support (surface №2, in-app API).
// Layer: VaniScript app services (spawns the local `qwen` binary).
// Must-not: no tokens in argv; no silent fallback; no MCP server other than vaniscript_embedded.
// Invariants: cancel() is idempotent; SIGTERM to process group; no zombie processes;
// stream emits .done exactly once on normal completion.

/// Concrete QwenChatProvider backed by the local `qwen` CLI subprocess.
/// Usage (no UI):
/// ```swift
/// let provider = QwenStreamingProvider()
/// let stream = provider.send(history: [...], settings: settings)
/// for try await chunk in stream {
///     switch chunk.kind {
///     case .text(let t): print(t, terminator: "")
///     case .toolUse(let name): print("[tool: \(name)]")
///     case .done(let run): print("\n[done: \(run.runID ?? "?")]")
///     }
/// }
/// // To cancel mid-stream:
/// provider.cancel()
/// ```
public final class QwenStreamingProvider: QwenChatProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var activeProcess: Process?
    private var isCancelled = false

    public init() {}

    public func send(
        history: [QwenChatHistoryItem],
        settings: AppSettings
    ) -> AsyncThrowingStream<QwenChatChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let mcpConfiguration = McpServerConfiguration(settings: settings)
                    guard mcpConfiguration.canStart else {
                        throw QwenChatError.mcpUnavailable
                    }
                    guard let executableURL = QwenAgentService.qwenExecutableURL() else {
                        throw QwenChatError.cliMissing
                    }

                    let workspaceURL = try QwenAgentService.embeddedWorkspaceURL()
                    try QwenAgentService.writeIsolatedMcpConfig(
                        workspaceURL: workspaceURL,
                        port: Int(mcpConfiguration.port)
                    )

                    let modelID = QwenChatModelCatalog.normalizedModelID(settings.qwenChatModelID)
                    let prompt = QwenAgentService.prompt(for: history)

                    let process = Process()
                    process.executableURL = executableURL
                    process.arguments = ["-p", prompt, "-o", "stream-json", "-m", modelID]
                    process.currentDirectoryURL = workspaceURL
                    process.environment = QwenAgentService.qwenEnvironment(
                        accessToken: mcpConfiguration.accessToken
                    )

                    let output = Pipe()
                    let errors = Pipe()
                    process.standardInput = FileHandle.nullDevice
                    process.standardOutput = output
                    process.standardError = errors

                    // Q6: register process for cancel before starting.
                    lock.lock()
                    guard !isCancelled else {
                        lock.unlock()
                        throw QwenChatError.cancelled
                    }
                    activeProcess = process
                    lock.unlock()

                    // Q6: stream NDJSON lines as QwenChatChunk in real time.
                    let outputTask = Task {
                        for try await line in output.fileHandleForReading.bytes.lines {
                            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty,
                                  let data = trimmed.data(using: .utf8),
                                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                            else { continue }
                            let eventType = (event["type"] as? String) ?? ""
                            if eventType == "assistant",
                               let message = event["message"] as? [String: Any] {
                                let blocks: [[String: Any]]
                                if let array = message["content"] as? [[String: Any]] {
                                    blocks = array
                                } else if let single = message["content"] as? [String: Any] {
                                    blocks = [single]
                                } else {
                                    blocks = []
                                }
                                for block in blocks {
                                    let blockType = (block["type"] as? String) ?? ""
                                    if blockType == "text", let text = block["text"] as? String {
                                        continuation.yield(QwenChatChunk(kind: .text(text)))
                                    } else if blockType == "tool_use", let name = block["name"] as? String {
                                        continuation.yield(QwenChatChunk(kind: .toolUse(name)))
                                    }
                                }
                            }
                        }
                    }

                    let errorTask = Task {
                        for try await _ in errors.fileHandleForReading.bytes.lines {}
                    }

                    let exitCode = try await withCheckedThrowingContinuation {
                        (cont: CheckedContinuation<Int32, Error>) in
                        process.terminationHandler = { p in
                            cont.resume(returning: p.terminationStatus)
                        }
                        do {
                            try process.run()
                        } catch {
                            outputTask.cancel()
                            errorTask.cancel()
                            cont.resume(throwing: QwenChatError.upstream(error.localizedDescription))
                        }
                    }

                    _ = try? await outputTask.value
                    _ = try? await errorTask.value

                    // Q6: clear active process after completion.
                    lock.lock()
                    activeProcess = nil
                    let wasCancelled = isCancelled
                    lock.unlock()

                    if wasCancelled { throw QwenChatError.cancelled }
                    guard exitCode == 0 else {
                        throw QwenChatError.upstream("qwen exited with code \(exitCode)")
                    }

                    continuation.yield(QwenChatChunk(kind: .done(QwenAgentRun())))
                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Q6: Idempotent cancel — SIGTERM to the process group, no zombies.
    public func cancel() {
        lock.lock()
        isCancelled = true
        let process = activeProcess
        activeProcess = nil
        lock.unlock()

        guard let process, process.isRunning else { return }
        // Q6: kill the entire process group so child shells also die.
        let pid = process.processIdentifier
        kill(-pid, SIGTERM)
        process.terminate()  // fallback in case group kill is not permitted
    }
}
```

ВАЖНО: для `kill(-pid, SIGTERM)` нужен `import Darwin` (или Foundation уже даёт).
Проверь что компилируется.

#### 3. QwenAgentService.swift — обновить error mapping

В существующем `QwenAgentService.send()` добавь маппинг на `QwenChatError`:
- `qwenNotInstalled` → также кидает `QwenChatError.cliMissing` (для совместимости)
- При exit code != 0: проверить stderr на "login" / "not logged in" → `QwenChatError.notLoggedIn`

Но НЕ ломай существующий `QwenAgentError` — `ChatSidebarView` ловит его.
Добавь новый маппинг только в `QwenStreamingProvider`.

#### 4. QwenAgentSupportTests.swift — добавить тесты Q6

Добавь тесты ПОСЛЕ существующих (не удаляя):

```swift
// Q6: streaming / cancel / error tests

@Test("QwenChatChunk text kind is equatable")
func chatChunkTextEquatable() {
    let a = QwenChatChunk(kind: .text("hello"))
    let b = QwenChatChunk(kind: .text("hello"))
    let c = QwenChatChunk(kind: .text("world"))
    #expect(a == b)
    #expect(a != c)
}

@Test("QwenChatChunk done kind carries run")
func chatChunkDoneCarriesRun() {
    let run = QwenAgentRun(runID: "sess-1", responseText: "Hi", toolNames: [], errorMessage: nil)
    let chunk = QwenChatChunk(kind: .done(run))
    if case .done(let r) = chunk.kind {
        #expect(r.runID == "sess-1")
        #expect(r.responseText == "Hi")
    } else {
        Issue.record("Expected .done kind")
    }
}

@Test("QwenChatError descriptions are non-empty")
func chatErrorDescriptions() {
    let errors: [QwenChatError] = [.cliMissing, .notLoggedIn, .mcpUnavailable, .cancelled, .upstream("x")]
    for error in errors {
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
    }
}

@Test("QwenChatError upstream carries message")
func chatErrorUpstreamMessage() {
    let error = QwenChatError.upstream("quota exceeded")
    #expect(error.errorDescription?.contains("quota exceeded") == true)
}

@Test("QwenChatHistoryItem is equatable and sendable")
func chatHistoryItemEquatable() {
    let a = QwenChatHistoryItem(sender: "user", text: "hello")
    let b = QwenChatHistoryItem(sender: "user", text: "hello")
    let c = QwenChatHistoryItem(sender: "assistant", text: "hi")
    #expect(a == b)
    #expect(a != c)
}

@Test("QwenStreamingProvider cancel is idempotent and safe without active process")
func cancelIdempotentNoProcess() {
    let provider = QwenStreamingProvider()
    // Q6: cancel before any send() must not crash.
    provider.cancel()
    provider.cancel()
    // No assertion needed — absence of crash is the test.
}
```

### Проверка (обязательно green)

```bash
cd "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon"

# 1. BUG-002 fix verification
grep -ci electron MCP_INSTRUCTIONS.md   # должно быть 0

# 2. Build + test
swift test 2>&1 | tail -10
# Ожидается: 261+ tests, 0 failures (App Store compliance теперь green)

# 3. Qwen-specific tests
swift test --filter QwenAgentSupport 2>&1 | tail -5
swift test --filter QwenMcpConfig 2>&1 | tail -5
```

### Out of scope (НЕ делать)
- Q7 (doc-only)
- Electron changes
- UI changes (ChatSidebarView, SettingsView)
- Grok/Codex changes
- MCP server changes
- Новые tools / scopes

### Сдача
FEEDBACK.md §1-4, implementation.status: waiting_review, next_actor: verification.
Скажи Human: «зови ревью».
```

---

Токены: Graphify first — MCP server "graphify" tools, или CLI:
graphify query|explain|path --graph "/Users/pavan/Documents/AI Projects/VaniScript/graphify-out/graph.json"
Skill: VaniScript/.agents/skills/graphify/SKILL.md. Не дампить дерево без graphify.
