import CryptoKit
import Foundation

/// Outcome of refreshing a document project's source file against a newly
/// imported manuscript (ADR-007 / S20).
public struct DocumentSourceRefreshResult: Equatable, Sendable {
    public var documentState: DocumentState
    public var matchedBlockCount: Int
    public var addedBlockCount: Int
    public var removedBlockCount: Int
    /// Plan indices that still need translation work after the refresh.
    public var changedChunkIndices: [Int]
    public var keptTranslationCount: Int

    public init(
        documentState: DocumentState,
        matchedBlockCount: Int,
        addedBlockCount: Int,
        removedBlockCount: Int,
        changedChunkIndices: [Int],
        keptTranslationCount: Int
    ) {
        self.documentState = documentState
        self.matchedBlockCount = matchedBlockCount
        self.addedBlockCount = addedBlockCount
        self.removedBlockCount = removedBlockCount
        self.changedChunkIndices = changedChunkIndices
        self.keptTranslationCount = keptTranslationCount
    }
}

/// Pure merge of a freshly imported document into an existing project document.
///
/// Blocks match by **text-only** identity (NFC + SHA-256 of joined span text).
/// DOCX `sourceHash` is intentionally not used for matching because it also
/// fingerprints formatting — a color-only upgrade must keep translations.
public enum DocumentSourceRefresh {
    /// Text-only identity used to match old↔new blocks.
    public static func textIdentity(for block: DocumentBlock) -> String {
        let text = block.spans.map(\.text).joined().precomposedStringWithCanonicalMapping
        return sha256(text)
    }

    /// Merge a freshly imported `new` document into the existing `old` one.
    ///
    /// Matching is a multiset by text identity, consuming old blocks in order.
    public static func merge(old: DocumentState, new newState: DocumentState) -> DocumentSourceRefreshResult {
        var oldIDsByText: [String: [String]] = [:]
        oldIDsByText.reserveCapacity(old.blocks.count)
        for block in old.blocks {
            oldIDsByText[textIdentity(for: block), default: []].append(block.id)
        }

        var mergedBlocks: [DocumentBlock] = []
        mergedBlocks.reserveCapacity(newState.blocks.count)
        var matchedOldIDs = Set<String>()
        var matchedBlockCount = 0
        var addedBlockCount = 0

        for newBlock in newState.blocks {
            let identity = textIdentity(for: newBlock)
            if var queue = oldIDsByText[identity], !queue.isEmpty {
                let oldID = queue.removeFirst()
                oldIDsByText[identity] = queue
                matchedOldIDs.insert(oldID)
                matchedBlockCount += 1
                var kept = newBlock
                kept.id = oldID
                mergedBlocks.append(kept)
            } else {
                addedBlockCount += 1
                mergedBlocks.append(newBlock)
            }
        }

        let removedBlockCount = old.blocks.count - matchedBlockCount

        var translationsByLanguage: [String: [String: TranslatedBlock]] = [:]
        var keptTranslationCount = 0
        for (language, map) in old.translationsByLanguage {
            var kept: [String: TranslatedBlock] = [:]
            for block in mergedBlocks {
                guard matchedOldIDs.contains(block.id),
                      var translation = map[block.id]
                else { continue }
                translation.id = block.id
                translation.sourceBlockID = block.id
                // Formatting-only refresh: realign hash so freshness stays clean.
                translation.sourceHash = block.sourceHash
                kept[block.id] = translation
                keptTranslationCount += 1
            }
            if !kept.isEmpty {
                translationsByLanguage[language] = kept
            }
        }

        var profile = newState.profile
        if profile.projectGlossary.isEmpty, !old.profile.projectGlossary.isEmpty {
            profile.projectGlossary = old.profile.projectGlossary
        }
        if profile.protectedTerms.isEmpty, !old.profile.protectedTerms.isEmpty {
            profile.protectedTerms = old.profile.protectedTerms
        }
        if profile.translatorNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !old.profile.translatorNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profile.translatorNotes = old.profile.translatorNotes
        }
        // Preserve the project's translation target when the import default differs.
        if !old.profile.targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profile.targetLanguage = old.profile.targetLanguage
        }

        var mergedState = DocumentState(
            format: newState.format,
            originalAsset: newState.originalAsset,
            metadata: newState.metadata,
            preflight: newState.preflight,
            blocks: mergedBlocks,
            chunks: [],
            translationsByLanguage: translationsByLanguage,
            outputs: newState.outputs,
            profile: profile
        )
        mergedState.preflight.blockCount = mergedBlocks.count
        let plans = SemanticChunkPlanner().plan(documentState: mergedState)
        mergedState.chunks = plans

        let languages = Set(old.translationsByLanguage.keys)
        var changedChunkIndices: [Int] = []
        if languages.isEmpty {
            changedChunkIndices = Array(plans.indices)
        } else {
            for (index, plan) in plans.enumerated() {
                let needsWork = languages.contains { language in
                    let map = translationsByLanguage[language] ?? [:]
                    return plan.blockIDs.contains { map[$0] == nil }
                }
                if needsWork {
                    changedChunkIndices.append(index)
                }
            }
        }

        return DocumentSourceRefreshResult(
            documentState: mergedState,
            matchedBlockCount: matchedBlockCount,
            addedBlockCount: addedBlockCount,
            removedBlockCount: removedBlockCount,
            changedChunkIndices: changedChunkIndices,
            keptTranslationCount: keptTranslationCount
        )
    }

    /// Rebuild session `ChunkData` rows from refreshed document plans.
    ///
    /// - Parameter preferredLanguageKey: archive key used for aggregate
    ///   `translated` text (usually the session target language).
    public static func rebuildSessionChunks(
        oldChunks: [ChunkData],
        documentState: DocumentState,
        sourceFilePath: String,
        preferredLanguageKey: String,
        changedChunkIndices: [Int]
    ) -> [ChunkData] {
        let changed = Set(changedChunkIndices)
        let blockByID = Dictionary(uniqueKeysWithValues: documentState.blocks.map { ($0.id, $0) })
        let preferredMap = documentState.translationsByLanguage[preferredLanguageKey] ?? [:]
        let languages = Array(documentState.translationsByLanguage.keys)

        return documentState.chunks.enumerated().map { index, plan in
            let blockTexts = plan.blockIDs.map { blockByID[$0]?.spans.map(\.text).joined() ?? "" }
            let original = blockTexts.joined(separator: "\n\n")
            let startID = plan.blockIDs.first ?? ""
            let endID = plan.blockIDs.last ?? startID
            let anchor = SourceAnchor.document(
                DocumentRange(startBlockID: startID, endBlockID: endID)
            )

            let translatedPieces = plan.blockIDs.compactMap { preferredMap[$0]?.text }
            let allPreferredPresent = !plan.blockIDs.isEmpty
                && translatedPieces.count == plan.blockIDs.count
            let translated = translatedPieces.joined(separator: "\n\n")

            let allPreferredApproved = allPreferredPresent
                && plan.blockIDs.allSatisfy { preferredMap[$0]?.reviewDisposition.isApproved == true }

            let hadAnyPriorTranslation = languages.contains { language in
                let map = documentState.translationsByLanguage[language] ?? [:]
                return plan.blockIDs.contains { map[$0] != nil }
            }

            let isChanged = changed.contains(index)
            let status: ChunkStatus
            let disposition: ReviewDisposition
            let approved: Bool
            if isChanged {
                status = allPreferredPresent ? .done : .pending
                disposition = hadAnyPriorTranslation && !allPreferredPresent
                    ? .needsReview
                    : (allPreferredApproved ? .manuallyApproved : .pending)
                approved = disposition.isApproved
            } else if allPreferredApproved {
                status = .done
                disposition = .manuallyApproved
                approved = true
            } else if allPreferredPresent {
                status = .done
                disposition = .pending
                approved = false
            } else {
                status = .pending
                disposition = .pending
                approved = false
            }

            // Preserve stable media timing fields from a prior row when present.
            let prior = oldChunks.indices.contains(index) ? oldChunks[index] : nil
            return ChunkData(
                index: index,
                filePath: sourceFilePath,
                durationSec: prior?.durationSec ?? 0,
                startSec: prior?.startSec ?? 0,
                endSec: prior?.endSec ?? 0,
                original: original,
                translated: translated,
                originalCues: nil,
                originalFormats: nil,
                translatedFormats: nil,
                translationsByLanguage: nil,
                unrecognizedFragments: nil,
                status: status,
                approved: approved,
                sourceAnchor: anchor,
                reviewDisposition: disposition,
                qualityReport: nil
            )
        }
    }

    private static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
