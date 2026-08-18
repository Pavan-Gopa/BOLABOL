import AppKit
import Combine
import Foundation
import VaniScriptCore

/// Owns dual-pane proofreading highlight state so keyboard monitors can mutate
/// a stable class reference (SwiftUI `View` value captures go stale).
@MainActor
final class ProofreadingHighlightController: ObservableObject {
    @Published var isEnabled = false
    @Published var unitIndex = 0
    @Published private(set) var units: [DocumentProofreadingUnit] = []
    /// Bumps on every intentional focus change (enable, chunk change, arrow move)
    /// so the text views force-scroll even when UTF-16 ranges coincide (e.g. both
    /// chunks start at NSRange(0, n)).
    @Published private(set) var focusToken: Int = 0

    private var scopeKey = ""

    var currentSourceRange: NSRange? {
        guard isEnabled, units.indices.contains(unitIndex) else { return nil }
        return units[unitIndex].sourceUTF16Range
    }

    var currentTranslatedRange: NSRange? {
        guard isEnabled, units.indices.contains(unitIndex) else { return nil }
        return units[unitIndex].translatedUTF16Range
    }

    var currentUnitID: String? {
        guard isEnabled, units.indices.contains(unitIndex) else { return nil }
        return units[unitIndex].id
    }

    var statusLine: String {
        guard !units.isEmpty else {
            return "No units in this chunk — arrows disabled"
        }
        let idx = min(max(0, unitIndex), units.count - 1)
        let preview = units[idx].sourceText
        let clipped = preview.count > 64 ? String(preview.prefix(61)) + "…" : preview
        return "Unit \(idx + 1) / \(units.count)  ·  ↑↓←→ move  ·  \(clipped)"
    }

    func disable() {
        isEnabled = false
    }

    func toggle(
        canEnable: Bool,
        sourceBlocks: [DocumentProofreadingAlignment.BlockText],
        translatedBlocks: [DocumentProofreadingAlignment.BlockText],
        scopeKey: String
    ) -> String? {
        if isEnabled {
            isEnabled = false
            return nil
        }
        guard canEnable else {
            return "Proofreading highlight needs Dual View with a translation."
        }
        isEnabled = true
        // Always land on the first sentence/word of the current chunk.
        rebuild(
            sourceBlocks: sourceBlocks,
            translatedBlocks: translatedBlocks,
            scopeKey: scopeKey,
            startAtFirst: true
        )
        return nil
    }

    /// - Parameter startAtFirst: `true` after enable, Approve & Next / chunk
    ///   change. `false` only for in-chunk text edits where preserving the unit
    ///   by id is useful.
    func rebuild(
        sourceBlocks: [DocumentProofreadingAlignment.BlockText],
        translatedBlocks: [DocumentProofreadingAlignment.BlockText],
        scopeKey: String,
        startAtFirst: Bool
    ) {
        let next = DocumentProofreadingAlignment.units(
            sourceBlocks: sourceBlocks,
            translatedBlocks: translatedBlocks
        )
        let scopeChanged = self.scopeKey != scopeKey
        let previousID: String? = {
            guard !startAtFirst, !scopeChanged, units.indices.contains(unitIndex) else { return nil }
            return units[unitIndex].id
        }()

        units = next
        self.scopeKey = scopeKey

        if startAtFirst || scopeChanged {
            unitIndex = 0
            bumpFocus()
            return
        }

        if let previousID, let match = next.firstIndex(where: { $0.id == previousID }) {
            unitIndex = match
        } else {
            // In-chunk edit removed the old unit — go to start, not the tail.
            unitIndex = 0
            bumpFocus()
        }
        if unitIndex >= next.count {
            unitIndex = 0
            bumpFocus()
        }
    }

    func move(delta: Int) {
        guard isEnabled, !units.isEmpty else { return }
        let count = units.count
        let next = (unitIndex + delta) % count
        unitIndex = next >= 0 ? next : next + count
        bumpFocus()
    }

    private func bumpFocus() {
        focusToken &+= 1
    }
}
