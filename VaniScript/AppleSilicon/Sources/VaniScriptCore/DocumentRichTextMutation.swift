import Foundation

/// Pure core engine for rich-text mutations over document spans with stable span identity (INV-3).
public enum DocumentRichTextMutation {

    /// Adjusts an NSRange in UTF-16 offsets so it never splits a UTF-16 surrogate pair.
    public static func safeUTF16Range(in text: String, requestedRange: NSRange) -> NSRange {
        let ns = text as NSString
        let len = ns.length
        guard len > 0 else { return NSRange(location: 0, length: 0) }
        var start = max(0, min(requestedRange.location, len))
        var end = max(start, min(requestedRange.location + requestedRange.length, len))

        // If start lands on a low surrogate, include the preceding high surrogate
        if start > 0 && start < len {
            let char = ns.character(at: start)
            if (0xDC00...0xDFFF).contains(char) {
                start -= 1
            }
        }
        // If end lands on a low surrogate, include it
        if end > 0 && end < len {
            let char = ns.character(at: end)
            if (0xDC00...0xDFFF).contains(char) {
                end = min(len, end + 1)
            }
        }
        return NSRange(location: start, length: end - start)
    }

    /// Replaces a targeted range within document spans, preserving span identity per INV-3.
    public static func replace(
        spans: [RichTextSpan],
        range: DocumentSpanRange,
        with replacement: String,
        policy: ReplacementFormattingPolicy = .inheritExisting
    ) throws -> [RichTextSpan] {
        return try replace(spans: spans, ranges: [range], with: replacement, policy: policy)
    }
    /// Replaces one structurally selected range that may span several adjacent
    /// rich-text spans. The replacement is inserted exactly once and inherits
    /// formatting from the first selected span; callers must reject mixed
    /// effective styles before invoking this operation.
    public static func replace(
        spans: [RichTextSpan],
        selection: [DocumentSpanRange],
        with replacement: String,
        policy: ReplacementFormattingPolicy = .inheritExisting
    ) throws -> [RichTextSpan] {
        guard !selection.isEmpty else { return spans }
        guard !spans.isEmpty else {
            return replacement.isEmpty ? [] : [RichTextSpan(id: UUID().uuidString, text: replacement)]
        }

        var selectedBySpan: [String: IndexSet] = [:]
        for range in selection {
            guard let span = spans.first(where: { $0.id == range.spanID }) else { continue }
            let safeRange = safeUTF16Range(in: span.text, requestedRange: range.utf16Range)
            guard safeRange.length > 0 else { continue }
            selectedBySpan[range.spanID, default: IndexSet()].insert(
                integersIn: safeRange.location..<(safeRange.location + safeRange.length)
            )
        }
        guard !selectedBySpan.isEmpty else { return spans }

        let firstSelectedSpan = spans.first { selectedBySpan[$0.id] != nil }!
        let inheritedTraits: Set<InlineTrait>
        let inheritedOverrides: EditorInlineOverrides?
        let inheritedColor: String?
        switch policy {
        case .inheritExisting, .preserveIslands:
            inheritedTraits = firstSelectedSpan.traits
            inheritedOverrides = firstSelectedSpan.editorOverrides
            inheritedColor = firstSelectedSpan.foregroundColorHex
        case .plain:
            inheritedTraits = []
            inheritedOverrides = nil
            inheritedColor = nil
        }

        var result: [RichTextSpan] = []
        var insertedReplacement = false

        for span in spans {
            guard let selectedSet = selectedBySpan[span.id], !selectedSet.isEmpty else {
                result.append(span)
                continue
            }

            let totalLength = (span.text as NSString).length
            guard totalLength > 0 else { continue }

            var boundaries: Set<Int> = [0, totalLength]
            for selectedIndex in selectedSet {
                boundaries.insert(selectedIndex)
                boundaries.insert(selectedIndex + 1)
            }
            let sortedBoundaries = boundaries.sorted()
            for boundaryIndex in 0..<(sortedBoundaries.count - 1) {
                let start = sortedBoundaries[boundaryIndex]
                let end = sortedBoundaries[boundaryIndex + 1]
                guard end > start else { continue }
                let segmentRange = NSRange(location: start, length: end - start)
                let segmentText = (span.text as NSString).substring(with: segmentRange)
                let isSelected = selectedSet.contains(start)

                if isSelected {
                    if !insertedReplacement {
                        let replacementID = result.last?.id == span.id ? UUID().uuidString : span.id
                        result.append(RichTextSpan(
                            id: replacementID,
                            text: replacement,
                            styleKey: firstSelectedSpan.styleKey,
                            traits: inheritedTraits,
                            translationPolicy: firstSelectedSpan.translationPolicy,
                            foregroundColorHex: inheritedColor,
                            editorOverrides: inheritedOverrides
                        ))
                        insertedReplacement = true
                    }
                } else {
                    let pieceID = result.last?.id == span.id ? UUID().uuidString : span.id
                    result.append(RichTextSpan(
                        id: pieceID,
                        text: segmentText,
                        styleKey: span.styleKey,
                        traits: span.traits,
                        translationPolicy: span.translationPolicy,
                        foregroundColorHex: span.foregroundColorHex,
                        editorOverrides: span.editorOverrides
                    ))
                }
            }
        }

        return normalize(result)
    }



    /// Replaces targeted ranges within document spans.
    public static func replace(
        spans: [RichTextSpan],
        ranges: [DocumentSpanRange],
        with replacement: String,
        policy: ReplacementFormattingPolicy = .inheritExisting
    ) throws -> [RichTextSpan] {
        guard !spans.isEmpty else {
            if !replacement.isEmpty {
                return [RichTextSpan(id: UUID().uuidString, text: replacement)]
            }
            return []
        }

        var result = spans

        for targetRange in ranges {
            guard let spanIndex = result.firstIndex(where: { $0.id == targetRange.spanID }) else {
                continue
            }

            let span = result[spanIndex]
            let nsText = span.text as NSString
            let safeRange = safeUTF16Range(in: span.text, requestedRange: targetRange.utf16Range)

            let loc = safeRange.location
            let len = safeRange.length
            let totalLen = nsText.length

            let leftText = loc > 0 ? nsText.substring(with: NSRange(location: 0, length: loc)) : ""
            let rightText = (loc + len) < totalLen ? nsText.substring(with: NSRange(location: loc + len, length: totalLen - (loc + len))) : ""

            // Formatting for the replacement portion
            let replacementTraits: Set<InlineTrait>
            let replacementOverrides: EditorInlineOverrides?
            let replacementColor: String?
            let replacementStyle: String
            let replacementPolicy: SpanTranslationPolicy

            switch policy {
            case .inheritExisting, .preserveIslands:
                replacementTraits = span.traits
                replacementOverrides = span.editorOverrides
                replacementColor = span.foregroundColorHex
                replacementStyle = span.styleKey
                replacementPolicy = span.translationPolicy
            case .plain:
                replacementTraits = []
                replacementOverrides = nil
                replacementColor = nil
                replacementStyle = span.styleKey
                replacementPolicy = span.translationPolicy
            }

            var replacementPieces: [RichTextSpan] = []

            // If whole span is replaced
            if leftText.isEmpty && rightText.isEmpty {
                let piece = RichTextSpan(
                    id: span.id,
                    text: replacement,
                    styleKey: replacementStyle,
                    traits: replacementTraits,
                    translationPolicy: replacementPolicy,
                    foregroundColorHex: replacementColor,
                    editorOverrides: replacementOverrides
                )
                replacementPieces.append(piece)
            } else if leftText.isEmpty {
                // Replacement at start: middle gets span.id, right gets new ID
                let middlePiece = RichTextSpan(
                    id: span.id,
                    text: replacement,
                    styleKey: replacementStyle,
                    traits: replacementTraits,
                    translationPolicy: replacementPolicy,
                    foregroundColorHex: replacementColor,
                    editorOverrides: replacementOverrides
                )
                let rightPiece = RichTextSpan(
                    id: UUID().uuidString,
                    text: rightText,
                    styleKey: span.styleKey,
                    traits: span.traits,
                    translationPolicy: span.translationPolicy,
                    foregroundColorHex: span.foregroundColorHex,
                    editorOverrides: span.editorOverrides
                )
                if !replacement.isEmpty {
                    replacementPieces.append(middlePiece)
                }
                if !rightText.isEmpty {
                    replacementPieces.append(rightPiece)
                }
            } else if rightText.isEmpty {
                // Replacement at end: left gets span.id, middle gets new ID
                let leftPiece = RichTextSpan(
                    id: span.id,
                    text: leftText,
                    styleKey: span.styleKey,
                    traits: span.traits,
                    translationPolicy: span.translationPolicy,
                    foregroundColorHex: span.foregroundColorHex,
                    editorOverrides: span.editorOverrides
                )
                replacementPieces.append(leftPiece)
                if !replacement.isEmpty {
                    let middlePiece = RichTextSpan(
                        id: UUID().uuidString,
                        text: replacement,
                        styleKey: replacementStyle,
                        traits: replacementTraits,
                        translationPolicy: replacementPolicy,
                        foregroundColorHex: replacementColor,
                        editorOverrides: replacementOverrides
                    )
                    replacementPieces.append(middlePiece)
                }
            } else {
                // Replacement in middle: left gets span.id, middle and right get new IDs
                let leftPiece = RichTextSpan(
                    id: span.id,
                    text: leftText,
                    styleKey: span.styleKey,
                    traits: span.traits,
                    translationPolicy: span.translationPolicy,
                    foregroundColorHex: span.foregroundColorHex,
                    editorOverrides: span.editorOverrides
                )
                replacementPieces.append(leftPiece)
                if !replacement.isEmpty {
                    let middlePiece = RichTextSpan(
                        id: UUID().uuidString,
                        text: replacement,
                        styleKey: replacementStyle,
                        traits: replacementTraits,
                        translationPolicy: replacementPolicy,
                        foregroundColorHex: replacementColor,
                        editorOverrides: replacementOverrides
                    )
                    replacementPieces.append(middlePiece)
                }
                let rightPiece = RichTextSpan(
                    id: UUID().uuidString,
                    text: rightText,
                    styleKey: span.styleKey,
                    traits: span.traits,
                    translationPolicy: span.translationPolicy,
                    foregroundColorHex: span.foregroundColorHex,
                    editorOverrides: span.editorOverrides
                )
                replacementPieces.append(rightPiece)
            }

            result.remove(at: spanIndex)
            result.insert(contentsOf: replacementPieces, at: spanIndex)
        }

        return normalize(result)
    }

    /// Toggles an inline trait across selected span ranges.
    /// If all selected portions already have the trait, turns it off; otherwise turns it on.
    /// Superscript and subscript are mutually exclusive.
    public static func toggleTrait(
        spans: [RichTextSpan],
        ranges: [DocumentSpanRange],
        trait: InlineTrait
    ) throws -> [RichTextSpan] {
        guard !spans.isEmpty && !ranges.isEmpty else { return spans }

        // Determine whether to turn trait ON or OFF
        // If all covered text in ranges has the trait -> turn off; else -> turn on.
        var allCoveredHaveTrait = true
        var foundCoveredText = false

        for range in ranges {
            guard let span = spans.first(where: { $0.id == range.spanID }) else { continue }
            let safeRange = safeUTF16Range(in: span.text, requestedRange: range.utf16Range)
            if safeRange.length > 0 {
                foundCoveredText = true
                if !span.traits.contains(trait) {
                    allCoveredHaveTrait = false
                    break
                }
            }
        }

        let turnOn = foundCoveredText ? !allCoveredHaveTrait : true

        var newSpans: [RichTextSpan] = []

        for span in spans {
            let matchingRanges = ranges.filter { $0.spanID == span.id }
            if matchingRanges.isEmpty {
                newSpans.append(span)
                continue
            }

            let nsText = span.text as NSString
            let totalLen = nsText.length
            guard totalLen > 0 else {
                newSpans.append(span)
                continue
            }

            // Merge target ranges for this span
            var selectedSet = IndexSet()
            for r in matchingRanges {
                let safe = safeUTF16Range(in: span.text, requestedRange: r.utf16Range)
                if safe.length > 0 {
                    selectedSet.insert(integersIn: safe.location..<(safe.location + safe.length))
                }
            }

            if selectedSet.isEmpty {
                newSpans.append(span)
                continue
            }

            // Segment the span into continuous selected and unselected subranges
            var segments: [(range: NSRange, isSelected: Bool)] = []
            var currentIndex = 0

            while currentIndex < totalLen {
                let isSel = selectedSet.contains(currentIndex)
                var nextIndex = currentIndex + 1
                while nextIndex < totalLen && selectedSet.contains(nextIndex) == isSel {
                    nextIndex += 1
                }
                segments.append((NSRange(location: currentIndex, length: nextIndex - currentIndex), isSel))
                currentIndex = nextIndex
            }

            for (segIdx, segment) in segments.enumerated() {
                let segText = nsText.substring(with: segment.range)
                var segTraits = span.traits
                var segOverrides = span.editorOverrides ?? EditorInlineOverrides()

                if segment.isSelected {
                    if turnOn {
                        segTraits.insert(trait)
                        segOverrides.traitOverrides[trait] = true
                        if trait == .superscript {
                            segTraits.remove(.subscriptText)
                            segOverrides.traitOverrides.removeValue(forKey: .subscriptText)
                        } else if trait == .subscriptText {
                            segTraits.remove(.superscript)
                            segOverrides.traitOverrides.removeValue(forKey: .superscript)
                        }
                    } else {
                        segTraits.remove(trait)
                        if span.editorOverrides?.traitOverrides[trait] == true {
                            segOverrides.traitOverrides.removeValue(forKey: trait)
                        } else {
                            segOverrides.traitOverrides[trait] = false
                        }
                    }
                }

                let finalOverrides = segOverrides.isEffectivelyEmpty ? nil : segOverrides

                // ID stability (INV-3): first segment keeps span.id; others get fresh IDs
                let segID = (segIdx == 0) ? span.id : UUID().uuidString

                let segSpan = RichTextSpan(
                    id: segID,
                    text: segText,
                    styleKey: span.styleKey,
                    traits: segTraits,
                    translationPolicy: span.translationPolicy,
                    foregroundColorHex: span.foregroundColorHex,
                    editorOverrides: finalOverrides
                )
                newSpans.append(segSpan)
            }
        }
        return normalize(newSpans)
    }

    /// Clears user-applied manual formatting overrides from the selected ranges.
    public static func clearFormatting(
        spans: [RichTextSpan],
        ranges: [DocumentSpanRange]
    ) throws -> [RichTextSpan] {
        guard !spans.isEmpty && !ranges.isEmpty else { return spans }

        var newSpans: [RichTextSpan] = []

        for span in spans {
            let matchingRanges = ranges.filter { $0.spanID == span.id }
            if matchingRanges.isEmpty {
                newSpans.append(span)
                continue
            }

            let nsText = span.text as NSString
            let totalLen = nsText.length
            guard totalLen > 0 else {
                newSpans.append(span)
                continue
            }

            var selectedSet = IndexSet()
            for r in matchingRanges {
                let safe = safeUTF16Range(in: span.text, requestedRange: r.utf16Range)
                if safe.length > 0 {
                    selectedSet.insert(integersIn: safe.location..<(safe.location + safe.length))
                }
            }

            if selectedSet.isEmpty {
                newSpans.append(span)
                continue
            }

            var segments: [(range: NSRange, isSelected: Bool)] = []
            var currentIndex = 0

            while currentIndex < totalLen {
                let isSel = selectedSet.contains(currentIndex)
                var nextIndex = currentIndex + 1
                while nextIndex < totalLen && selectedSet.contains(nextIndex) == isSel {
                    nextIndex += 1
                }
                segments.append((NSRange(location: currentIndex, length: nextIndex - currentIndex), isSel))
                currentIndex = nextIndex
            }

            for (segIdx, segment) in segments.enumerated() {
                let segText = nsText.substring(with: segment.range)
                let segID = (segIdx == 0) ? span.id : UUID().uuidString

                if segment.isSelected {
                    let clearedSpan = RichTextSpan(
                        id: segID,
                        text: segText,
                        styleKey: span.styleKey,
                        traits: [],
                        translationPolicy: span.translationPolicy,
                        foregroundColorHex: nil,
                        editorOverrides: nil
                    )
                    newSpans.append(clearedSpan)
                } else {
                    let unchangedSpan = RichTextSpan(
                        id: segID,
                        text: segText,
                        styleKey: span.styleKey,
                        traits: span.traits,
                        translationPolicy: span.translationPolicy,
                        foregroundColorHex: span.foregroundColorHex,
                        editorOverrides: span.editorOverrides
                    )
                    newSpans.append(unchangedSpan)
                }
            }
        }

        return normalize(newSpans)
    }

    /// Replaces all matches in document spans, respecting protected text.
    public static func replaceAll(
        spans: [RichTextSpan],
        matches: [DocumentTextMatch],
        replacement: String
    ) throws -> MutationResult {
        var currentSpans = spans
        var replacedCount = 0
        var skippedProtectedCount = 0

        for match in matches {
            if match.protectedMatch {
                skippedProtectedCount += 1
                continue
            }

            // Check if any matching span is protected
            var hasProtectedSpan = false
            for range in match.spanRanges {
                if let span = currentSpans.first(where: { $0.id == range.spanID }), span.translationPolicy == .protect {
                    hasProtectedSpan = true
                    break
                }
            }

            if hasProtectedSpan {
                skippedProtectedCount += 1
                continue
            }

            replacedCount += 1
            currentSpans = try replace(spans: currentSpans, ranges: match.spanRanges, with: replacement, policy: .inheritExisting)
        }

        return MutationResult(
            spans: currentSpans,
            replacedCount: replacedCount,
            skippedProtectedCount: skippedProtectedCount
        )
    }

    /// Merges adjacent equivalent spans and removes empty spans, preserving the first span's identity (INV-3).
    public static func normalize(_ spans: [RichTextSpan]) -> [RichTextSpan] {
        guard !spans.isEmpty else { return [] }

        // Filter out empty spans
        let nonEmpty = spans.filter { !$0.text.isEmpty }
        guard let first = nonEmpty.first else { return [] }

        var merged: [RichTextSpan] = [first]

        for span in nonEmpty.dropFirst() {
            guard let last = merged.last else {
                merged.append(span)
                continue
            }

            if canMerge(last, span) {
                var combined = last
                combined.text += span.text
                merged[merged.count - 1] = combined
            } else {
                merged.append(span)
            }
        }

        return merged
    }

    private static func canMerge(_ a: RichTextSpan, _ b: RichTextSpan) -> Bool {
        let aOverrides = (a.editorOverrides?.isEffectivelyEmpty == true) ? nil : a.editorOverrides
        let bOverrides = (b.editorOverrides?.isEffectivelyEmpty == true) ? nil : b.editorOverrides
        return a.styleKey == b.styleKey &&
               a.traits == b.traits &&
               a.translationPolicy == b.translationPolicy &&
               a.foregroundColorHex == b.foregroundColorHex &&
               aOverrides == bOverrides
    }
}
