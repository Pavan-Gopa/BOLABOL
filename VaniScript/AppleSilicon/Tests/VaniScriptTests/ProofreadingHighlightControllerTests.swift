import Foundation
import Testing
@testable import VaniScript
@testable import VaniScriptCore

@Suite("Proofreading highlight controller")
@MainActor
struct ProofreadingHighlightControllerTests {

    /// Unpunctuated word pairs build deterministic word-level units (source and
    /// translated word counts match, so pairing is 1:1 by index).
    private func inputBlocks(
        sourceText: String,
        blockID: String = "b1"
    ) -> (
        source: [DocumentProofreadingAlignment.BlockText],
        translated: [DocumentProofreadingAlignment.BlockText]
    ) {
        let words = sourceText.split(separator: " ").map(String.init)
        return (
            [DocumentProofreadingAlignment.BlockText(id: blockID, text: sourceText)],
            [DocumentProofreadingAlignment.BlockText(id: blockID, text: words.joined(separator: "-"))]
        )
    }

    @discardableResult
    private func enable(
        _ controller: ProofreadingHighlightController,
        sourceText: String,
        scopeKey: String = "chunk-1"
    ) -> String? {
        let blocks = inputBlocks(sourceText: sourceText)
        return controller.toggle(
            canEnable: true,
            sourceBlocks: blocks.source,
            translatedBlocks: blocks.translated,
            scopeKey: scopeKey
        )
    }

    @Test("toggle enable with canEnable false returns message and stays disabled")
    func toggleRejectsWhenCannotEnable() {
        let controller = ProofreadingHighlightController()
        let blocks = inputBlocks(sourceText: "one two")
        let message = controller.toggle(
            canEnable: false,
            sourceBlocks: blocks.source,
            translatedBlocks: blocks.translated,
            scopeKey: "chunk-1"
        )
        #expect(message == "Proofreading highlight needs Dual View with a translation.")
        #expect(controller.isEnabled == false)
        #expect(controller.units.isEmpty)
        #expect(controller.unitIndex == 0)
        #expect(controller.currentSourceRange == nil)
        #expect(controller.currentTranslatedRange == nil)
        #expect(controller.currentUnitID == nil)
        #expect(controller.focusToken == 0)
    }

    @Test("toggle enable succeeds, lands on first unit, bumps focusToken")
    func toggleEnableActivates() {
        let controller = ProofreadingHighlightController()
        let message = enable(controller, sourceText: "one two three")
        #expect(message == nil)
        #expect(controller.isEnabled == true)
        #expect(controller.unitIndex == 0)
        #expect(controller.units.count == 3)
        #expect(controller.currentUnitID == "b1#0")
        #expect(controller.focusToken == 1)
        #expect(controller.currentTranslatedRange == controller.units[0].translatedUTF16Range)
    }

    @Test("toggle while enabled disables and returns no message")
    func toggleDisables() {
        let controller = ProofreadingHighlightController()
        enable(controller, sourceText: "one two")
        #expect(controller.isEnabled == true)
        let blocks = inputBlocks(sourceText: "one two")
        let secondMessage = controller.toggle(
            canEnable: true,
            sourceBlocks: blocks.source,
            translatedBlocks: blocks.translated,
            scopeKey: "chunk-1"
        )
        #expect(secondMessage == nil)
        #expect(controller.isEnabled == false)
        #expect(controller.currentSourceRange == nil)
        #expect(controller.currentTranslatedRange == nil)
        // Disabling does not fabricate focus churn.
        #expect(controller.focusToken == 1)
    }

    @Test("rebuild with startAtFirst true always resets to unit zero and bumps focus")
    func rebuildStartAtFirstResetsIndex() {
        let controller = ProofreadingHighlightController()
        enable(controller, sourceText: "one two three four")

        // Simulate a user advanced to an interior unit, then a startAtFirst rebuild
        // on the SAME scope (Approve & Next style re-pin).
        controller.move(delta: 2)
        #expect(controller.unitIndex == 2)

        let blocks = inputBlocks(sourceText: "one two three four")
        controller.rebuild(
            sourceBlocks: blocks.source,
            translatedBlocks: blocks.translated,
            scopeKey: "chunk-1",
            startAtFirst: true
        )
        #expect(controller.unitIndex == 0)
        #expect(controller.focusToken == 3) // enable + move + rebuild
    }

    @Test("chunk-open path: new scopeKey forces first unit even with startAtFirst false")
    func scopeChangeForcesFirstUnit() {
        let controller = ProofreadingHighlightController()
        enable(controller, sourceText: "one two three", scopeKey: "chunk-1")
        controller.move(delta: 1)
        #expect(controller.unitIndex == 1)
        let focusBeforeSwitch = controller.focusToken

        // Unit ids repeat across chunks ("b1#1"), but scope change must ignore them.
        let blocks = inputBlocks(sourceText: "alpha beta")
        controller.rebuild(
            sourceBlocks: blocks.source,
            translatedBlocks: blocks.translated,
            scopeKey: "chunk-2",
            startAtFirst: false
        )
        #expect(controller.unitIndex == 0)
        #expect(controller.focusToken == focusBeforeSwitch + 1)
        #expect(controller.units.map(\.id) == ["b1#0", "b1#1"])
    }

    @Test("in-chunk rebuild with startAtFirst false preserves unit by id")
    func rebuildPreservesUnitByID() {
        let controller = ProofreadingHighlightController()
        enable(controller, sourceText: "one two three four")
        controller.move(delta: 1)
        #expect(controller.unitIndex == 1)
        let focusBefore = controller.focusToken

        // In-chunk text edit grows both panes but ids stay stable.
        let edited = inputBlocks(sourceText: "one two three and four")
        controller.rebuild(
            sourceBlocks: edited.source,
            translatedBlocks: edited.translated,
            scopeKey: "chunk-1",
            startAtFirst: false
        )
        #expect(controller.unitIndex == 1)
        // Preserved focus: no forced scroll on mere text edit.
        #expect(controller.focusToken == focusBefore)
    }

    @Test("in-chunk rebuild when previous id vanished resets to zero and bumps focus")
    func rebuildMissingIDResetsToStart() {
        let controller = ProofreadingHighlightController()
        enable(controller, sourceText: "one two three")
        controller.move(delta: 2)
        #expect(controller.unitIndex == 2)
        let focusBefore = controller.focusToken

        // Edit drops the block to a single word; "b1#2" no longer exists.
        let edited = inputBlocks(sourceText: "one")
        controller.rebuild(
            sourceBlocks: edited.source,
            translatedBlocks: edited.translated,
            scopeKey: "chunk-1",
            startAtFirst: false
        )
        #expect(controller.unitIndex == 0)
        #expect(controller.focusToken == focusBefore + 1)
    }

    @Test("move wraps forward past last unit and bumps focus each step")
    func moveWrapsForward() {
        let controller = ProofreadingHighlightController()
        enable(controller, sourceText: "one two three")
        #expect(controller.unitIndex == 0)
        #expect(controller.focusToken == 1)

        controller.move(delta: 1)
        #expect(controller.unitIndex == 1)
        #expect(controller.focusToken == 2)

        controller.move(delta: 1)
        #expect(controller.unitIndex == 2)
        #expect(controller.focusToken == 3)

        controller.move(delta: 1)
        #expect(controller.unitIndex == 0)
        #expect(controller.focusToken == 4)
        #expect(controller.currentSourceRange == controller.units[0].sourceUTF16Range)
    }

    @Test("move wraps backward past first unit")
    func moveWrapsBackward() {
        let controller = ProofreadingHighlightController()
        enable(controller, sourceText: "one two three")
        controller.move(delta: -1)
        #expect(controller.unitIndex == 2)
        #expect(controller.focusToken == 2)
        #expect(controller.currentSourceRange == controller.units[2].sourceUTF16Range)
    }

    @Test("move is a no-op while disabled")
    func moveNoOpWhenDisabled() {
        let controller = ProofreadingHighlightController()
        enable(controller, sourceText: "one two three")
        controller.disable()
        #expect(controller.isEnabled == false)
        let focusBefore = controller.focusToken
        controller.move(delta: 1)
        #expect(controller.unitIndex == 0)
        #expect(controller.focusToken == focusBefore)
        // move() while disabled must not resurrect ranges.
        #expect(controller.currentSourceRange == nil)
        #expect(controller.currentTranslatedRange == nil)
    }

    @Test("move with empty units is a no-op; statusLine flags disabled arrows")
    func moveNoOpWhenNoUnits() {
        let controller = ProofreadingHighlightController()
        let source = [DocumentProofreadingAlignment.BlockText(id: "b1", text: "   ")]
        let translated = [DocumentProofreadingAlignment.BlockText(id: "b1", text: "ett två")]
        _ = controller.toggle(
            canEnable: true,
            sourceBlocks: source,
            translatedBlocks: translated,
            scopeKey: "chunk-1"
        )
        #expect(controller.isEnabled == true)
        #expect(controller.units.isEmpty)
        let focusBefore = controller.focusToken
        controller.move(delta: 1)
        controller.move(delta: -1)
        #expect(controller.unitIndex == 0)
        #expect(controller.focusToken == focusBefore)
        #expect(controller.currentSourceRange == nil)
        #expect(controller.statusLine == "No units in this chunk — arrows disabled")
    }

    @Test("ranges are nil while disabled and restore on re-enable")
    func rangesGateOnEnabled() {
        let controller = ProofreadingHighlightController()
        enable(controller, sourceText: "one two")
        let sourceRange = controller.currentSourceRange
        let translatedRange = controller.currentTranslatedRange
        #expect(sourceRange != nil)
        #expect(translatedRange != nil)

        controller.disable()
        #expect(controller.currentSourceRange == nil)
        #expect(controller.currentTranslatedRange == nil)
        #expect(controller.currentUnitID == nil)

        let message = enable(controller, sourceText: "one two")
        #expect(message == nil)
        #expect(controller.currentSourceRange == sourceRange)
        #expect(controller.currentTranslatedRange == translatedRange)
    }

    @Test("multi-block scope spans both blocks in unit ordering")
    func multiBlockUnitOrdering() {
        let controller = ProofreadingHighlightController()
        let source = [
            DocumentProofreadingAlignment.BlockText(id: "b1", text: "one two"),
            DocumentProofreadingAlignment.BlockText(id: "b2", text: "three four")
        ]
        let translated = [
            DocumentProofreadingAlignment.BlockText(id: "b1", text: "ett-två"),
            DocumentProofreadingAlignment.BlockText(id: "b2", text: "tre-fyra")
        ]
        _ = controller.toggle(
            canEnable: true,
            sourceBlocks: source,
            translatedBlocks: translated,
            scopeKey: "chunk-1"
        )
        #expect(controller.units.map(\.id) == ["b1#0", "b1#1", "b2#0", "b2#1"])

        var visited: [String] = []
        visited.append(controller.currentUnitID ?? "")
        controller.move(delta: 1)
        visited.append(controller.currentUnitID ?? "")
        controller.move(delta: 1)
        visited.append(controller.currentUnitID ?? "")
        controller.move(delta: 1)
        visited.append(controller.currentUnitID ?? "")
        #expect(visited == ["b1#0", "b1#1", "b2#0", "b2#1"])

        // Each move crossed blocks yet focus bumped once per move.
        #expect(controller.focusToken == 4)
    }
}
