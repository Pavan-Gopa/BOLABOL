import Foundation

/// The versioned wire contract used for literary document translation.
public enum DocumentTranslationContract {
    public static let schema = "vaniscript.document.translation.v1"
    public static let validatorVersion = 1

    /// The response object shape shown to providers. Concrete IDs and styles
    /// are supplied by the selected request so a provider never has to infer
    /// VaniScript's private contract from prose.
    public static func canonicalResponseTemplate(
        chunkID: String,
        blockIDs: [String],
        styleIDs: [String]
    ) -> String {
        let blockID = blockIDs.first ?? "required-block-id"
        let styleID = styleIDs.first ?? "plain"
        return """
        {
          "schema": "\(schema)",
          "chunkId": "\(chunkID)",
          "blocks": [
            {
              "id": "\(blockID)",
              "spans": [
                {
                  "id": "optional-span-id",
                  "style": "\(styleID)",
                  "text": "translated text"
                }
              ]
            }
          ]
        }
        """
    }
}

public struct DocumentTranslationInputSpan: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var style: String
    public var text: String
    public var translationPolicy: SpanTranslationPolicy

    public var styleID: String { style }

    public init(
        id: String = UUID().uuidString,
        style: String = "plain",
        text: String,
        translationPolicy: SpanTranslationPolicy = .translate
    ) {
        self.id = id
        self.style = style
        self.text = text
        self.translationPolicy = translationPolicy
    }

    public init(
        id: String = UUID().uuidString,
        styleID: String,
        text: String,
        translationPolicy: SpanTranslationPolicy = .translate
    ) {
        self.init(id: id, style: styleID, text: text, translationPolicy: translationPolicy)
    }
}

public struct DocumentTranslationInputBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var role: DocumentBlockKind
    public var sourceText: String
    public var spans: [DocumentTranslationInputSpan]
    public var translationPolicy: BlockTranslationPolicy

    public var styleIDs: [String] {
        spans.map(\.style)
    }

    public init(
        id: String,
        role: DocumentBlockKind = .paragraph,
        sourceText: String? = nil,
        spans: [DocumentTranslationInputSpan] = [],
        translationPolicy: BlockTranslationPolicy = .translate
    ) {
        self.id = id
        self.role = role
        let resolvedText = sourceText ?? spans.map(\.text).joined()
        self.spans = spans.isEmpty && !resolvedText.isEmpty
            ? [DocumentTranslationInputSpan(text: resolvedText)]
            : spans
        self.sourceText = resolvedText
        self.translationPolicy = translationPolicy
    }

    public init(block: DocumentBlock) {
        self.init(
            id: block.id,
            role: block.kind,
            sourceText: block.spans.map(\.text).joined(),
            spans: block.spans.map {
                DocumentTranslationInputSpan(
                    id: $0.id,
                    style: $0.styleKey.isEmpty ? "plain" : $0.styleKey,
                    text: $0.text,
                    translationPolicy: $0.translationPolicy
                )
            },
            translationPolicy: block.translationPolicy
        )
    }
}

public struct DocumentTranslationContextBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var style: String?
    public var isReadOnly: Bool

    public init(id: String, text: String, style: String? = nil, isReadOnly: Bool = true) {
        self.id = id
        self.text = text
        self.style = style
        self.isReadOnly = isReadOnly
    }
}
public struct DocumentTranslationMemory: Codable, Equatable, Sendable {
    public var glossary: [GlossaryEntry]
    public var protectedTerms: [String]
    public var voiceRules: [String]
    public var recentApprovedBlocks: [DocumentTranslationMemoryBlock]
    public var chapterContext: String
    public var modelVersion: String
    public var promptVersion: String

    public init(
        glossary: [GlossaryEntry] = [],
        protectedTerms: [String] = [],
        voiceRules: [String] = [],
        recentApprovedBlocks: [DocumentTranslationMemoryBlock] = [],
        chapterContext: String = "",
        modelVersion: String = "",
        promptVersion: String = DocumentTranslationContract.schema
    ) {
        self.glossary = glossary
        self.protectedTerms = protectedTerms
        self.voiceRules = voiceRules
        self.recentApprovedBlocks = recentApprovedBlocks
        self.chapterContext = chapterContext
        self.modelVersion = modelVersion
        self.promptVersion = promptVersion
    }
}

public struct DocumentTranslationMemoryBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var source: String
    public var target: String

    public init(id: String, source: String, target: String) {
        self.id = id
        self.source = source
        self.target = target
    }
}

public struct DocumentTranslationRequest: Codable, Equatable, Sendable {
    public var schema: String
    public var chunkId: String
    public var sourceLanguage: String
    public var targetLanguage: String
    public var profile: DocumentTranslationProfile
    public var protectedTokens: [String]
    public var knownStyleIDs: [String]
    public var readOnlyContextBefore: [DocumentTranslationContextBlock]
    public var readOnlyContextAfter: [DocumentTranslationContextBlock]
    public var blocks: [DocumentTranslationInputBlock]
    public var memory: DocumentTranslationMemory?
    public var repair: DocumentTranslationRepairRequest?

    public init(
        schema: String = DocumentTranslationContract.schema,
        chunkId: String,
        sourceLanguage: String = "auto",
        targetLanguage: String,
        profile: DocumentTranslationProfile = .default,
        protectedTokens: [String] = [],
        knownStyleIDs: [String] = [],
        readOnlyContextBefore: [DocumentTranslationContextBlock] = [],
        readOnlyContextAfter: [DocumentTranslationContextBlock] = [],
        blocks: [DocumentTranslationInputBlock],
        memory: DocumentTranslationMemory? = nil,
        repair: DocumentTranslationRepairRequest? = nil
    ) {
        self.schema = schema
        self.chunkId = chunkId
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.profile = profile
        self.protectedTokens = protectedTokens
        self.knownStyleIDs = knownStyleIDs.isEmpty
            ? Array(Set(blocks.flatMap(\.styleIDs))).sorted()
            : knownStyleIDs
        self.readOnlyContextBefore = readOnlyContextBefore
        self.readOnlyContextAfter = readOnlyContextAfter
        self.blocks = blocks
        self.memory = memory
        self.repair = repair
    }

    public init(
        chunkId: String,
        targetLanguage: String,
        blocks: [DocumentTranslationInputBlock],
        knownStyleIDs: [String] = []
    ) {
        self.init(
            chunkId: chunkId,
            targetLanguage: targetLanguage,
            knownStyleIDs: knownStyleIDs,
            blocks: blocks
        )
    }

    public var expectedBlockIDs: [String] { blocks.map(\.id) }

    public var expectedStyleIDs: Set<String> {
        Set(knownStyleIDs + blocks.flatMap(\.styleIDs))
    }

    /// Blocks with no translatable source are completed locally. Keeping this
    /// distinction on the request lets the provider see only work that needs
    /// language generation while the validator still checks the full chunk.
    public var deterministicBlocks: [DocumentTranslationInputBlock] {
        blocks.filter(Self.isDeterministic)
    }

    /// The provider-facing subset for an initial translation request.
    public var translatableBlocks: [DocumentTranslationInputBlock] {
        blocks.filter { !Self.isDeterministic($0) }
    }

    public var deterministicBlockIDs: [String] {
        deterministicBlocks.map(\.id)
    }

    public var translatableBlockIDs: [String] {
        translatableBlocks.map(\.id)
    }

    public static func isDeterministic(_ block: DocumentTranslationInputBlock) -> Bool {
        block.translationPolicy == .protect
            || block.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func block(id: String) -> DocumentTranslationInputBlock? {
        blocks.first { $0.id == id }
    }
}

public struct DocumentTranslationRepairRequest: Codable, Equatable, Sendable {
    public var blockIDs: [String]
    public var sourceBlocks: [DocumentTranslationInputBlock]
    public var previousCandidate: [DocumentTranslationOutputBlock]
    public var issues: [QualityIssue]

    public init(
        blockIDs: [String],
        sourceBlocks: [DocumentTranslationInputBlock] = [],
        previousCandidate: [DocumentTranslationOutputBlock] = [],
        issues: [QualityIssue] = []
    ) {
        self.blockIDs = blockIDs
        self.sourceBlocks = sourceBlocks
        self.previousCandidate = previousCandidate
        self.issues = issues
    }
}

public struct DocumentTranslationOutputSpan: Codable, Equatable, Sendable, Identifiable {
    public var id: String?
    public var style: String
    public var text: String

    public var styleID: String { style }

    public init(id: String? = nil, style: String = "plain", text: String) {
        self.id = id
        self.style = style
        self.text = text
    }

    public init(id: String? = nil, styleID: String, text: String) {
        self.init(id: id, style: styleID, text: text)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case id, style, text }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: DocumentTranslationAnyCodingKey.self)
        for key in raw.allKeys where !CodingKeys.allCases.contains(where: { $0.stringValue == key.stringValue }) {
            throw DocumentTranslationContractError.unexpectedField(key.stringValue)
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.style = try container.decode(String.self, forKey: .style)
        self.text = try container.decode(String.self, forKey: .text)
    }
}

public struct DocumentTranslationOutputBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var spans: [DocumentTranslationOutputSpan]

    public var text: String { spans.map(\.text).joined() }

    public init(id: String, spans: [DocumentTranslationOutputSpan]) {
        self.id = id
        self.spans = spans
    }

    public init(id: String, text: String, style: String = "plain") {
        self.init(id: id, spans: [DocumentTranslationOutputSpan(style: style, text: text)])
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case id, spans, text }
    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: DocumentTranslationAnyCodingKey.self)
        for key in raw.allKeys where !CodingKeys.allCases.contains(where: { $0.stringValue == key.stringValue }) {
            throw DocumentTranslationContractError.unexpectedField(key.stringValue)
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        if let spans = try container.decodeIfPresent([DocumentTranslationOutputSpan].self, forKey: .spans) {
            self.spans = spans
        } else if let text = try container.decodeIfPresent(String.self, forKey: .text) {
            self.spans = [DocumentTranslationOutputSpan(text: text)]
        } else {
            throw DocumentTranslationContractError.missingField("blocks[].spans")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(spans, forKey: .spans)
    }

    private static func rejectUnknownKeys<K: CodingKey>(_ container: KeyedDecodingContainer<K>, allowed: Set<K>) throws {
        for key in container.allKeys where !allowed.contains(key) {
            throw DocumentTranslationContractError.unexpectedField(key.stringValue)
        }
    }
}

public struct DocumentTranslationResponse: Codable, Equatable, Sendable {
    public var schema: String
    public var chunkId: String
    public var blocks: [DocumentTranslationOutputBlock]

    public init(
        schema: String = DocumentTranslationContract.schema,
        chunkId: String,
        blocks: [DocumentTranslationOutputBlock]
    ) {
        self.schema = schema
        self.chunkId = chunkId
        self.blocks = blocks
    }

    public var blockIDs: [String] { blocks.map(\.id) }
    public var text: String { blocks.map(\.text).joined(separator: "\n\n") }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schema, chunkId, blocks }
    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: DocumentTranslationAnyCodingKey.self)
        for key in raw.allKeys where !CodingKeys.allCases.contains(where: { $0.stringValue == key.stringValue }) {
            throw DocumentTranslationContractError.unexpectedField(key.stringValue)
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schema = try container.decode(String.self, forKey: .schema)
        self.chunkId = try container.decode(String.self, forKey: .chunkId)
        self.blocks = try container.decode([DocumentTranslationOutputBlock].self, forKey: .blocks)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(chunkId, forKey: .chunkId)
        try container.encode(blocks, forKey: .blocks)
    }

    private static func rejectUnknownKeys<K: CodingKey>(_ container: KeyedDecodingContainer<K>, allowed: Set<K>) throws {
        for key in container.allKeys where !allowed.contains(key) {
            throw DocumentTranslationContractError.unexpectedField(key.stringValue)
        }
    }
}


private struct DocumentTranslationAnyCodingKey: CodingKey {
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

public enum DocumentTranslationContractError: LocalizedError, Equatable, Sendable {
    case missingField(String)
    case unexpectedField(String)
    case invalidJSON

    public var errorDescription: String? {
        switch self {
        case let .missingField(field): "Missing required document translation field: \(field)."
        case let .unexpectedField(field): "Unexpected document translation field: \(field)."
        case .invalidJSON: "The document translation response is not valid JSON."
        }
    }
}

public extension DocumentTranslationResponse {
    static func decodeStrict(_ data: Data) throws -> DocumentTranslationResponse {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(DocumentTranslationResponse.self, from: data)
        } catch let error as DocumentTranslationContractError {
            throw error
        } catch {
            throw DocumentTranslationContractError.invalidJSON
        }
    }
}
