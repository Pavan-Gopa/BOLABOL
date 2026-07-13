import Testing
@testable import VaniScriptCore

@Suite("VaniScript MCP project versioning")
struct McpProjectVersioningTests {
    @Test("stable chunk and cue IDs round trip")
    func stableEntityIDs() {
        let chunk = ChunkData(
            index: 4,
            filePath: "/tmp/chunk.wav",
            durationSec: 10,
            startSec: 40,
            endSec: 50,
            original: "Hare Krishna",
            translated: "Харе Кришна",
            status: .done,
            approved: false
        )

        #expect(McpEntityIdentifier.chunkID(chunk) == "chunk-4")
        #expect(McpEntityIdentifier.chunkIndex(from: "chunk-4") == 4)
        #expect(McpEntityIdentifier.chunkIndex(from: "invalid") == nil)
        #expect(McpEntityIdentifier.cueID(chunk: chunk, side: "Original", index: 2) == "chunk-4-original-cue-2")
    }

    @Test("project revision is deterministic and changes with project content")
    func projectRevisionTracksContent() {
        var workflow = WorkflowState.initial(settings: .defaults)
        workflow.selectSource(path: "/tmp/lecture.mp3", durationSec: 60)
        workflow.startSession()

        let first = McpProjectRevision.make(workflow: workflow)
        let repeated = McpProjectRevision.make(workflow: workflow)
        workflow.session?.chunks[0].original = "Changed transcript"
        let changed = McpProjectRevision.make(workflow: workflow)

        #expect(first == repeated)
        #expect(first.hasPrefix("rev-"))
        #expect(first != changed)
    }
}
