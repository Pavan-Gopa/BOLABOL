import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Grok embedded agent output")
struct GrokAgentSupportTests {
    @Test("normalizes embedded chat model selections and reasoning")
    func normalizesEmbeddedChatModelSelection() {
        #expect(GrokChatModelCatalog.defaultModelID == "grok-4.5")
        #expect(GrokChatModelCatalog.normalizedModelID("unknown-model") == "grok-4.5")
        // Retired / invented IDs must never reach the CLI.
        #expect(GrokChatModelCatalog.normalizedModelID("grok-4.5-fast") == "grok-4.5")
        #expect(GrokChatModelCatalog.normalizedModelID("grok-4.5-composer") == "grok-4.5")
        #expect(GrokChatModelCatalog.normalizedReasoningEffort(
            modelID: "grok-4.5",
            effort: "high"
        ) == "high")
        #expect(GrokChatModelCatalog.normalizedReasoningEffort(
            modelID: "grok-4.5-fast",
            effort: "ultra"
        ) == "medium")
        #expect(GrokChatModelCatalog.displayLabel(
            modelID: "grok-4.5",
            effort: "high"
        ) == "Grok · High")
        #expect(GrokChatModelCatalog.displayLabel(
            modelID: "grok-4.5-fast",
            effort: "low"
        ) == "Grok · Low")
    }

    @Test("parses live Grok Build streaming-json text events")
    func parsesLiveStreamingJSON() {
        let output = """
        {"type":"thought","data":"The"}
        {"type":"thought","data":" user"}
        {"type":"text","data":"pong"}
        {"type":"end","stopReason":"EndTurn","sessionId":"019f76a9-7675-7161-9c2d-1a7efaabe8bd","requestId":"85abeb1f-d49a-4d0a-9c29-df83d5de51d0"}
        """

        let run = GrokAgentOutputParser.parse(jsonLines: Data(output.utf8))

        #expect(run.runID == "019f76a9-7675-7161-9c2d-1a7efaabe8bd")
        #expect(run.responseText == "pong")
        #expect(run.toolNames.isEmpty)
        #expect(run.errorMessage == nil)
    }

    @Test("parses a successful MCP-backed Grok response (legacy fixture)")
    func parsesSuccessfulRunLegacy() {
        let output = """
        {"type":"message_start","id":"run-123"}
        {"type":"tool_call","name":"get_project_state"}
        {"type":"tool_call","name":"get_project_state"}
        {"type":"content","text":"В проекте "}
        {"type":"content","text":"5 чанков."}
        {"type":"message_stop"}
        """

        let run = GrokAgentOutputParser.parse(jsonLines: Data(output.utf8))

        #expect(run.runID == "run-123")
        #expect(run.responseText == "В проекте 5 чанков.")
        #expect(run.toolNames == ["get_project_state"])
        #expect(run.errorMessage == nil)
    }

    @Test("preserves a Grok availability error")
    func preservesAvailabilityError() {
        let output = """
        {"type":"message_start","id":"run-456"}
        {"type":"error","message":"Your workspace is out of credits."}
        """

        let run = GrokAgentOutputParser.parse(jsonLines: Data(output.utf8))

        #expect(run.runID == "run-456")
        #expect(run.responseText == nil)
        #expect(run.toolNames.isEmpty)
        #expect(run.errorMessage == "Your workspace is out of credits.")
    }

    @Test("ignores malformed diagnostic lines")
    func ignoresMalformedLines() {
        let output = """
        Grok diagnostic output
        {"type":"text","data":"Ready."}
        """

        let run = GrokAgentOutputParser.parse(jsonLines: Data(output.utf8))

        #expect(run.responseText == "Ready.")
        #expect(run.errorMessage == nil)
    }

    @Test("falls back to plain non-JSON stdout")
    func plainStdoutFallback() {
        let run = GrokAgentOutputParser.parse(jsonLines: Data("OK\n".utf8))
        #expect(run.responseText == "OK")
        #expect(run.errorMessage == nil)
    }
}
