import Foundation

/// Versioned wire contract for re-translating one structurally selected target fragment.
///
/// The request carries trusted context only. The response deliberately contains no
/// block, span, style, colour, or policy metadata (INV-4); the mutation layer owns all
/// document identity and formatting decisions.
public enum DocumentSelectionTranslationContract {
    public static let schema = "vaniscript.document.selection.v1"
}

public enum DocumentSelectionSourceAlignment: String, Codable, CaseIterable, Sendable {
    case mappedSpans
    case blockContext
}

public struct DocumentSelectionSourceSpan: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var styleKey: String

    public init(id: String, text: String, styleKey: String = "") {
        self.id = id
        self.text = text
        self.styleKey = styleKey
    }
}

/// Bounded glossary context sent to the provider without exposing editor metadata.
public struct DocumentSelectionGlossaryHint: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var source: String
    public var translation: String

    public init(id: String = UUID().uuidString, source: String, translation: String = "") {
        self.id = id
        self.source = source
        self.translation = translation
    }
}

public typealias DocumentGlossaryHint = DocumentSelectionGlossaryHint

public struct DocumentSelectionTranslationRequest: Codable, Equatable, Sendable {
    public var schema: String
    public var operationID: String
    public var targetLanguage: String
    public var sourceBlockID: String
    public var sourceBlockHash: String
    public var sourceContext: String
    public var sourceSpans: [DocumentSelectionSourceSpan]
    public var sourceAlignment: DocumentSelectionSourceAlignment
    public var selectedTargetText: String
    public var targetPrefix: String
    public var targetSuffix: String
    public var protectedTokens: [String]
    public var glossary: [DocumentSelectionGlossaryHint]

    /// True when the request intentionally supplies the whole source block because
    /// no trustworthy source-span alignment exists.
    public var isBlockContextAlignment: Bool {
        sourceAlignment == .blockContext
    }

    public init(
        schema: String = DocumentSelectionTranslationContract.schema,
        operationID: String,
        targetLanguage: String,
        sourceBlockID: String,
        sourceBlockHash: String,
        sourceContext: String,
        sourceSpans: [DocumentSelectionSourceSpan] = [],
        sourceAlignment: DocumentSelectionSourceAlignment = .blockContext,
        selectedTargetText: String,
        targetPrefix: String = "",
        targetSuffix: String = "",
        protectedTokens: [String] = [],
        glossary: [DocumentSelectionGlossaryHint] = []
    ) {
        self.schema = schema
        self.operationID = operationID
        self.targetLanguage = targetLanguage
        self.sourceBlockID = sourceBlockID
        self.sourceBlockHash = sourceBlockHash
        self.sourceContext = sourceContext
        self.sourceSpans = sourceSpans
        self.sourceAlignment = sourceAlignment
        self.selectedTargetText = selectedTargetText
        self.targetPrefix = targetPrefix
        self.targetSuffix = targetSuffix
        self.protectedTokens = protectedTokens
        self.glossary = glossary
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schema
        case operationID = "operationId"
        case targetLanguage
        case sourceBlockID = "sourceBlockId"
        case sourceBlockHash
        case sourceContext
        case sourceSpans
        case sourceAlignment
        case selectedTargetText
        case targetPrefix
        case targetSuffix
        case protectedTokens
        case glossary
    }
}

public struct DocumentSelectionTranslationResponse: Codable, Equatable, Sendable {
    public var schema: String
    public var operationID: String
    public var replacementText: String

    public init(
        schema: String = DocumentSelectionTranslationContract.schema,
        operationID: String,
        replacementText: String
    ) {
        self.schema = schema
        self.operationID = operationID
        self.replacementText = replacementText
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schema
        case operationID = "operationId"
        case replacementText
    }

    /// Decodes exactly the response shape accepted by the selection command.
    public static func decodeStrict(_ data: Data) throws -> DocumentSelectionTranslationResponse {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(DocumentSelectionTranslationResponse.self, from: data)
        } catch let error as DocumentSelectionTranslationContractError {
            throw error
        } catch {
            throw DocumentSelectionTranslationContractError.invalidJSON
        }
    }
}

public enum DocumentSelectionTranslationContractError: LocalizedError, Equatable, Sendable {
    case missingField(String)
    case unexpectedField(String)
    case invalidJSON

    public var errorDescription: String? {
        switch self {
        case let .missingField(field):
            "Missing required selection translation field: \(field)."
        case let .unexpectedField(field):
            "Unexpected selection translation field: \(field)."
        case .invalidJSON:
            "The selection translation response is not valid JSON."
        }
    }
}

private struct DocumentSelectionTranslationAnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension DocumentSelectionTranslationRequest {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: DocumentSelectionTranslationAnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        for key in raw.allKeys where !allowed.contains(key.stringValue) {
            throw DocumentSelectionTranslationContractError.unexpectedField(key.stringValue)
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let schema = try container.decodeIfPresent(String.self, forKey: .schema) else {
            throw DocumentSelectionTranslationContractError.missingField(CodingKeys.schema.stringValue)
        }
        guard let operationID = try container.decodeIfPresent(String.self, forKey: .operationID) else {
            throw DocumentSelectionTranslationContractError.missingField(CodingKeys.operationID.stringValue)
        }
        guard let targetLanguage = try container.decodeIfPresent(String.self, forKey: .targetLanguage) else {
            throw DocumentSelectionTranslationContractError.missingField(CodingKeys.targetLanguage.stringValue)
        }
        guard let sourceBlockID = try container.decodeIfPresent(String.self, forKey: .sourceBlockID) else {
            throw DocumentSelectionTranslationContractError.missingField(CodingKeys.sourceBlockID.stringValue)
        }
        guard let sourceBlockHash = try container.decodeIfPresent(String.self, forKey: .sourceBlockHash) else {
            throw DocumentSelectionTranslationContractError.missingField(CodingKeys.sourceBlockHash.stringValue)
        }
        guard let sourceContext = try container.decodeIfPresent(String.self, forKey: .sourceContext) else {
            throw DocumentSelectionTranslationContractError.missingField(CodingKeys.sourceContext.stringValue)
        }
        guard let selectedTargetText = try container.decodeIfPresent(String.self, forKey: .selectedTargetText) else {
            throw DocumentSelectionTranslationContractError.missingField(CodingKeys.selectedTargetText.stringValue)
        }

        self.init(
            schema: schema,
            operationID: operationID,
            targetLanguage: targetLanguage,
            sourceBlockID: sourceBlockID,
            sourceBlockHash: sourceBlockHash,
            sourceContext: sourceContext,
            sourceSpans: try container.decodeIfPresent([DocumentSelectionSourceSpan].self, forKey: .sourceSpans) ?? [],
            sourceAlignment: try container.decodeIfPresent(DocumentSelectionSourceAlignment.self, forKey: .sourceAlignment) ?? .blockContext,
            selectedTargetText: selectedTargetText,
            targetPrefix: try container.decodeIfPresent(String.self, forKey: .targetPrefix) ?? "",
            targetSuffix: try container.decodeIfPresent(String.self, forKey: .targetSuffix) ?? "",
            protectedTokens: try container.decodeIfPresent([String].self, forKey: .protectedTokens) ?? [],
            glossary: try container.decodeIfPresent([DocumentSelectionGlossaryHint].self, forKey: .glossary) ?? []
        )
    }
}

extension DocumentSelectionTranslationResponse {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: DocumentSelectionTranslationAnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        for key in raw.allKeys where !allowed.contains(key.stringValue) {
            throw DocumentSelectionTranslationContractError.unexpectedField(key.stringValue)
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let schema = try container.decodeIfPresent(String.self, forKey: .schema) else {
            throw DocumentSelectionTranslationContractError.missingField(CodingKeys.schema.stringValue)
        }
        guard let operationID = try container.decodeIfPresent(String.self, forKey: .operationID) else {
            throw DocumentSelectionTranslationContractError.missingField(CodingKeys.operationID.stringValue)
        }
        guard let replacementText = try container.decodeIfPresent(String.self, forKey: .replacementText) else {
            throw DocumentSelectionTranslationContractError.missingField(CodingKeys.replacementText.stringValue)
        }
        self.init(schema: schema, operationID: operationID, replacementText: replacementText)
    }
}
