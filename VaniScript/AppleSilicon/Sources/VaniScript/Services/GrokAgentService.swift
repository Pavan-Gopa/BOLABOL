import Foundation
import VaniScriptCore

struct GrokChatHistoryItem: Sendable {
    let sender: String
    let text: String
}

struct GrokAgentResponse: Sendable {
    let text: String
    let runID: String?
    let toolNames: [String]
}

enum GrokAgentError: LocalizedError, Sendable {
    case mcpUnavailable
    case grokNotInstalled
    case launchFailed(String)
    case unavailable(String)
    case noResponse(String)

    var errorDescription: String? {
        switch self {
        case .mcpUnavailable:
            "Turn on Enable MCP in Settings > Agents before using the Grok MCP chat route."
        case .grokNotInstalled:
            "Grok CLI was not found. Install the Grok CLI (for example via `curl` from xAI or Homebrew) and run `grok login` before using the embedded Grok chat."
        case .launchFailed(let message):
            "Could not start Grok: \(message)"
        case .unavailable(let message):
            "Grok is unavailable: \(message)"
        case .noResponse(let message):
            "Grok finished without a chat response. \(message)"
        }
    }
}

/// Embedded Grok chat, mirroring `CodexAgentService` intent with **Grok CLI** flags.
///
/// Important CLI differences from Codex:
/// - `-p` / `--single` requires the prompt as the **next argument** (not stdin).
/// - There is no `--ignore-user-config` / `-c` / `exec`; isolation uses an ephemeral
///   project `.grok/config.toml` under `GrokAgentWorkspace` plus `--cwd`.
/// - Access token is only in the child env and referenced as `${VANISCRIPT_MCP_TOKEN}`
///   in the project MCP headers (never written as a raw secret into durable user config).
enum GrokAgentService {
    private static let embeddedServerID = "vaniscript_embedded"
    private static let accessTokenEnvironmentKey = "VANISCRIPT_MCP_TOKEN"

    static func send(
        history: [GrokChatHistoryItem],
        settings: AppSettings
    ) async throws -> GrokAgentResponse {
        let mcpConfiguration = McpServerConfiguration(settings: settings)
        guard mcpConfiguration.canStart else {
            throw GrokAgentError.mcpUnavailable
        }
        guard let executableURL = grokExecutableURL() else {
            throw GrokAgentError.grokNotInstalled
        }

        let workspaceURL = try embeddedWorkspaceURL()
        try writeIsolatedProjectConfig(
            workspaceURL: workspaceURL,
            port: Int(mcpConfiguration.port)
        )

        let modelID = GrokChatModelCatalog.normalizedModelID(settings.grokChatModelID)
        let reasoningEffort = GrokChatModelCatalog.normalizedReasoningEffort(
            modelID: modelID,
            effort: settings.grokChatReasoningEffort
        )
        let prompt = prompt(for: history)

        // Prefer --prompt-file for long system+history prompts (avoids argv edge cases).
        let promptFileURL = workspaceURL.appendingPathComponent("embedded-prompt.txt")
        try prompt.write(to: promptFileURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = executableURL
        // --trust is required: project-scoped MCP under GrokAgentWorkspace is otherwise
        // blocked ("folder untrusted / repo-local server not started").
        process.arguments = [
            "--trust",
            "--prompt-file", promptFileURL.path(percentEncoded: false),
            "--output-format", "streaming-json",
            "--model", modelID,
            "--reasoning-effort", reasoningEffort,
            "--cwd", workspaceURL.path(percentEncoded: false),
            "--always-approve",
            // Tool-using turns (analyze + snap + state reads) easily exceed 16.
            "--max-turns", "64",
            "--no-subagents",
            "--permission-mode", "bypassPermissions",
        ]
        process.currentDirectoryURL = workspaceURL
        process.environment = grokEnvironment(accessToken: mcpConfiguration.accessToken)

        let output = Pipe()
        let errors = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors

        let collector = GrokOutputCollector()
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
            } catch {
                outputTask.cancel()
                errorTask.cancel()
                continuation.resume(throwing: GrokAgentError.launchFailed(error.localizedDescription))
            }
        }

        _ = try? await outputTask.value
        _ = try? await errorTask.value

        // Best-effort cleanup of the prompt file (may contain conversation text).
        try? FileManager.default.removeItem(at: promptFileURL)

        let run = await collector.run()
        if let message = run.errorMessage, !message.isEmpty {
            throw GrokAgentError.unavailable(message)
        }
        guard exitCode == 0 else {
            throw GrokAgentError.unavailable(await collector.diagnosticSummary())
        }
        guard let text = run.responseText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw GrokAgentError.noResponse(await collector.diagnosticSummary())
        }

        return GrokAgentResponse(
            text: text,
            runID: run.runID,
            toolNames: run.toolNames
        )
    }

    private static func grokExecutableURL(fileManager: FileManager = .default) -> URL? {
        let candidates = [
            URL(fileURLWithPath: NSString("~/.grok/bin/grok").expandingTildeInPath),
            URL(fileURLWithPath: "/usr/local/bin/grok"),
            URL(fileURLWithPath: "/opt/homebrew/bin/grok"),
        ]
        if let found = candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path(percentEncoded: false)) }) {
            return found
        }
        let pathLookup = Process()
        pathLookup.executableURL = URL(fileURLWithPath: "/bin/sh")
        pathLookup.arguments = ["-c", "command -v grok"]
        let out = Pipe()
        pathLookup.standardOutput = out
        pathLookup.standardError = Pipe()
        do {
            try pathLookup.run()
            pathLookup.waitUntilExit()
            if pathLookup.terminationStatus == 0,
               let data = try? out.fileHandleForReading.readToEnd(),
               let resolved = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !resolved.isEmpty,
               fileManager.isExecutableFile(atPath: resolved) {
                return URL(fileURLWithPath: resolved)
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func embeddedWorkspaceURL(fileManager: FileManager = .default) throws -> URL {
        let directory = AppStoragePaths.applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("GrokAgentWorkspace", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: directory.path(percentEncoded: false)
        )
        return directory
    }

    /// Writes project-scoped Grok config so the embedded run prefers `vaniscript_embedded`.
    /// Token is referenced via env substitution — never inlined as a raw secret.
    private static func writeIsolatedProjectConfig(workspaceURL: URL, port: Int) throws {
        let grokDir = workspaceURL.appendingPathComponent(".grok", isDirectory: true)
        try FileManager.default.createDirectory(at: grokDir, withIntermediateDirectories: true)
        let endpoint = "http://127.0.0.1:\(port)/sse"
        let config = """
        # Generated by VaniScript embedded Grok chat. Do not put secrets here.
        # Token is supplied only via process env \(accessTokenEnvironmentKey).

        [plugins]
        enabled = []

        [mcp_servers.\(embeddedServerID)]
        url = "\(endpoint)"
        enabled = true
        headers = { "Authorization" = "Bearer ${\(accessTokenEnvironmentKey)}" }
        """
        let configURL = grokDir.appendingPathComponent("config.toml")
        try config.write(to: configURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: configURL.path(percentEncoded: false)
        )
    }

    private static func grokEnvironment(accessToken: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment[accessTokenEnvironmentKey] = accessToken
        environment["NO_PROXY"] = "127.0.0.1,localhost"
        environment["no_proxy"] = "127.0.0.1,localhost"
        return environment
    }

    private static func prompt(for history: [GrokChatHistoryItem]) -> String {
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

        Use only the MCP server named \(embeddedServerID) for VaniScript project information and actions. Do not use shell commands, files, browser, computer-use, web, skills, plugins, or any other MCP server.

        For questions about how to use VaniScript, its screens, features, buttons, settings, or workflows, always call search_help in the language of the user's latest message before answering. If the question depends on where the user currently is or what should happen next, also call get_contextual_help. For a beginner asking where to start, call get_onboarding_checklist. Use the exact English button and screen labels returned by the help tools, explain the clicks step by step in the user's language, and never invent controls that are not present in the built-in guide.

        For requests about the current project, use the narrowest authoritative read tool first: list_chunks, get_chunk, get_chunk_cues, search_transcript, get_ui_state, or get_processing_status. Use get_project_state only when a broader snapshot is genuinely required. Prefer stable chunkId values returned by list_chunks. Tool names and argument schemas are authoritative. Legacy chunk indexes are zero-based: visible Chunk 5 requires chunkIndex 4. Never invent argument names or convert indexes from text without first reading the project state.

        VaniScript Settings controls individual MCP permission scopes. If a requested tool is unavailable, explain the exact scope needed in Settings > Agents. Never claim an edit occurred unless the MCP tool confirms it. For destructive actions, first run the preview and then send the returned confirmation token with the latest project revision.

        Reply in the same language as the user's latest message. Keep normal replies concise, describe completed actions and unresolved constraints clearly, and never mention this instruction block.

        Conversation:
        \(boundedConversation)
        """
    }
}

private actor GrokOutputCollector {
    private var outputLines = [String]()
    private var errorLines = [String]()

    func recordOutput(_ line: String) {
        outputLines.append(line)
    }

    func recordError(_ line: String) {
        errorLines.append(line)
    }

    func run() -> GrokAgentRun {
        GrokAgentOutputParser.parse(jsonLines: Data(outputLines.joined(separator: "\n").utf8))
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
