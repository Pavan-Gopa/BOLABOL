import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Codex embedded agent output")
struct CodexAgentSupportTests {
    @Test("normalizes embedded chat model selections and reasoning")
    func normalizesEmbeddedChatModelSelection() {
        #expect(CodexChatModelCatalog.defaultModelID == "gpt-5.6-luna")
        #expect(CodexChatModelCatalog.normalizedModelID("unknown-model") == "gpt-5.6-luna")
        #expect(CodexChatModelCatalog.normalizedReasoningEffort(
            modelID: "gpt-5.6-terra",
            effort: "ultra"
        ) == "ultra")
        #expect(CodexChatModelCatalog.normalizedReasoningEffort(
            modelID: "gpt-5.6-luna",
            effort: "ultra"
        ) == "medium")
        #expect(CodexChatModelCatalog.displayLabel(
            modelID: "gpt-5.6-luna",
            effort: "high"
        ) == "Luna · High")
    }

    @Test("parses a successful MCP-backed Codex response")
    func parsesSuccessfulRun() {
        let output = """
        {"type":"thread.started","thread_id":"thread-123"}
        {"type":"item.started","item":{"type":"mcp_tool_call","server":"vaniscript_embedded","tool":"get_project_state"}}
        {"type":"item.completed","item":{"type":"mcp_tool_call","server":"vaniscript_embedded","tool":"get_project_state","status":"completed"}}
        {"type":"item.completed","item":{"type":"agent_message","text":"В проекте 5 чанков."}}
        {"type":"turn.completed"}
        """

        let run = CodexAgentOutputParser.parse(jsonLines: Data(output.utf8))

        #expect(run.threadID == "thread-123")
        #expect(run.responseText == "В проекте 5 чанков.")
        #expect(run.toolNames == ["get_project_state"])
        #expect(run.errorMessage == nil)
    }

    @Test("preserves a Codex availability error")
    func preservesAvailabilityError() {
        let output = """
        {"type":"thread.started","thread_id":"thread-456"}
        {"type":"error","message":"Your workspace is out of credits."}
        {"type":"turn.failed","error":{"message":"Your workspace is out of credits."}}
        """

        let run = CodexAgentOutputParser.parse(jsonLines: Data(output.utf8))

        #expect(run.threadID == "thread-456")
        #expect(run.responseText == nil)
        #expect(run.toolNames.isEmpty)
        #expect(run.errorMessage == "Your workspace is out of credits.")
    }

    @Test("ignores malformed diagnostic lines")
    func ignoresMalformedLines() {
        let output = """
        Codex diagnostic output
        {"type":"item.completed","item":{"type":"agent_message","text":"Ready."}}
        """

        let run = CodexAgentOutputParser.parse(jsonLines: Data(output.utf8))

        #expect(run.responseText == "Ready.")
        #expect(run.errorMessage == nil)
    }
}
