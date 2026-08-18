import Foundation
import Testing
@testable import VaniScriptCore

@Suite("DocumentSelectionTranslationTests (PRD §26.5)")
struct DocumentSelectionTranslationTests {
    @Test("strict response rejects schema, operation, and unknown fields")
    func strictResponseValidation() throws {
        let request = DocumentSelectionTranslationRequest(
            operationID: "op-1",
            targetLanguage: "Russian",
            sourceBlockID: "block-1",
            sourceBlockHash: String(repeating: "a", count: 64),
            sourceContext: "Keep Krishna",
            selectedTargetText: "Keep Krishna"
        )
        let validator = DocumentSelectionTranslationValidator()

        let wrongSchema = validator.validate(
            response: DocumentSelectionTranslationResponse(
                schema: "other.schema",
                operationID: "op-1",
                replacementText: "Keep Krishna"
            ),
            request: request
        )
        #expect(wrongSchema.errors.contains(where: { $0.code == "schema" }))

        let wrongOperation = validator.validate(
            response: DocumentSelectionTranslationResponse(
                operationID: "op-2",
                replacementText: "Keep Krishna"
            ),
            request: request
        )
        #expect(wrongOperation.errors.contains(where: { $0.code == "operationID" }))

        let unknownField = #"{"schema":"vaniscript.document.selection.v1","operationId":"op-1","replacementText":"ok","blockId":"never-trusted"}"#
        #expect(throws: DocumentSelectionTranslationContractError.self) {
            try DocumentSelectionTranslationResponse.decodeStrict(Data(unknownField.utf8))
        }
    }

    @Test("protected terms are required and source residue is a warning")
    func protectedTermsAndResidue() {
        let request = DocumentSelectionTranslationRequest(
            operationID: "op-1",
            targetLanguage: "Russian",
            sourceBlockID: "block-1",
            sourceBlockHash: "hash",
            sourceContext: "This is an English sentence with Krishna.",
            selectedTargetText: "This is an English sentence with Krishna.",
            protectedTokens: ["Krishna"]
        )
        let validator = DocumentSelectionTranslationValidator()

        let removed = validator.validate(
            response: DocumentSelectionTranslationResponse(operationID: "op-1", replacementText: "Это предложение."),
            request: request
        )
        #expect(removed.errors.contains(where: { $0.code == "protectedTermMissing" }))

        let unchanged = validator.validate(
            response: DocumentSelectionTranslationResponse(operationID: "op-1", replacementText: request.selectedTargetText),
            request: request
        )
        #expect(unchanged.isValid)
        #expect(unchanged.warnings.contains(where: { $0.code == "unchangedSelection" }))
        #expect(unchanged.warnings.contains(where: { $0.code == "languageResidue" }))
    }

    @Test("selection replacement inserts once across equivalent spans and inherits trusted style")
    func replacementInheritsTrustedFormatting() throws {
        let spans = [
            RichTextSpan(id: "span-1", text: "Hello ", styleKey: "body", traits: [.bold], foregroundColorHex: "336699"),
            RichTextSpan(id: "span-2", text: "world", styleKey: "body", traits: [.bold], foregroundColorHex: "336699")
        ]
        let mutated = try DocumentRichTextMutation.replace(
            spans: spans,
            selection: [
                DocumentSpanRange(spanID: "span-1", location: 3, length: 3),
                DocumentSpanRange(spanID: "span-2", location: 0, length: 5)
            ],
            with: "there",
            policy: .inheritExisting
        )

        #expect(mutated.map(\.text).joined() == "Helthere")
        #expect(mutated.count == 1)
        #expect(mutated[0].traits == [.bold])
        #expect(mutated[0].styleKey == "body")
        #expect(mutated[0].foregroundColorHex == "336699")
    }
}
