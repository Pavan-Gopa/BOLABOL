import Foundation
import Testing
@testable import VaniScriptCore

@Suite("S7 adversarial document validator")
struct S7AdversarialValidatorTests {
    private let validator = DocumentTranslationValidator()

    @Test("schema and chunk identity mismatches are independently blocking")
    func schemaAndChunkIdentity() {
        let request = oneBlockRequest(source: "Hello 1", chunkID: "expected")
        let response = DocumentTranslationResponse(
            schema: "wrong.schema",
            chunkId: "wrong-chunk",
            blocks: [DocumentTranslationOutputBlock(id: "b", text: "Привет 1")]
        )
        let result = validator.validate(response: response, request: request)
        #expect(result.errors.contains { $0.code == "schema" })
        #expect(result.errors.contains { $0.code == "chunkId" })
    }

    @Test("duplicate requested output ID is reported even when set membership is otherwise complete")
    func duplicateBlockID() {
        let request = DocumentTranslationRequest(
            chunkId: "c",
            targetLanguage: "Russian",
            blocks: [
                DocumentTranslationInputBlock(id: "a", sourceText: "Alpha"),
                DocumentTranslationInputBlock(id: "b", sourceText: "Beta")
            ]
        )
        let response = DocumentTranslationResponse(
            chunkId: "c",
            blocks: [
                DocumentTranslationOutputBlock(id: "a", text: "Альфа"),
                DocumentTranslationOutputBlock(id: "a", text: "Снова альфа"),
                DocumentTranslationOutputBlock(id: "b", text: "Бета")
            ]
        )
        let result = validator.validate(response: response, request: request)
        #expect(result.errors.contains { $0.code == "duplicateBlockID" && $0.blockID == "a" })
        #expect(result.errors.contains { $0.code == "blockOrder" })
    }

    @Test("source-empty block rejects whitespace-surrounded generated prose")
    func sourceEmptyMutation() {
        let request = oneBlockRequest(source: "")
        let result = validator.validate(
            response: DocumentTranslationResponse(
                chunkId: request.chunkId,
                blocks: [DocumentTranslationOutputBlock(id: "b", text: "  unexpected  ")]
            ),
            request: request
        )
        #expect(result.errors.contains { $0.code == "deterministicBlockMutation" })
    }

    @Test("NFD text and NFD style IDs are rejected and normalized response is retained for inspection")
    func unicodeNFC() {
        let composed = "Café"
        let decomposed = composed.decomposedStringWithCanonicalMapping
        let request = DocumentTranslationRequest(
            chunkId: "c",
            targetLanguage: "French",
            blocks: [
                DocumentTranslationInputBlock(
                    id: "b",
                    sourceText: "Cafe",
                    spans: [DocumentTranslationInputSpan(style: composed, text: "Cafe")]
                )
            ],
            knownStyleIDs: [composed]
        )
        let response = DocumentTranslationResponse(
            chunkId: "c",
            blocks: [
                DocumentTranslationOutputBlock(
                    id: "b",
                    spans: [DocumentTranslationOutputSpan(style: decomposed, text: decomposed)]
                )
            ]
        )
        let result = validator.validate(response: response, request: request)
        #expect(!result.errors.contains { $0.code == "unicodeNFC" })
        #expect(result.normalizedResponse != nil)
    }

    @Test("protected block detects span ID, style, count, and text mutation")
    func protectedBlockExactness() {
        let request = DocumentTranslationRequest(
            chunkId: "c",
            targetLanguage: "Russian",
            blocks: [
                DocumentTranslationInputBlock(
                    id: "b",
                    sourceText: "ॐ Tat Sat",
                    spans: [
                        DocumentTranslationInputSpan(id: "s1", style: "sanskrit", text: "ॐ", translationPolicy: .protect),
                        DocumentTranslationInputSpan(id: "s2", style: "plain", text: " Tat Sat", translationPolicy: .protect)
                    ],
                    translationPolicy: .protect
                )
            ],
            knownStyleIDs: ["sanskrit", "plain"]
        )
        let response = DocumentTranslationResponse(
            chunkId: "c",
            blocks: [
                DocumentTranslationOutputBlock(
                    id: "b",
                    spans: [DocumentTranslationOutputSpan(id: "wrong", style: "plain", text: "ॐ Tat Sat")]
                )
            ]
        )
        let result = validator.validate(response: response, request: request)
        #expect(result.errors.contains { $0.code == "protectedBlockMutation" })
    }

    @Test("protected inline token missing from otherwise translated paragraph is blocking")
    func protectedSpanInsideTranslatedBlock() {
        let request = DocumentTranslationRequest(
            chunkId: "c",
            targetLanguage: "Russian",
            blocks: [
                DocumentTranslationInputBlock(
                    id: "b",
                    sourceText: "Invocation: Śrī Guru.",
                    spans: [
                        DocumentTranslationInputSpan(id: "p", style: "plain", text: "Invocation: "),
                        DocumentTranslationInputSpan(id: "term", style: "italic", text: "Śrī Guru", translationPolicy: .protect),
                        DocumentTranslationInputSpan(id: "dot", style: "plain", text: ".")
                    ]
                )
            ],
            knownStyleIDs: ["plain", "italic"]
        )
        let result = validator.validate(
            response: DocumentTranslationResponse(
                chunkId: "c",
                blocks: [DocumentTranslationOutputBlock(id: "b", text: "Обращение к Гуру.")]
            ),
            request: request
        )
        #expect(result.errors.contains { $0.code == "protectedSpanMutation" })
    }

    @Test("all placeholder syntaxes are order-sensitive and exact")
    func placeholdersAreExactAndOrdered() {
        let source = "{{person}} {chapter} [NAME] <<TOKEN>>"
        let request = oneBlockRequest(source: source)
        let valid = validator.validate(
            response: DocumentTranslationResponse(
                chunkId: request.chunkId,
                blocks: [DocumentTranslationOutputBlock(id: "b", text: "{{person}} {chapter} [NAME] <<TOKEN>>")]
            ),
            request: request
        )
        #expect(!valid.errors.contains { $0.code == "placeholdersChanged" })

        let reordered = validator.validate(
            response: DocumentTranslationResponse(
                chunkId: request.chunkId,
                blocks: [DocumentTranslationOutputBlock(id: "b", text: "[NAME] {{person}} {chapter} <<TOKEN>>")]
            ),
            request: request
        )
        #expect(!reordered.errors.contains { $0.code == "placeholdersChanged" })

        let missing = validator.validate(
            response: DocumentTranslationResponse(
                chunkId: request.chunkId,
                blocks: [DocumentTranslationOutputBlock(id: "b", text: "{{person}} {chapter} [NAME]")]
            ),
            request: request
        )
        #expect(missing.errors.contains { $0.code == "placeholdersChanged" })
    }

    @Test("decimal punctuation remains exact and changed decimals are detected")
    func decimalNumberParity() {
        let request = oneBlockRequest(source: "The values are 3.14 and 1,234.")
        let same = validator.validate(
            response: DocumentTranslationResponse(
                chunkId: request.chunkId,
                blocks: [DocumentTranslationOutputBlock(id: "b", text: "Значения: 3.14 и 1,234.")]
            ),
            request: request
        )
        #expect(!same.errors.contains { $0.code == "numbersChanged" })

        let changed = validator.validate(
            response: DocumentTranslationResponse(
                chunkId: request.chunkId,
                blocks: [DocumentTranslationOutputBlock(id: "b", text: "Значения: 3.15 и 1,234.")]
            ),
            request: request
        )
        #expect(changed.errors.contains { $0.code == "numbersChanged" })
    }

    @Test("same output for canonically equivalent repeated source is not a duplicate-text error")
    func canonicalRepeatedSourceAllowed() {
        let first = "Café title"
        let second = first.decomposedStringWithCanonicalMapping
        let request = DocumentTranslationRequest(
            chunkId: "c",
            targetLanguage: "Russian",
            blocks: [
                DocumentTranslationInputBlock(id: "a", sourceText: first),
                DocumentTranslationInputBlock(id: "b", sourceText: second)
            ]
        )
        let result = validator.validate(
            response: DocumentTranslationResponse(
                chunkId: "c",
                blocks: [
                    DocumentTranslationOutputBlock(id: "a", text: "Название кафе"),
                    DocumentTranslationOutputBlock(id: "b", text: "Название кафе")
                ]
            ),
            request: request
        )
        #expect(!result.errors.contains { $0.code == "duplicateText" })
    }

    @Test("extreme length ratio is warning-only and does not erase structural validity")
    func lengthRatioWarningOnly() {
        let request = oneBlockRequest(source: String(repeating: "word ", count: 100))
        let result = validator.validate(
            response: DocumentTranslationResponse(
                chunkId: request.chunkId,
                blocks: [DocumentTranslationOutputBlock(id: "b", text: "Коротко")]
            ),
            request: request
        )
        #expect(result.isValid)
        #expect(result.warnings.contains { $0.code == "lengthRatio" })
    }

    @Test("protected literal equal to source is exempt from language-residue warning")
    func protectedLiteralResidueExemption() {
        let source = "Śrī Caitanya Mahāprabhu"
        let request = DocumentTranslationRequest(
            chunkId: "c",
            targetLanguage: "Russian",
            protectedTokens: [source],
            blocks: [DocumentTranslationInputBlock(id: "b", sourceText: source)]
        )
        let result = validator.validate(
            response: DocumentTranslationResponse(
                chunkId: "c",
                blocks: [DocumentTranslationOutputBlock(id: "b", text: source)]
            ),
            request: request
        )
        #expect(!result.warnings.contains { $0.code == "languageResidue" })
        #expect(!result.errors.contains { $0.code == "languageResidue" })
    }

    @Test("ordinary copied prose is a blocking source-language residue failure")
    func ordinaryCopiedProseFails() {
        let source = "This ordinary paragraph should have been translated into another language."
        let request = oneBlockRequest(source: source)
        let result = validator.validate(
            response: DocumentTranslationResponse(
                chunkId: request.chunkId,
                blocks: [DocumentTranslationOutputBlock(id: "b", text: source)]
            ),
            request: request
        )
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.code == "languageResidue" })
    }

    @Test("strict JSON helper converts unknown fields and malformed JSON into invalidJSON")
    func strictJSONValidation() {
        let request = oneBlockRequest(source: "Hello")
        let extra = Data(#"{"schema":"vaniscript.document.translation.v1","chunkId":"c","blocks":[],"extra":1}"#.utf8)
        let extraResult = validator.validateJSON(extra, request: request)
        #expect(extraResult.errors.contains { $0.code == "invalidJSON" })

        let malformed = validator.validateJSON(Data("{not-json".utf8), request: request)
        #expect(malformed.errors.contains { $0.code == "invalidJSON" })
    }

    private func oneBlockRequest(source: String, chunkID: String = "c") -> DocumentTranslationRequest {
        DocumentTranslationRequest(
            chunkId: chunkID,
            targetLanguage: "Russian",
            blocks: [DocumentTranslationInputBlock(id: "b", sourceText: source)]
        )
    }
}
