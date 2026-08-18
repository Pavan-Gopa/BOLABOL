import Foundation

/// One paired source↔translation unit for editor proofreading highlight.
public struct DocumentProofreadingUnit: Equatable, Sendable, Identifiable {
    public var id: String
    public var blockID: String
    public var unitIndexInBlock: Int
    /// UTF-16 range in the full dual-pane attributed string (blocks joined by `"\n\n"`).
    public var sourceUTF16Range: NSRange
    public var translatedUTF16Range: NSRange
    public var sourceText: String
    public var translatedText: String

    public init(
        id: String,
        blockID: String,
        unitIndexInBlock: Int,
        sourceUTF16Range: NSRange,
        translatedUTF16Range: NSRange,
        sourceText: String,
        translatedText: String
    ) {
        self.id = id
        self.blockID = blockID
        self.unitIndexInBlock = unitIndexInBlock
        self.sourceUTF16Range = sourceUTF16Range
        self.translatedUTF16Range = translatedUTF16Range
        self.sourceText = sourceText
        self.translatedText = translatedText
    }
}

/// Builds synchronized sentence/word units for dual-pane document review.
///
/// Layout contract matches `DocumentAttributedTextView`: blocks are joined with
/// `"\n\n"`. Pairing is per shared `blockID`; when sentence counts differ, each
/// source unit maps proportionally into the translated block.
public enum DocumentProofreadingAlignment {
    public static let blockSeparator = "\n\n"

    public struct BlockText: Equatable, Sendable {
        public var id: String
        public var text: String

        public init(id: String, text: String) {
            self.id = id
            self.text = text
        }
    }

    public static func units(
        sourceBlocks: [BlockText],
        translatedBlocks: [BlockText]
    ) -> [DocumentProofreadingUnit] {
        let translatedByID = Dictionary(uniqueKeysWithValues: translatedBlocks.map { ($0.id, $0.text) })
        var result: [DocumentProofreadingUnit] = []
        var sourceCursor = 0
        var translatedCursorByID: [String: Int] = [:]

        // Pre-compute translated block start offsets in the translated full string.
        var translatedFullCursor = 0
        var translatedStartByID: [String: Int] = [:]
        for (index, block) in translatedBlocks.enumerated() {
            if index > 0 { translatedFullCursor += blockSeparator.utf16.count }
            translatedStartByID[block.id] = translatedFullCursor
            translatedFullCursor += (block.text as NSString).length
        }

        for (blockIndex, sourceBlock) in sourceBlocks.enumerated() {
            if blockIndex > 0 {
                sourceCursor += blockSeparator.utf16.count
            }
            let sourceText = sourceBlock.text
            let sourceNS = sourceText as NSString
            let sourceBlockStart = sourceCursor
            let sourceBlockLen = sourceNS.length
            sourceCursor += sourceBlockLen

            let translatedText = translatedByID[sourceBlock.id] ?? ""
            let translatedNS = translatedText as NSString
            let translatedBlockStart = translatedStartByID[sourceBlock.id] ?? 0
            let translatedBlockLen = translatedNS.length
            _ = translatedCursorByID[sourceBlock.id] // keep symmetry for future edits

            let sourcePieces = splitIntoUnits(sourceText)
            guard !sourcePieces.isEmpty else { continue }

            if translatedBlockLen == 0 {
                for (unitIndex, piece) in sourcePieces.enumerated() {
                    let sourceRange = NSRange(
                        location: sourceBlockStart + piece.utf16Location,
                        length: piece.utf16Length
                    )
                    result.append(
                        DocumentProofreadingUnit(
                            id: "\(sourceBlock.id)#\(unitIndex)",
                            blockID: sourceBlock.id,
                            unitIndexInBlock: unitIndex,
                            sourceUTF16Range: sourceRange,
                            translatedUTF16Range: NSRange(location: translatedBlockStart, length: 0),
                            sourceText: piece.text,
                            translatedText: ""
                        )
                    )
                }
                continue
            }

            let translatedPieces = splitIntoUnits(translatedText)
            if translatedPieces.count == sourcePieces.count {
                for (unitIndex, pair) in zip(sourcePieces, translatedPieces).enumerated() {
                    let sourceRange = NSRange(
                        location: sourceBlockStart + pair.0.utf16Location,
                        length: pair.0.utf16Length
                    )
                    let translatedRange = NSRange(
                        location: translatedBlockStart + pair.1.utf16Location,
                        length: pair.1.utf16Length
                    )
                    result.append(
                        DocumentProofreadingUnit(
                            id: "\(sourceBlock.id)#\(unitIndex)",
                            blockID: sourceBlock.id,
                            unitIndexInBlock: unitIndex,
                            sourceUTF16Range: sourceRange,
                            translatedUTF16Range: translatedRange,
                            sourceText: pair.0.text,
                            translatedText: pair.1.text
                        )
                    )
                }
            } else {
                // Proportional mapping inside the block keeps a stable left→right
                // correspondence even when sentence segmentation disagrees.
                for (unitIndex, piece) in sourcePieces.enumerated() {
                    let sourceRange = NSRange(
                        location: sourceBlockStart + piece.utf16Location,
                        length: piece.utf16Length
                    )
                    let translatedRange: NSRange
                    if sourceBlockLen <= 0 {
                        translatedRange = NSRange(location: translatedBlockStart, length: 0)
                    } else {
                        let startRatio = Double(piece.utf16Location) / Double(sourceBlockLen)
                        let endRatio = Double(piece.utf16Location + piece.utf16Length) / Double(sourceBlockLen)
                        var tStart = Int((startRatio * Double(translatedBlockLen)).rounded(.down))
                        var tEnd = Int((endRatio * Double(translatedBlockLen)).rounded(.up))
                        tStart = max(0, min(translatedBlockLen, tStart))
                        tEnd = max(tStart, min(translatedBlockLen, tEnd))
                        // Prefer word-ish bounds so highlight does not mid-cut glyphs.
                        tStart = snapToTokenBoundary(in: translatedNS, preferred: tStart, blockLength: translatedBlockLen, favorStart: true)
                        tEnd = snapToTokenBoundary(in: translatedNS, preferred: tEnd, blockLength: translatedBlockLen, favorStart: false)
                        if tEnd < tStart { tEnd = tStart }
                        translatedRange = NSRange(location: translatedBlockStart + tStart, length: tEnd - tStart)
                    }
                    let translatedSlice: String
                    if translatedRange.length > 0,
                       translatedRange.location >= translatedBlockStart,
                       translatedRange.location + translatedRange.length <= translatedBlockStart + translatedBlockLen {
                        let local = NSRange(
                            location: translatedRange.location - translatedBlockStart,
                            length: translatedRange.length
                        )
                        translatedSlice = translatedNS.substring(with: local)
                    } else {
                        translatedSlice = ""
                    }
                    result.append(
                        DocumentProofreadingUnit(
                            id: "\(sourceBlock.id)#\(unitIndex)",
                            blockID: sourceBlock.id,
                            unitIndexInBlock: unitIndex,
                            sourceUTF16Range: sourceRange,
                            translatedUTF16Range: translatedRange,
                            sourceText: piece.text,
                            translatedText: translatedSlice
                        )
                    )
                }
            }
        }
        return result
    }

    // MARK: - Splitters

    private struct Piece {
        var text: String
        var utf16Location: Int
        var utf16Length: Int
    }

    /// Sentences when punctuation exists; otherwise individual words.
    public static func splitIntoUnitTexts(_ text: String) -> [String] {
        splitIntoUnits(text).map(\.text)
    }

    private static func splitIntoUnits(_ text: String) -> [Piece] {
        let trimmedProbe = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProbe.isEmpty else { return [] }

        let sentencePieces = sentencePiecesWithRanges(text)
        if sentencePieces.count >= 2 {
            return sentencePieces
        }
        if sentencePieces.count == 1 {
            let only = sentencePieces[0]
            let core = only.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let last = core.last, ".!?。！？".contains(last) {
                return sentencePieces
            }
            // No sentence boundary → word-level units.
            let words = wordPiecesWithRanges(text)
            return words.isEmpty ? sentencePieces : words
        }
        return wordPiecesWithRanges(text)
    }

    private static func sentencePiecesWithRanges(_ text: String) -> [Piece] {
        var pieces: [Piece] = []
        var currentStart = text.startIndex
        var index = text.startIndex
        var quoteDepth = 0
        var parenthesisDepth = 0
        let openingQuotes: Set<Character> = ["\"", "“", "«", "„"]
        let closingQuotes: Set<Character> = ["\"", "”", "»"]

        func flush(upTo end: String.Index) {
            guard currentStart < end else { return }
            let slice = String(text[currentStart..<end])
            let trimmed = slice.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                currentStart = end
                return
            }
            // Keep leading spaces out of the highlight where possible.
            var highlightStart = currentStart
            while highlightStart < end, text[highlightStart].isWhitespace {
                highlightStart = text.index(after: highlightStart)
            }
            var highlightEnd = end
            while highlightEnd > highlightStart {
                let prev = text.index(before: highlightEnd)
                if text[prev].isWhitespace || text[prev].isNewline {
                    highlightEnd = prev
                } else {
                    break
                }
            }
            let highlight = String(text[highlightStart..<highlightEnd])
            let utf16Location = text.utf16.distance(from: text.startIndex, to: highlightStart)
            let utf16Length = highlight.utf16.count
            pieces.append(Piece(text: highlight, utf16Location: utf16Location, utf16Length: utf16Length))
            currentStart = end
        }

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)

            if openingQuotes.contains(character) {
                if character == "\"" {
                    quoteDepth = quoteDepth == 0 ? 1 : 0
                } else {
                    quoteDepth += 1
                }
            } else if closingQuotes.contains(character), quoteDepth > 0 {
                quoteDepth -= 1
            } else if character == "(" || character == "[" || character == "{" {
                parenthesisDepth += 1
            } else if (character == ")" || character == "]" || character == "}"), parenthesisDepth > 0 {
                parenthesisDepth -= 1
            }

            if ".!?。！？".contains(character), quoteDepth == 0, parenthesisDepth == 0 {
                flush(upTo: next)
            }
            index = next
        }
        flush(upTo: text.endIndex)
        return pieces
    }

    private static func wordPiecesWithRanges(_ text: String) -> [Piece] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var pieces: [Piece] = []
        ns.enumerateSubstrings(in: full, options: [.byWords, .localized]) { substring, range, _, _ in
            guard let substring, !substring.isEmpty else { return }
            pieces.append(Piece(text: substring, utf16Location: range.location, utf16Length: range.length))
        }
        if pieces.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pieces.append(Piece(text: text, utf16Location: 0, utf16Length: ns.length))
        }
        return pieces
    }

    private static func snapToTokenBoundary(
        in ns: NSString,
        preferred: Int,
        blockLength: Int,
        favorStart: Bool
    ) -> Int {
        let clamped = max(0, min(blockLength, preferred))
        if clamped == 0 || clamped == blockLength { return clamped }
        // Walk outward a few characters to avoid mid-word cuts.
        let window = 24
        if favorStart {
            var i = clamped
            let lower = max(0, clamped - window)
            while i > lower {
                let ch = ns.substring(with: NSRange(location: i - 1, length: 1))
                if ch.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
                    return i
                }
                i -= 1
            }
            return clamped
        } else {
            var i = clamped
            let upper = min(blockLength, clamped + window)
            while i < upper {
                let ch = ns.substring(with: NSRange(location: i, length: 1))
                if ch.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
                    return i
                }
                i += 1
            }
            return clamped
        }
    }
}
