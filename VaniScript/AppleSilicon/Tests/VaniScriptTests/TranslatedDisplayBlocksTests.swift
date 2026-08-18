import CryptoKit
import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

// S13: untranslated document blocks must display the matching source block's
// spans in the Review translation pane so explicit foreground colors survive
// (mirrors the export fallback: source spans for untranslated blocks). The
// store-level write-back test guards that editing one block never materializes
// or mutates its untranslated sibling's persisted translation entry.
@MainActor
@Suite("Translated display blocks (S13 color fallback)")
struct TranslatedDisplayBlocksTests {
    private let sourceText = "Source paragraph"
    private let translatedText = "Переведенный абзац"

    private func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Pure helper behavior

    @Test("untranslated block displays source spans with explicit foreground color")
    func untranslatedBlockShowsSourceSpans() {
        let sourceBlock = DocumentBlock(
            id: "b1",
            location: DocumentLocation(paragraphOrdinal: 0),
            kind: .paragraph,
            spans: [RichTextSpan(id: "s1", text: sourceText, foregroundColorHex: "FF0000")]
        )
        let translated = TranslatedBlock(id: "b1", sourceBlockID: "b1", text: sourceText, spans: [])

        let items = DocumentEditorBlockItem.translatedDisplayBlocks(
            translated: [translated],
            sourceBlocks: [sourceBlock]
        )

        #expect(items.count == 1)
        let item = items[0]
        #expect(item.id == "b1")
        #expect(item.spans == sourceBlock.spans)
        #expect(item.spans.first?.foregroundColorHex == "FF0000")
        #expect(item.fallbackText == sourceText)
    }

    @Test("translated block keeps its own spans, not the source spans")
    func translatedBlockKeepsOwnSpans() {
        let sourceBlock = DocumentBlock(
            id: "b1",
            location: DocumentLocation(paragraphOrdinal: 0),
            kind: .paragraph,
            spans: [RichTextSpan(id: "s1", text: sourceText, foregroundColorHex: "FF0000")]
        )
        let ownSpans = [RichTextSpan(id: "ts1", text: translatedText)]
        let translated = TranslatedBlock(id: "tb1", sourceBlockID: "b1", text: translatedText, spans: ownSpans)

        let items = DocumentEditorBlockItem.translatedDisplayBlocks(
            translated: [translated],
            sourceBlocks: [sourceBlock]
        )

        #expect(items.count == 1)
        #expect(items[0].id == "b1")
        #expect(items[0].spans == ownSpans)
        #expect(items[0].spans.first?.foregroundColorHex == nil)
        #expect(items[0].fallbackText == translatedText)
    }

    @Test("translated collapsed span inherits source color on preserved token text")
    func collapsedTranslatedSpanInheritsTokenColor() {
        let sourceBlock = DocumentBlock(
            id: "b1",
            location: DocumentLocation(paragraphOrdinal: 0),
            kind: .paragraph,
            spans: [
                RichTextSpan(id: "s1", text: "Published in ", foregroundColorHex: nil),
                RichTextSpan(id: "s2", text: "[YEAR]", foregroundColorHex: "FF0000"),
                RichTextSpan(id: "s3", text: " by press", foregroundColorHex: nil)
            ]
        )
        // Translation pane already has a single colorless collapsed span that
        // still contains the preserved placeholder token.
        let ownSpans = [
            RichTextSpan(id: "ts1", text: "Опубліковано у [YEAR] видавництвом")
        ]
        let translated = TranslatedBlock(
            id: "tb1",
            sourceBlockID: "b1",
            text: "Опубліковано у [YEAR] видавництвом",
            spans: ownSpans
        )

        let items = DocumentEditorBlockItem.translatedDisplayBlocks(
            translated: [translated],
            sourceBlocks: [sourceBlock]
        )

        #expect(items.count == 1)
        let red = items[0].spans.filter { $0.foregroundColorHex == "FF0000" }
        #expect(red.count == 1)
        #expect(red.first?.text == "[YEAR]")
        #expect(items[0].spans.contains(where: { $0.text.contains("Опубліковано") && $0.foregroundColorHex == nil }))
        #expect(items[0].fallbackText == "Опубліковано у [YEAR] видавництвом")
    }

    @Test("mixed chunk maps each block to the right spans and preserves order")
    func mixedChunkPreservesOrderAndSpans() {
        let sourceBlocks = [
            DocumentBlock(
                id: "b1",
                location: DocumentLocation(paragraphOrdinal: 0),
                kind: .paragraph,
                spans: [RichTextSpan(id: "s1", text: sourceText)]
            ),
            DocumentBlock(
                id: "b2",
                location: DocumentLocation(paragraphOrdinal: 1),
                kind: .paragraph,
                spans: [RichTextSpan(id: "s2", text: "Red source line", foregroundColorHex: "FF0000")]
            )
        ]
        let ownSpans = [RichTextSpan(id: "ts1", text: translatedText)]
        let translated = [
            TranslatedBlock(id: "tb1", sourceBlockID: "b1", text: translatedText, spans: ownSpans),
            TranslatedBlock(id: "b2", sourceBlockID: "b2", text: "Red source line", spans: [])
        ]

        let items = DocumentEditorBlockItem.translatedDisplayBlocks(
            translated: translated,
            sourceBlocks: sourceBlocks
        )

        #expect(items.map(\.id) == ["b1", "b2"])
        #expect(items[0].spans == ownSpans)
        #expect(items[1].spans == sourceBlocks[1].spans)
        #expect(items[1].spans.first?.foregroundColorHex == "FF0000")
    }

    // MARK: - Store-level write-back hazard

    private func makeSession() -> SessionState {
        let block1 = DocumentBlock(
            id: "b1",
            location: DocumentLocation(paragraphOrdinal: 0),
            kind: .paragraph,
            spans: [RichTextSpan(id: "s1", text: sourceText)],
            sourceHash: hash(sourceText)
        )
        let redText = "Красный абзац"
        let block2 = DocumentBlock(
            id: "b2",
            location: DocumentLocation(paragraphOrdinal: 1),
            kind: .paragraph,
            spans: [RichTextSpan(id: "s2", text: redText, foregroundColorHex: "FF0000")],
            sourceHash: hash(redText)
        )
        let chunk = ChunkData(
            index: 0,
            filePath: "/tmp/doc.docx",
            durationSec: 0,
            startSec: 0,
            endSec: 0,
            original: [sourceText, redText].joined(separator: "\n\n"),
            translated: translatedText,
            status: .pending,
            approved: false,
            sourceAnchor: .document(DocumentRange(startBlockID: "b1", endBlockID: "b2"))
        )
        let documentState = DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(key: "src", originalFileName: "doc.docx"),
            blocks: [block1, block2],
            chunks: [DocumentChunkPlan(id: "p1", blockIDs: ["b1", "b2"])],
            translationsByLanguage: [
                "russian": [
                    "b1": TranslatedBlock(
                        id: "tb1",
                        blockID: "b1",
                        text: translatedText,
                        sourceHash: hash(sourceText),
                        reviewDisposition: .autoApproved
                    ),
                ],
            ]
        )
        var session = SessionState(
            sourceFile: "/tmp/doc.docx",
            sourceFileName: "doc.docx",
            durationSec: 0,
            metadata: .empty,
            sourceLang: "auto",
            targetLang: "Russian",
            transcriptionProvider: "coreml-whisperkit",
            translationProvider: "mlx-native",
            outputFormats: [.txt],
            chunks: [chunk],
            currentChunkIndex: 0,
            sourceKind: .document,
            documentState: documentState,
            approvalMode: .manual
        )
        session.activeTranslationLanguage = "Russian"
        return session
    }

    private func makeStore(session: SessionState) -> WorkflowStore {
        let record = ProjectRecord(
            id: "proj-1",
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
            session: session
        )
        return WorkflowStore(
            settings: AppSettings.defaults,
            projects: [record],
            settingsPersistence: { _ in },
            projectsPersistence: { _ in },
            autosaveInterval: .seconds(600),
            startInitialModelScan: false
        )
    }

    @Test("editing one block leaves the untranslated sibling's persisted entry untouched")
    func editingOneBlockDoesNotMaterializeSibling() {
        let store = makeStore(session: makeSession())
        store.openProject(id: "proj-1")

        // Precondition: b2 has no persisted translation entry.
        #expect(store.workflow.session?.documentState?.translationsByLanguage["russian"]?["b2"] == nil)
        let chunkDispositionBefore = store.workflow.session?.chunks[0].reviewDisposition

        store.updateCurrentDocumentTranslated(
            blocks: [(blockID: "b1", spans: [RichTextSpan(id: "s1e", text: "Edited translation")], text: "Edited translation")]
        )

        let documentState = store.workflow.session?.documentState
        // b1's edit landed.
        let b1 = documentState?.translationsByLanguage["russian"]?["b1"]
        #expect(b1?.text == "Edited translation")
        #expect(b1?.spans == [RichTextSpan(id: "s1e", text: "Edited translation")])
        // PRD §23 pre-existing behavior: manual edit of an auto-approved block
        // re-approves it as a human decision.
        #expect(b1?.reviewDisposition == .manuallyApproved)
        // b2's entry was not created or mutated; chunk disposition unchanged.
        #expect(documentState?.translationsByLanguage["russian"]?["b2"] == nil)
        #expect(store.workflow.session?.chunks[0].reviewDisposition == chunkDispositionBefore)
        // Freshness is derived from persisted entries only: b2 has none, so it
        // cannot prove staleness and the approve gate is unaffected.
        #expect(store.isCurrentDocumentChunkStale == false)

        // The display derivation still shows b2's red source spans in the
        // translation pane without persisting anything.
        let items = DocumentEditorBlockItem.translatedDisplayBlocks(
            translated: store.currentDocumentTranslatedBlocks,
            sourceBlocks: store.currentDocumentSourceBlocks
        )
        #expect(items.map(\.id) == ["b1", "b2"])
        #expect(items[0].spans == [RichTextSpan(id: "s1e", text: "Edited translation")])
        #expect(items[1].spans.first?.foregroundColorHex == "FF0000")
        // Still nothing persisted for b2 after the display derivation.
        #expect(store.workflow.session?.documentState?.translationsByLanguage["russian"]?["b2"] == nil)
    }
}
