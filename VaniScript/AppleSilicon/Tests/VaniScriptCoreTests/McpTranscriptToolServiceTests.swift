import Foundation
import Testing
@testable import VaniScriptCore

@MainActor
@Suite("VaniScript MCP transcript tools")
struct McpTranscriptToolServiceTests {
    @Test("previews and confirms a project-wide replacement")
    func replacementRequiresPreviewToken() throws {
        let workflow = makeWorkflow()
        let confirmations = McpConfirmationStore()
        let previewArguments: [String: Any] = [
            "query": "Krishna",
            "replacement": "Krsna",
            "side": "original",
            "dryRun": true,
        ]

        let preview = try McpTranscriptToolService.execute(
            name: "replace_transcript_text",
            arguments: previewArguments,
            workflow: workflow,
            confirmationStore: confirmations
        )
        let token = try #require(preview.details["confirmationToken"] as? String)
        #expect(preview.workflow == workflow)
        #expect(preview.details["matchCount"] as? Int == 2)

        var applyArguments = previewArguments
        applyArguments["dryRun"] = false
        applyArguments["confirmationToken"] = token
        applyArguments["expectedRevision"] = McpProjectRevision.make(workflow: workflow)
        let applied = try McpTranscriptToolService.execute(
            name: "replace_transcript_text",
            arguments: applyArguments,
            workflow: workflow,
            confirmationStore: confirmations
        )

        #expect(applied.details["replacementCount"] as? Int == 2)
        #expect(applied.workflow.session?.chunks[0].original.contains("Krsna") == true)
        #expect(applied.workflow.session?.chunks[1].original.contains("Krsna") == true)

        do {
            _ = try McpTranscriptToolService.execute(
                name: "replace_transcript_text",
                arguments: applyArguments,
                workflow: workflow,
                confirmationStore: confirmations
            )
            Issue.record("A consumed confirmation token was accepted twice")
        } catch {
            #expect(error.localizedDescription.contains("CONFIRMATION_REQUIRED"))
        }
    }

    @Test("updates, splits, merges, inserts, and deletes timed cues")
    func cueEditingWorkflow() throws {
        let confirmations = McpConfirmationStore()
        var workflow = makeWorkflow()
        let revision = McpProjectRevision.make(workflow: workflow)

        let updated = try McpTranscriptToolService.execute(
            name: "update_cue_text",
            arguments: [
                "chunkId": "chunk-0",
                "side": "original",
                "cueId": "chunk-0-original-cue-0",
                "text": "Hare Krishna forever",
                "expectedRevision": revision,
            ],
            workflow: workflow,
            confirmationStore: confirmations
        )
        workflow = updated.workflow
        #expect(workflow.session?.chunks[0].original.contains("forever") == true)

        let split = try McpTranscriptToolService.execute(
            name: "split_cue",
            arguments: [
                "chunkId": "chunk-0",
                "side": "original",
                "cueId": "chunk-0-original-cue-0",
                "splitAtCharacter": 13,
                "splitSec": 2.0,
            ],
            workflow: workflow,
            confirmationStore: confirmations
        )
        workflow = split.workflow
        #expect(workflow.session?.chunks[0].originalCues?.count == 3)

        let merged = try McpTranscriptToolService.execute(
            name: "merge_cues",
            arguments: [
                "chunkId": "chunk-0",
                "side": "original",
                "firstCueId": "chunk-0-original-cue-0",
            ],
            workflow: workflow,
            confirmationStore: confirmations
        )
        workflow = merged.workflow
        #expect(workflow.session?.chunks[0].originalCues?.count == 2)

        let inserted = try McpTranscriptToolService.execute(
            name: "insert_cue",
            arguments: [
                "chunkId": "chunk-0",
                "side": "original",
                "insertAt": 1,
                "startSec": 4.0,
                "endSec": 5.0,
                "text": "Inserted cue",
            ],
            workflow: workflow,
            confirmationStore: confirmations
        )
        workflow = inserted.workflow
        #expect(workflow.session?.chunks[0].originalCues?.count == 3)

        let deleted = try McpTranscriptToolService.execute(
            name: "delete_cue",
            arguments: [
                "chunkId": "chunk-0",
                "side": "original",
                "cueId": "chunk-0-original-cue-1",
            ],
            workflow: workflow,
            confirmationStore: confirmations
        )
        #expect(deleted.workflow.session?.chunks[0].originalCues?.count == 2)
    }

    @Test("batch updates are atomic and approvals use stable chunk IDs")
    func batchUpdatesAndApprovals() throws {
        let confirmations = McpConfirmationStore()
        let workflow = makeWorkflow()
        let updated = try McpTranscriptToolService.execute(
            name: "batch_update_chunk_text",
            arguments: [
                "updates": [
                    ["chunkId": "chunk-0", "original": "First revised"],
                    ["chunkId": "chunk-1", "translated": "Второй исправлен"],
                ],
            ],
            workflow: workflow,
            confirmationStore: confirmations
        )
        #expect(updated.workflow.session?.chunks[0].original == "First revised")
        #expect(updated.workflow.session?.chunks[1].translated == "Второй исправлен")

        let approved = try McpTranscriptToolService.execute(
            name: "batch_approve_chunks",
            arguments: [
                "chunkIds": ["chunk-0", "chunk-1"],
                "approved": true,
            ],
            workflow: updated.workflow,
            confirmationStore: confirmations
        )
        #expect(approved.workflow.session?.chunks.allSatisfy(\.approved) == true)

        do {
            _ = try McpTranscriptToolService.execute(
                name: "batch_update_chunk_text",
                arguments: [
                    "updates": [
                        ["chunkId": "chunk-0", "original": "Must not apply"],
                        ["chunkId": "chunk-99", "original": "Invalid"],
                    ],
                ],
                workflow: workflow,
                confirmationStore: confirmations
            )
            Issue.record("An invalid atomic batch was accepted")
        } catch {
            #expect(workflow.session?.chunks[0].original != "Must not apply")
        }
    }
}

private extension McpTranscriptToolServiceTests {
    func makeWorkflow() -> WorkflowState {
        let sourceCues = [
            TranscriptCue(startSec: 0, endSec: 4, text: "Hare Krishna"),
            TranscriptCue(startSec: 5, endSec: 9, text: "Hare Rama"),
        ]
        let targetCues = [
            TranscriptCue(startSec: 0, endSec: 4, text: "Харе Кришна"),
            TranscriptCue(startSec: 5, endSec: 9, text: "Харе Рама"),
        ]
        var first = ChunkData(
            index: 0,
            filePath: "/tmp/chunk-0.wav",
            durationSec: 10,
            startSec: 0,
            endSec: 10,
            original: "Hare Krishna Hare Rama",
            translated: "Харе Кришна\nХаре Рама",
            originalCues: sourceCues,
            status: .done,
            approved: false
        )
        first.setTranslation("Харе Кришна\nХаре Рама", language: "Russian", cues: targetCues)
        let second = ChunkData(
            index: 1,
            filePath: "/tmp/chunk-1.wav",
            durationSec: 10,
            startSec: 10,
            endSec: 20,
            original: "Remember Krishna",
            translated: "Помни Кришну",
            status: .done,
            approved: false
        )
        var workflow = WorkflowState.initial(settings: .defaults)
        workflow.sourceFile = "/tmp/lecture.wav"
        workflow.sourceFileName = "lecture.wav"
        workflow.durationSec = 20
        workflow.screen = .review
        workflow.session = SessionState(
            sourceFile: workflow.sourceFile,
            sourceFileName: workflow.sourceFileName,
            durationSec: 20,
            metadata: .empty,
            sourceLang: "English",
            targetLang: "Russian",
            transcriptionProvider: "coreml-whisperkit",
            translationProvider: "mlx-native",
            outputFormats: [.txt, .srt],
            chunks: [first, second],
            currentChunkIndex: 0,
            availableTranslationLanguages: ["Russian"],
            activeTranslationLanguage: "Russian"
        )
        return workflow
    }
}
