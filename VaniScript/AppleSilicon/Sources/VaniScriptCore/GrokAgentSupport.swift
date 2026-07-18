import Foundation

public struct GrokChatModelOption: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let shortName: String
    public let description: String
    public let reasoningEfforts: [String]
    public let defaultReasoningEffort: String

    public init(
        id: String,
        displayName: String,
        shortName: String,
        description: String,
        reasoningEfforts: [String],
        defaultReasoningEffort: String
    ) {
        self.id = id
        self.displayName = displayName
        self.shortName = shortName
        self.description = description
        self.reasoningEfforts = reasoningEfforts
        self.defaultReasoningEffort = defaultReasoningEffort
    }
}

public enum GrokChatModelCatalog {
    public static let grok45ID = "grok-4.5"
    public static let grok45FastID = "grok-4.5-fast"
    public static let grok45ComposerID = "grok-4.5-composer"
    public static let defaultModelID = grok45ID

    public static let options: [GrokChatModelOption] = [
        GrokChatModelOption(
            id: grok45ID,
            displayName: "Grok 4.5",
            shortName: "Grok",
            description: "Default Grok agent for everyday VaniScript work.",
            reasoningEfforts: ["low", "medium", "high"],
            defaultReasoningEffort: "medium"
        ),
        GrokChatModelOption(
            id: grok45FastID,
            displayName: "Grok 4.5 Fast",
            shortName: "Fast",
            description: "Cost-efficient Grok agent for quick edits and lookups.",
            reasoningEfforts: ["low", "medium", "high"],
            defaultReasoningEffort: "low"
        ),
        GrokChatModelOption(
            id: grok45ComposerID,
            displayName: "Grok 4.5 Composer",
            shortName: "Composer",
            description: "Frontier Grok agent for complex technical and research tasks.",
            reasoningEfforts: ["low", "medium", "high"],
            defaultReasoningEffort: "high"
        ),
    ]

    public static func option(id: String) -> GrokChatModelOption? {
        options.first { $0.id == id }
    }

    public static func normalizedModelID(_ id: String) -> String {
        option(id: id) == nil ? defaultModelID : id
    }

    public static func normalizedReasoningEffort(modelID: String, effort: String) -> String {
        let option = option(id: normalizedModelID(modelID)) ?? options[0]
        return option.reasoningEfforts.contains(effort) ? effort : option.defaultReasoningEffort
    }

    public static func displayLabel(modelID: String, effort: String) -> String {
        let option = option(id: normalizedModelID(modelID)) ?? options[0]
        let normalizedEffort = normalizedReasoningEffort(modelID: option.id, effort: effort)
        return "\(option.shortName) · \(normalizedEffort.capitalized)"
    }
}

public struct GrokAgentRun: Equatable, Sendable {
    public let runID: String?
    public let responseText: String?
    public let toolNames: [String]
    public let errorMessage: String?

    public init(
        runID: String? = nil,
        responseText: String? = nil,
        toolNames: [String] = [],
        errorMessage: String? = nil
    ) {
        self.runID = runID
        self.responseText = responseText
        self.toolNames = toolNames
        self.errorMessage = errorMessage
    }
}

/// Parses headless `grok` CLI output emitted with `--output-format streaming-json` / `json`.
///
/// Live Grok Build schema (captured from CLI):
/// - `{"type":"thought","data":"..."}` — reasoning tokens (ignored for chat text)
/// - `{"type":"text","data":"..."}` — assistant reply chunks (concatenated)
/// - `{"type":"end","sessionId":"...","stopReason":"..."}` — completion
///
/// Legacy/Codex-like branches are kept for fixtures and forward compatibility.
public enum GrokAgentOutputParser {
    public static func parse(jsonLines data: Data) -> GrokAgentRun {
        guard let output = String(data: data, encoding: .utf8) else {
            return GrokAgentRun(errorMessage: "Grok returned invalid UTF-8 output.")
        }

        var runID: String?
        var responseText: String?
        var toolNames = [String]()
        var errorMessage: String?
        var sawJSON = false

        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let lineData = trimmed.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else {
                continue
            }
            sawJSON = true

            let eventType = (event["type"] as? String) ?? ""

            switch eventType {
            case "text":
                // Live Grok: {"type":"text","data":"pong"}
                if let chunk = event["data"] as? String {
                    responseText = (responseText ?? "") + chunk
                } else if let chunk = event["text"] as? String {
                    responseText = (responseText ?? "") + chunk
                }
            case "content":
                // Legacy fixture: {"type":"content","text":"..."}
                if let chunk = event["text"] as? String {
                    responseText = (responseText ?? "") + chunk
                } else if let chunk = event["data"] as? String {
                    responseText = (responseText ?? "") + chunk
                }
            case "end":
                if let sessionID = event["sessionId"] as? String {
                    runID = sessionID
                } else if let requestID = event["requestId"] as? String {
                    runID = requestID
                }
            case "message_start":
                runID = event["id"] as? String ?? runID
            case "tool_call", "tool_use", "mcp_tool_call":
                if let toolName = event["name"] as? String, !toolNames.contains(toolName) {
                    toolNames.append(toolName)
                } else if let tool = event["tool"] as? String, !toolNames.contains(tool) {
                    toolNames.append(tool)
                } else if let data = event["data"] as? [String: Any],
                          let toolName = data["name"] as? String,
                          !toolNames.contains(toolName) {
                    toolNames.append(toolName)
                }
            case "error":
                if let message = event["message"] as? String {
                    errorMessage = message
                } else if let message = event["data"] as? String {
                    errorMessage = message
                }
            case "thought":
                // Ignore reasoning stream for the chat panel.
                break
            default:
                // Some dialects emit assistant text without a typed event.
                if let chunk = event["text"] as? String, !chunk.isEmpty {
                    responseText = (responseText ?? "") + chunk
                }
            }
        }

        // Fallback: plain non-JSON stdout (e.g. --output-format plain).
        if !sawJSON {
            let plain = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !plain.isEmpty {
                responseText = plain
            }
        }

        return GrokAgentRun(
            runID: runID,
            responseText: responseText,
            toolNames: toolNames,
            errorMessage: errorMessage
        )
    }
}
