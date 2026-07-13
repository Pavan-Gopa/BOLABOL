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
/// The event schema below is fixture-based and mirrors the Codex agent event contract; confirm
/// against real `grok` CLI output and extend the `switch` when the live schema is captured.
public enum GrokAgentOutputParser {
    public static func parse(jsonLines data: Data) -> GrokAgentRun {
        guard let output = String(data: data, encoding: .utf8) else {
            return GrokAgentRun(errorMessage: "Grok returned invalid UTF-8 output.")
        }

        var runID: String?
        var responseText: String?
        var toolNames = [String]()
        var errorMessage: String?

        for line in output.split(whereSeparator: \.isNewline) {
            guard let lineData = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let eventType = event["type"] as? String
            else {
                continue
            }

            switch eventType {
            case "message_start":
                runID = event["id"] as? String ?? runID
            case "content":
                if let text = event["text"] as? String {
                    responseText = (responseText ?? "") + text
                }
            case "tool_call":
                if let toolName = event["name"] as? String,
                   !toolNames.contains(toolName) {
                    toolNames.append(toolName)
                }
            case "error":
                errorMessage = event["message"] as? String ?? errorMessage
            default:
                continue
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
