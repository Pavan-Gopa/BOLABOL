import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Document translation export builder and policy")
struct DocumentTranslationExportTests {
    @Test("empty chunk policy approves when original and block texts trim empty")
    func emptyChunkPolicyApprovesEmptySources() {
        #expect(DocumentApprovalAdvancePolicy.isSourceEmptyChunk(original: "", blockTexts: []))
        #expect(DocumentApprovalAdvancePolicy.isSourceEmptyChunk(original: nil, blockTexts: []))
        #expect(DocumentApprovalAdvancePolicy.isSourceEmptyChunk(original: "   \n\t", blockTexts: ["", "  \n"]))
        #expect(DocumentApprovalAdvancePolicy.isSourceEmptyChunk(original: "", blockTexts: ["   "]))
    }

    @Test("empty chunk policy guards when original or block texts have content")
    func emptyChunkPolicyGuardsNonEmptySources() {
        #expect(!DocumentApprovalAdvancePolicy.isSourceEmptyChunk(original: "Chapter 1", blockTexts: []))
        #expect(!DocumentApprovalAdvancePolicy.isSourceEmptyChunk(original: "", blockTexts: ["Non-empty block"]))
        #expect(!DocumentApprovalAdvancePolicy.isSourceEmptyChunk(original: "Original text", blockTexts: ["Block text"]))
        #expect(!DocumentApprovalAdvancePolicy.isSourceEmptyChunk(original: nil, blockTexts: ["Heading text", ""]))
    }

    @Test("builder preserves block order and emits empty blocks as empty lines")
    func builderPreservesOrderAndEmptyLines() {
        let blocks = [
            DocumentBlock(
                id: "b1",
                location: DocumentLocation(paragraphOrdinal: 0),
                kind: .heading,
                styleID: "Heading1",
                spans: [RichTextSpan(id: "s1", text: "Chapter One")]
            ),
            DocumentBlock(
                id: "b2",
                location: DocumentLocation(paragraphOrdinal: 1),
                kind: .empty,
                spans: []
            ),
            DocumentBlock(
                id: "b3",
                location: DocumentLocation(paragraphOrdinal: 2),
                kind: .paragraph,
                spans: [RichTextSpan(id: "s2", text: "First body paragraph.")]
            ),
            DocumentBlock(
                id: "b4",
                location: DocumentLocation(paragraphOrdinal: 3),
                kind: .paragraph,
                spans: [RichTextSpan(id: "s3", text: "Second body paragraph.")]
            )
        ]

        let translations: [String: TranslatedBlock] = [
            "b1": TranslatedBlock(id: "tb1", blockID: "b1", text: "Глава Первая"),
            "b3": TranslatedBlock(id: "tb3", blockID: "b3", text: "Первый абзац текста.")
            // b4 is untranslated to test fallback to source text
        ]

        let documentState = DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(key: "src", originalFileName: "test.docx"),
            metadata: DocumentMetadata(title: "Book"),
            blocks: blocks,
            translationsByLanguage: ["russian": translations]
        )

        let exported = DocumentTranslationExportBuilder.translatedDocumentText(
            documentState: documentState,
            language: "Russian",
            includeUntranslatedAsOriginal: true
        )

        let expected = "Глава Первая\n\n\n\nПервый абзац текста.\n\nSecond body paragraph."
        #expect(exported == expected)
    }

    @Test("builder resolves language canonical keys and falls back when no language supplied")
    func builderResolvesLanguagesDeterministically() {
        let blocks = [
            DocumentBlock(
                id: "b1",
                location: DocumentLocation(paragraphOrdinal: 0),
                kind: .paragraph,
                spans: [RichTextSpan(id: "s1", text: "Hello")]
            )
        ]

        let documentState = DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(key: "src", originalFileName: "test.docx"),
            blocks: blocks,
            translationsByLanguage: [
                "russian": ["b1": TranslatedBlock(id: "tb1", blockID: "b1", text: "Привет")],
                "german": ["b1": TranslatedBlock(id: "tb2", blockID: "b1", text: "Hallo")]
            ]
        )

        let ru = DocumentTranslationExportBuilder.translatedDocumentText(documentState: documentState, language: "ru")
        #expect(ru == "Привет")

        let de = DocumentTranslationExportBuilder.translatedDocumentText(documentState: documentState, language: "German")
        #expect(de == "Hallo")

        let defaultLang = DocumentTranslationExportBuilder.translatedDocumentText(documentState: documentState, language: nil)
        // German sorted before Russian
        #expect(defaultLang == "Hallo")
    }
}
