import Foundation

public struct DocumentTranslationValidationResult: Equatable, Sendable {
    public var errors: [QualityIssue]
    public var warnings: [QualityIssue]
    public var normalizedResponse: DocumentTranslationResponse?

    public init(
        errors: [QualityIssue] = [],
        warnings: [QualityIssue] = [],
        normalizedResponse: DocumentTranslationResponse? = nil
    ) {
        self.errors = errors
        self.warnings = warnings
        self.normalizedResponse = normalizedResponse
    }

    public var isValid: Bool { errors.isEmpty }
    public var hasBlockingErrors: Bool { !errors.isEmpty }
    public var issues: [QualityIssue] { errors + warnings }

    public func qualityReport(sourceHash: String, attempts: Int, outputHash: String?) -> ChunkQualityReport {
        ChunkQualityReport(
            validatorVersion: DocumentTranslationContract.validatorVersion,
            errors: errors,
            warnings: warnings,
            attempts: attempts,
            sourceHash: sourceHash,
            outputHash: outputHash
        )
    }
}

/// Local checks are deliberately conservative about structure and protected
/// material. Language quality and expansion ratio are signals only.
public struct DocumentTranslationValidator: Sendable {
    public static let version = DocumentTranslationContract.validatorVersion

    public init() {}

    public func validate(
        response: DocumentTranslationResponse,
        request: DocumentTranslationRequest
    ) -> DocumentTranslationValidationResult {
        var errors: [QualityIssue] = []
        var warnings: [QualityIssue] = []

        if response.schema != DocumentTranslationContract.schema {
            errors.append(issue("schema", "Response schema must be \(DocumentTranslationContract.schema)."))
        }
        if response.chunkId != request.chunkId {
            errors.append(issue("chunkId", "Response chunkId does not match the requested chunk.", blockID: response.chunkId))
        }

        let expectedIDs = request.expectedBlockIDs
        let actualIDs = response.blockIDs
        let expectedSet = Set(expectedIDs)
        var seen = Set<String>()
        for id in actualIDs {
            if !seen.insert(id).inserted {
                errors.append(issue("duplicateBlockID", "Block ID appears more than once.", blockID: id))
            }
            if !expectedSet.contains(id) {
                errors.append(issue("extraBlockID", "Response contains a block ID that was not requested.", blockID: id))
            }
        }
        for id in expectedIDs where !actualIDs.contains(id) {
            errors.append(issue("missingBlockID", "Every requested block must have exactly one translated output.", blockID: id))
        }
        if actualIDs != expectedIDs {
            errors.append(issue("blockOrder", "Output block IDs must match the requested order exactly."))
        }

        let expectedByID = Dictionary(uniqueKeysWithValues: request.blocks.map { ($0.id, $0) })
        var normalizedBlocks: [DocumentTranslationOutputBlock] = []
        var seenOutputTexts: [String: String] = [:]

        for output in response.blocks {
            guard let input = expectedByID[output.id] else { continue }
            let rawText = output.text
            if rawText != rawText.precomposedStringWithCanonicalMapping {
                errors.append(issue("unicodeNFC", "Translated text must use Unicode NFC.", blockID: output.id))
            }
            let normalizedSpans = output.spans.map { span in
                let normalizedStyle = span.style.precomposedStringWithCanonicalMapping
                let normalizedText = span.text.precomposedStringWithCanonicalMapping
                if span.style != normalizedStyle || span.text != normalizedText {
                    errors.append(issue("unicodeNFC", "Translated span text and style must use Unicode NFC.", blockID: output.id))
                }
                return DocumentTranslationOutputSpan(
                    id: span.id,
                    style: normalizedStyle,
                    text: normalizedText
                )
            }
            let normalized = DocumentTranslationOutputBlock(id: output.id, spans: normalizedSpans)
            normalizedBlocks.append(normalized)

            let allText = normalized.text
            let sourceIsEmpty = input.sourceText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
            let outputIsEmpty = allText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if sourceIsEmpty, !outputIsEmpty {
                errors.append(issue("deterministicBlockMutation", "Source-empty blocks must remain empty.", blockID: output.id))
            } else if !sourceIsEmpty, outputIsEmpty {
                errors.append(issue("emptyBlock", "Translated blocks cannot be empty when the source contains text.", blockID: output.id))
            }
            if containsModelExplanation(allText, source: input.sourceText) {
                errors.append(issue("modelExplanation", "Output must contain only translated block text, without unsolicited labels or explanations.", blockID: output.id))
            }

            if !(sourceIsEmpty && outputIsEmpty) {
                let knownStyles = request.expectedStyleIDs
                for span in normalized.spans {
                    if span.style.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        errors.append(issue("emptyStyleID", "Every output span must reference a known style ID.", blockID: output.id))
                    } else if !knownStyles.contains(span.style) {
                        errors.append(issue("unknownStyleID", "Output uses a style ID that was not captured from the source.", blockID: output.id))
                    }
                }
            }

            let sourceText = input.sourceText
            if input.translationPolicy == .protect {
                let protectedSpansMatch = normalized.spans.count == input.spans.count
                    && zip(normalized.spans, input.spans).allSatisfy { outputSpan, sourceSpan in
                        outputSpan.id == sourceSpan.id
                            && outputSpan.style == sourceSpan.style
                            && outputSpan.text == sourceSpan.text
                    }
                if !protectedSpansMatch {
                    errors.append(issue("protectedBlockMutation", "Protected blocks and spans must be copied byte-for-byte.", blockID: output.id))
                }
            }

            let sourceProtected = input.spans
                .filter { $0.translationPolicy == .protect }
                .map(\.text)
                .filter { !$0.isEmpty }
            for protected in sourceProtected where !allText.contains(protected) {
                errors.append(issue("protectedSpanMutation", "Protected source spans must remain unchanged.", blockID: output.id))
            }

            let sourceNumbers = numberTokens(in: sourceText)
            let outputNumbers = numberTokens(in: allText)
            if sourceNumbers != outputNumbers {
                errors.append(issue("numbersChanged", "Numbers and verse/chapter references must be preserved in order.", blockID: output.id))
            }

            let sourcePlaceholders = placeholderTokens(in: sourceText)
            let outputPlaceholders = placeholderTokens(in: allText)
            if sourcePlaceholders != outputPlaceholders {
                errors.append(issue("placeholdersChanged", "Placeholders and inline markers must be preserved exactly.", blockID: output.id))
            }

            let sourceLength = sourceText.trimmingCharacters(in: .whitespacesAndNewlines).count
            let outputLength = allText.trimmingCharacters(in: .whitespacesAndNewlines).count
            if sourceLength > 0, outputLength > 0 {
                let ratio = Double(outputLength) / Double(sourceLength)
                if ratio < 0.1 || ratio > 4.0 {
                    warnings.append(issue(
                        "lengthRatio",
                        "Translation length ratio is outside the soft review range (\(String(format: "%.2f", ratio))).",
                        severity: .warning,
                        blockID: output.id
                    ))
                }
            }
            if isLikelySourceLanguageResidue(
                source: sourceText,
                output: allText,
                input: input,
                request: request
            ) {
                warnings.append(issue(
                    "languageResidue",
                    "Output contains substantial source-language residue; review is recommended.",
                    severity: .warning,
                    blockID: output.id
                ))
            }

            let duplicateKey = normalizedComparison(allText)
            if !duplicateKey.isEmpty, let previousID = seenOutputTexts[duplicateKey], previousID != output.id {
                let previousSource = expectedByID[previousID]?.sourceText ?? ""
                if normalizedComparison(previousSource) != normalizedComparison(sourceText) {
                    errors.append(issue("duplicateText", "The same translated paragraph was emitted for multiple block IDs with different source text.", blockID: output.id))
                }
            } else if !duplicateKey.isEmpty {
                seenOutputTexts[duplicateKey] = output.id
            }
        }

        let normalizedResponse = DocumentTranslationResponse(
            schema: response.schema,
            chunkId: response.chunkId,
            blocks: normalizedBlocks
        )
        return DocumentTranslationValidationResult(
            errors: errors,
            warnings: warnings,
            normalizedResponse: errors.isEmpty ? normalizedResponse : response
        )
    }

    public func validate(
        _ response: DocumentTranslationResponse,
        against request: DocumentTranslationRequest
    ) -> DocumentTranslationValidationResult {
        validate(response: response, request: request)
    }

    public func validateJSON(
        _ data: Data,
        request: DocumentTranslationRequest
    ) -> DocumentTranslationValidationResult {
        do {
            let response = try DocumentTranslationResponse.decodeStrict(data)
            return validate(response: response, request: request)
        } catch let error as DocumentTranslationContractError {
            return DocumentTranslationValidationResult(errors: [
                issue("invalidJSON", error.localizedDescription)
            ])
        } catch {
            return DocumentTranslationValidationResult(errors: [issue("invalidJSON", "The model response is not a valid document translation JSON object.")])
        }
    }

    private func issue(
        _ code: String,
        _ message: String,
        severity: QualityIssueSeverity = .error,
        blockID: String? = nil
    ) -> QualityIssue {
        QualityIssue(code: code, message: message, severity: severity, blockID: blockID)
    }

    private func containsModelExplanation(_ text: String, source: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("```") { return true }
        let lower = trimmed.lowercased()
        let prefixes = [
            "translation:", "translated text:", "here is the translation:",
            "вот перевод:", "перевод:", "ответ:", "notes:", "explanation:"
        ]
        guard prefixes.contains(where: { lower.hasPrefix($0) }) else { return false }

        // A source-authored structural label is content, not a wrapper. For
        // example, `Translation: [NAME]` may legitimately become
        // `Перевод: [NAME]`; the generic "Here is the translation:" wrapper
        // remains an error because it is not a structural label class.
        guard let sourceClass = structuralLabelClass(in: source),
              let outputClass = structuralLabelClass(in: trimmed)
        else {
            return true
        }
        return sourceClass != outputClass
    }

    private func structuralLabelClass(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        let label = normalizedComparison(String(trimmed[..<colon]))
        switch label {
        case "translation", "translated text", "перевод", "перевод текста":
            return "translation"
        case "note", "notes", "заметка", "заметки":
            return "notes"
        case "explanation", "пояснение":
            return "explanation"
        case "answer", "ответ":
            return "answer"
        default:
            return nil
        }
    }

    private func tokens(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }

    private func numberTokens(in text: String) -> [String] {
        let pattern = #"(?<![\p{L}\d])(\d+(?:[.,]\d+)?)(?:[-‐‑‒–—'’]?\p{L}+)?(?![\p{L}\d])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  match.range(at: 1).location != NSNotFound,
                  let swiftRange = Range(match.range(at: 1), in: text)
            else {
                guard let fullRange = Range(match.range, in: text) else { return nil }
                return String(text[fullRange])
            }
            return String(text[swiftRange])
        }
    }

    private func placeholderTokens(in text: String) -> [String] {
        let patterns = [
            #"\{\{[^{}]+\}\}"#,
            #"\{[^{}]+\}"#,
            #"\[[A-Z][A-Z0-9_:-]*\]"#,
            #"<<[^<>]+>>"#
        ]
        return patterns.flatMap { tokens(in: text, pattern: $0) }
    }

    private func normalizedComparison(_ text: String) -> String {
        text
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func isLikelySourceLanguageResidue(
        source: String,
        output: String,
        input: DocumentTranslationInputBlock,
        request: DocumentTranslationRequest
    ) -> Bool {
        guard source.count >= 12, output.count >= 12 else { return false }
        let sourceNormalized = normalizedComparison(source)
        let outputNormalized = normalizedComparison(output)
        guard sourceNormalized == outputNormalized else { return false }
        if input.translationPolicy == .protect
            || (!input.spans.isEmpty && input.spans.allSatisfy { $0.translationPolicy == .protect })
        {
            return false
        }
        if isLiteralFrontMatter(source) {
            return false
        }
        let protected = Set(request.protectedTokens.map(normalizedComparison))
        return !protected.contains(sourceNormalized)
    }

    private func isLiteralFrontMatter(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let lower = trimmed.lowercased()
        if lower == "all rights reserved."
            || lower == "all rights reserved"
            || trimmed.hasPrefix("©")
            || lower.hasPrefix("(c)")
            || lower.hasPrefix("copyright")
        {
            return true
        }

        let urlPattern = #"^(?:(?:https?://|www\.)?[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}(?:/[^\s]*)?|https?://[^\s]+)$"#
        if let regex = try? NSRegularExpression(pattern: urlPattern),
           regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)) != nil
        {
            return true
        }

        let placeholders = placeholderTokens(in: trimmed)
        guard !placeholders.isEmpty else { return false }
        var residual = trimmed
        for placeholder in placeholders {
            residual = residual.replacingOccurrences(of: placeholder, with: " ")
        }
        let residualWords = residual
            .split(whereSeparator: { $0.isWhitespace || $0 == ":" || $0 == "-" || $0 == "—" })
        // Front matter such as `Author: [NAME]` is literal metadata. Ordinary
        // prose containing a placeholder still has enough words to review.
        return residualWords.count <= 2 && residual.contains(":")
    }
}

public typealias DocumentTranslationValidation = DocumentTranslationValidationResult
