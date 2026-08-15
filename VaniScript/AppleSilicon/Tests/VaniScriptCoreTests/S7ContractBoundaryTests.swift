import Foundation
import Testing
@testable import VaniScriptCore

@Suite("S7 contract and Codable boundaries")
struct S7ContractBoundaryTests {
    @Test("source anchors round-trip media and document ranges including offsets")
    func sourceAnchorRoundTrip() throws {
        let anchors: [SourceAnchor] = [
            .media(startSec: 12.25, endSec: 99.75),
            .document(DocumentRange(startBlockID: "a", endBlockID: "b", startOffset: 3, endOffset: 17))
        ]
        for anchor in anchors {
            let data = try JSONEncoder().encode(anchor)
            #expect(try JSONDecoder().decode(SourceAnchor.self, from: data) == anchor)
        }
    }

    @Test("source anchor decoder accepts legacy flat media payload and rejects unknown kind")
    func sourceAnchorLegacyAndUnknown() throws {
        let legacy = Data(#"{"startSec":1.5,"endSec":2.5}"#.utf8)
        #expect(try JSONDecoder().decode(SourceAnchor.self, from: legacy) == .media(startSec: 1.5, endSec: 2.5))

        let unknown = Data(#"{"kind":"telepathy","startSec":1,"endSec":2}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SourceAnchor.self, from: unknown)
        }
    }

    @Test("source anchor decoder rejects payload with no usable media or document range")
    func sourceAnchorMissingPayload() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SourceAnchor.self, from: Data("{}".utf8))
        }
    }

    @Test("document block slice clamps negative starts and backwards ends")
    func blockSliceClamping() {
        let negative = DocumentBlockSlice(blockID: "b", startOffset: -10, endOffset: 4)
        #expect(negative.startOffset == 0)
        #expect(negative.endOffset == 4)

        let backwards = DocumentBlockSlice(blockID: "b", startOffset: 8, endOffset: 3)
        #expect(backwards.startOffset == 8)
        #expect(backwards.endOffset == 8)
    }

    @Test("document request treats whitespace-only and protected blocks as deterministic")
    func deterministicClassificationBoundaries() {
        let request = DocumentTranslationRequest(
            chunkId: "c",
            targetLanguage: "Russian",
            blocks: [
                DocumentTranslationInputBlock(id: "blank", sourceText: " \n\t "),
                DocumentTranslationInputBlock(id: "protected", sourceText: "Keep", translationPolicy: .protect),
                DocumentTranslationInputBlock(id: "normal", sourceText: "Translate")
            ]
        )
        #expect(request.deterministicBlockIDs == ["blank", "protected"])
        #expect(request.translatableBlockIDs == ["normal"])
        #expect(request.expectedBlockIDs == ["blank", "protected", "normal"])
    }

    @Test("known style IDs are inferred, unique, and sorted when omitted")
    func styleInference() {
        let request = DocumentTranslationRequest(
            chunkId: "c",
            targetLanguage: "Russian",
            blocks: [
                DocumentTranslationInputBlock(id: "a", spans: [
                    DocumentTranslationInputSpan(style: "zeta", text: "A"),
                    DocumentTranslationInputSpan(style: "alpha", text: "B")
                ]),
                DocumentTranslationInputBlock(id: "b", spans: [
                    DocumentTranslationInputSpan(style: "alpha", text: "C")
                ])
            ]
        )
        #expect(request.knownStyleIDs == ["alpha", "zeta"])
        #expect(request.expectedStyleIDs == Set(["alpha", "zeta"]))
    }

    @Test("input block synthesizes one plain span only when source text is nonempty")
    func inputBlockSpanSynthesis() {
        let nonempty = DocumentTranslationInputBlock(id: "a", sourceText: "Hello", spans: [])
        #expect(nonempty.spans.count == 1)
        #expect(nonempty.spans[0].text == "Hello")
        #expect(nonempty.sourceText == "Hello")

        let empty = DocumentTranslationInputBlock(id: "b", sourceText: "", spans: [])
        #expect(empty.spans.isEmpty)
        #expect(empty.sourceText.isEmpty)
    }

    @Test("strict output span decoder rejects unknown fields")
    func outputSpanRejectsUnknownField() {
        let data = Data(#"{"schema":"vaniscript.document.translation.v1","chunkId":"c","blocks":[{"id":"b","spans":[{"style":"plain","text":"x","confidence":0.9}]}]}"#.utf8)
        #expect(throws: DocumentTranslationContractError.self) {
            try DocumentTranslationResponse.decodeStrict(data)
        }
    }

    @Test("strict output block decoder accepts legacy text field but encoder emits spans")
    func legacyTextDecodeCanonicalSpanEncode() throws {
        let legacy = Data(#"{"schema":"vaniscript.document.translation.v1","chunkId":"c","blocks":[{"id":"b","text":"Перевод"}]}"#.utf8)
        let decoded = try DocumentTranslationResponse.decodeStrict(legacy)
        #expect(decoded.blocks[0].text == "Перевод")
        #expect(decoded.blocks[0].spans.count == 1)

        let encoded = try JSONEncoder().encode(decoded)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let blocks = try #require(object["blocks"] as? [[String: Any]])
        #expect(blocks[0]["spans"] != nil)
        #expect(blocks[0]["text"] == nil)
    }

    @Test("strict response decoder rejects missing schema, chunkId, and blocks")
    func requiredResponseFields() {
        for raw in [
            #"{"chunkId":"c","blocks":[]}"#,
            #"{"schema":"vaniscript.document.translation.v1","blocks":[]}"#,
            #"{"schema":"vaniscript.document.translation.v1","chunkId":"c"}"#
        ] {
            #expect(throws: DocumentTranslationContractError.self) {
                try DocumentTranslationResponse.decodeStrict(Data(raw.utf8))
            }
        }
    }

    @Test("document state round-trips multiple languages, plans, outputs, and rich text traits")
    func documentStateRoundTrip() throws {
        let block = DocumentBlock(
            id: "b",
            location: DocumentLocation(part: .header, paragraphOrdinal: 3, tablePath: [1, 2], xmlPath: "word/header2.xml"),
            kind: .heading,
            styleID: "Heading1",
            paragraphPropertiesFingerprint: "ppr",
            spans: [RichTextSpan(id: "s", text: "Title", styleKey: "run", traits: [.bold, .italic], translationPolicy: .translateWithGlossary)],
            sourceHash: "hash",
            translationPolicy: .translateWithGlossary
        )
        let plan = DocumentChunkPlan(
            id: "p",
            blockIDs: ["b"],
            sourceTokenEstimate: 12,
            contextBeforeBlockIDs: ["before"],
            contextAfterBlockIDs: ["after"],
            sourceHash: "plan-hash",
            blockSlices: [DocumentBlockSlice(blockID: "b", startOffset: 1, endOffset: 4)]
        )
        let state = DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(key: "source", originalFileName: "book.docx", role: .originalSource, format: "docx", sha256: "abc", size: 123),
            metadata: DocumentMetadata(title: "Book", author: "Author", customProperties: ["x": "y"]),
            blocks: [block],
            chunks: [plan],
            translationsByLanguage: [
                "russian": ["b": TranslatedBlock(id: "tr", blockID: "b", text: "Заголовок", reviewDisposition: .manuallyApproved)],
                "german": ["b": TranslatedBlock(id: "de", blockID: "b", text: "Titel")]
            ],
            outputs: [DocumentOutputAsset(id: "out", key: "asset", format: .pdf, language: "Russian", originalFileName: "book.pdf")]
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(DocumentState.self, from: data)
        #expect(decoded == state)
    }

    @Test("document range offsets survive Codable boundaries at Int extremes used by planner contracts")
    func documentRangeOffsetRoundTrip() throws {
        let range = DocumentRange(startBlockID: "a", endBlockID: "a", startOffset: 0, endOffset: Int.max)
        let data = try JSONEncoder().encode(range)
        #expect(try JSONDecoder().decode(DocumentRange.self, from: data) == range)
    }
}
