import Foundation

public enum S1MiniRequestEligibility: Equatable, Sendable {
    case supported
    case nonEnglishText
    case unsupportedVariant
    case customPrompt
    case translation

    public var diagnosticLabel: String {
        switch self {
        case .supported:
            "supported"
        case .nonEnglishText:
            "non-English text"
        case .unsupportedVariant:
            "unsupported variant"
        case .customPrompt:
            "custom prompt"
        case .translation:
            "translation"
        }
    }

    public var userFacingMessage: String {
        switch self {
        case .supported:
            "S1-mini can process this request."
        case .nonEnglishText:
            "S1-mini by Superwhisper supports English transcript cleanup only."
        case .unsupportedVariant:
            "S1-mini by Superwhisper supports the standard Variant 1 cleanup route only."
        case .customPrompt:
            "S1-mini by Superwhisper is a fixed transcript normalizer and does not support custom polishing prompts."
        case .translation:
            "S1-mini by Superwhisper cannot translate text. Choose Qwen, another local MLX model, or a cloud provider."
        }
    }
}

public enum S1MiniPolishingPolicy {
    public static let modelID = "superwhisper-s1-mini"
    public static let repositoryID = "superwhisper/s1-mini"
    public static let pinnedRevision = "65f84bcda1d13df582c4a8443c1c5aa53c0c66db"

    public static let systemInstruction = "You are a text normalizer for speech-to-text transcripts. The input begins with a control line specifying the styling, structure, and context settings; clean the transcript to match those settings and output only the cleaned text."

    public static let controlLine = "[Styling: semi-formal] [Structure: prose] [Context: general]"

    public static func isS1Mini(_ model: PolishingModelDescriptor) -> Bool {
        model.id == modelID
            || model.repositoryID.caseInsensitiveCompare(repositoryID) == .orderedSame
    }

    public static func eligibility(
        for request: PolishingRequest
    ) -> S1MiniRequestEligibility {
        if isTranslationRequest(request) {
            return .translation
        }

        if containsNonLatinLetters(request.rawText) {
            return .nonEnglishText
        }

        switch request.variant {
        case .raw, .variantOne:
            break
        case .variantTwo:
            return .unsupportedVariant
        }

        guard isDefaultVariantOneTemplate(request.template) else {
            return .customPrompt
        }

        return .supported
    }

    public static func renderedPrompt(
        for request: PolishingRequest
    ) -> RenderedPrompt {
        RenderedPrompt(
            systemInstruction: systemInstruction,
            userContent: "\(controlLine)\n\(request.rawText)"
        )
    }

    public static func containsNonLatinLetters(_ text: String) -> Bool {
        for scalar in text.unicodeScalars where CharacterSet.letters.contains(scalar) {
            guard isLatinLetter(scalar.value) else {
                return true
            }
        }
        return false
    }

    private static func isTranslationRequest(_ request: PolishingRequest) -> Bool {
        let id = request.template.id.lowercased()
        let title = request.template.title.lowercased()
        let body = request.template.body.lowercased()

        return id.contains("translation")
            || title.contains("translation")
            || body.contains("=== translation override")
            || body.contains("task: translate the provided text to")
            || body.contains("text to translate:")
    }

    private static func isDefaultVariantOneTemplate(_ template: PromptTemplate) -> Bool {
        normalized(template.body) == normalized(PromptTemplate.variantOneDefault.body)
    }

    private static func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isLatinLetter(_ value: UInt32) -> Bool {
        switch value {
        case 0x0041...0x005A,
             0x0061...0x007A,
             0x00C0...0x00FF,
             0x0100...0x024F,
             0x1D00...0x1D7F,
             0x1D80...0x1DBF,
             0x1E00...0x1EFF,
             0x2C60...0x2C7F,
             0xA720...0xA7FF,
             0xAB30...0xAB6F,
             0x10780...0x107BF,
             0x1DF00...0x1DFFF:
            true
        default:
            false
        }
    }
}

public enum S1MiniPolishingError: LocalizedError, Equatable, Sendable {
    case unsupportedRequest(S1MiniRequestEligibility)

    public var errorDescription: String? {
        switch self {
        case .unsupportedRequest(let eligibility):
            eligibility.userFacingMessage
        }
    }
}
