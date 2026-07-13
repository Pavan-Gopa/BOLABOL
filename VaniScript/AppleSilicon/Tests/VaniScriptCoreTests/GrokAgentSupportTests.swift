import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Grok embedded agent output")
struct GrokAgentSupportTests {
    @Test("normalizes embedded chat model selections and reasoning")
    func normalizesEmbeddedChatModelSelection() {
        #expect(GrokChatModelCatalog.defaultModelID == "grok-4.5")
        #expect(GrokChatModelCatalog.normalizedModelID("unknown-model") == "grok-4.5")
        #expect(GrokChatModelCatalog.normalizedReasoningEffort(
            modelID: "grok-4.5-composer",
            effort: "high"
        ) == "high")
        #expect(GrokChatModelCatalog.normalizedReasoningEffort(
            modelID: "grok-4.5-fast",
            effort: "ultra"
        ) == "low")
        #expect(GrokChatModelCatalog.displayLabel(
            modelID: "grok-4.5",
            effort: "high"
        ) == "Grok · High")
    }

    @Test("parses a successful MCP-backed Grok response")
    func parsesSuccessfulRun() {
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
        {"type":"content","text":"Ready."}
        """

        let run = GrokAgentOutputParser.parse(jsonLines: Data(output.utf8))

        #expect(run.responseText == "Ready.")
        #expect(run.errorMessage == nil)
    }
}
