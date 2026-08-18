import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Document translation validator")
struct DocumentTranslationValidatorTests {
    private func request() -> DocumentTranslationRequest {
        DocumentTranslationRequest(
            chunkId: "chunk-1",
            targetLanguage: "Russian",
            blocks: [
                DocumentTranslationInputBlock(
                    id: "b1",
                    sourceText: "Chapter 2: {{name}}",
                    spans: [DocumentTranslationInputSpan(style: "plain", text: "Chapter 2: {{name}}")]
                ),
                DocumentTranslationInputBlock(
                    id: "b2",
                    sourceText: "ॐ",
                    spans: [DocumentTranslationInputSpan(style: "italic-1", text: "ॐ", translationPolicy: .protect)],
                    translationPolicy: .protect
                )
            ],
            knownStyleIDs: ["plain", "italic-1"]
        )
    }

    @Test("missing, extra, and reordered block IDs are errors")
    func exactIDs() {
        let response = DocumentTranslationResponse(
            chunkId: "chunk-1",
            blocks: [
                DocumentTranslationOutputBlock(id: "b2", text: "ॐ", style: "italic-1"),
                DocumentTranslationOutputBlock(id: "extra", text: "x")
            ]
        )
        let result = DocumentTranslationValidator().validate(response: response, request: request())
        #expect(result.errors.contains { $0.code == "missingBlockID" })
        #expect(result.errors.contains { $0.code == "extraBlockID" })
        #expect(result.errors.contains { $0.code == "blockOrder" })
    }

    @Test("protected text, placeholders, explanations, and styles fail locally")
    func protectedAndFormattingChecks() {
        let response = DocumentTranslationResponse(
            chunkId: "chunk-1",
            blocks: [
                DocumentTranslationOutputBlock(id: "b1", text: "Translation: Глава 3: {{other}}", style: "unknown"),
                DocumentTranslationOutputBlock(id: "b2", text: "изменено", style: "italic-1")
            ]
        )
        let result = DocumentTranslationValidator().validate(response: response, request: request())
        #expect(result.errors.contains { $0.code == "unknownStyleID" })
        #expect(result.errors.contains { $0.code == "protectedBlockMutation" })
        #expect(result.errors.contains { $0.code == "numbersChanged" })
        #expect(result.errors.contains { $0.code == "placeholdersChanged" })
        #expect(result.errors.contains { $0.code == "modelExplanation" })
    }

    @Test("full source-language echo is a blocking translation failure")
    func languageResidueBlocksCommit() {
        let simple = DocumentTranslationRequest(chunkId: "c", targetLanguage: "Russian", blocks: [DocumentTranslationInputBlock(id: "b", sourceText: "A source paragraph.")])
        let result = DocumentTranslationValidator().validate(
            response: DocumentTranslationResponse(chunkId: "c", blocks: [DocumentTranslationOutputBlock(id: "b", text: "A source paragraph.")]),
            request: simple
        )
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.code == "languageResidue" })
        #expect(!result.warnings.contains { $0.code == "languageResidue" })
    }
    @Test("source-aware front matter accepts deterministic literals and repeated sources")
    func sourceAwareFrontMatter() {
        let request = DocumentTranslationRequest(
            chunkId: "front-matter",
            targetLanguage: "Russian",
            blocks: [
                DocumentTranslationInputBlock(id: "empty", sourceText: ""),
                DocumentTranslationInputBlock(id: "rights-1", sourceText: "All rights reserved."),
                DocumentTranslationInputBlock(id: "rights-2", sourceText: "All rights reserved."),
                DocumentTranslationInputBlock(id: "label", sourceText: "Translation: [NAME]"),
                DocumentTranslationInputBlock(id: "url", sourceText: "kadambafoundation.com"),
                DocumentTranslationInputBlock(id: "copyright", sourceText: "© 2026 Kadamba Foundation"),
                DocumentTranslationInputBlock(id: "placeholder", sourceText: "Author: [NAME]"),
                DocumentTranslationInputBlock(
                    id: "protected",
                    sourceText: "ॐ",
                    spans: [DocumentTranslationInputSpan(id: "protected-span", style: "italic", text: "ॐ")],
                    translationPolicy: .protect
                ),
                DocumentTranslationInputBlock(id: "prose", sourceText: "Ordinary source paragraph.")
            ]
        )
        let response = DocumentTranslationResponse(
            chunkId: "front-matter",
            blocks: [
                DocumentTranslationOutputBlock(id: "empty", text: ""),
                DocumentTranslationOutputBlock(id: "rights-1", text: "All rights reserved."),
                DocumentTranslationOutputBlock(id: "rights-2", text: "All rights reserved."),
                DocumentTranslationOutputBlock(id: "label", text: "Перевод: [NAME]"),
                DocumentTranslationOutputBlock(id: "url", text: "kadambafoundation.com"),
                DocumentTranslationOutputBlock(id: "copyright", text: "© 2026 Kadamba Foundation"),
                DocumentTranslationOutputBlock(id: "placeholder", text: "Author: [NAME]"),
                DocumentTranslationOutputBlock(
                    id: "protected",
                    spans: [DocumentTranslationOutputSpan(id: "protected-span", style: "italic", text: "ॐ")]
                ),
                DocumentTranslationOutputBlock(id: "prose", text: "Обычный переведённый абзац.")
            ]
        )

        let result = DocumentTranslationValidator().validate(response: response, request: request)
        #expect(result.isValid)
        #expect(!result.errors.contains { $0.code == "duplicateText" })
        #expect(!result.errors.contains { $0.code == "modelExplanation" })
        #expect(!result.warnings.contains { $0.code == "languageResidue" })
    }

    @Test("empty output and duplicate output remain blocking for different sources")
    func emptyAndDifferentSourceDuplicateFail() {
        let request = DocumentTranslationRequest(
            chunkId: "negative",
            targetLanguage: "Russian",
            blocks: [
                DocumentTranslationInputBlock(id: "nonempty", sourceText: "A non-empty source paragraph."),
                DocumentTranslationInputBlock(id: "first", sourceText: "First source paragraph."),
                DocumentTranslationInputBlock(id: "second", sourceText: "Second source paragraph.")
            ]
        )
        let response = DocumentTranslationResponse(
            chunkId: "negative",
            blocks: [
                DocumentTranslationOutputBlock(id: "nonempty", text: ""),
                DocumentTranslationOutputBlock(id: "first", text: "Одинаковый результат."),
                DocumentTranslationOutputBlock(id: "second", text: "Одинаковый результат.")
            ]
        )

        let result = DocumentTranslationValidator().validate(response: response, request: request)
        #expect(result.errors.contains { $0.code == "emptyBlock" && $0.blockID == "nonempty" })
        #expect(result.errors.contains { $0.code == "duplicateText" && $0.blockID == "second" })
    }

    @Test("source-authored label is allowed but unsolicited wrapper is blocking")
    func explanationPrefixClassification() {
        let labeledRequest = DocumentTranslationRequest(
            chunkId: "labels",
            targetLanguage: "Russian",
            blocks: [DocumentTranslationInputBlock(id: "label", sourceText: "Translation: [NAME]")]
        )
        let labeled = DocumentTranslationValidator().validate(
            response: DocumentTranslationResponse(
                chunkId: "labels",
                blocks: [DocumentTranslationOutputBlock(id: "label", text: "Перевод: [NAME]")]
            ),
            request: labeledRequest
        )
        #expect(!labeled.errors.contains { $0.code == "modelExplanation" })

        let proseRequest = DocumentTranslationRequest(
            chunkId: "wrapper",
            targetLanguage: "Russian",
            blocks: [DocumentTranslationInputBlock(id: "prose", sourceText: "An ordinary paragraph.")]
        )
        let wrapped = DocumentTranslationValidator().validate(
            response: DocumentTranslationResponse(
                chunkId: "wrapper",
                blocks: [DocumentTranslationOutputBlock(id: "prose", text: "Here is the translation: Обычный абзац.")]
            ),
            request: proseRequest
        )
        #expect(wrapped.errors.contains { $0.code == "modelExplanation" })
    }

    @Test("number parity permits decade and ordinal suffixes but flags changed or reordered numbers")
    func numberParityWithDecadeAndOrdinalSuffixes() {
        let validator = DocumentTranslationValidator()

        // 'the late 1970s' vs 'в конце 1970-х' passes
        let decadeReq = DocumentTranslationRequest(
            chunkId: "decade",
            targetLanguage: "Russian",
            blocks: [DocumentTranslationInputBlock(id: "b1", sourceText: "In the late 1970s, many changes took place.")]
        )
        let decadeValid = validator.validate(
            response: DocumentTranslationResponse(
                chunkId: "decade",
                blocks: [DocumentTranslationOutputBlock(id: "b1", text: "В конце 1970-х годов произошло много изменений.")]
            ),
            request: decadeReq
        )
        #expect(decadeValid.isValid)
        #expect(!decadeValid.errors.contains { $0.code == "numbersChanged" })

        // Non-breaking hyphen '1970‑х' passes
        let nonBreakingHyphenValid = validator.validate(
            response: DocumentTranslationResponse(
                chunkId: "decade",
                blocks: [DocumentTranslationOutputBlock(id: "b1", text: "В конце 1970\u{2011}х годов произошло много изменений.")]
            ),
            request: decadeReq
        )
        #expect(nonBreakingHyphenValid.isValid)
        #expect(!nonBreakingHyphenValid.errors.contains { $0.code == "numbersChanged" })

        // Changed number still errors
        let changedNum = validator.validate(
            response: DocumentTranslationResponse(
                chunkId: "decade",
                blocks: [DocumentTranslationOutputBlock(id: "b1", text: "В конце 1985 года произошло много изменений.")]
            ),
            request: decadeReq
        )
        #expect(changedNum.errors.contains { $0.code == "numbersChanged" })

        // Reordered numbers error
        let reorderedReq = DocumentTranslationRequest(
            chunkId: "reordered",
            targetLanguage: "Russian",
            blocks: [DocumentTranslationInputBlock(id: "b1", sourceText: "From 1970 to 1980.")]
        )
        let reordered = validator.validate(
            response: DocumentTranslationResponse(
                chunkId: "reordered",
                blocks: [DocumentTranslationOutputBlock(id: "b1", text: "С 1980 по 1970 год.")]
            ),
            request: reorderedReq
        )
        #expect(reordered.errors.contains { $0.code == "numbersChanged" })

        // Ordinals pass (1st, 2nd, 3rd)
        let ordinalReq = DocumentTranslationRequest(
            chunkId: "ordinal",
            targetLanguage: "Russian",
            blocks: [DocumentTranslationInputBlock(id: "b1", sourceText: "The 1st edition in 1970.")]
        )
        let ordinalValid = validator.validate(
            response: DocumentTranslationResponse(
                chunkId: "ordinal",
                blocks: [DocumentTranslationOutputBlock(id: "b1", text: "1-е издание в 1970 году.")]
            ),
            request: ordinalReq
        )
        #expect(ordinalValid.isValid)
        #expect(!ordinalValid.errors.contains { $0.code == "numbersChanged" })
    }
}
