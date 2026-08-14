import Foundation
import Testing
import VaniScriptCore

@Suite("Document Config workflow")
struct DocumentConfigWorkflowTests {
    @Test("document Config visibility removes media-only controls")
    func documentConfigVisibilityPolicy() {
        let document = WorkflowConfigPolicy(sourceKind: .document)
        #expect(!document.showsAudioMetadata)
        #expect(!document.showsTranscriptionModel)
        #expect(!document.showsChunkDuration)
        #expect(!document.showsSliceMode)
        #expect(document.showsDocumentMetadata)
        #expect(document.sourceLanguageIsFixedAuto)

        let media = WorkflowConfigPolicy(sourceKind: .media)
        #expect(media.showsAudioMetadata)
        #expect(media.showsTranscriptionModel)
        #expect(media.showsChunkDuration)
        #expect(media.showsSliceMode)
        #expect(!media.showsDocumentMetadata)
        #expect(!media.sourceLanguageIsFixedAuto)
    }

    @Test("document source remains auto while target data stays editable")
    func documentLanguageContract() {
        var workflow = WorkflowState.initial(settings: .defaults)
        workflow.sourceLang = "en"
        workflow.transcriptionProvider = ""

        var documentState = makeDocumentState(
            profile: DocumentTranslationProfile(sourceLanguage: "English", targetLanguage: "Russian")
        )
        workflow.selectDocument(path: "/tmp/notes.txt", documentState: documentState)

        #expect(workflow.sourceKind == .document)
        #expect(workflow.sourceLang == NativeLanguagePolicy.autoCode)
        #expect(workflow.documentState?.profile.sourceLanguage == NativeLanguagePolicy.autoCode)
        #expect(workflow.canStartSession)

        workflow.updateTargetLanguage("French")
        #expect(workflow.targetLang == "French")
        #expect(workflow.documentState?.profile.targetLanguage == "French")
        #expect(workflow.documentState?.profile.sourceLanguage == NativeLanguagePolicy.autoCode)
        #expect(workflow.translationProvider == workflow.settings.translationProvider)

        documentState = workflow.documentState ?? documentState
        #expect(documentState.profile.sourceLanguage == NativeLanguagePolicy.autoCode)
    }

    @Test("document start builds semantic aggregate chunks with document anchors")
    func documentStartBuildsAnchoredChunks() throws {
        let blocks = [
            DocumentBlock(
                id: "heading-1",
                location: DocumentLocation(paragraphOrdinal: 0),
                kind: .heading,
                styleID: "ChapterTitle",
                spans: [
                    RichTextSpan(id: "heading-1-a", text: "Chapter "),
                    RichTextSpan(id: "heading-1-b", text: "One")
                ]
            ),
            DocumentBlock(
                id: "paragraph-2",
                location: DocumentLocation(paragraphOrdinal: 1),
                spans: [RichTextSpan(id: "paragraph-2-a", text: "A paragraph.")]
            ),
            DocumentBlock(
                id: "empty-3",
                location: DocumentLocation(paragraphOrdinal: 2),
                kind: .empty
            )
        ]
        var workflow = WorkflowState.initial(settings: .defaults)
        workflow.transcriptionProvider = ""
        workflow.selectDocument(
            path: "/tmp/notes.txt",
            documentState: makeDocumentState(blocks: blocks)
        )
        workflow.startSession()

        let session = try #require(workflow.session)
        #expect(workflow.screen == .review)
        #expect(session.sourceKind == .document)
        #expect(session.chunks.count == 1)
        #expect(session.documentState?.chunks.count == session.chunks.count)
        #expect(session.chunks[0].original == "Chapter One\n\nA paragraph.\n\n")
        #expect(session.chunks[0].translated.isEmpty)
        #expect(session.chunks[0].originalCues == nil)
        #expect(session.chunks[0].status == ChunkStatus.pending)
        #expect(session.chunks[0].reviewDisposition == ReviewDisposition.pending)
        #expect(!session.chunks[0].approved)

        guard case let .document(range) = session.chunks[0].sourceAnchor else {
            #expect(Bool(false))
            return
        }
        #expect(range.startBlockID == "heading-1")
        #expect(range.endBlockID == "empty-3")
        #expect(session.documentState?.chunks[0].blockIDs == ["heading-1", "paragraph-2", "empty-3"])
        #expect(session.documentState?.chunks[0].sourceTokenEstimate ?? 0 > 0)
    }

    @Test("media start keeps planner output and transcription gate")
    func mediaStartRemainsUnchanged() {
        var media = WorkflowState.initial(settings: .defaults)
        media.selectSource(path: "/audio/lecture.wav", durationSec: 1_250)
        let expected = ChunkPlanner.plan(
            sourcePath: "/audio/lecture.wav",
            durationSec: 1_250,
            chunkDurationMin: media.settings.chunkDurationMin
        )

        #expect(media.canStartSession)
        media.startSession()
        #expect(media.session?.sourceKind == .media)
        #expect(media.session?.chunks == expected)

        var gatedMedia = WorkflowState.initial(settings: .defaults)
        gatedMedia.selectSource(path: "/audio/lecture.wav", durationSec: 120)
        gatedMedia.transcriptionProvider = ""
        #expect(!gatedMedia.canStartSession)
    }


    @Test("document session approval mode is a snapshot of the launch setting")
    func approvalModeIsSessionSnapshot() throws {
        var workflow = WorkflowState.initial(settings: .defaults)
        workflow.transcriptionProvider = ""
        workflow.documentApprovalMode = .automatic
        workflow.selectDocument(
            path: "/tmp/notes.txt",
            documentState: makeDocumentState(
                blocks: [
                    DocumentBlock(
                        id: "body",
                        location: DocumentLocation(paragraphOrdinal: 0),
                        spans: [RichTextSpan(id: "span", text: "A paragraph.")]
                    )
                ]
            )
        )
        workflow.startSession()

        #expect(workflow.session?.approvalMode == .automatic)
        workflow.settings.documentApprovalModeDefault = .manual
        workflow.documentApprovalMode = .manual
        #expect(workflow.session?.approvalMode == .automatic)
    }

    private func makeDocumentState(
        blocks: [DocumentBlock] = [],
        profile: DocumentTranslationProfile = .default
    ) -> DocumentState {
        DocumentState(
            format: .txt,
            originalAsset: ProjectAssetReference(
                key: "sourceFile",
                originalFileName: "notes.txt",
                format: "txt",
                sha256: "document-hash",
                size: 128
            ),
            metadata: DocumentMetadata(title: "Notes", author: "Author"),
            blocks: blocks,
            profile: profile
        )
    }
}
