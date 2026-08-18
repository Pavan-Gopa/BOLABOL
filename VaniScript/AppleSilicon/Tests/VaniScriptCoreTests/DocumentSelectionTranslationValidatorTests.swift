import Foundation
import Testing
@testable import VaniScriptCore

@Suite("DocumentSelectionTranslationValidatorTests (PRD §26.5)")
struct DocumentSelectionTranslationValidatorTests {
    @Test("empty and whitespace-only replacements are rejected")
    func emptyReplacementRejected() {
        let validator = DocumentSelectionTranslationValidator()
        let request = makeRequest()

        for replacement in ["", "   \n "] {
            let result = validator.validate(
                response: makeResponse(replacement),
                request: request
            )
            #expect(result.errors.contains(where: { $0.code == "emptyReplacement" }))
            #expect(result.isValid == false)
        }
    }

    @Test("unicode NFC check is currently unreachable (product bug)")
    func unicodeNFCCheckIsUnreachable() {
        // PRODUCT BUG (pinned to actual behavior, not fixed): the validator checks
        // `replacement != replacement.precomposedStringWithCanonicalMapping`, but
        // Swift `String` equality is canonical-equivalence based, so a decomposed
        // string always compares equal to its NFC form and the `unicodeNFC` error
        // can never fire. A scalar-level comparison is required to enforce NFC.
        let validator = DocumentSelectionTranslationValidator()
        let request = makeRequest()

        // Swift NFC-normalizes string literals at compile time, so the decomposed
        // form must be produced at runtime to exercise the check.
        let decomposedText = "Kéep Krishna".decomposedStringWithCanonicalMapping
        // The input is genuinely decomposed at the scalar level...
        #expect(Array(decomposedText.unicodeScalars) != Array(decomposedText.precomposedStringWithCanonicalMapping.unicodeScalars))
        // ...yet Swift `String ==` reports it equal to its NFC form.
        #expect(decomposedText == decomposedText.precomposedStringWithCanonicalMapping)
        let decomposed = validator.validate(
            response: makeResponse(decomposedText),
            request: request
        )
        // Actual behavior: no unicodeNFC error is raised for decomposed input.
        #expect(decomposed.errors.contains(where: { $0.code == "unicodeNFC" }) == false)

        let precomposed = validator.validate(
            response: makeResponse("Kéep Krishna"),
            request: request
        )
        #expect(precomposed.errors.contains(where: { $0.code == "unicodeNFC" }) == false)
    }

    @Test("markdown fences in the replacement are rejected")
    func markdownFenceRejected() {
        let validator = DocumentSelectionTranslationValidator()
        let request = makeRequest()

        let result = validator.validate(
            response: makeResponse("Keep Krishna\n```\ncode\n```"),
            request: request
        )
        #expect(result.errors.contains(where: { $0.code == "markdownFence" }))
    }

    @Test("model wrapper prefixes are rejected; plain translations pass")
    func modelExplanationRejected() {
        let validator = DocumentSelectionTranslationValidator()
        let request = makeRequest()

        for wrapped in ["Translation: Keep Krishna", "Вот перевод: Keep Krishna"] {
            let result = validator.validate(
                response: makeResponse(wrapped),
                request: request
            )
            #expect(result.errors.contains(where: { $0.code == "modelExplanation" }))
        }

        let plain = validator.validate(
            response: makeResponse("Keep Krishna"),
            request: request
        )
        #expect(plain.errors.contains(where: { $0.code == "modelExplanation" }) == false)
    }

    @Test("extreme length ratios warn; in-range replacements do not")
    func lengthRatioWarnsOnExtremeRatios() {
        let validator = DocumentSelectionTranslationValidator()

        let longSelection = makeRequest(
            selectedTargetText: "Это очень длинная выделенная фраза, которую нужно заменить.",
            sourceContext: "Это очень длинная выделенная фраза, которую нужно заменить."
        )
        let tooShort = validator.validate(
            response: makeResponse("О"),
            request: longSelection
        )
        #expect(tooShort.warnings.contains(where: { $0.code == "lengthRatio" }))

        let shortSelection = makeRequest(
            selectedTargetText: "Фраза",
            sourceContext: "Фраза"
        )
        let tooLong = validator.validate(
            response: makeResponse("Это очень длинная заменяющая фраза, которая намного длиннее исходной."),
            request: shortSelection
        )
        #expect(tooLong.warnings.contains(where: { $0.code == "lengthRatio" }))

        let inRange = validator.validate(
            response: makeResponse("Новая фраза"),
            request: makeRequest(
                selectedTargetText: "Старая фраза",
                sourceContext: "Старая фраза"
            )
        )
        #expect(inRange.warnings.contains(where: { $0.code == "lengthRatio" }) == false)
    }

    @Test("replacement echoing the surrounding target text warns")
    func surroundingTargetEchoWarns() {
        let validator = DocumentSelectionTranslationValidator()
        let request = makeRequest(
            selectedTargetText: "middle",
            sourceContext: "foo middle bar",
            targetPrefix: "foo",
            targetSuffix: "bar"
        )

        let result = validator.validate(
            response: makeResponse("foobar"),
            request: request
        )
        #expect(result.warnings.contains(where: { $0.code == "surroundingTarget" }))
    }

    @Test("protected tokens match case-insensitively across selection and replacement")
    func protectedTokenCaseInsensitivePreservation() {
        let validator = DocumentSelectionTranslationValidator()
        let request = makeRequest(
            selectedTargetText: "Keep krishna",
            sourceContext: "Keep krishna",
            protectedTokens: ["Krishna"]
        )

        let result = validator.validate(
            response: makeResponse("Сохрани KRISHNA"),
            request: request
        )
        #expect(result.errors.contains(where: { $0.code == "protectedTermMissing" }) == false)
    }

    @Test("protected tokens absent from selection and source context are ignored")
    func protectedTokenAbsentFromContextIgnored() {
        let validator = DocumentSelectionTranslationValidator()
        let request = makeRequest(
            selectedTargetText: "Keep the phrase",
            sourceContext: "Keep the phrase",
            protectedTokens: ["Rama"]
        )

        let result = validator.validate(
            response: makeResponse("Сохрани фразу"),
            request: request
        )
        #expect(result.errors.contains(where: { $0.code == "protectedTermMissing" }) == false)
    }

    @Test("dropping a protected token from the replacement is still an error")
    func protectedTokenDropRejected() {
        let validator = DocumentSelectionTranslationValidator()
        let request = makeRequest(
            selectedTargetText: "Keep Krishna",
            sourceContext: "Keep Krishna",
            protectedTokens: ["Krishna"]
        )

        let result = validator.validate(
            response: makeResponse("Сохрани фразу"),
            request: request
        )
        #expect(result.errors.contains(where: { $0.code == "protectedTermMissing" }))
    }

    @Test("validateJSON rejects malformed and unknown-field bodies before field checks")
    func validateJSONRejectsBadBodies() {
        let validator = DocumentSelectionTranslationValidator()
        let request = makeRequest()

        let malformed = validator.validateJSON(Data("not json".utf8), request: request)
        #expect(malformed.errors.map(\.code) == ["invalidJSON"])

        let unknownField = Data(#"{"schema":"vaniscript.document.selection.v1","operationId":"op-1","replacementText":"ok","blockId":"x"}"#.utf8)
        let unexpected = validator.validateJSON(unknownField, request: request)
        #expect(unexpected.errors.map(\.code) == ["invalidJSON"])

        let valid = Data(#"{"schema":"vaniscript.document.selection.v1","operationId":"op-1","replacementText":"Keep Krishna"}"#.utf8)
        let accepted = validator.validateJSON(valid, request: request)
        #expect(accepted.errors.contains(where: { $0.code == "invalidJSON" }) == false)
    }

    @Test("request decoding enforces required fields and rejects unknown keys")
    func requestStrictDecoding() {
        let missingField = Data(#"{"schema":"vaniscript.document.selection.v1","operationId":"op-1","targetLanguage":"Russian","sourceBlockId":"block-1","sourceBlockHash":"hash","sourceContext":"Keep Krishna"}"#.utf8)
        #expect(throws: DocumentSelectionTranslationContractError.missingField("selectedTargetText")) {
            try JSONDecoder().decode(DocumentSelectionTranslationRequest.self, from: missingField)
        }

        let unexpectedField = Data(#"{"schema":"vaniscript.document.selection.v1","operationId":"op-1","targetLanguage":"Russian","sourceBlockId":"block-1","sourceBlockHash":"hash","sourceContext":"Keep Krishna","selectedTargetText":"Keep Krishna","blockId":"x"}"#.utf8)
        #expect(throws: DocumentSelectionTranslationContractError.unexpectedField("blockId")) {
            try JSONDecoder().decode(DocumentSelectionTranslationRequest.self, from: unexpectedField)
        }
    }

    @Test("request encodes camelCase wire keys and round-trips losslessly")
    func requestWireRoundTrip() throws {
        let request = makeRequest(
            selectedTargetText: "Keep Krishna",
            sourceContext: "Keep Krishna and neighbors",
            protectedTokens: ["Krishna"],
            targetPrefix: "before ",
            targetSuffix: " after"
        )

        let data = try JSONEncoder().encode(request)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"operationId\""))
        #expect(json.contains("\"sourceBlockId\""))

        let decoded = try JSONDecoder().decode(DocumentSelectionTranslationRequest.self, from: data)
        #expect(decoded == request)
    }

    @Test("mismatched schema and operation ID are rejected as errors")
    func schemaAndOperationIDMismatchRejected() {
        let validator = DocumentSelectionTranslationValidator()
        let request = makeRequest()

        let wrongSchema = validator.validate(
            response: DocumentSelectionTranslationResponse(schema: "other-schema", operationID: "op-1", replacementText: "Keep Krishna"),
            request: request
        )
        #expect(wrongSchema.errors.contains(where: { $0.code == "schema" }))
        #expect(wrongSchema.isValid == false)

        let mismatchedID = validator.validate(
            response: makeResponse("Keep Krishna", operationID: "other"),
            request: request
        )
        #expect(mismatchedID.errors.contains(where: { $0.code == "operationID" }))
        #expect(mismatchedID.isValid == false)
    }

    @Test("replacement identical to the selection warns without blocking")
    func unchangedSelectionWarns() {
        let validator = DocumentSelectionTranslationValidator()
        let request = makeRequest()

        let identical = validator.validate(
            response: makeResponse("Keep Krishna"),
            request: request
        )
        #expect(identical.isValid == true)
        #expect(identical.warnings.contains(where: { $0.code == "unchangedSelection" }))

        // Casing-only change still normalizes to the selection, so a no-op
        // case flip earns the same review warning.
        let caseFlip = validator.validate(
            response: makeResponse("KEEP krishna"),
            request: request
        )
        #expect(caseFlip.warnings.contains(where: { $0.code == "unchangedSelection" }))

        // A genuinely different replacement earns no warning.
        let changed = validator.validate(
            response: makeResponse("Сохрани Кришну"),
            request: request
        )
        #expect(changed.warnings.contains(where: { $0.code == "unchangedSelection" }) == false)
    }

    @Test("replacement echoing the source language warns; short echo is silent")
    func languageResidueWarns() {
        let validator = DocumentSelectionTranslationValidator()
        let request = makeRequest()

        let echo = validator.validate(
            response: makeResponse("Keep Krishna"),
            request: request
        )
        #expect(echo.warnings.contains(where: { $0.code == "languageResidue" }))

        // Diacritic-only difference still normalizes to the source text.
        let requestDiacritic = makeRequest(
            selectedTargetText: "Держи Кришну",
            sourceContext: "Krishna speaks"
        )
        let diacriticEcho = validator.validate(
            response: makeResponse("Krishná speaks"),
            request: requestDiacritic
        )
        #expect(diacriticEcho.warnings.contains(where: { $0.code == "languageResidue" }))

        // Source context under the 12-unit minimum never warns.
        let shortRequest = makeRequest(
            selectedTargetText: "Фраза",
            sourceContext: "short"
        )
        let shortEcho = validator.validate(
            response: makeResponse("short"),
            request: shortRequest
        )
        #expect(shortEcho.warnings.contains(where: { $0.code == "languageResidue" }) == false)
    }

    private func makeRequest(
        selectedTargetText: String = "Keep Krishna",
        sourceContext: String = "Keep Krishna",
        protectedTokens: [String] = [],
        targetPrefix: String = "",
        targetSuffix: String = ""
    ) -> DocumentSelectionTranslationRequest {
        DocumentSelectionTranslationRequest(
            operationID: "op-1",
            targetLanguage: "Russian",
            sourceBlockID: "block-1",
            sourceBlockHash: String(repeating: "a", count: 64),
            sourceContext: sourceContext,
            selectedTargetText: selectedTargetText,
            targetPrefix: targetPrefix,
            targetSuffix: targetSuffix,
            protectedTokens: protectedTokens
        )
    }

    private func makeResponse(_ text: String, operationID: String = "op-1") -> DocumentSelectionTranslationResponse {
        DocumentSelectionTranslationResponse(operationID: operationID, replacementText: text)
    }
}
