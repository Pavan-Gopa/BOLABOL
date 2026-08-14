import Foundation
import Testing
import VaniScriptCore

@Suite("Document translation contracts")
struct DocumentTranslationContractTests {
    @Test("strict response round trips exact block and span structure")
    func roundTrip() throws {
        let response = DocumentTranslationResponse(
            chunkId: "chunk-1",
            blocks: [DocumentTranslationOutputBlock(
                id: "b1",
                spans: [DocumentTranslationOutputSpan(style: "plain", text: "Перевод")]
            )]
        )
        let data = try JSONEncoder().encode(response)
        let decoded = try DocumentTranslationResponse.decodeStrict(data)
        #expect(decoded == response)
    }

    @Test("strict decoder rejects unknown fields and markdown fences")
    func rejectsNonContractShapes() {
        let unknown = Data(#"{"schema":"vaniscript.document.translation.v1","chunkId":"c","blocks":[],"note":"no"}"#.utf8)
        #expect(throws: DocumentTranslationContractError.self) {
            try DocumentTranslationResponse.decodeStrict(unknown)
        }
        let fenced = Data("```json\n{}\n```".utf8)
        #expect(throws: DocumentTranslationContractError.self) {
            try DocumentTranslationResponse.decodeStrict(fenced)
        }
    }

    @Test("canonical response template names exact chunk IDs and styles")
    func canonicalTemplate() {
        let template = DocumentTranslationContract.canonicalResponseTemplate(
            chunkID: "chunk-exact",
            blockIDs: ["b1", "b2"],
            styleIDs: ["plain", "Quote"]
        )
        #expect(template.contains("\"schema\": \"\(DocumentTranslationContract.schema)\""))
        #expect(template.contains("\"chunkId\": \"chunk-exact\""))
        #expect(template.contains("\"id\": \"b1\""))
        #expect(template.contains("\"style\": \"plain\""))
    }
    @Test("request partitions deterministic and provider blocks without changing full IDs")
    func deterministicPartition() {
        let request = DocumentTranslationRequest(
            chunkId: "chunk-partition",
            targetLanguage: "Russian",
            blocks: [
                DocumentTranslationInputBlock(id: "empty", sourceText: ""),
                DocumentTranslationInputBlock(
                    id: "protected",
                    sourceText: "ॐ",
                    spans: [DocumentTranslationInputSpan(id: "s-protected", style: "italic", text: "ॐ")],
                    translationPolicy: .protect
                ),
                DocumentTranslationInputBlock(id: "translate", sourceText: "A paragraph.")
            ]
        )

        #expect(request.expectedBlockIDs == ["empty", "protected", "translate"])
        #expect(request.deterministicBlockIDs == ["empty", "protected"])
        #expect(request.translatableBlockIDs == ["translate"])
        #expect(request.blocks.map(\.id) == request.expectedBlockIDs)
    }
}
