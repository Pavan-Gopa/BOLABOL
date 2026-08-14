import Foundation

public enum WorkflowSourceKind: String, Codable, Equatable, Sendable {
    case media
    case document
}

/// The Config controls that are meaningful for a source kind.
///
/// Keeping this policy in the core module lets the app render a document-only
/// surface without introducing a second, user-selectable workflow mode.
public struct WorkflowConfigPolicy: Equatable, Sendable {
    public let showsAudioMetadata: Bool
    public let showsTranscriptionModel: Bool
    public let showsChunkDuration: Bool
    public let showsSliceMode: Bool
    public let showsDocumentMetadata: Bool
    public let sourceLanguageIsFixedAuto: Bool

    public init(sourceKind: WorkflowSourceKind) {
        let isDocument = sourceKind == .document
        self.showsAudioMetadata = !isDocument
        self.showsTranscriptionModel = !isDocument
        self.showsChunkDuration = !isDocument
        self.showsSliceMode = !isDocument
        self.showsDocumentMetadata = isDocument
        self.sourceLanguageIsFixedAuto = isDocument
    }
}

public struct DocumentRange: Codable, Equatable, Sendable {
    public var startBlockID: String
    public var endBlockID: String
    public var startOffset: Int?
    public var endOffset: Int?

    public init(
        startBlockID: String,
        endBlockID: String,
        startOffset: Int? = nil,
        endOffset: Int? = nil
    ) {
        self.startBlockID = startBlockID
        self.endBlockID = endBlockID
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
}

public enum SourceAnchor: Codable, Equatable, Sendable {
    case media(startSec: Double, endSec: Double)
    case document(DocumentRange)

    private enum CodingKeys: String, CodingKey {
        case kind
        case startSec
        case endSec
        case range
        case media
        case document
    }

    private struct MediaPayload: Codable {
        var startSec: Double
        var endSec: Double
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let kind = try container.decodeIfPresent(String.self, forKey: .kind) {
            switch kind {
            case "media":
                self = .media(
                    startSec: try container.decode(Double.self, forKey: .startSec),
                    endSec: try container.decode(Double.self, forKey: .endSec)
                )
            case "document":
                self = .document(try container.decode(DocumentRange.self, forKey: .range))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .kind,
                    in: container,
                    debugDescription: "Unknown source anchor kind: \(kind)"
                )
            }
            return
        }

        // Support both the explicit v4 shape and the synthesized associated
        // value shape used by a few early Slice 1 fixtures.
        if let mediaPayload = try container.decodeIfPresent(MediaPayload.self, forKey: .media) {
            self = .media(startSec: mediaPayload.startSec, endSec: mediaPayload.endSec)
            return
        }
        if let range = try container.decodeIfPresent(DocumentRange.self, forKey: .document) {
            self = .document(range)
            return
        }
        if let startSec = try container.decodeIfPresent(Double.self, forKey: .startSec),
           let endSec = try container.decodeIfPresent(Double.self, forKey: .endSec) {
            self = .media(startSec: startSec, endSec: endSec)
            return
        }
        if let range = try container.decodeIfPresent(DocumentRange.self, forKey: .range) {
            self = .document(range)
            return
        }
        throw DecodingError.dataCorruptedError(
            forKey: .range,
            in: container,
            debugDescription: "Source anchor is missing a media payload or document range"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .media(startSec, endSec):
            try container.encode("media", forKey: .kind)
            try container.encode(startSec, forKey: .startSec)
            try container.encode(endSec, forKey: .endSec)
        case let .document(range):
            try container.encode("document", forKey: .kind)
            try container.encode(range, forKey: .range)
        }
    }
}


public enum DocumentFormat: String, Codable, CaseIterable, Equatable, Sendable {
    case docx = "docx"
    case pdf = "pdf"
    case txt = "txt"
    case markdown = "markdown"
    case rtf = "rtf"
}

public enum DocumentOutputFormat: String, Codable, CaseIterable, Equatable, Sendable {
    case docx = "DOCX"
    case txt = "TXT"
    case markdown = "Markdown"
    case pdf = "PDF"
}

public enum DocumentPart: String, Codable, CaseIterable, Equatable, Sendable {
    case mainBody
    case header
    case footer
    case footnote
    case endnote
    case textBox
}

public enum DocumentBlockKind: String, Codable, CaseIterable, Equatable, Sendable {
    case paragraph
    case heading
    case quote
    case verse
    case listItem
    case table
    case tableRow
    case empty
    case other
}

public enum BlockTranslationPolicy: String, Codable, CaseIterable, Equatable, Sendable {
    case translate
    case protect
    case translateWithGlossary
    case editorApproved
}

public enum SpanTranslationPolicy: String, Codable, CaseIterable, Equatable, Sendable {
    case translate
    case protect
    case translateWithGlossary
}

public enum InlineTrait: String, Codable, CaseIterable, Hashable, Sendable {
    case bold
    case italic
    case underline
    case strikethrough
    case superscript
    case subscriptText
    case smallCaps
}

public struct DocumentMetadata: Codable, Equatable, Sendable {
    public var title: String?
    public var author: String?
    public var subject: String?
    public var language: String?
    public var createdAt: String?
    public var modifiedAt: String?
    public var customProperties: [String: String]

    public init(
        title: String? = nil,
        author: String? = nil,
        subject: String? = nil,
        language: String? = nil,
        createdAt: String? = nil,
        modifiedAt: String? = nil,
        customProperties: [String: String] = [:]
    ) {
        self.title = title
        self.author = author
        self.subject = subject
        self.language = language
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.customProperties = customProperties
    }
}

public struct ProjectAssetReference: Codable, Equatable, Sendable {
    public var key: String
    public var originalFileName: String
    public var role: ProjectAssetRole
    public var format: String
    public var sha256: String?
    public var size: Int64?

    public init(
        key: String,
        originalFileName: String = "",
        role: ProjectAssetRole = .originalSource,
        format: String = "",
        sha256: String? = nil,
        size: Int64? = nil
    ) {
        self.key = key
        self.originalFileName = originalFileName
        self.role = role
        self.format = format
        self.sha256 = sha256
        self.size = size
    }
}

public struct RichTextSpan: Codable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var styleKey: String
    public var traits: Set<InlineTrait>
    public var translationPolicy: SpanTranslationPolicy

    public init(
        id: String,
        text: String,
        styleKey: String = "",
        traits: Set<InlineTrait> = [],
        translationPolicy: SpanTranslationPolicy = .translate
    ) {
        self.id = id
        self.text = text
        self.styleKey = styleKey
        self.traits = traits
        self.translationPolicy = translationPolicy
    }
}

public struct DocumentLocation: Codable, Equatable, Sendable {
    public var part: DocumentPart
    public var paragraphOrdinal: Int
    public var tablePath: [Int]?
    public var xmlPath: String

    public init(
        part: DocumentPart = .mainBody,
        paragraphOrdinal: Int,
        tablePath: [Int]? = nil,
        xmlPath: String = ""
    ) {
        self.part = part
        self.paragraphOrdinal = paragraphOrdinal
        self.tablePath = tablePath
        self.xmlPath = xmlPath
    }
}

public struct DocumentBlock: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var location: DocumentLocation
    public var kind: DocumentBlockKind
    public var styleID: String?
    public var paragraphPropertiesFingerprint: String
    public var spans: [RichTextSpan]
    public var sourceHash: String
    public var translationPolicy: BlockTranslationPolicy

    public init(
        id: String,
        location: DocumentLocation,
        kind: DocumentBlockKind = .paragraph,
        styleID: String? = nil,
        paragraphPropertiesFingerprint: String = "",
        spans: [RichTextSpan] = [],
        sourceHash: String = "",
        translationPolicy: BlockTranslationPolicy = .translate
    ) {
        self.id = id
        self.location = location
        self.kind = kind
        self.styleID = styleID
        self.paragraphPropertiesFingerprint = paragraphPropertiesFingerprint
        self.spans = spans
        self.sourceHash = sourceHash
        self.translationPolicy = translationPolicy
    }
}

/// A range into one oversized source block when the planner has to use its
/// sentence/word fallback. Normal chunks keep this nil and remain block-atomic.
public struct DocumentBlockSlice: Codable, Equatable, Sendable {
    public var blockID: String
    public var startOffset: Int
    public var endOffset: Int

    public init(blockID: String, startOffset: Int = 0, endOffset: Int? = nil) {
        self.blockID = blockID
        self.startOffset = max(0, startOffset)
        self.endOffset = max(self.startOffset, endOffset ?? Int.max)
    }
}

public struct DocumentChunkPlan: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var blockIDs: [String]
    public var sourceTokenEstimate: Int
    public var contextBeforeBlockIDs: [String]
    public var contextAfterBlockIDs: [String]
    public var sourceHash: String
    public var blockSlices: [DocumentBlockSlice]?

    public init(
        id: String,
        blockIDs: [String] = [],
        sourceTokenEstimate: Int = 0,
        contextBeforeBlockIDs: [String] = [],
        contextAfterBlockIDs: [String] = [],
        sourceHash: String = "",
        blockSlices: [DocumentBlockSlice]? = nil
    ) {
        self.id = id
        self.blockIDs = blockIDs
        self.sourceTokenEstimate = sourceTokenEstimate
        self.contextBeforeBlockIDs = contextBeforeBlockIDs
        self.contextAfterBlockIDs = contextAfterBlockIDs
        self.sourceHash = sourceHash
        self.blockSlices = blockSlices
    }
}


public struct TranslatedBlock: Codable, Equatable, Sendable {
    public var id: String
    public var sourceBlockID: String
    public var text: String
    public var spans: [RichTextSpan]
    public var sourceHash: String
    public var reviewDisposition: ReviewDisposition
    public var qualityReport: ChunkQualityReport?

    public var blockID: String {
        get { sourceBlockID }
        set { sourceBlockID = newValue }
    }

    public init(
        id: String,
        sourceBlockID: String,
        text: String = "",
        spans: [RichTextSpan] = [],
        sourceHash: String = "",
        reviewDisposition: ReviewDisposition = .pending,
        qualityReport: ChunkQualityReport? = nil
    ) {
        self.id = id
        self.sourceBlockID = sourceBlockID
        self.text = text
        self.spans = spans
        self.sourceHash = sourceHash
        self.reviewDisposition = reviewDisposition
        self.qualityReport = qualityReport
    }

    public init(
        id: String,
        blockID: String,
        text: String = "",
        spans: [RichTextSpan] = [],
        sourceHash: String = "",
        reviewDisposition: ReviewDisposition = .pending,
        qualityReport: ChunkQualityReport? = nil
    ) {
        self.init(
            id: id,
            sourceBlockID: blockID,
            text: text,
            spans: spans,
            sourceHash: sourceHash,
            reviewDisposition: reviewDisposition,
            qualityReport: qualityReport
        )
    }
}

public struct DocumentOutputAsset: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var key: String
    public var format: DocumentOutputFormat
    public var language: String?
    public var originalFileName: String
    public var sha256: String?
    public var size: Int64?

    public init(
        id: String,
        key: String,
        format: DocumentOutputFormat,
        language: String? = nil,
        originalFileName: String = "",
        sha256: String? = nil,
        size: Int64? = nil
    ) {
        self.id = id
        self.key = key
        self.format = format
        self.language = language
        self.originalFileName = originalFileName
        self.sha256 = sha256
        self.size = size
    }
}

public struct DocumentState: Codable, Equatable, Sendable {
    public var format: DocumentFormat
    public var originalAsset: ProjectAssetReference
    public var metadata: DocumentMetadata
    public var blocks: [DocumentBlock]
    public var chunks: [DocumentChunkPlan]
    public var translationsByLanguage: [String: [String: TranslatedBlock]]
    public var outputs: [DocumentOutputAsset]
    public var profile: DocumentTranslationProfile

    public init(
        format: DocumentFormat = .docx,
        originalAsset: ProjectAssetReference = ProjectAssetReference(key: "originalSource"),
        metadata: DocumentMetadata = DocumentMetadata(),
        blocks: [DocumentBlock] = [],
        chunks: [DocumentChunkPlan] = [],
        translationsByLanguage: [String: [String: TranslatedBlock]] = [:],
        outputs: [DocumentOutputAsset] = [],
        profile: DocumentTranslationProfile = .default
    ) {
        self.format = format
        self.originalAsset = originalAsset
        self.metadata = metadata
        self.blocks = blocks
        self.chunks = chunks
        self.translationsByLanguage = translationsByLanguage
        self.outputs = outputs
        self.profile = profile
    }
}
