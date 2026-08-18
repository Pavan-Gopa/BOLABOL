import Foundation

/// Represents the active editor side in the document review workspace.
public enum DocumentEditorSide: String, Codable, Sendable {
    case source
    case translation
}

/// A selected fragment of rich text belonging to a specific block and span.
public struct DocumentTextFragment: Codable, Equatable, Sendable {
    public var blockID: String
    public var spanID: String?
    public var utf16RangeInSpan: NSRange
    public var text: String
    public var styleKey: String
    public var traits: Set<InlineTrait>
    public var translationPolicy: SpanTranslationPolicy
    public var foregroundColorHex: String?

    public init(
        blockID: String,
        spanID: String? = nil,
        utf16RangeInSpan: NSRange,
        text: String,
        styleKey: String = "",
        traits: Set<InlineTrait> = [],
        translationPolicy: SpanTranslationPolicy = .translate,
        foregroundColorHex: String? = nil
    ) {
        self.blockID = blockID
        self.spanID = spanID
        self.utf16RangeInSpan = utf16RangeInSpan
        self.text = text
        self.styleKey = styleKey
        self.traits = traits
        self.translationPolicy = translationPolicy
        self.foregroundColorHex = foregroundColorHex
    }
}

/// A complete snapshot of structural selection across one or more document blocks and spans.
public struct DocumentTextSelectionSnapshot: Codable, Equatable, Sendable {
    public var operationID: UUID
    public var side: DocumentEditorSide
    public var languageKey: String?
    public var chunkPlanID: String
    public var fragments: [DocumentTextFragment]
    public var selectedText: String
    public var blockHashes: [String: String]
    public var targetRevisionHash: String

    public init(
        operationID: UUID = UUID(),
        side: DocumentEditorSide,
        languageKey: String? = nil,
        chunkPlanID: String = "",
        fragments: [DocumentTextFragment] = [],
        selectedText: String = "",
        blockHashes: [String: String] = [:],
        targetRevisionHash: String = ""
    ) {
        self.operationID = operationID
        self.side = side
        self.languageKey = languageKey
        self.chunkPlanID = chunkPlanID
        self.fragments = fragments
        self.selectedText = selectedText
        self.blockHashes = blockHashes
        self.targetRevisionHash = targetRevisionHash
    }
}

/// Target UTF-16 range within a specific span.
public struct DocumentSpanRange: Codable, Equatable, Sendable {
    public var spanID: String
    public var utf16Range: NSRange

    public init(spanID: String, utf16Range: NSRange) {
        self.spanID = spanID
        self.utf16Range = utf16Range
    }

    public init(spanID: String, location: Int, length: Int) {
        self.spanID = spanID
        self.utf16Range = NSRange(location: location, length: length)
    }
}

/// User-applied formatting overrides on top of imported/base styles.
public struct EditorInlineOverrides: Codable, Equatable, Sendable {
    public var traitOverrides: [InlineTrait: Bool]
    public var foregroundColorOverride: String?
    public var clearsForegroundColor: Bool

    public var isEffectivelyEmpty: Bool {
        return traitOverrides.isEmpty && foregroundColorOverride == nil && !clearsForegroundColor
    }

    public init(
        traitOverrides: [InlineTrait: Bool] = [:],
        foregroundColorOverride: String? = nil,
        clearsForegroundColor: Bool = false
    ) {
        self.traitOverrides = traitOverrides
        self.foregroundColorOverride = foregroundColorOverride
        self.clearsForegroundColor = clearsForegroundColor
    }
}

/// Policy for formatting inheritance during replacement.
public enum ReplacementFormattingPolicy: String, Codable, CaseIterable, Sendable {
    case inheritExisting
    case plain
    case preserveIslands
}

/// Match location in a document for find-and-replace operations.
public struct DocumentTextMatch: Codable, Equatable, Sendable {
    public var side: DocumentEditorSide
    public var languageKey: String?
    public var blockID: String
    public var spanRanges: [DocumentSpanRange]
    public var matchedText: String
    public var protectedMatch: Bool

    public init(
        side: DocumentEditorSide,
        languageKey: String? = nil,
        blockID: String,
        spanRanges: [DocumentSpanRange],
        matchedText: String,
        protectedMatch: Bool = false
    ) {
        self.side = side
        self.languageKey = languageKey
        self.blockID = blockID
        self.spanRanges = spanRanges
        self.matchedText = matchedText
        self.protectedMatch = protectedMatch
    }
}

/// Result of a rich-text mutation operation over a sequence of spans.
public struct MutationResult: Equatable, Sendable {
    public var spans: [RichTextSpan]
    public var replacedCount: Int
    public var skippedProtectedCount: Int

    public init(
        spans: [RichTextSpan],
        replacedCount: Int = 0,
        skippedProtectedCount: Int = 0
    ) {
        self.spans = spans
        self.replacedCount = replacedCount
        self.skippedProtectedCount = skippedProtectedCount
    }
}
