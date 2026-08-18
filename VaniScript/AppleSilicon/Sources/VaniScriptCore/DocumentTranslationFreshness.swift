import Foundation

/// Freshness of a translation relative to its source block, derived purely
/// from the already-persisted `sourceHash` values (PRD §9.1, INV-5).
///
/// No additional persisted state is required: a translation is fresh exactly
/// when it was produced from the source text the block currently holds.
public enum TranslationFreshness: String, Codable, CaseIterable, Equatable, Sendable {
    /// No translation exists for the block in the given language.
    case missing
    /// The translation was produced from the block's current source text.
    case fresh
    /// The source text changed after the translation was produced; the
    /// previous translation is kept and needs review (ADR-E5).
    case stale
}

public extension TranslationFreshness {
    /// Derive freshness for one source/translation pair.
    ///
    /// - `missing` when there is no translated block.
    /// - `fresh` when both hashes are non-empty and equal.
    /// - `stale` otherwise (hash mismatch, or an empty hash that cannot prove
    ///   the translation matches the current source text).
    static func derive(sourceBlock: DocumentBlock?, translatedBlock: TranslatedBlock?) -> TranslationFreshness {
        guard let translatedBlock else { return .missing }
        guard let sourceBlock else { return .stale }
        guard !sourceBlock.sourceHash.isEmpty,
              !translatedBlock.sourceHash.isEmpty,
              translatedBlock.sourceHash == sourceBlock.sourceHash
        else { return .stale }
        return .fresh
    }

    /// Convenience for a whole document state: freshness of the translation
    /// stored under `languageKey` for `blockID`.
    static func derive(
        documentState: DocumentState,
        blockID: String,
        languageKey: String
    ) -> TranslationFreshness {
        derive(
            sourceBlock: documentState.blocks.first(where: { $0.id == blockID }),
            translatedBlock: documentState.translationsByLanguage[languageKey]?[blockID]
        )
    }
}

public extension TranslationFreshness {
    /// Provably stale: both hashes present and different. Unlike `derive`,
    /// empty hashes are NOT stale — legacy/hashless blocks cannot prove
    /// staleness and must not block approval, the banner, or export.
    static func isProvablyStale(
        documentState: DocumentState,
        blockID: String,
        languageKey: String
    ) -> Bool {
        guard let source = documentState.blocks.first(where: { $0.id == blockID }),
              let translated = documentState.translationsByLanguage[languageKey]?[blockID]
        else { return false }
        return !source.sourceHash.isEmpty
            && !translated.sourceHash.isEmpty
            && source.sourceHash != translated.sourceHash
    }
}
