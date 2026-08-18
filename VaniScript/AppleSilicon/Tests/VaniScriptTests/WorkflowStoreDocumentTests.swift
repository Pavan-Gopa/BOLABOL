import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

@MainActor
@Suite("WorkflowStore document approval and export")
struct WorkflowStoreDocumentTests {
    @Test("approveAndAdvanceDocument approves source-empty chunk without requiring usable translation")
    func approveAndAdvanceSourceEmptyChunk() throws {
        let store = WorkflowStore(
            projects: [],
            settingsPersistence: { _ in },
            projectsPersistence: { _ in },
            startInitialModelScan: false
        )

        let block1 = DocumentBlock(
            id: "b1",
            location: DocumentLocation(paragraphOrdinal: 0),
            kind: .paragraph,
            spans: [RichTextSpan(id: "s1", text: "Source paragraph")]
        )
        let block2 = DocumentBlock(
            id: "b2",
            location: DocumentLocation(paragraphOrdinal: 1),
            kind: .empty,
            spans: []
        )

        let chunk1 = ChunkData(
            index: 0,
            filePath: "/tmp/doc.docx",
            durationSec: 0,
            startSec: 0,
            endSec: 0,
            original: "Source paragraph",
            translated: "Переведенный абзац",
            status: .pending,
            approved: false,
            sourceAnchor: .document(DocumentRange(startBlockID: "b1", endBlockID: "b1"))
        )
        let chunk2 = ChunkData(
            index: 1,
            filePath: "/tmp/doc.docx",
            durationSec: 0,
            startSec: 0,
            endSec: 0,
            original: "",
            translated: "",
            status: .pending,
            approved: false,
            sourceAnchor: .document(DocumentRange(startBlockID: "b2", endBlockID: "b2"))
        )

        let documentState = DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(key: "src", originalFileName: "doc.docx"),
            blocks: [block1, block2],
            chunks: [
                DocumentChunkPlan(id: "p1", blockIDs: ["b1"]),
                DocumentChunkPlan(id: "p2", blockIDs: ["b2"])
            ],
            translationsByLanguage: [
                "russian": [
                    "b1": TranslatedBlock(id: "tb1", blockID: "b1", text: "Переведенный абзац")
                ]
            ]
        )

        var session = SessionState(
            sourceFile: "/tmp/doc.docx",
            sourceFileName: "doc.docx",
            durationSec: 0,
            metadata: .empty,
            sourceLang: "auto",
            targetLang: "Russian",
            transcriptionProvider: "",
            translationProvider: "gemini-cloud",
            outputFormats: [.txt],
            chunks: [chunk1, chunk2],
            currentChunkIndex: 0,
            sourceKind: .document,
            documentState: documentState,
            approvalMode: .manual
        )
        session.activeTranslationLanguage = "Russian"
        store.workflow.session = session
        store.workflow.screen = .review

        // Approve chunk 0 (translated) -> advances to chunk 1
        store.approveAndAdvance()
        #expect(store.workflow.session?.currentChunkIndex == 1)
        #expect(store.workflow.session?.chunks[0].approved == true)
        #expect(store.workflow.screen == .review)

        // Approve chunk 1 (source-empty) -> approves without requiring translation, reaches export screen
        store.approveAndAdvance()
        #expect(store.workflow.session?.chunks[1].approved == true)
        #expect(store.workflow.session?.chunks[1].reviewDisposition == .manuallyApproved)
        #expect(store.workflow.session?.chunks[1].status == .done)
        #expect(store.workflow.screen == .export)
    }

    @Test("approveAndAdvanceDocument blocks non-empty untranslated chunk")
    func approveAndAdvanceBlocksUntranslatedNonEmptyChunk() throws {
        let store = WorkflowStore(
            projects: [],
            settingsPersistence: { _ in },
            projectsPersistence: { _ in },
            startInitialModelScan: false
        )

        let block1 = DocumentBlock(
            id: "b1",
            location: DocumentLocation(paragraphOrdinal: 0),
            kind: .paragraph,
            spans: [RichTextSpan(id: "s1", text: "Untranslated text")]
        )

        let chunk1 = ChunkData(
            index: 0,
            filePath: "/tmp/doc.docx",
            durationSec: 0,
            startSec: 0,
            endSec: 0,
            original: "Untranslated text",
            translated: "",
            status: .pending,
            approved: false,
            sourceAnchor: .document(DocumentRange(startBlockID: "b1", endBlockID: "b1"))
        )

        let documentState = DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(key: "src", originalFileName: "doc.docx"),
            blocks: [block1],
            chunks: [DocumentChunkPlan(id: "p1", blockIDs: ["b1"])],
            translationsByLanguage: [:]
        )

        var session = SessionState(
            sourceFile: "/tmp/doc.docx",
            sourceFileName: "doc.docx",
            durationSec: 0,
            metadata: .empty,
            sourceLang: "auto",
            targetLang: "Russian",
            transcriptionProvider: "",
            translationProvider: "gemini-cloud",
            outputFormats: [.txt],
            chunks: [chunk1],
            currentChunkIndex: 0,
            sourceKind: .document,
            documentState: documentState,
            approvalMode: .manual
        )
        session.activeTranslationLanguage = "Russian"
        store.workflow.session = session
        store.workflow.screen = .review

        store.approveAndAdvance()

        #expect(store.workflow.session?.chunks[0].approved == false)
        #expect(store.statusMessage == "Translate the current document chunk before approving it.")
        #expect(store.workflow.screen == .review)
    }
}
