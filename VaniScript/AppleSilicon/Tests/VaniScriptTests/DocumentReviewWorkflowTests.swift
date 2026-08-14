import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

@Suite("Document Review workflow")
struct DocumentReviewWorkflowTests {
    @Test("document start persists a bounded semantic plan and visible source presentation")
    func documentStartAndPresentation() throws {
        let blocks = [
            DocumentBlock(
                id: "chapter-1",
                location: DocumentLocation(paragraphOrdinal: 0),
                kind: .heading,
                styleID: "ChapterTitle",
                spans: [RichTextSpan(id: "s1", text: "Chapter One")]
            ),
            DocumentBlock(
                id: "body-1",
                location: DocumentLocation(paragraphOrdinal: 1),
                spans: [RichTextSpan(id: "s2", text: "A visible source paragraph for document Review.")]
            ),
            DocumentBlock(
                id: "quote-1",
                location: DocumentLocation(paragraphOrdinal: 2),
                kind: .quote,
                styleID: "Quote",
                spans: [RichTextSpan(id: "s3", text: "A quoted line.")]
            )
        ]
        var workflow = WorkflowState.initial(settings: .defaults)
        workflow.transcriptionProvider = ""
        workflow.selectDocument(
            path: "/tmp/book.txt",
            documentState: DocumentState(
                format: .txt,
                originalAsset: ProjectAssetReference(key: "source", originalFileName: "book.txt", format: "txt"),
                metadata: DocumentMetadata(title: "Book", author: "Author"),
                blocks: blocks
            )
        )
        workflow.startSession()

        let session = try #require(workflow.session)
        #expect(workflow.screen == .review)
        #expect(session.sourceKind == .document)
        #expect(session.documentState?.chunks.count == session.chunks.count)
        #expect(session.chunks.count < blocks.count)
        let presentation = try #require(DocumentReviewPresentationPolicy.make(session: session, chunk: session.chunks[0]))
        #expect(!presentation.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(presentation.sourceText.contains("visible source paragraph"))
        #expect(presentation.chapterLabel == "Chapter One")
        #expect(presentation.blockRangeLabel.contains("paragraph"))
        #expect(presentation.displayLabel.contains("Chapter One"))
        #expect(presentation.blockRoles.contains("heading"))
        #expect(!presentation.showsAudioBar)
        #expect(!presentation.showsWaveform)
        #expect(!presentation.showsTimecode)
        #expect(presentation.usesSourceTextFallback)
    }

    @Test("media presentation does not opt into document-only rendering")
    func mediaRemainsMedia() {
        var workflow = WorkflowState.initial(settings: .defaults)
        workflow.selectSource(path: "/tmp/audio.wav", durationSec: 10)
        workflow.startSession()
        let chunk = workflow.session?.chunks.first
        #expect(chunk != nil)
        if let chunk, let session = workflow.session {
            #expect(DocumentReviewPresentationPolicy.make(session: session, chunk: chunk) == nil)
            #expect(chunk.sourceAnchor == .media(startSec: chunk.startSec, endSec: chunk.endSec))
        }
    }

    @Test("document policy falls back to aggregated source when chunk text is empty")
    func sourceFallback() throws {
        let block = DocumentBlock(
            id: "body",
            location: DocumentLocation(paragraphOrdinal: 3),
            spans: [RichTextSpan(id: "span", text: "Recovered source text.")]
        )
        let documentState = DocumentState(
            format: .txt,
            originalAsset: ProjectAssetReference(key: "source"),
            blocks: block == block ? [block] : []
        )
        let plan = DocumentChunkPlan(id: "plan", blockIDs: [block.id], sourceTokenEstimate: 4)
        var session = SessionState(
            sourceFile: "/tmp/book.txt",
            sourceFileName: "book.txt",
            durationSec: 0,
            metadata: .empty,
            sourceLang: "auto",
            targetLang: "Russian",
            transcriptionProvider: "",
            translationProvider: "mlx-native",
            outputFormats: [.txt],
            chunks: [ChunkData(
                index: 0,
                filePath: "/tmp/book.txt",
                durationSec: 0,
                startSec: 0,
                endSec: 0,
                original: "",
                translated: "",
                status: .pending,
                approved: false,
                sourceAnchor: .document(DocumentRange(startBlockID: block.id, endBlockID: block.id))
            )],
            currentChunkIndex: 0,
            sourceKind: .document,
            documentState: DocumentState(
                format: documentState.format,
                originalAsset: documentState.originalAsset,
                blocks: documentState.blocks,
                chunks: [plan]
            )
        )
        let presentation = try #require(DocumentReviewPresentationPolicy.make(session: session, chunk: session.chunks[0]))
        #expect(presentation.sourceText == "Recovered source text.")
        #expect(presentation.usesSourceTextFallback)
    }

    @Test("Approve & Next policy only starts manual translation for an unusable next chunk")
    func approvalAdvancePolicy() {
        #expect(
            DocumentApprovalAdvancePolicy.shouldTranslateNext(
                approvalMode: .manual,
                hasNextChunk: true,
                nextTranslationIsUsable: false
            )
        )
        #expect(
            !DocumentApprovalAdvancePolicy.shouldTranslateNext(
                approvalMode: .manual,
                hasNextChunk: true,
                nextTranslationIsUsable: true
            )
        )
        #expect(
            !DocumentApprovalAdvancePolicy.shouldTranslateNext(
                approvalMode: .automatic,
                hasNextChunk: true,
                nextTranslationIsUsable: false
            )
        )
        #expect(
            !DocumentApprovalAdvancePolicy.shouldTranslateNext(
                approvalMode: .manual,
                hasNextChunk: false,
                nextTranslationIsUsable: false
            )
        )
    }
}
