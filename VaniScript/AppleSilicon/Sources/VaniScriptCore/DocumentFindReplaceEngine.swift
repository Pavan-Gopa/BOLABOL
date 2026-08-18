import Foundation

/// The document-wide search scope for Replace Everywhere (PRD §11). Only the
/// currently open document is ever searched: the source side or exactly one
/// active translation. Cross-document and all-languages scopes are out of
/// scope by design (ADR-E2).
public enum DocumentSearchScope: Equatable, Sendable {
    case currentSourceDocument
    case currentTranslation(languageKey: String)
}

/// Find/replace options for the document engine (PRD §11.1).
public struct DocumentFindReplaceOptions: Equatable, Sendable {
    public var wholeWord: Bool
    public var caseSensitive: Bool
    public var skipProtected: Bool

    public init(wholeWord: Bool = true, caseSensitive: Bool = false, skipProtected: Bool = true) {
        self.wholeWord = wholeWord
        self.caseSensitive = caseSensitive
        self.skipProtected = skipProtected
    }
}

/// One block's fully computed replacement result (plan-then-apply, PRD §24).
public struct DocumentFindReplacePatch: Equatable, Sendable {
    public var blockID: String
    public var spans: [RichTextSpan]
    public var text: String

    public init(blockID: String, spans: [RichTextSpan], text: String) {
        self.blockID = blockID
        self.spans = spans
        self.text = text
    }
}

/// Aggregate outcome of a document-wide search (PRD §11.4): replaceable
/// matches plus the two skip categories that are counted, never flattened.
public struct DocumentFindReplaceReport: Equatable, Sendable {
    public var foundCount: Int
    public var blockCount: Int
    public var skippedProtectedCount: Int
    public var skippedMixedStyleCount: Int
    public var matchesByBlock: [String: [DocumentTextMatch]]

    public init(
        foundCount: Int = 0,
        blockCount: Int = 0,
        skippedProtectedCount: Int = 0,
        skippedMixedStyleCount: Int = 0,
        matchesByBlock: [String: [DocumentTextMatch]] = [:]
    ) {
        self.foundCount = foundCount
        self.blockCount = blockCount
        self.skippedProtectedCount = skippedProtectedCount
        self.skippedMixedStyleCount = skippedMixedStyleCount
        self.matchesByBlock = matchesByBlock
    }
}

/// A fully computed, ready-to-apply document-wide mutation plan (PRD §24).
/// The plan is computed over the canonical DocumentState (ADR-E2) and never
/// over aggregate ChunkData strings.
public struct DocumentFindReplacePlan: Equatable, Sendable {
    public var scope: DocumentSearchScope
    public var patches: [DocumentFindReplacePatch]
    public var report: DocumentFindReplaceReport

    public init(scope: DocumentSearchScope, patches: [DocumentFindReplacePatch], report: DocumentFindReplaceReport) {
        self.scope = scope
        self.patches = patches
        self.report = report
    }
}

/// Pure search + plan engine for document-wide Replace Everywhere (PRD §11,
/// §25, ADR-E2). Searches the canonical DocumentState IR directly — never the
/// aggregate ChunkData strings — and is rich-text safe: protected spans are
/// skipped and counted, mixed-style matches are never silently flattened.
public enum DocumentFindReplaceEngine {

    /// Search only. The regex is compiled exactly once per operation (PRD §25).
    public static func matches(
        in documentState: DocumentState,
        scope: DocumentSearchScope,
        query: String,
        options: DocumentFindReplaceOptions
    ) -> DocumentFindReplaceReport {
        search(documentState: documentState, scope: scope, query: query, options: options).report
    }

    /// Search + fully computed mutation plan. Returns nil when the query is
    /// empty or there is nothing to replace: a 0-match operation is a no-op
    /// with no transaction, no save, and no Undo (PRD §26.6).
    public static func plan(
        in documentState: DocumentState,
        scope: DocumentSearchScope,
        query: String,
        replacement: String,
        options: DocumentFindReplaceOptions
    ) -> DocumentFindReplacePlan? {
        let outcome = search(documentState: documentState, scope: scope, query: query, options: options)
        guard outcome.report.foundCount > 0 else { return nil }

        var patches: [DocumentFindReplacePatch] = []
        for (blockID, blockMatches) in outcome.report.matchesByBlock {
            let currentSpans = outcome.spansByBlock[blockID] ?? []
            let newSpans = apply(matches: blockMatches, to: currentSpans, replacement: replacement)
            patches.append(DocumentFindReplacePatch(
                blockID: blockID,
                spans: newSpans,
                text: newSpans.map(\.text).joined()
            ))
        }
        // Deterministic patch order: document order of the touched blocks.
        patches.sort { lhs, rhs in
            (outcome.orderByBlock[lhs.blockID] ?? Int.max) < (outcome.orderByBlock[rhs.blockID] ?? Int.max)
        }
        return DocumentFindReplacePlan(scope: scope, patches: patches, report: outcome.report)
    }

    // MARK: - Search

    private struct SearchOutcome {
        var report: DocumentFindReplaceReport
        var spansByBlock: [String: [RichTextSpan]]
        var orderByBlock: [String: Int]
    }

    private static func search(
        documentState: DocumentState,
        scope: DocumentSearchScope,
        query: String,
        options: DocumentFindReplaceOptions
    ) -> SearchOutcome {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let regex = makeRegex(query: trimmed, options: options) else {
            return SearchOutcome(report: DocumentFindReplaceReport(), spansByBlock: [:], orderByBlock: [:])
        }

        let side: DocumentEditorSide
        let languageKey: String?
        var entries: [(blockID: String, spans: [RichTextSpan], blockProtected: Bool)] = []

        switch scope {
        case .currentSourceDocument:
            side = .source
            languageKey = nil
            entries = documentState.blocks.map {
                (blockID: $0.id, spans: $0.spans, blockProtected: $0.translationPolicy == .protect)
            }
        case .currentTranslation(let key):
            side = .translation
            languageKey = key
            // Only the active language is ever searched (PRD §11). Blocks are
            // visited in deterministic (sorted) dictionary order.
            entries = (documentState.translationsByLanguage[key] ?? [:])
                .sorted { $0.key < $1.key }
                .map { (blockID: $0.value.sourceBlockID, spans: $0.value.spans, blockProtected: false) }
        }

        var foundCount = 0
        var skippedProtectedCount = 0
        var skippedMixedStyleCount = 0
        var matchesByBlock: [String: [DocumentTextMatch]] = [:]
        var spansByBlock: [String: [RichTextSpan]] = [:]
        var orderByBlock: [String: Int] = [:]

        for (order, entry) in entries.enumerated() {
            // A block with no spans contributes nothing to search: the engine
            // never fabricates spans (e.g. a translation stored as plain text).
            guard !entry.spans.isEmpty else { continue }
            let blockMatches = searchBlock(
                blockID: entry.blockID,
                spans: entry.spans,
                blockProtected: entry.blockProtected,
                side: side,
                languageKey: languageKey,
                regex: regex,
                options: options,
                skippedProtectedCount: &skippedProtectedCount,
                skippedMixedStyleCount: &skippedMixedStyleCount
            )
            guard !blockMatches.isEmpty else { continue }
            foundCount += blockMatches.count
            matchesByBlock[entry.blockID] = blockMatches
            spansByBlock[entry.blockID] = entry.spans
            orderByBlock[entry.blockID] = order
        }

        let report = DocumentFindReplaceReport(
            foundCount: foundCount,
            blockCount: matchesByBlock.count,
            skippedProtectedCount: skippedProtectedCount,
            skippedMixedStyleCount: skippedMixedStyleCount,
            matchesByBlock: matchesByBlock
        )
        return SearchOutcome(report: report, spansByBlock: spansByBlock, orderByBlock: orderByBlock)
    }

    /// The exact whole-word boundary used across the codebase
    /// (GlossaryTextRewriter / McpReadToolService / media search): Unicode
    /// letter/number/underscore neighbours reject the match.
    private static func makeRegex(query: String, options: DocumentFindReplaceOptions) -> NSRegularExpression? {
        let escaped = NSRegularExpression.escapedPattern(for: query)
        let pattern = options.wholeWord ? "(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])" : escaped
        let regexOptions: NSRegularExpression.Options = options.caseSensitive ? [] : [.caseInsensitive]
        return try? NSRegularExpression(pattern: pattern, options: regexOptions)
    }

    private static func searchBlock(
        blockID: String,
        spans: [RichTextSpan],
        blockProtected: Bool,
        side: DocumentEditorSide,
        languageKey: String?,
        regex: NSRegularExpression,
        options: DocumentFindReplaceOptions,
        skippedProtectedCount: inout Int,
        skippedMixedStyleCount: inout Int
    ) -> [DocumentTextMatch] {
        // Concatenate span texts with NO separator and build the cumulative
        // UTF-16 offset map so matches may span adjacent same-style spans.
        var concatenated = ""
        var offsets: [Int] = []
        offsets.reserveCapacity(spans.count)
        for span in spans {
            offsets.append((concatenated as NSString).length)
            concatenated += span.text
        }
        let nsText = concatenated as NSString
        guard nsText.length > 0 else { return [] }

        let results = regex.matches(in: concatenated, range: NSRange(location: 0, length: nsText.length))
        guard !results.isEmpty else { return [] }

        var replaceable: [DocumentTextMatch] = []
        for result in results {
            let matchRange = result.range
            guard matchRange.length > 0 else { continue }
            let matchEnd = matchRange.location + matchRange.length

            // Clip the match to every span it touches (UTF-16 extents).
            var spanRanges: [DocumentSpanRange] = []
            var touchedSpans: [RichTextSpan] = []
            for (index, span) in spans.enumerated() {
                let spanStart = offsets[index]
                let spanEnd = spanStart + (span.text as NSString).length
                let clippedLocation = max(matchRange.location, spanStart)
                let clippedEnd = min(matchEnd, spanEnd)
                guard clippedEnd > clippedLocation else { continue }
                spanRanges.append(DocumentSpanRange(
                    spanID: span.id,
                    location: clippedLocation - spanStart,
                    length: clippedEnd - clippedLocation
                ))
                touchedSpans.append(span)
            }
            guard !spanRanges.isEmpty else { continue }

            // Block-level protect is treated exactly like span-level protect.
            let isProtected = blockProtected || touchedSpans.contains { $0.translationPolicy == .protect }
            if isProtected, options.skipProtected {
                skippedProtectedCount += 1
                continue
            }

            // PRD §11.4: a match touching 2+ spans with differing effective
            // styles must never be silently flattened — skip and count it.
            if touchedSpans.count > 1, hasMixedEffectiveStyle(touchedSpans) {
                skippedMixedStyleCount += 1
                continue
            }

            replaceable.append(DocumentTextMatch(
                side: side,
                languageKey: languageKey,
                blockID: blockID,
                spanRanges: spanRanges,
                matchedText: nsText.substring(with: matchRange),
                protectedMatch: isProtected
            ))
        }
        return replaceable
    }

    /// Effective style = (styleKey, traits, foregroundColorHex,
    /// editorOverrides) tuple equality. Effectively-empty overrides compare
    /// equal to nil, mirroring DocumentRichTextMutation.normalize.
    private static func hasMixedEffectiveStyle(_ spans: [RichTextSpan]) -> Bool {
        guard let first = spans.first else { return false }
        let firstOverrides = normalizedOverrides(first.editorOverrides)
        for span in spans.dropFirst() {
            if span.styleKey != first.styleKey
                || span.traits != first.traits
                || span.foregroundColorHex != first.foregroundColorHex
                || normalizedOverrides(span.editorOverrides) != firstOverrides {
                return true
            }
        }
        return false
    }

    private static func normalizedOverrides(_ overrides: EditorInlineOverrides?) -> EditorInlineOverrides? {
        guard let overrides, !overrides.isEffectivelyEmpty else { return nil }
        return overrides
    }

    // MARK: - Apply

    /// Applies one block's matches back-to-front by start position so earlier
    /// UTF-16 offsets stay valid, then normalizes the result. A defensive
    /// throw from the mutation primitive skips that single match only — the
    /// plan was validated by search, so this should not happen.
    private static func apply(
        matches: [DocumentTextMatch],
        to spans: [RichTextSpan],
        replacement: String
    ) -> [RichTextSpan] {
        // Global UTF-16 start offset per span so matches touching different
        // spans can be ordered. Span-relative offsets alone are not comparable
        // across spans.
        var globalOffsetBySpanID: [String: Int] = [:]
        var runningOffset = 0
        for span in spans {
            globalOffsetBySpanID[span.id] = runningOffset
            runningOffset += (span.text as NSString).length
        }

        func globalStart(_ match: DocumentTextMatch) -> Int {
            guard let firstRange = match.spanRanges.first else { return 0 }
            let spanOffset = globalOffsetBySpanID[firstRange.spanID] ?? 0
            return spanOffset + firstRange.utf16Range.location
        }

        var currentSpans = spans
        // Back-to-front by global start so earlier offsets stay valid.
        let ordered = matches.sorted { globalStart($0) > globalStart($1) }
        for match in ordered {
            guard let updated = try? DocumentRichTextMutation.replace(
                spans: currentSpans,
                selection: match.spanRanges,
                with: replacement,
                policy: .inheritExisting
            ) else { continue }
            currentSpans = updated
        }
        return DocumentRichTextMutation.normalize(currentSpans)
    }
}
