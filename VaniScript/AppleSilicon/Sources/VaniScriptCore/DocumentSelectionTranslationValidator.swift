import Foundation

public struct DocumentSelectionTranslationValidationResult: Equatable, Sendable {
    public var errors: [QualityIssue]
    public var warnings: [QualityIssue]

    public init(errors: [QualityIssue] = [], warnings: [QualityIssue] = []) {
        self.errors = errors
        self.warnings = warnings
    }

    public var isValid: Bool { errors.isEmpty }
    public var issues: [QualityIssue] { errors + warnings }
    public var validationCodes: [String] { issues.map(\.code) }
}

/// Local, deterministic checks for a plain-text selection replacement.
///
/// Only the response schema and text are validated here. Structural identity and
/// formatting remain trusted application state and are never accepted from the AI.
public struct DocumentSelectionTranslationValidator: Sendable {
    public init() {}

    public func validate(
        response: DocumentSelectionTranslationResponse,
        request: DocumentSelectionTranslationRequest
    ) -> DocumentSelectionTranslationValidationResult {
        var errors: [QualityIssue] = []
        var warnings: [QualityIssue] = []

        if response.schema != DocumentSelectionTranslationContract.schema {
            errors.append(issue("schema", "Response schema is not the selection translation schema."))
        }
        if response.operationID != request.operationID {
            errors.append(issue("operationID", "Response operation ID does not match the request."))
        }

        let replacement = response.replacementText
        let trimmed = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            errors.append(issue("emptyReplacement", "The selection translation response is empty."))
        }
        if replacement != replacement.precomposedStringWithCanonicalMapping {
            errors.append(issue("unicodeNFC", "Replacement text must use Unicode NFC."))
        }
        if trimmed.contains("```") {
            errors.append(issue("markdownFence", "Replacement text must not contain markdown fences."))
        }
        if hasModelWrapper(trimmed) {
            errors.append(issue("modelExplanation", "Replacement text must not include labels, notes, or explanations."))
        }

        for token in request.protectedTokens {
            let normalizedToken = normalized(token)
            guard !normalizedToken.isEmpty,
                  normalized(request.selectedTargetText).contains(normalizedToken)
                    || normalized(request.sourceContext).contains(normalizedToken)
            else { continue }
            if !normalized(trimmed).contains(normalizedToken) {
                errors.append(issue("protectedTermMissing", "A protected term was not preserved."))
            }
        }

        let normalizedReplacement = normalized(trimmed)
        let normalizedSelection = normalized(request.selectedTargetText)
        let normalizedSource = normalized(request.sourceContext)
        if !normalizedSelection.isEmpty && normalizedReplacement == normalizedSelection {
            warnings.append(issue(
                "unchangedSelection",
                "Replacement is identical to the selected text; review is recommended.",
                severity: .warning
            ))
        }
        if normalizedSource.count >= 12,
           normalizedReplacement == normalizedSource
        {
            warnings.append(issue(
                "languageResidue",
                "Replacement appears to retain the source-language text; review is recommended.",
                severity: .warning
            ))
        }

        let selectedLength = normalizedSelection.count
        let replacementLength = normalizedReplacement.count
        if selectedLength > 0 && replacementLength > 0 {
            let ratio = Double(replacementLength) / Double(selectedLength)
            if ratio < 0.1 || ratio > 4.0 {
                warnings.append(issue(
                    "lengthRatio",
                    "Replacement length is outside the soft review range.",
                    severity: .warning
                ))
            }
        }

        if !request.targetPrefix.isEmpty,
           !request.targetSuffix.isEmpty,
           normalizedReplacement.contains(normalized(request.targetPrefix) + normalized(request.targetSuffix))
        {
            warnings.append(issue(
                "surroundingTarget",
                "Replacement appears to include surrounding target context; review is recommended.",
                severity: .warning
            ))
        }

        return DocumentSelectionTranslationValidationResult(errors: errors, warnings: warnings)
    }

    public func validate(
        _ response: DocumentSelectionTranslationResponse,
        against request: DocumentSelectionTranslationRequest
    ) -> DocumentSelectionTranslationValidationResult {
        validate(response: response, request: request)
    }

    public func validateJSON(
        _ data: Data,
        request: DocumentSelectionTranslationRequest
    ) -> DocumentSelectionTranslationValidationResult {
        do {
            let response = try DocumentSelectionTranslationResponse.decodeStrict(data)
            return validate(response: response, request: request)
        } catch let error as DocumentSelectionTranslationContractError {
            return DocumentSelectionTranslationValidationResult(errors: [
                issue("invalidJSON", error.localizedDescription)
            ])
        } catch {
            return DocumentSelectionTranslationValidationResult(errors: [
                issue("invalidJSON", "The selection translation response is not a valid JSON object.")
            ])
        }
    }

    private func issue(
        _ code: String,
        _ message: String,
        severity: QualityIssueSeverity = .error
    ) -> QualityIssue {
        QualityIssue(code: code, message: message, severity: severity)
    }

    private func normalized(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func hasModelWrapper(_ value: String) -> Bool {
        let lower = value.lowercased()
        let prefixes = [
            "translation:",
            "translated text:",
            "here is the translation:",
            "вот перевод:",
            "перевод:",
            "ответ:",
            "notes:",
            "explanation:"
        ]
        return prefixes.contains(where: lower.hasPrefix)
    }
}
