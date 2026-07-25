import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Qwen embedded agent output")
struct QwenAgentSupportTests {
    @Test("normalizes embedded chat model selections")
    func normalizesEmbeddedChatModelSelection() {
        #expect(QwenChatModelCatalog.defaultModelID == "qwen3.8-max-preview")
        #expect(QwenChatModelCatalog.normalizedModelID("qwen3.8-max-preview") == "qwen3.8-max-preview")
        #expect(QwenChatModelCatalog.normalizedModelID("unknown-model") == "qwen3.8-max-preview")
        #expect(QwenChatModelCatalog.normalizedModelID("") == "qwen3.8-max-preview")
        #expect(QwenChatModelCatalog.normalizedModelID("   ") == "qwen3.8-max-preview")
        #expect(QwenChatModelCatalog.displayLabel(modelID: "qwen3.8-max-preview") == "Qwen")
        #expect(QwenChatModelCatalog.displayLabel(modelID: "unknown-model") == "Qwen")
    }

    @Test("parses live Qwen Code stream-json assistant events")
    func parsesLiveStreamJSON() {
        let output = """
        {"type":"system","subtype":"init","session_id":"0199aa1b-2c3d-4e5f-8091-a2b3c4d5e6f7","model":"qwen3.8-max-preview"}
        {"type":"assistant","message":{"content":[{"type":"text","text":"Hello"},{"type":"text","text":"!"}]}}
        {"type":"result","subtype":"success","result":"Hello!","usage":{"input_tokens":10,"output_tokens":2}}
        """

        let run = QwenAgentOutputParser.parse(jsonLines: Data(output.utf8))

        #expect(run.runID == "0199aa1b-2c3d-4e5f-8091-a2b3c4d5e6f7")
        #expect(run.responseText == "Hello!")
        #expect(run.toolNames.isEmpty)
        #expect(run.errorMessage == nil)
    }

    @Test("parses assistant content emitted as a single object")
    func parsesSingleObjectContent() {
        let output = """
        {"type":"assistant","message":{"content":{"type":"text","text":"Hi there"}}}
        """

        let run = QwenAgentOutputParser.parse(jsonLines: Data(output.utf8))

        #expect(run.responseText == "Hi there")
        #expect(run.errorMessage == nil)
    }

    @Test("falls back to result.result when no assistant text streamed")
    func fallsBackToResult() {
        let output = """
        {"type":"system","subtype":"init","session_id":"sess-1","model":"qwen3.8-max-preview"}
        {"type":"result","subtype":"success","result":"Fallback answer.","usage":{}}
        """

        let run = QwenAgentOutputParser.parse(jsonLines: Data(output.utf8))

        #expect(run.runID == "sess-1")
        #expect(run.responseText == "Fallback answer.")
        #expect(run.errorMessage == nil)
    }

    @Test("preserves a Qwen failure result as an error")
    func preservesFailureResult() {
        let output = """
        {"type":"system","subtype":"init","session_id":"sess-2","model":"qwen3.8-max-preview"}
        {"type":"result","subtype":"error","result":"Quota exceeded."}
        """

        let run = QwenAgentOutputParser.parse(jsonLines: Data(output.utf8))

        #expect(run.runID == "sess-2")
        #expect(run.responseText == nil)
        #expect(run.errorMessage == "Quota exceeded.")
    }

    @Test("ignores malformed diagnostic lines")
    func ignoresMalformedLines() {
        let output = """
        Qwen diagnostic output
        {"type":"assistant","message":{"content":[{"type":"text","text":"Ready."}]}}
        """

        let run = QwenAgentOutputParser.parse(jsonLines: Data(output.utf8))

        #expect(run.responseText == "Ready.")
        #expect(run.errorMessage == nil)
    }

    @Test("falls back to plain non-JSON stdout")
    func plainStdoutFallback() {
        let run = QwenAgentOutputParser.parse(jsonLines: Data("OK\n".utf8))
        #expect(run.responseText == "OK")
        #expect(run.errorMessage == nil)
    }
}
