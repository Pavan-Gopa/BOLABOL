import Foundation
import VaniScriptCore

/// Why a programmatic document edit happened. Drives the Undo action name.
enum DocumentEditReason: String, Sendable {
    case typing
    case formatting
    case aiRetranslation
    case replaceEverywhere
    case programmatic

    var undoActionName: String {
        switch self {
        case .typing: return "Edit Document"
        case .formatting: return "Format Document"
        case .aiRetranslation: return "Retranslate Selection with AI"
        case .replaceEverywhere: return "Replace Everywhere"
        case .programmatic: return "Edit Document"
        }
    }
}

/// The full replacement state for one block inside a transaction.
struct DocumentBlockPatch: Equatable, Sendable {
    let blockID: String
    let spans: [RichTextSpan]
    let text: String
    /// Translation-side patches carry the block's review disposition so an
    /// undo restores it exactly (the forward autoApproved→manuallyApproved
    /// rule is not invertible from spans/text alone). Nil for source-side and
    /// chunk-scoped patches, which never carry a disposition.
    let reviewDisposition: ReviewDisposition?

    init(blockID: String, spans: [RichTextSpan], text: String, reviewDisposition: ReviewDisposition? = nil) {
        self.blockID = blockID
        self.spans = spans
        self.text = text
        self.reviewDisposition = reviewDisposition
    }
}

/// One atomic programmatic document edit (PRD §14.2). Applying it registers
/// exactly one inverse operation with the UndoManager, so one mutation is
/// always one Undo step regardless of how many blocks it touches.
struct DocumentEditTransaction: Equatable, Sendable {
    let id: String
    let reason: DocumentEditReason
    let side: DocumentEditorSide
    let before: [DocumentBlockPatch]
    let after: [DocumentBlockPatch]
    /// Document-wide transactions (Replace Everywhere, PRD §11) apply through
    /// the canonical store path that can touch ANY block, not just the current
    /// chunk's plan. Defaults keep chunk-scoped transactions unchanged.
    let documentWide: Bool
    /// The translation language a document-wide translation-side transaction
    /// targets; nil for source-side transactions.
    let languageKey: String?

    init(
        id: String = UUID().uuidString,
        reason: DocumentEditReason,
        side: DocumentEditorSide,
        before: [DocumentBlockPatch],
        after: [DocumentBlockPatch],
        documentWide: Bool = false,
        languageKey: String? = nil
    ) {
        self.id = id
        self.reason = reason
        self.side = side
        self.before = before
        self.after = after
        self.documentWide = documentWide
        self.languageKey = languageKey
    }

    /// The transaction that reverts this one.
    var inverse: DocumentEditTransaction {
        DocumentEditTransaction(
            id: UUID().uuidString,
            reason: reason,
            side: side,
            before: after,
            after: before,
            documentWide: documentWide,
            languageKey: languageKey
        )
    }
}

/// Applies programmatic document edits through the canonical WorkflowStore
/// paths and keeps Undo/Redo model-consistent (PRD §14.3): undo and redo
/// re-apply patches through the store, never through NSTextStorage alone.
@MainActor
final class DocumentEditingCoordinator {
    private let store: WorkflowStore
    private weak var undoManager: UndoManager?

    init(store: WorkflowStore, undoManager: UndoManager? = nil) {
        self.store = store
        self.undoManager = undoManager
    }

    /// Applies the transaction's `after` patches through the canonical store
    /// update paths and registers exactly one inverse operation with the
    /// UndoManager. One mutation = one Undo step.
    func apply(_ transaction: DocumentEditTransaction) {
        applyPatches(transaction.after, side: transaction.side)
        registerUndoAction(for: transaction)
        // PRD §15: every programmatic transaction is a mandatory flush point.
        store.flushAutosave()
    }

    /// Applies a document-wide transaction (PRD §11) through the canonical
    /// store path that touches ANY block, not just the current chunk's plan.
    /// One mutation = one Undo step; mandatory autosave flush (PRD §15).
    func applyDocumentWide(_ transaction: DocumentEditTransaction, languageKey: String?) {
        store.applyDocumentEditTransaction(transaction, languageKey: languageKey)
        registerUndoAction(for: transaction)
        store.flushAutosave()
    }

    /// Programmatic undo: re-applies the `before` patches through the canonical
    /// store paths, then registers the forward operation. Registration during an
    /// UndoManager undo routes it onto the redo stack automatically.
    func performUndo(_ transaction: DocumentEditTransaction) {
        if transaction.documentWide {
            // Document-wide undo re-applies the inverse transaction through the
            // same canonical store path (any block, not just the current chunk).
            store.applyDocumentEditTransaction(transaction.inverse, languageKey: transaction.languageKey)
        } else {
            applyPatches(transaction.before, side: transaction.side)
        }
        registerRedoAction(for: transaction)
        store.flushAutosave()
    }

    /// Programmatic redo: re-applies the `after` patches through the canonical
    /// store paths, then registers the inverse. Registration during an
    /// UndoManager redo routes it back onto the undo stack automatically.
    func performRedo(_ transaction: DocumentEditTransaction) {
        if transaction.documentWide {
            store.applyDocumentEditTransaction(transaction, languageKey: transaction.languageKey)
        } else {
            applyPatches(transaction.after, side: transaction.side)
        }
        registerUndoAction(for: transaction)
        store.flushAutosave()
    }

    private func applyPatches(_ patches: [DocumentBlockPatch], side: DocumentEditorSide) {
        guard !patches.isEmpty else { return }
        let mapped = patches.map { (blockID: $0.blockID, spans: $0.spans, text: $0.text) }
        switch side {
        case .source:
            store.updateCurrentDocumentSource(blocks: mapped)
        case .translation:
            store.updateCurrentDocumentTranslated(blocks: mapped)
        }
    }

    private func registerUndoAction(for transaction: DocumentEditTransaction) {
        guard let undoManager else { return }
        // The closure captures `self` strongly so the coordinator stays alive
        // until the undo action is consumed. Document-wide transactions create
        // the coordinator in a local scope (WorkflowStore.replaceEverywhereInDocument);
        // without this retention the target would deallocate before undo()/redo().
        undoManager.registerUndo(withTarget: self) { coordinator in
            _ = coordinator
            MainActor.assumeIsolated {
                self.performUndo(transaction)
            }
        }
        undoManager.setActionName(transaction.reason.undoActionName)
    }

    private func registerRedoAction(for transaction: DocumentEditTransaction) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { coordinator in
            _ = coordinator
            MainActor.assumeIsolated {
                self.performRedo(transaction)
            }
        }
        undoManager.setActionName(transaction.reason.undoActionName)
    }
}
