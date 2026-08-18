import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Document proofreading alignment")
struct DocumentProofreadingAlignmentTests {
    @Test("multi-sentence paragraph pairs left and right by index")
    func pairsEqualSentenceCounts() {
        let source = [
            DocumentProofreadingAlignment.BlockText(
                id: "b1",
                text: "Hello world. Second sentence."
            )
        ]
        let translated = [
            DocumentProofreadingAlignment.BlockText(
                id: "b1",
                text: "Hej världen. Andra meningen."
            )
        ]
        let units = DocumentProofreadingAlignment.units(sourceBlocks: source, translatedBlocks: translated)
        #expect(units.count == 2)
        #expect(units[0].sourceText.contains("Hello"))
        #expect(units[0].translatedText.contains("Hej"))
        #expect(units[1].sourceText.contains("Second"))
        #expect(units[1].translatedText.contains("Andra"))
        #expect(units[0].sourceUTF16Range.length > 0)
        #expect(units[0].translatedUTF16Range.length > 0)
    }

    @Test("no sentence punctuation falls back to word units")
    func wordFallbackWhenNoSentenceBoundary() {
        let source = [DocumentProofreadingAlignment.BlockText(id: "b1", text: "one two three")]
        let translated = [DocumentProofreadingAlignment.BlockText(id: "b1", text: "ett två tre")]
        let units = DocumentProofreadingAlignment.units(sourceBlocks: source, translatedBlocks: translated)
        #expect(units.count == 3)
        #expect(units.map(\.sourceText) == ["one", "two", "three"])
        #expect(units.map(\.translatedText) == ["ett", "två", "tre"])
    }

    @Test("unequal sentence counts still produce proportional translated ranges")
    func proportionalWhenCountsDiffer() {
        let source = [
            DocumentProofreadingAlignment.BlockText(
                id: "b1",
                text: "Alpha sentence one. Beta sentence two. Gamma three."
            )
        ]
        let translated = [
            DocumentProofreadingAlignment.BlockText(
                id: "b1",
                text: "Allt i en enda översatt mening utan punkt"
            )
        ]
        let units = DocumentProofreadingAlignment.units(sourceBlocks: source, translatedBlocks: translated)
        #expect(units.count == 3)
        let fullTranslatedLen = ("Allt i en enda översatt mening utan punkt" as NSString).length
        let covered = units.reduce(0) { $0 + $1.translatedUTF16Range.length }
        #expect(covered > 0)
        for unit in units {
            #expect(unit.translatedUTF16Range.location >= 0)
            #expect(unit.translatedUTF16Range.location + unit.translatedUTF16Range.length <= fullTranslatedLen)
        }
    }

    @Test("block separators shift UTF-16 ranges for later blocks")
    func blockSeparatorOffsets() {
        let source = [
            DocumentProofreadingAlignment.BlockText(id: "a", text: "First."),
            DocumentProofreadingAlignment.BlockText(id: "b", text: "Second.")
        ]
        let translated = [
            DocumentProofreadingAlignment.BlockText(id: "a", text: "Första."),
            DocumentProofreadingAlignment.BlockText(id: "b", text: "Andra.")
        ]
        let units = DocumentProofreadingAlignment.units(sourceBlocks: source, translatedBlocks: translated)
        #expect(units.count == 2)
        #expect(units[0].blockID == "a")
        #expect(units[1].blockID == "b")
        // Second block starts after "First." + "\n\n"
        let expectedStart = ("First." as NSString).length + ("\n\n" as NSString).length
        #expect(units[1].sourceUTF16Range.location == expectedStart)
    }

    @Test("splitIntoUnitTexts exposes sentence pieces for single-block prose")
    func splitHelper() {
        let pieces = DocumentProofreadingAlignment.splitIntoUnitTexts(
            "One. Two! Three?"
        )
        #expect(pieces.count == 3)
        #expect(pieces[0].hasPrefix("One"))
        #expect(pieces[1].hasPrefix("Two"))
        #expect(pieces[2].hasPrefix("Three"))
    }
}
