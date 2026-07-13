import Foundation

public struct CodexChatModelOption: Equatable, Identifiable, Sendable {
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

public enum CodexChatModelCatalog {
    public static let lunaID = "gpt-5.6-luna"
    public static let terraID = "gpt-5.6-terra"
    public static let solID = "gpt-5.6-sol"
    public static let defaultModelID = lunaID

    public static let options: [CodexChatModelOption] = [
        CodexChatModelOption(
            id: lunaID,
            displayName: "GPT-5.6-Luna",
            shortName: "Luna",
            description: "Fast, cost-efficient Codex agent for everyday VaniScript work.",
            reasoningEfforts: ["low", "medium", "high", "xhigh", "max"],
            defaultReasoningEffort: "medium"
        ),
        CodexChatModelOption(
            id: terraID,
            displayName: "GPT-5.6-Terra",
            shortName: "Terra",
            description: "Balanced Codex agent with deeper reasoning options for complex work.",
            reasoningEfforts: ["low", "medium", "high", "xhigh", "max", "ultra"],
            defaultReasoningEffort: "medium"
        ),
        CodexChatModelOption(
            id: solID,
            displayName: "GPT-5.6-Sol",
            shortName: "Sol",
            description: "Frontier Codex agent for complex technical and research tasks.",
            reasoningEfforts: ["low", "medium", "high", "xhigh", "max"],
            defaultReasoningEffort: "high"
        ),
    ]

    public static func option(id: String) -> CodexChatModelOption? {
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

public struct CodexAgentRun: Equatable, Sendable {
    public let threadID: String?
    public let responseText: String?
    public let toolNames: [String]
    public let errorMessage: String?

    public init(
        threadID: String? = nil,
        responseText: String? = nil,
        toolNames: [String] = [],
        errorMessage: String? = nil
    ) {
        self.threadID = threadID
        self.responseText = responseText
        self.toolNames = toolNames
        self.errorMessage = errorMessage
    }
}

public enum CodexAgentOutputParser {
    public static func parse(jsonLines data: Data) -> CodexAgentRun {
        guard let output = String(data: data, encoding: .utf8) else {
            return CodexAgentRun(errorMessage: "Codex returned invalid UTF-8 output.")
        }

        var threadID: String?
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
            case "thread.started":
                threadID = event["thread_id"] as? String ?? threadID
            case "item.started", "item.completed":
                guard let item = event["item"] as? [String: Any],
                      let itemType = item["type"] as? String
                else {
                    continue
                }

                if itemType == "agent_message", let text = item["text"] as? String {
                    responseText = text
                }

                if itemType == "mcp_tool_call", let toolName = item["tool"] as? String,
                   !toolNames.contains(toolName) {
                    toolNames.append(toolName)
                }
            case "error":
                errorMessage = event["message"] as? String ?? errorMessage
            case "turn.failed":
                if let error = event["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    errorMessage = message
                }
            default:
                continue
            }
        }

        return CodexAgentRun(
            threadID: threadID,
            responseText: responseText,
            toolNames: toolNames,
            errorMessage: errorMessage
        )
    }
}
