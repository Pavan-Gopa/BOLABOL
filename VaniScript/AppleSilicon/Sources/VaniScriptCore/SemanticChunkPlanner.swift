import CryptoKit
import Foundation

/// Inputs that make a semantic plan reproducible across runs and machines.
public struct SemanticChunkPlannerConfiguration: Equatable, Sendable {
    public var capabilities: TranslationModelCapabilities
    public var budgetConfiguration: TranslationBudgetConfiguration
    public var modelID: String
    public var promptVersion: String
    public var contextBeforeBlockCount: Int
    public var contextAfterBlockCount: Int

    public init(
        capabilities: TranslationModelCapabilities = .cloudDefault,
        budgetConfiguration: TranslationBudgetConfiguration = .literaryDefault,
        modelID: String? = nil,
        promptVersion: String = "document-semantic-v1",
        contextBeforeBlockCount: Int = 2,
        contextAfterBlockCount: Int = 1
    ) {
        self.capabilities = capabilities
        self.budgetConfiguration = budgetConfiguration
        self.modelID = modelID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? modelID!
            : capabilities.modelID
        self.promptVersion = promptVersion
        self.contextBeforeBlockCount = max(0, contextBeforeBlockCount)
        self.contextAfterBlockCount = max(0, contextAfterBlockCount)
    }

    public static let cloudDefault = SemanticChunkPlannerConfiguration()
}

/// Groups document blocks into bounded semantic requests without treating a
/// paragraph as a string window. Chapter boundaries, quote/verse groups, and
/// blank output blocks are handled before token-budget packing.
public struct SemanticChunkPlanner: Sendable {
    public typealias Configuration = SemanticChunkPlannerConfiguration

    public let configuration: SemanticChunkPlannerConfiguration
    private let budgetPlanner: TranslationBudgetPlanner

    public init(configuration: SemanticChunkPlannerConfiguration = .cloudDefault) {
        self.configuration = configuration
        self.budgetPlanner = TranslationBudgetPlanner(
            capabilities: configuration.capabilities,
            configuration: configuration.budgetConfiguration
        )
    }

    public func plan(
        blocks: [DocumentBlock],
        profile: DocumentTranslationProfile
    ) -> [DocumentChunkPlan] {
        guard !blocks.isEmpty else { return [] }

        let hardLimit = budgetPlanner.budget(forSourceTokenEstimate: 1).hardSourceTokenLimit
        let softTarget = budgetPlanner.budget(forSourceTokenEstimate: 1).softSourceTokenTarget
        let atoms = semanticAtoms(from: blocks, hardLimit: hardLimit)
        let packed = pack(atoms, hardLimit: hardLimit, softTarget: softTarget)
        return makePlans(packed, blocks: blocks, profile: profile)
    }

    public func plan(documentState: DocumentState) -> [DocumentChunkPlan] {
        plan(blocks: documentState.blocks, profile: documentState.profile)
    }

    public static func plan(
        blocks: [DocumentBlock],
        profile: DocumentTranslationProfile,
        configuration: SemanticChunkPlannerConfiguration = .cloudDefault
    ) -> [DocumentChunkPlan] {
        SemanticChunkPlanner(configuration: configuration).plan(blocks: blocks, profile: profile)
    }
    
    public static func plan(
        blocks: [DocumentBlock],
        profile: DocumentTranslationProfile,
        capabilities: TranslationModelCapabilities,
        budgetConfiguration: TranslationBudgetConfiguration = .literaryDefault,
        modelID: String? = nil,
        promptVersion: String = "document-semantic-v1"
    ) -> [DocumentChunkPlan] {
        SemanticChunkPlanner(
            capabilities: capabilities,
            budgetConfiguration: budgetConfiguration,
            modelID: modelID,
            promptVersion: promptVersion
        ).plan(blocks: blocks, profile: profile)
    }

    public static func plan(
        documentState: DocumentState,
        configuration: SemanticChunkPlannerConfiguration = .cloudDefault
    ) -> [DocumentChunkPlan] {
        SemanticChunkPlanner(configuration: configuration).plan(documentState: documentState)
    }
    
    public init(
        capabilities: TranslationModelCapabilities,
        budgetConfiguration: TranslationBudgetConfiguration = .literaryDefault,
        modelID: String? = nil,
        promptVersion: String = "document-semantic-v1",
        contextBeforeBlockCount: Int = 2,
        contextAfterBlockCount: Int = 1
    ) {
        self.init(configuration: SemanticChunkPlannerConfiguration(
            capabilities: capabilities,
            budgetConfiguration: budgetConfiguration,
            modelID: modelID,
            promptVersion: promptVersion,
            contextBeforeBlockCount: contextBeforeBlockCount,
            contextAfterBlockCount: contextAfterBlockCount
        ))
    }

    private struct Atom: Sendable {
        var blockIDs: [String]
        var blockSlices: [DocumentBlockSlice]?
        var text: String
        var sourceTokenEstimate: Int
        var isAtomic: Bool
        var startsNewChapter: Bool = false

        var isBlank: Bool {
            sourceTokenEstimate == 0 && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func semanticAtoms(from blocks: [DocumentBlock], hardLimit: Int) -> [Atom] {
        var atoms: [Atom] = []
        var index = 0
        var pendingChapterPrefix: [DocumentBlock] = []

        while index < blocks.count {
            let block = blocks[index]
            if isChapterTitle(block) {
                // A chapter heading cannot be packed with the preceding chapter.
                atoms.append(contentsOf: pendingChapterPrefixAtoms())
                pendingChapterPrefix.removeAll(keepingCapacity: true)
                pendingChapterPrefix.append(block)
                index += 1

                // Preserve typographic spacing between a chapter title and its
                // first text block without spending model budget on the blanks.
                while index < blocks.count, isBlank(blocks[index]) {
                    pendingChapterPrefix.append(blocks[index])
                    index += 1
                }

                if index == blocks.count || isChapterTitle(blocks[index]) {
                    atoms.append(contentsOf: pendingChapterPrefixAtoms())
                    pendingChapterPrefix.removeAll(keepingCapacity: true)
                    continue
                }
                let prefixTokenEstimate = pendingChapterPrefix.reduce(0) {
                    $0 + budgetPlanner.estimateTokens(blockText($1))
                }
                let bodyLimit = max(1, hardLimit - prefixTokenEstimate)
                let (nextAtoms, nextIndex) = atomsStarting(at: index, blocks: blocks, hardLimit: bodyLimit)
                if !nextAtoms.isEmpty {
                    var prefixed = nextAtoms
                    prefixed[0] = prepend(pendingChapterPrefix, to: prefixed[0])
                    atoms.append(contentsOf: prefixed)
                    pendingChapterPrefix.removeAll(keepingCapacity: true)
                    index = nextIndex
                } else {
                    atoms.append(contentsOf: pendingChapterPrefixAtoms())
                    pendingChapterPrefix.removeAll(keepingCapacity: true)
                }
                continue
            }

            let (nextAtoms, nextIndex) = atomsStarting(at: index, blocks: blocks, hardLimit: hardLimit)
            atoms.append(contentsOf: nextAtoms)
            index = nextIndex
        }

        atoms.append(contentsOf: pendingChapterPrefixAtoms())
        return atoms

        func pendingChapterPrefixAtoms() -> [Atom] {
            guard !pendingChapterPrefix.isEmpty else { return [] }
            let text = pendingChapterPrefix.map(blockText).joined(separator: "\n\n")
            return [Atom(
                blockIDs: pendingChapterPrefix.map(\.id),
                blockSlices: nil,
                text: text,
                sourceTokenEstimate: pendingChapterPrefix.reduce(0) { $0 + budgetPlanner.estimateTokens(blockText($1)) },
                isAtomic: true,
                startsNewChapter: true
            )]
        }
    }

    private func atomsStarting(
        at start: Int,
        blocks: [DocumentBlock],
        hardLimit: Int
    ) -> ([Atom], Int) {
        guard blocks.indices.contains(start) else { return ([], start) }
        let block = blocks[start]

        if isBlank(block) {
            let text = blockText(block)
            return ([Atom(
                blockIDs: [block.id],
                blockSlices: nil,
                text: text,
                sourceTokenEstimate: 0,
                isAtomic: true
            )], start + 1)
        }

        if isVerseIntroduction(block), blocks.indices.contains(start + 1), isQuoteOrVerse(blocks[start + 1]) {
            var group = [block]
            var index = start + 1
            while blocks.indices.contains(index), isQuoteOrVerse(blocks[index]) {
                group.append(blocks[index])
                index += 1
            }
            let text = group.map(blockText).joined(separator: "\n\n")
            return ([Atom(
                blockIDs: group.map(\.id),
                blockSlices: nil,
                text: text,
                sourceTokenEstimate: budgetPlanner.estimateTokens(text),
                isAtomic: true
            )], index)
        }

        if isQuoteOrVerse(block) {
            var quoteBlocks: [DocumentBlock] = []
            var index = start
            while blocks.indices.contains(index), isQuoteOrVerse(blocks[index]) {
                quoteBlocks.append(blocks[index])
                index += 1
            }
            let text = quoteBlocks.map(blockText).joined(separator: "\n\n")
            return ([Atom(
                blockIDs: quoteBlocks.map(\.id),
                blockSlices: nil,
                text: text,
                sourceTokenEstimate: budgetPlanner.estimateTokens(text),
                isAtomic: true
            )], index)
        }

        // A body paragraph is one semantic atom unless it exceeds the
        // provider-aware hard token limit. Only that exceptional path may use
        // sentence/word fallback slices.
        let text = blockText(block)
        return (splitOrdinaryBlock(block, text: text, hardLimit: hardLimit), start + 1)
    }

    private func splitOrdinaryBlock(
        _ block: DocumentBlock,
        text: String,
        hardLimit: Int
    ) -> [Atom] {
        let estimate = budgetPlanner.estimateTokens(text)
        guard estimate > hardLimit else {
            return [Atom(
                blockIDs: [block.id],
                blockSlices: nil,
                text: text,
                sourceTokenEstimate: estimate,
                isAtomic: true
            )]
        }

        let sentences = sentencePieces(text)
        var pieces: [(text: String, startOffset: Int, endOffset: Int)] = []
        var cursor = 0
        for sentence in sentences where !sentence.isEmpty {
            guard let range = text.range(of: sentence, range: text.index(text.startIndex, offsetBy: cursor)..<text.endIndex) else {
                continue
            }
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let end = text.distance(from: text.startIndex, to: range.upperBound)
            pieces.append(contentsOf: boundedPieces(sentence, startOffset: start, hardLimit: hardLimit))
            cursor = end
        }
        if pieces.isEmpty {
            pieces = boundedPieces(text, startOffset: 0, hardLimit: hardLimit)
        }

        return pieces.map { piece in
            Atom(
                blockIDs: [block.id],
                blockSlices: [DocumentBlockSlice(
                    blockID: block.id,
                    startOffset: piece.startOffset,
                    endOffset: piece.endOffset
                )],
                text: piece.text,
                sourceTokenEstimate: budgetPlanner.estimateTokens(piece.text),
                isAtomic: false
            )
        }
    }

    private func boundedPieces(
        _ text: String,
        startOffset: Int,
        hardLimit: Int
    ) -> [(text: String, startOffset: Int, endOffset: Int)] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        if budgetPlanner.estimateTokens(normalized) <= hardLimit {
            return [(normalized, startOffset, startOffset + normalized.count)]
        }

        let words = normalized.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
        var result: [(text: String, startOffset: Int, endOffset: Int)] = []
        var current = ""
        var localOffset = startOffset
        for word in words {
            let candidate = current.isEmpty ? word : "\(current) \(word)"
            if !current.isEmpty && budgetPlanner.estimateTokens(candidate) > hardLimit {
                result.append((current, localOffset, localOffset + current.count))
                localOffset += current.count + 1
                current = word
            } else if current.isEmpty && budgetPlanner.estimateTokens(candidate) > hardLimit {
                // An unusually long token has no safe sentence boundary. Slice
                // only this exceptional word, retaining a deterministic offset.
                let characters = Array(word)
                var pieceStart = 0
                while pieceStart < characters.count {
                    var pieceEnd = min(characters.count, pieceStart + max(1, hardLimit * 4))
                    while pieceEnd > pieceStart {
                        let candidatePiece = String(characters[pieceStart..<pieceEnd])
                        if budgetPlanner.estimateTokens(candidatePiece) <= hardLimit { break }
                        pieceEnd -= 1
                    }
                    if pieceEnd == pieceStart { pieceEnd = min(characters.count, pieceStart + 1) }
                    let piece = String(characters[pieceStart..<pieceEnd])
                    result.append((piece, localOffset + pieceStart, localOffset + pieceEnd))
                    pieceStart = pieceEnd
                }
                localOffset += word.count + 1
            } else {
                current = candidate
            }
        }
        if !current.isEmpty {
            result.append((current, localOffset, localOffset + current.count))
        }
        return result
    }

    private func sentencePieces(_ text: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var quoteDepth = 0
        var parenthesisDepth = 0
        let openingQuotes: Set<Character> = ["\"", "“", "«", "„"]
        let closingQuotes: Set<Character> = ["\"", "”", "»", "“"]

        for character in text {
            current.append(character)
            if openingQuotes.contains(character) {
                if character == "\"" {
                    quoteDepth = quoteDepth == 0 ? 1 : 0
                } else if character != "“" || quoteDepth == 0 {
                    quoteDepth += 1
                }
            } else if closingQuotes.contains(character), character != "\"", quoteDepth > 0 {
                quoteDepth -= 1
            } else if character == "(" || character == "[" || character == "{" {
                parenthesisDepth += 1
            } else if (character == ")" || character == "]" || character == "}"), parenthesisDepth > 0 {
                parenthesisDepth -= 1
            }

            if ".!?。！？".contains(character), quoteDepth == 0, parenthesisDepth == 0 {
                pieces.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pieces.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return pieces.isEmpty ? [text] : pieces
    }

    private func pack(_ atoms: [Atom], hardLimit: Int, softTarget: Int) -> [[Atom]] {
        var plans: [[Atom]] = []
        var current: [Atom] = []
        var currentTokens = 0

        func flush() {
            guard !current.isEmpty else { return }
            plans.append(current)
            current.removeAll(keepingCapacity: true)
            currentTokens = 0
        }

        for atom in atoms {
            if atom.startsNewChapter {
                flush()
            }
            let wouldExceedSoft = currentTokens > 0 && currentTokens + atom.sourceTokenEstimate > softTarget
            let wouldExceedHard = currentTokens > 0 && currentTokens + atom.sourceTokenEstimate > hardLimit
            if wouldExceedSoft || wouldExceedHard {
                flush()
            }

            // Atomic quote/verse groups never split or merge past the hard
            // boundary. A pathological group remains intact for editorial
            // review rather than being silently rewritten by the planner.
            if atom.isAtomic && !atom.isBlank && atom.sourceTokenEstimate > hardLimit {
                flush()
                current.append(atom)
                currentTokens += atom.sourceTokenEstimate
                flush()
                continue
            }

            current.append(atom)
            currentTokens += atom.sourceTokenEstimate
        }
        flush()
        return plans
    }

    private func makePlans(
        _ packed: [[Atom]],
        blocks: [DocumentBlock],
        profile: DocumentTranslationProfile
    ) -> [DocumentChunkPlan] {
        let profileFingerprint = stableProfileFingerprint(profile)
        let blockByID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
        let blockIndexByID = Dictionary(uniqueKeysWithValues: blocks.enumerated().map { ($0.element.id, $0.offset) })

        return packed.map { atoms in
            let blockIDs = atoms.flatMap(\.blockIDs)
            let slices = atoms.flatMap { $0.blockSlices ?? [] }
            let sourceBlockFingerprint = blockIDs.map { blockID in
                "\(blockID):\(blockByID[blockID]?.sourceHash ?? "")"
            }.joined(separator: "|")
            let sourceHash = stableHash([
                "source",
                sourceBlockFingerprint,
                slices.map { "\($0.blockID):\($0.startOffset)-\($0.endOffset)" }.joined(separator: "|"),
                atoms.map(\.text).joined(separator: "\n\n"),
                profileFingerprint,
                configuration.modelID,
                configuration.promptVersion
            ])
            let firstIndex = blockIDs.compactMap { blockIndexByID[$0] }.min() ?? 0
            let lastIndex = blockIDs.compactMap { blockIndexByID[$0] }.max() ?? firstIndex
            let ownIDs = Set(blockIDs)
            let before = contextBefore(
                firstIndex: firstIndex,
                ownIDs: ownIDs,
                blocks: blocks,
                count: configuration.contextBeforeBlockCount
            )
            let after = contextAfter(
                lastIndex: lastIndex,
                ownIDs: ownIDs,
                blocks: blocks,
                count: configuration.contextAfterBlockCount
            )
            let normalizedSlices = slices.isEmpty ? nil : slices
            return DocumentChunkPlan(
                id: "document-chunk-\(sourceHash.prefix(20))",
                blockIDs: blockIDs,
                sourceTokenEstimate: atoms.reduce(0) { $0 + $1.sourceTokenEstimate },
                contextBeforeBlockIDs: before,
                contextAfterBlockIDs: after,
                sourceHash: sourceHash,
                blockSlices: normalizedSlices
            )
        }
    }

    private func contextBefore(
        firstIndex: Int,
        ownIDs: Set<String>,
        blocks: [DocumentBlock],
        count: Int
    ) -> [String] {
        guard count > 0 else { return [] }
        var result: [String] = []
        var index = firstIndex - 1
        while index >= 0, result.count < count {
            let block = blocks[index]
            if !ownIDs.contains(block.id), !isBlank(block) {
                result.append(block.id)
            }
            index -= 1
        }
        return result.reversed()
    }

    private func contextAfter(
        lastIndex: Int,
        ownIDs: Set<String>,
        blocks: [DocumentBlock],
        count: Int
    ) -> [String] {
        guard count > 0 else { return [] }
        var result: [String] = []
        var index = lastIndex + 1
        while index < blocks.count, result.count < count {
            let block = blocks[index]
            if !ownIDs.contains(block.id), !isBlank(block) {
                result.append(block.id)
            }
            index += 1
        }
        return result
    }

    private func prepend(_ prefix: [DocumentBlock], to atom: Atom) -> Atom {
        let prefixText = prefix.map(blockText).joined(separator: "\n\n")
        let text = [prefixText, atom.text]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let prefixSlices = atom.blockSlices == nil
            ? nil
            : prefix.map { block in
                DocumentBlockSlice(
                    blockID: block.id,
                    startOffset: 0,
                    endOffset: blockText(block).count
                )
            }
        return Atom(
            blockIDs: prefix.map(\.id) + atom.blockIDs,
            blockSlices: prefixSlices.map { $0 + (atom.blockSlices ?? []) },
            text: text,
            sourceTokenEstimate: prefix.reduce(0) { $0 + budgetPlanner.estimateTokens(blockText($1)) } + atom.sourceTokenEstimate,
            isAtomic: atom.isAtomic,
            startsNewChapter: true
        )
    }
    private func isVerseIntroduction(_ block: DocumentBlock) -> Bool {
        let text = blockText(block).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let style = (block.styleID ?? "").lowercased()
        return style.contains("verse intro")
            || text.contains("shloka")
            || text.contains("śloka")
            || text.contains("verse")
            || text.contains("stanza")
    }

    private func blockText(_ block: DocumentBlock) -> String {
        block.spans.map(\.text).joined()
    }

    private func isBlank(_ block: DocumentBlock) -> Bool {
        block.kind == .empty || blockText(block).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isQuoteOrVerse(_ block: DocumentBlock) -> Bool {
        if block.kind == .quote || block.kind == .verse { return true }
        let style = (block.styleID ?? "").lowercased()
        return style.contains("quote")
            || style.contains("verse")
            || style.contains("shlok")
            || style.contains("stanza")
            || style.contains("poem")
    }

    private func isChapterTitle(_ block: DocumentBlock) -> Bool {
        guard block.kind == .heading || (block.styleID?.lowercased().contains("chapter") == true) else {
            return false
        }
        let style = (block.styleID ?? "").lowercased()
        if style.contains("book title") || style.contains("book-title") { return false }
        if style.contains("chapter") { return true }
        let rawText = blockText(block).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let text = rawText.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
        let chapterPrefixes = [
            "chapter ", "глава ", "part ", "часть ", "prologue", "эпилог", "epilogue",
            "preface", "предисловие", "afterword", "послесловие"
        ]
        return chapterPrefixes.contains(where: text.hasPrefix)
    }

    private func stableProfileFingerprint(_ profile: DocumentTranslationProfile) -> String {
        let protected = profile.protectedTerms
            .sorted { $0.id < $1.id }
            .map { "\($0.id)=\($0.source)=>\($0.translation):\($0.notes ?? "")" }
            .joined(separator: "|")
        let glossary = profile.projectGlossary
            .sorted { $0.id < $1.id }
            .map { entry in
                let translations = entry.translations
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ",")
                return "\(entry.id)=\(entry.source)=>\(entry.translation)[\(translations)]"
            }
            .joined(separator: "|")
        return [
            profile.sourceLanguage,
            profile.targetLanguage,
            profile.mode.rawValue,
            profile.voice.rawValue,
            profile.sanskritPolicy.rawValue,
            protected,
            glossary,
            profile.translatorNotes
        ].joined(separator: "\u{1F}" )
    }

    private func stableHash(_ components: [String]) -> String {
        let seed = components.joined(separator: "\u{1E}")
        return SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
