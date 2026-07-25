import Foundation

// Q2: Qwen CLI output parsing and model catalog for embedded chat.
// Layer: VaniScriptCore (pure logic, no process spawning, no UI).
// Must-not: never invent model IDs that were not verified via `qwen` CLI;
// never read tokens or environment here.
// Invariants: parser is tolerant of malformed NDJSON lines and falls back
// to `result.result`, then to plain stdout, without fabricating content.

public struct QwenChatModelOption: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let shortName: String
    public let description: String

    public init(
        id: String,
        displayName: String,
        shortName: String,
        description: String
    ) {
        self.id = id
        self.displayName = displayName
        self.shortName = shortName
        self.description = description
    }
}

public enum QwenChatModelCatalog {
    /// Only IDs verified against the local `qwen` CLI (Q1 Discovery) may appear here.
    public static let qwen38MaxPreviewID = "qwen3.8-max-preview"
    public static let defaultModelID = qwen38MaxPreviewID

    public static let options: [QwenChatModelOption] = [
        QwenChatModelOption(
            id: qwen38MaxPreviewID,
            displayName: "Qwen 3.8 Max Preview",
            shortName: "Qwen",
            description: "Default Qwen agent for VaniScript embedded chat (Qwen Code CLI `-m`)."
        ),
    ]

    public static func option(id: String) -> QwenChatModelOption? {
        options.first { $0.id == id }
    }

    public static func normalizedModelID(_ id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return defaultModelID
        }
        return option(id: trimmed) == nil ? defaultModelID : trimmed
    }

    public static func displayLabel(modelID: String) -> String {
        let option = option(id: normalizedModelID(modelID)) ?? options[0]
        return option.shortName
    }
}

public struct QwenAgentRun: Equatable, Sendable {
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

/// Parses headless `qwen` CLI output emitted with `-o stream-json` (NDJSON).
///
/// Verified Qwen Code schema (Q1 Discovery):
/// - `{"type":"system","subtype":"init","session_id":"...","model":"..."}`
/// - `{"type":"assistant","message":{"content":[{"type":"text","text":"..."}]}}`
///   (`content` may also arrive as a single object instead of an array)
/// - `{"type":"result","subtype":"success","result":"...","usage":{...}}`
public enum QwenAgentOutputParser {
    public static func parse(jsonLines data: Data) -> QwenAgentRun {
        guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
            return QwenAgentRun()
        }

        var runID: String?
        var assistantText: String?
        var resultText: String?
        var toolNames = [String]()
        var errorMessage: String?
        var sawJSON = false

        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let lineData = trimmed.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else {
                // Q2: skip non-JSON diagnostic lines emitted before/around the stream.
                continue
            }
            sawJSON = true

            let eventType = (event["type"] as? String) ?? ""

            switch eventType {
            case "system":
                // {"type":"system","subtype":"init","session_id":"..."}
                if let sessionID = event["session_id"] as? String {
                    runID = sessionID
                }
            case "assistant":
                guard let message = event["message"] as? [String: Any] else { break }
                // `content` is normally an array of blocks, but tolerate a single object.
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
                    if blockType == "text", let chunk = block["text"] as? String {
                        assistantText = (assistantText ?? "") + chunk
                    } else if blockType == "tool_use",
                              let toolName = block["name"] as? String,
                              !toolNames.contains(toolName) {
                        toolNames.append(toolName)
                    }
                }
            case "result":
                let subtype = (event["subtype"] as? String) ?? ""
                if let sessionID = event["session_id"] as? String {
                    runID = sessionID
                }
                if subtype == "success" {
                    // result.result is the fallback when no assistant text streamed.
                    if let text = event["result"] as? String {
                        resultText = text
                    }
                } else if let message = event["error"] as? String {
                    errorMessage = message
                } else if let message = event["result"] as? String {
                    errorMessage = message
                }
            default:
                break
            }
        }

        // Fallback chain: streamed assistant text > result.result > plain stdout.
        var responseText = assistantText ?? resultText
        if !sawJSON {
            let plain = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !plain.isEmpty {
                responseText = plain
            }
        }

        return QwenAgentRun(
            runID: runID,
            responseText: responseText,
            toolNames: toolNames,
            errorMessage: errorMessage
        )
    }
}
