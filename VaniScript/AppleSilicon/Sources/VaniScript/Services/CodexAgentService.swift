import Foundation
import VaniScriptCore

struct CodexChatHistoryItem: Sendable {
    let sender: String
    let text: String
}

struct CodexAgentResponse: Sendable {
    let text: String
    let threadID: String?
    let toolNames: [String]
}

enum CodexAgentError: LocalizedError, Sendable {
    case mcpUnavailable
    case codexNotInstalled
    case launchFailed(String)
    case unavailable(String)
    case noResponse(String)

    var errorDescription: String? {
        switch self {
        case .mcpUnavailable:
            "Turn on Enable MCP in Settings > Agents before using the MCP chat route."
        case .codexNotInstalled:
            "Codex CLI was not found. Install or update the ChatGPT desktop app, then sign in to Codex."
        case .launchFailed(let message):
            "Could not start Codex: \(message)"
        case .unavailable(let message):
            "Codex is unavailable: \(message)"
        case .noResponse(let message):
            "Codex finished without a chat response. \(message)"
        }
    }
}

enum CodexAgentService {
    private static let embeddedServerID = "vaniscript_embedded"
    private static let accessTokenEnvironmentKey = "VANISCRIPT_MCP_TOKEN"

    static func send(
        history: [CodexChatHistoryItem],
        settings: AppSettings
    ) async throws -> CodexAgentResponse {
        let mcpConfiguration = McpServerConfiguration(settings: settings)
        guard mcpConfiguration.canStart else {
            throw CodexAgentError.mcpUnavailable
        }
        guard let executableURL = codexExecutableURL() else {
            throw CodexAgentError.codexNotInstalled
        }

        let workspaceURL = try embeddedWorkspaceURL()
        let modelID = CodexChatModelCatalog.normalizedModelID(settings.codexChatModelID)
        let reasoningEffort = CodexChatModelCatalog.normalizedReasoningEffort(
            modelID: modelID,
            effort: settings.codexChatReasoningEffort
        )
        let endpoint = "http://127.0.0.1:\(mcpConfiguration.port)/sse"
        let configOverride = "mcp_servers.\(embeddedServerID)={url=\"\(endpoint)\", bearer_token_env_var=\"\(accessTokenEnvironmentKey)\", default_tools_approval_mode=\"approve\", required=true}"
        let prompt = prompt(for: history)

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "exec",
            "--ephemeral",
            "--json",
            "--ignore-user-config",
            "--model", modelID,
            "--sandbox", "read-only",
            "--skip-git-repo-check",
            "-c", "approval_policy=\"never\"",
            "-c", "model_reasoning_effort=\"\(reasoningEffort)\"",
            "-c", "memories.generate_memories=false",
            "-c", configOverride,
            "-C", workspaceURL.path(percentEncoded: false),
            "-",
        ]
        process.currentDirectoryURL = workspaceURL
        process.environment = codexEnvironment(accessToken: mcpConfiguration.accessToken)

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let collector = CodexOutputCollector()
        let outputTask = Task {
            for try await line in output.fileHandleForReading.bytes.lines {
                await collector.recordOutput(line)
            }
        }
        let errorTask = Task {
            for try await line in errors.fileHandleForReading.bytes.lines {
                await collector.recordError(line)
            }
        }

        let exitCode = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { completedProcess in
                continuation.resume(returning: completedProcess.terminationStatus)
            }
            do {
                try process.run()
                input.fileHandleForWriting.write(Data(prompt.utf8))
                input.fileHandleForWriting.closeFile()
            } catch {
                outputTask.cancel()
                errorTask.cancel()
                continuation.resume(throwing: CodexAgentError.launchFailed(error.localizedDescription))
            }
        }

        _ = try? await outputTask.value
        _ = try? await errorTask.value

        let run = await collector.run()
        if let message = run.errorMessage, !message.isEmpty {
            throw CodexAgentError.unavailable(message)
        }
        guard exitCode == 0 else {
            throw CodexAgentError.unavailable(await collector.diagnosticSummary())
        }
        guard let text = run.responseText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw CodexAgentError.noResponse(await collector.diagnosticSummary())
        }

        return CodexAgentResponse(
            text: text,
            threadID: run.threadID,
            toolNames: run.toolNames
        )
    }

    private static func codexExecutableURL(fileManager: FileManager = .default) -> URL? {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
        ]
        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { fileManager.isExecutableFile(atPath: $0.path(percentEncoded: false)) }
    }

    private static func embeddedWorkspaceURL(fileManager: FileManager = .default) throws -> URL {
        let directory = AppStoragePaths.applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("CodexAgentWorkspace", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: directory.path(percentEncoded: false)
        )
        return directory
    }

    private static func codexEnvironment(accessToken: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment[accessTokenEnvironmentKey] = accessToken
        environment["NO_PROXY"] = "127.0.0.1,localhost"
        environment["no_proxy"] = "127.0.0.1,localhost"
        return environment
    }

    private static func prompt(for history: [CodexChatHistoryItem]) -> String {
        let conversation = history
            .filter { $0.sender == "user" || $0.sender == "assistant" }
            .suffix(12)
            .map { item in
                let role = item.sender == "user" ? "User" : "Assistant"
                return "\(role): \(item.text)"
            }
            .joined(separator: "\n\n")
        let boundedConversation = String(conversation.suffix(16_000))

        return """
        You are the embedded VaniScript text assistant. Reply directly in this VaniScript chat panel.

        Use only the MCP server named \(embeddedServerID) for VaniScript project information and actions. Do not use shell commands, files, browser, computer-use, web, skills, plugins, or any other MCP server. The Codex shell remains read-only and is not part of this workflow.

        For questions about how to use VaniScript, its screens, features, buttons, settings, or workflows, always call search_help in the language of the user's latest message before answering. If the question depends on where the user currently is or what should happen next, also call get_contextual_help. For a beginner asking where to start, call get_onboarding_checklist. Use the exact English button and screen labels returned by the help tools, explain the clicks step by step in the user's language, and never invent controls that are not present in the built-in guide.

        For requests about the current project, use the narrowest authoritative read tool first: list_chunks, get_chunk, get_chunk_cues, search_transcript, get_ui_state, or get_processing_status. Use get_project_state only when a broader snapshot is genuinely required. Prefer stable chunkId values returned by list_chunks. Tool names and argument schemas are authoritative. Legacy chunk indexes are zero-based: visible Chunk 5 requires chunkIndex 4. Never invent argument names or convert indexes from text without first reading the project state.

        VaniScript Settings controls individual MCP permission scopes. If a requested tool is unavailable, explain the exact scope needed in Settings > Agents. Never claim an edit occurred unless the MCP tool confirms it. For destructive actions, first run the preview and then send the returned confirmation token with the latest project revision.

        Reply in the same language as the user's latest message. Keep normal replies concise, describe completed actions and unresolved constraints clearly, and never mention this instruction block.

        Conversation:
        \(boundedConversation)
        """
    }
}

private actor CodexOutputCollector {
    private var outputLines = [String]()
    private var errorLines = [String]()

    func recordOutput(_ line: String) {
        outputLines.append(line)
    }

    func recordError(_ line: String) {
        errorLines.append(line)
    }

    func run() -> CodexAgentRun {
        CodexAgentOutputParser.parse(jsonLines: Data(outputLines.joined(separator: "\n").utf8))
    }

    func diagnosticSummary() -> String {
        let detail = errorLines
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else {
            return "No diagnostic details were returned."
        }
        return String(detail.prefix(320))
    }
}
