import Foundation
import AppKit
import SwiftUI
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
        let session = SessionState(
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
    @Test("manual edit of document source and translation spans persists colors")
    @MainActor
    func manualEditRetainsColor() throws {
        let block = DocumentBlock(
            id: "b1",
            location: DocumentLocation(paragraphOrdinal: 0),
            spans: [
                RichTextSpan(id: "s1", text: "Default ", foregroundColorHex: nil),
                RichTextSpan(id: "s2", text: "red", foregroundColorHex: "FF0000")
            ]
        )
        let plan = DocumentChunkPlan(id: "chunk-1", blockIDs: ["b1"], sourceHash: "h1")
        let chunk = ChunkData(
            index: 0,
            filePath: "/tmp/doc.docx",
            durationSec: 0,
            startSec: 0,
            endSec: 0,
            original: "Default red",
            translated: "",
            status: .pending,
            approved: false,
            sourceAnchor: .document(DocumentRange(startBlockID: "b1", endBlockID: "b1"))
        )
        let session = SessionState(
            sourceFile: "/tmp/doc.docx",
            sourceFileName: "doc.docx",
            durationSec: 0,
            metadata: .empty,
            sourceLang: "English",
            targetLang: "Russian",
            transcriptionProvider: "",
            translationProvider: "mock",
            outputFormats: [.txt],
            chunks: [chunk],
            currentChunkIndex: 0,
            sourceKind: .document,
            documentState: DocumentState(
                format: .docx,
                originalAsset: ProjectAssetReference(key: "source"),
                blocks: [block],
                chunks: [plan]
            ),
            approvalMode: .manual
        )
        let store = WorkflowStore()
        store.workflow.session = session

        let editedSourceSpans = [
            RichTextSpan(id: "s1", text: "Edited default ", foregroundColorHex: nil),
            RichTextSpan(id: "s2", text: "edited red", foregroundColorHex: "FF0000")
        ]
        store.updateCurrentDocumentSource(spans: editedSourceSpans, text: "Edited default edited red")
        #expect(store.currentDocumentSourceSpans == editedSourceSpans)

        let editedTransSpans = [
            RichTextSpan(id: "ts1", text: "Перевод ", foregroundColorHex: nil),
            RichTextSpan(id: "ts2", text: "красный", foregroundColorHex: "FF0000")
        ]
        store.updateCurrentDocumentTranslated(spans: editedTransSpans, text: "Перевод красный")
        #expect(store.currentDocumentTranslatedSpans == editedTransSpans)
        #expect(store.workflow.session?.documentState?.translationsByLanguage["russian"]?["b1"]?.spans == editedTransSpans)
    }

    @Test("attributed storage round-trip preserves block identities, colors, and style policies")
    @MainActor
    func attributedStorageRoundTrip() throws {
        let block1 = DocumentBlock(
            id: "b1",
            location: DocumentLocation(paragraphOrdinal: 0),
            kind: .heading,
            spans: [
                RichTextSpan(
                    id: "s1",
                    text: "Chapter 1: ",
                    styleKey: "Heading1",
                    traits: [.bold, .smallCaps],
                    translationPolicy: .translate,
                    foregroundColorHex: nil
                ),
                RichTextSpan(
                    id: "s2",
                    text: "The Beginning",
                    styleKey: "Heading1",
                    traits: [.bold, .superscript],
                    translationPolicy: .protect,
                    foregroundColorHex: "FF0000"
                )
            ]
        )
        let block2 = DocumentBlock(
            id: "b2",
            location: DocumentLocation(paragraphOrdinal: 1),
            kind: .paragraph,
            spans: [
                RichTextSpan(
                    id: "s3",
                    text: "It was a dark and ",
                    styleKey: "BodyText",
                    traits: [.subscriptText],
                    translationPolicy: .translate,
                    foregroundColorHex: nil
                ),
                RichTextSpan(
                    id: "s4",
                    text: "stormy night",
                    styleKey: "BodyText",
                    traits: [.italic, .smallCaps],
                    translationPolicy: .translateWithGlossary,
                    foregroundColorHex: "FF0000"
                )
            ]
        )
        let plan = DocumentChunkPlan(id: "chunk-1", blockIDs: ["b1", "b2"], sourceHash: "h1")
        let chunk = ChunkData(
            index: 0,
            filePath: "/tmp/doc.docx",
            durationSec: 0,
            startSec: 0,
            endSec: 0,
            original: "Chapter 1: The Beginning\n\nIt was a dark and stormy night",
            translated: "",
            status: .pending,
            approved: false,
            sourceAnchor: .document(DocumentRange(startBlockID: "b1", endBlockID: "b2"))
        )
        let session = SessionState(
            sourceFile: "/tmp/doc.docx",
            sourceFileName: "doc.docx",
            durationSec: 0,
            metadata: .empty,
            sourceLang: "English",
            targetLang: "Russian",
            transcriptionProvider: "",
            translationProvider: "mock",
            outputFormats: [.txt],
            chunks: [chunk],
            currentChunkIndex: 0,
            sourceKind: .document,
            documentState: DocumentState(
                format: .docx,
                originalAsset: ProjectAssetReference(key: "source"),
                blocks: [block1, block2],
                chunks: [plan]
            ),
            approvalMode: .manual
        )
        let store = WorkflowStore()
        store.workflow.session = session

        // 1. Verify initial store block projection
        let initialBlocks = store.currentDocumentSourceBlocks
        #expect(initialBlocks.count == 2)
        #expect(initialBlocks[0].id == "b1")
        #expect(initialBlocks[1].id == "b2")

        // 2. Set up DocumentAttributedTextView and load the blocks into its NSTextView
        var textBinding = chunk.original
        let binding = Binding(get: { textBinding }, set: { textBinding = $0 })
        let editorBlocks = initialBlocks.map {
            DocumentEditorBlockItem(id: $0.id, spans: $0.spans, fallbackText: $0.spans.map(\.text).joined())
        }

        var savedBlocks: [DocumentEditorBlockItem] = []
        var savedAggregateText: String = ""

        let editorView = DocumentAttributedTextView(
            text: binding,
            blocks: editorBlocks,
            onBlocksChanged: { blocks, aggregateText in
                savedBlocks = blocks
                savedAggregateText = aggregateText
                store.updateCurrentDocumentSource(
                    blocks: blocks.map { ($0.id, $0.spans, $0.fallbackText) },
                    text: aggregateText
                )
            },
            fontFamily: .sans,
            fontSize: .md,
            fontScale: 1.0
        )

        let coordinator = editorView.makeCoordinator()
        let textView = DocumentNSTextView()
        textView.delegate = coordinator
        coordinator.textView = textView
        coordinator.setAttributedString(from: editorBlocks, fallbackText: textBinding, textView: textView)

        // 3. Verify text storage has proper attributes before edit
        let storage = try #require(textView.textStorage)
        let renderedString = storage.string
        #expect(renderedString.contains("Chapter 1: The Beginning"))
        #expect(renderedString.contains("It was a dark and stormy night"))

        // 4. Perform an edit in the red run of block 1: replace "The Beginning" with "A New Era"
        let nsRendered = renderedString as NSString
        let targetRange = nsRendered.range(of: "The Beginning")
        #expect(targetRange.location != NSNotFound)

        var attrsAtTarget: [NSAttributedString.Key: Any] = [:]
        storage.enumerateAttributes(in: targetRange, options: []) { attrs, _, _ in
            attrsAtTarget = attrs
        }
        #expect(attrsAtTarget[DocumentTextAttribute.explicitColorHex] as? String == "FF0000")
        #expect(attrsAtTarget[DocumentTextAttribute.styleKey] as? String == "Heading1")
        #expect(attrsAtTarget[DocumentTextAttribute.translationPolicy] as? String == SpanTranslationPolicy.protect.rawValue)
        #expect(attrsAtTarget[DocumentTextAttribute.blockID] as? String == "b1")
        #expect(attrsAtTarget[DocumentTextAttribute.inlineTraits] as? [String] == ["bold", "superscript"])
        let replacementAttrString = NSAttributedString(string: "A New Era", attributes: attrsAtTarget)
        storage.replaceCharacters(in: targetRange, with: replacementAttrString)

        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        // 4b. Verify newly typed text insertion point inherits the active run's trait metadata
        let stormyRange = (storage.string as NSString).range(of: "stormy night")
        #expect(stormyRange.location != NSNotFound)
        let insertionPoint = stormyRange.location + stormyRange.length
        textView.setSelectedRange(NSRange(location: insertionPoint, length: 0))
        let typingAttrs = textView.typingAttributes
        #expect(typingAttrs[DocumentTextAttribute.inlineTraits] as? [String] == ["italic", "smallCaps"])
        #expect(typingAttrs[DocumentTextAttribute.explicitColorHex] as? String == "FF0000")
        #expect(typingAttrs[DocumentTextAttribute.styleKey] as? String == "BodyText")
        #expect(typingAttrs[DocumentTextAttribute.translationPolicy] as? String == SpanTranslationPolicy.translateWithGlossary.rawValue)

        // 5. Verify the save callback was called and store was updated
        #expect(savedBlocks.count == 2)
        #expect(savedBlocks[0].id == "b1")
        #expect(savedBlocks[1].id == "b2")
        #expect(savedAggregateText == "Chapter 1: A New Era\n\nIt was a dark and stormy night")

        // 6. Reload from store to verify round-trip
        let reloadedBlocks = store.currentDocumentSourceBlocks
        #expect(reloadedBlocks.count == 2)

        // Assertions on Block 1
        let reloadedB1 = reloadedBlocks[0]
        #expect(reloadedB1.id == "b1")
        #expect(reloadedB1.spans.count == 2)
        #expect(reloadedB1.spans[0].id == "s1")
        #expect(reloadedB1.spans[0].text == "Chapter 1: ")
        #expect(reloadedB1.spans[0].foregroundColorHex == nil)
        #expect(reloadedB1.spans[0].styleKey == "Heading1")
        #expect(reloadedB1.spans[0].translationPolicy == .translate)
        #expect(reloadedB1.spans[0].traits == [.bold, .smallCaps])

        #expect(reloadedB1.spans[1].id == "s2")
        #expect(reloadedB1.spans[1].text == "A New Era")
        #expect(reloadedB1.spans[1].foregroundColorHex == "FF0000")
        #expect(reloadedB1.spans[1].styleKey == "Heading1")
        #expect(reloadedB1.spans[1].translationPolicy == .protect)
        #expect(reloadedB1.spans[1].traits == [.bold, .superscript])
        let b1Text = reloadedB1.spans.map(\.text).joined()
        #expect(b1Text == "Chapter 1: A New Era")
        #expect(!b1Text.contains("stormy night"))

        // Assertions on Block 2
        let reloadedB2 = reloadedBlocks[1]
        #expect(reloadedB2.id == "b2")
        #expect(reloadedB2.spans.count == 2)
        #expect(reloadedB2.spans[0].id == "s3")
        #expect(reloadedB2.spans[0].text == "It was a dark and ")
        #expect(reloadedB2.spans[0].foregroundColorHex == nil)
        #expect(reloadedB2.spans[0].styleKey == "BodyText")
        #expect(reloadedB2.spans[0].translationPolicy == .translate)
        #expect(reloadedB2.spans[0].traits == [.subscriptText])

        #expect(reloadedB2.spans[1].id == "s4")
        #expect(reloadedB2.spans[1].text == "stormy night")
        #expect(reloadedB2.spans[1].foregroundColorHex == "FF0000")
        #expect(reloadedB2.spans[1].styleKey == "BodyText")
        #expect(reloadedB2.spans[1].translationPolicy == .translateWithGlossary)
        #expect(reloadedB2.spans[1].traits == [.italic, .smallCaps])

        let b2Text = reloadedB2.spans.map(\.text).joined()
        #expect(b2Text == "It was a dark and stormy night")
        #expect(!b2Text.contains("Chapter 1"))

        // Assertions on chunk aggregate
        #expect(store.currentChunk?.original == "Chapter 1: A New Era\n\nIt was a dark and stormy night")

        // 7. Verify translated block independence and color round-trip
        let transBlocks = [
            DocumentEditorBlockItem(
                id: "b1",
                spans: [
                    RichTextSpan(id: "ts1", text: "Глава 1: ", styleKey: "Heading1", traits: [.bold, .smallCaps], translationPolicy: .translate, foregroundColorHex: nil),
                    RichTextSpan(id: "ts2", text: "Новая Эра", styleKey: "Heading1", traits: [.bold, .superscript], translationPolicy: .protect, foregroundColorHex: "FF0000")
                ],
                fallbackText: "Глава 1: Новая Эра"
            ),
            DocumentEditorBlockItem(
                id: "b2",
                spans: [
                    RichTextSpan(id: "ts3", text: "Была темная и ", styleKey: "BodyText", traits: [.subscriptText], translationPolicy: .translate, foregroundColorHex: nil),
                    RichTextSpan(id: "ts4", text: "ненастная ночь", styleKey: "BodyText", traits: [.italic, .smallCaps], translationPolicy: .translateWithGlossary, foregroundColorHex: "FF0000")
                ],
                fallbackText: "Была темная и ненастная ночь"
            )
        ]

        store.updateCurrentDocumentTranslated(
            blocks: transBlocks.map { ($0.id, $0.spans, $0.fallbackText) },
            text: "Глава 1: Новая Эра\n\nБыла темная и ненастная ночь"
        )

        let reloadedTrans = store.currentDocumentTranslatedBlocks
        #expect(reloadedTrans.count == 2)
        #expect(reloadedTrans[0].sourceBlockID == "b1")
        #expect(reloadedTrans[0].spans[0].foregroundColorHex == nil)
        #expect(reloadedTrans[0].spans[0].traits == [.bold, .smallCaps])
        #expect(reloadedTrans[0].spans[1].foregroundColorHex == "FF0000")
        #expect(reloadedTrans[0].spans[1].traits == [.bold, .superscript])
        #expect(reloadedTrans[0].text == "Глава 1: Новая Эра")

        #expect(reloadedTrans[1].sourceBlockID == "b2")
        #expect(reloadedTrans[1].spans[0].foregroundColorHex == nil)
        #expect(reloadedTrans[1].spans[0].traits == [.subscriptText])
        #expect(reloadedTrans[1].spans[1].foregroundColorHex == "FF0000")
        #expect(reloadedTrans[1].spans[1].traits == [.italic, .smallCaps])
        #expect(reloadedTrans[1].text == "Была темная и ненастная ночь")
        #expect(store.currentChunk?.translated == "Глава 1: Новая Эра\n\nБыла темная и ненастная ночь")
        #expect(store.workflow.session?.documentState?.translationsByLanguage["russian"]?["b1"]?.spans[1].foregroundColorHex == "FF0000")
        #expect(store.workflow.session?.documentState?.translationsByLanguage["russian"]?["b2"]?.spans[0].foregroundColorHex == nil)
    }
}
