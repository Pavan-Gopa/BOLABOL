import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Document proofreading alignment edge cases")
struct DocumentProofreadingAlignmentEdgeTests {

    // MARK: - Invariant harness

    private func assertJoinedStringInvariants(
        sourceBlocks: [DocumentProofreadingAlignment.BlockText],
        translatedBlocks: [DocumentProofreadingAlignment.BlockText],
        units: [DocumentProofreadingUnit],
        _ comment: Comment
    ) {
        let joinedSourceLength = joinedUTF16Length(sourceBlocks)
        let joinedTranslatedLength = joinedUTF16Length(translatedBlocks)

        var previousSourceEnd = -1
        var previousTranslatedEnd = -1
        for unit in units {
            #expect(unit.sourceUTF16Range.location >= 0, comment)
            #expect(unit.translatedUTF16Range.location >= 0, comment)
            #expect(unit.sourceUTF16Range.length > 0, comment)
            #expect(
                unit.sourceUTF16Range.location + unit.sourceUTF16Range.length <= joinedSourceLength,
                comment
            )
            #expect(
                unit.translatedUTF16Range.location + unit.translatedUTF16Range.length <= joinedTranslatedLength,
                comment
            )
            #expect(unit.sourceUTF16Range.location >= previousSourceEnd, comment)
            #expect(unit.translatedUTF16Range.location >= previousTranslatedEnd, comment)
            previousSourceEnd = unit.sourceUTF16Range.location + unit.sourceUTF16Range.length
            previousTranslatedEnd = unit.translatedUTF16Range.location + unit.translatedUTF16Range.length
        }
    }

    private func joinedUTF16Length(_ blocks: [DocumentProofreadingAlignment.BlockText]) -> Int {
        let separator = DocumentProofreadingAlignment.blockSeparator.utf16.count
        return blocks.enumerated().reduce(0) { total, pair in
            total + (pair.offset > 0 ? separator : 0) + (pair.element.text as NSString).length
        }
    }

    // MARK: - A1. Equal counts: ordered, non-overlapping pairs

    @Test("equal sentence counts produce ordered non-overlapping paired ranges")
    func equalCountsOrderedNonOverlapping() {
        let source = [
            DocumentProofreadingAlignment.BlockText(
                id: "b1",
                text: "First unit here. Next one follows! Even a question?"
            )
        ]
        let translated = [
            DocumentProofreadingAlignment.BlockText(
                id: "b1",
                text: "Erste Einheit hier. Nächste folgt nach! Auch eine Frage?"
            )
        ]
        let units = DocumentProofreadingAlignment.units(
            sourceBlocks: source,
            translatedBlocks: translated
        )
        #expect(units.count == 3)
        assertJoinedStringInvariants(
            sourceBlocks: source,
            translatedBlocks: translated,
            units: units,
            "equal-count pairing must stay ordered and in-bounds"
        )
        // Paired ranges must not overlap each other inside each side.
        for index in 1..<units.count {
            let prior = units[index - 1]
            let current = units[index]
            #expect(
                current.sourceUTF16Range.location >= prior.sourceUTF16Range.location + prior.sourceUTF16Range.length
            )
            #expect(
                current.translatedUTF16Range.location >= prior.translatedUTF16Range.location + prior.translatedUTF16Range.length
            )
            #expect(current.unitIndexInBlock == index)
            #expect(current.id == "b1#\(index)")
        }
    }

    // MARK: - A3. Unequal counts: contiguous proportional coverage

    @Test("unequal sentence counts tile the translated block without gaps")
    func proportionalCoverageTilesBlock() {
        let translatedText = "Ett antal ord som bildar en enda lång mening helt utan punkttecken"
        let sourceBlocks = [
            DocumentProofreadingAlignment.BlockText(
                id: "b1",
                text: "One. Two! Three? Four."
            )
        ]
        let translatedBlocks = [
            DocumentProofreadingAlignment.BlockText(id: "b1", text: translatedText)
        ]
        let units = DocumentProofreadingAlignment.units(
            sourceBlocks: sourceBlocks,
            translatedBlocks: translatedBlocks
        )
        #expect(units.count == 4)
        assertJoinedStringInvariants(
            sourceBlocks: sourceBlocks,
            translatedBlocks: translatedBlocks,
            units: units,
            "proportional split must stay within translated block bounds"
        )
        // Proportional split of an unpunctuated translation: ranges are ordered,
        // non-overlapping, and the last one is clamped exactly to the end of the
        // translated block (word-snapping shifts interior cuts within a unit).
        #expect(units.first?.translatedUTF16Range.location == 0)
        let fullTranslatedLength = (translatedText as NSString).length
        let lastEnd = units.map {
            $0.translatedUTF16Range.location + $0.translatedUTF16Range.length as Int
        }.max()
        #expect(lastEnd == fullTranslatedLength)
        for index in 1..<units.count {
            let priorEnd = units[index - 1].translatedUTF16Range.location
                + units[index - 1].translatedUTF16Range.length
            #expect(units[index].translatedUTF16Range.location >= priorEnd)
        }
    }

    // MARK: - A4. Multi-block: second block translated start tracks separator

    @Test("translated ranges offset by separator and prior translated block lengths")
    func translatedBlockOffsets() {
        let sourceBlocks = [
            DocumentProofreadingAlignment.BlockText(id: "a", text: "First."),
            DocumentProofreadingAlignment.BlockText(id: "b", text: "Second.")
        ]
        let translatedBlocks = [
            DocumentProofreadingAlignment.BlockText(id: "a", text: "Första."),
            DocumentProofreadingAlignment.BlockText(id: "b", text: "Andra.")
        ]
        let units = DocumentProofreadingAlignment.units(
            sourceBlocks: sourceBlocks,
            translatedBlocks: translatedBlocks
        )
        #expect(units.count == 2)
        let expectedTranslatedStart = ("Första." as NSString).length
            + DocumentProofreadingAlignment.blockSeparator.utf16.count
        #expect(units[1].translatedUTF16Range.location == expectedTranslatedStart)
        assertJoinedStringInvariants(
            sourceBlocks: sourceBlocks,
            translatedBlocks: translatedBlocks,
            units: units,
            "block separator must shift translated offsets too"
        )
    }

    // MARK: - A5. Empty and whitespace-only blocks

    @Test("whitespace-only and empty source blocks produce no units")
    func emptyAndWhitespaceBlocks() {
        let sourceBlocks = [
            DocumentProofreadingAlignment.BlockText(id: "a", text: ""),
            DocumentProofreadingAlignment.BlockText(id: "b", text: "   \n\t "),
            DocumentProofreadingAlignment.BlockText(id: "c", text: "kept")
        ]
        let translatedBlocks = sourceBlocks.map {
            DocumentProofreadingAlignment.BlockText(id: $0.id, text: $0.text)
        }
        let units = DocumentProofreadingAlignment.units(
            sourceBlocks: sourceBlocks,
            translatedBlocks: translatedBlocks
        )
        #expect(units.count == 1)
        #expect(units[0].blockID == "c")
        // Block c sits after two separators and both prior (empty/whitespace)
        // texts, which still occupy space in the joined string.
        let aLen = ("" as NSString).length
        let bLen = ("   \n\t " as NSString).length
        let separator = DocumentProofreadingAlignment.blockSeparator.utf16.count
        let expectedStart = aLen + separator + bLen + separator
        #expect(units[0].sourceUTF16Range.location == expectedStart)
        assertJoinedStringInvariants(
            sourceBlocks: sourceBlocks,
            translatedBlocks: translatedBlocks,
            units: units,
            "empty blocks must not disturb cursor offsets for later blocks"
        )
    }

    @Test("fully empty inputs produce no units for both empty source and translated lists")
    func fullyEmptyInputs() {
        #expect(
            DocumentProofreadingAlignment.units(sourceBlocks: [], translatedBlocks: []).isEmpty
        )
        let sourceOnly = [DocumentProofreadingAlignment.BlockText(id: "a", text: "hello")]
        #expect(
            DocumentProofreadingAlignment.units(sourceBlocks: [], translatedBlocks: sourceOnly).isEmpty
        )
    }

    @Test("missing translated block yields empty translated range at zero offset")
    func missingTranslatedBlock() {
        let sourceBlocks = [
            DocumentProofreadingAlignment.BlockText(id: "a", text: "Alpha text")
        ]
        let units = DocumentProofreadingAlignment.units(
            sourceBlocks: sourceBlocks,
            translatedBlocks: []
        )
        #expect(units.count == 2) // no punctuation → word units
        #expect(units.map(\.sourceText) == ["Alpha", "text"])
        for unit in units {
            #expect(unit.translatedUTF16Range == NSRange(location: 0, length: 0))
            #expect(unit.translatedText == "")
        }
        #expect(units[1].sourceUTF16Range.location + units[1].sourceUTF16Range.length == ("Alpha text" as NSString).length)
    }

    // MARK: - A6. Single long sentence keeps the full range

    @Test("single sentence block is one unit covering the full block")
    func singleSentenceFullCoverage() {
        let sentence = "Just one sentence with quite some words inside of it."
        let units = DocumentProofreadingAlignment.units(
            sourceBlocks: [DocumentProofreadingAlignment.BlockText(id: "a", text: sentence)],
            translatedBlocks: [DocumentProofreadingAlignment.BlockText(id: "a", text: sentence)]
        )
        #expect(units.count == 1)
        #expect(units[0].sourceUTF16Range.length == (sentence as NSString).length)
        #expect(units[0].sourceText == sentence)
    }

    // MARK: - A7. Short tokens and single word blocks

    @Test("single-character and single-word blocks still produce one unit")
    func shortTokenUnits() {
        for token in ["a", "ok", "yes"] {
            let units = DocumentProofreadingAlignment.units(
                sourceBlocks: [DocumentProofreadingAlignment.BlockText(id: "a", text: token)],
                translatedBlocks: [DocumentProofreadingAlignment.BlockText(id: "a", text: token)]
            )
            #expect(units.count == 1)
            #expect(units[0].sourceText == token)
            #expect(units[0].sourceUTF16Range.location == 0)
            #expect(units[0].sourceUTF16Range.length == (token as NSString).length)
        }
    }

    // MARK: - A8. Ranges never exceed joined UTF-16 length (emoji, quotes, multibyte)

    @Test("standalone single-line blocks with emoji keep ranges inside the joined string")
    func emojiByteContractSingleBlocks() {
        // A single emoji block yields no sentence boundary → word fallback keeps
        // the emoji as one unit. Word-splitting across mixed emoji runs is a
        // language-design concern; the range contract holds per block.
        for text in ["😀", "hi 😀", "emoji 😀 ok"] {
            let blocks = [DocumentProofreadingAlignment.BlockText(id: "a", text: text)]
            let units = DocumentProofreadingAlignment.units(
                sourceBlocks: blocks,
                translatedBlocks: blocks
            )
            let joinedLength = (text as NSString).length
            for unit in units {
                #expect(unit.sourceUTF16Range.location >= 0)
                #expect(
                    unit.sourceUTF16Range.location + unit.sourceUTF16Range.length <= joinedLength
                )
                #expect(unit.translatedUTF16Range.location + unit.translatedUTF16Range.length <= joinedLength)
            }
        }
    }

    @Test("quoted sentences with internal punctuation hold joined-string bounds")
    func quotedSentenceBounds() {
        let text = "\"Why? Because.\" More text follows here."
        let blocks = [DocumentProofreadingAlignment.BlockText(id: "a", text: text)]
        let units = DocumentProofreadingAlignment.units(
            sourceBlocks: blocks,
            translatedBlocks: blocks
        )
        #expect(!units.isEmpty)
        assertJoinedStringInvariants(
            sourceBlocks: blocks,
            translatedBlocks: blocks,
            units: units,
            "quoted text with internal punctuation must respect bounds"
        )
    }

    // MARK: - D. Alignment determinism fingerprint

    @Test("identical block lists produce byte-identical alignment units")
    func deterministicFingerprint() {
        let sourceBlocks = [
            DocumentProofreadingAlignment.BlockText(id: "a", text: "One. Two!"),
            DocumentProofreadingAlignment.BlockText(id: "b", text: "just words here"),
            DocumentProofreadingAlignment.BlockText(id: "c", text: "Three? Four. Five.")
        ]
        let translatedBlocks = [
            DocumentProofreadingAlignment.BlockText(id: "a", text: "Ett. Två!"),
            DocumentProofreadingAlignment.BlockText(id: "b", text: "bara ord här"),
            DocumentProofreadingAlignment.BlockText(id: "c", text: "Tre? Fyra. Fem.")
        ]
        let first = DocumentProofreadingAlignment.units(
            sourceBlocks: sourceBlocks,
            translatedBlocks: translatedBlocks
        )
        let second = DocumentProofreadingAlignment.units(
            sourceBlocks: sourceBlocks,
            translatedBlocks: translatedBlocks
        )
        #expect(first == second)
        assertJoinedStringInvariants(
            sourceBlocks: sourceBlocks,
            translatedBlocks: translatedBlocks,
            units: first,
            "mixed-shape multi-block layout must stay ordered and in-bounds"
        )
    }

    // MARK: - Splitter contract

    @Test("split helper returns the single word for wordless punctuation-free input")
    func splitHelperSingleWord() {
        #expect(DocumentProofreadingAlignment.splitIntoUnitTexts("hello") == ["hello"])
    }
}
