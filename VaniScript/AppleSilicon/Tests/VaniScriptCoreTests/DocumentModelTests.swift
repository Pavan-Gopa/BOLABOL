import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Document source contracts")
struct DocumentModelTests {
    @Test("round trips document state and typed source anchors")
    func roundTripsDocumentState() throws {
        let block = DocumentBlock(
            id: "block-1",
            location: DocumentLocation(part: .mainBody, paragraphOrdinal: 3, xmlPath: "/w:document/w:body/w:p[3]"),
            kind: .heading,
            styleID: "ChapterTitle",
            paragraphPropertiesFingerprint: "ppr-hash",
            spans: [
                RichTextSpan(
                    id: "span-1",
                    text: "Chapter One",
                    styleKey: "Gentium",
                    traits: [.italic],
                    translationPolicy: .translate
                )
            ],
            sourceHash: "source-hash",
            translationPolicy: .translate
        )
        let state = DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(
                key: "sourceFile",
                originalFileName: "synthetic-document.docx",
                role: .originalSource,
                format: "docx",
                sha256: "abc",
                size: 123
            ),
            metadata: DocumentMetadata(title: "Synthetic", author: "VaniScript"),
            blocks: [block],
            chunks: [DocumentChunkPlan(id: "chunk-1", blockIDs: [block.id], sourceTokenEstimate: 12)],
            translationsByLanguage: [
                "Russian": [
                    block.id: TranslatedBlock(
                        id: "translation-1",
                        sourceBlockID: block.id,
                        text: "Глава первая",
                        reviewDisposition: .manuallyApproved
                    )
                ]
            ],
            outputs: [
                DocumentOutputAsset(
                    id: "output-1",
                    key: "localizedDocument",
                    format: .docx,
                    language: "Russian",
                    originalFileName: "synthetic-document-ru.docx"
                )
            ],
            profile: .faithfulLiteraryDefault
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(DocumentState.self, from: data)
        #expect(decoded == state)

        let media = SourceAnchor.media(startSec: 1.25, endSec: 4.5)
        let document = SourceAnchor.document(DocumentRange(startBlockID: "block-1", endBlockID: "block-2"))
        #expect(try JSONDecoder().decode(SourceAnchor.self, from: JSONEncoder().encode(media)) == media)
        #expect(try JSONDecoder().decode(SourceAnchor.self, from: JSONEncoder().encode(document)) == document)
    }

    @Test("preserves the default literary profile")
    func preservesDefaultLiteraryProfile() {
        let profile = DocumentTranslationProfile.default
        #expect(profile.mode == .faithfulLiterary)
        #expect(profile.sanskritPolicy == .preserveTransliterationTranslateGloss)
        #expect(profile.voice == .preserveVoice)
    }

    @Test("reconstructs media anchors and approval disposition for legacy chunks")
    func migratesLegacyChunkFields() throws {
        let data = Data(
            #"{"index":2,"startSec":12.5,"endSec":18.0,"original":"Original text","translated":"Translated text","status":"done","approved":true}"#.utf8
        )
        var chunk = try JSONDecoder().decode(ChunkData.self, from: data)

        #expect(chunk.original == "Original text")
        #expect(chunk.translated == "Translated text")
        #expect(chunk.sourceAnchor == .media(startSec: 12.5, endSec: 18.0))
        #expect(chunk.reviewDisposition == .manuallyApproved)
        #expect(chunk.approved)

        chunk.approved = false
        #expect(chunk.reviewDisposition == .pending)
        chunk.reviewDisposition = .needsReview
        #expect(!chunk.approved)
        chunk.reviewDisposition = .autoApproved
        #expect(chunk.approved)
    }

    @Test("document sessions do not require a transcription provider")
    func startsDocumentWithoutTranscriptionProvider() {
        var workflow = WorkflowState.initial(settings: .defaults)
        workflow.transcriptionProvider = ""
        let state = DocumentState(
            format: .txt,
            originalAsset: ProjectAssetReference(
                key: "sourceFile",
                originalFileName: "notes.txt",
                format: "txt",
                sha256: "hash",
                size: 5
            )
        )

        workflow.selectDocument(path: "/tmp/notes.txt", documentState: state)
        #expect(workflow.canStartSession)
        workflow.startSession()
        #expect(workflow.session?.sourceKind == .document)
        #expect(workflow.session?.documentState == state)
        #expect(workflow.session?.chunks.isEmpty == true)
    }
    @Test("legacy bundle without foregroundColorHex decodes nil and persists normalized color")
    func decodesLegacyAndNormalizedColors() throws {
        let legacyJSON = """
        {
            "id": "span-legacy",
            "text": "Old text without color",
            "styleKey": "k1",
            "traits": ["bold"],
            "translationPolicy": "translate"
        }
        """.data(using: .utf8)!

        let decodedLegacy = try JSONDecoder().decode(RichTextSpan.self, from: legacyJSON)
        #expect(decodedLegacy.foregroundColorHex == nil)
        #expect(decodedLegacy.text == "Old text without color")
        #expect(decodedLegacy.traits.contains(.bold))

        let coloredSpan = RichTextSpan(
            id: "span-color",
            text: "Red placeholder",
            styleKey: "k2",
            foregroundColorHex: "#ff0000"
        )
        #expect(coloredSpan.foregroundColorHex == "FF0000")

        let encoded = try JSONEncoder().encode(coloredSpan)
        let decodedColored = try JSONDecoder().decode(RichTextSpan.self, from: encoded)
        #expect(decodedColored.foregroundColorHex == "FF0000")

        #expect(RichTextSpan.normalizeHexColor("#f00") == "FF0000")
        #expect(RichTextSpan.normalizeHexColor("00FF00") == "00FF00")
        #expect(RichTextSpan.normalizeHexColor("auto") == nil)
        #expect(RichTextSpan.normalizeHexColor("invalid") == nil)
        #expect(RichTextSpan.normalizeHexColor(nil) == nil)
    }
}
