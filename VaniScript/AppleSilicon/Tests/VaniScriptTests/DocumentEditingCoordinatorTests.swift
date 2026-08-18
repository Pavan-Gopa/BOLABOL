import CryptoKit
import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

// S15 (PRD §9, §14, §15, §23, §24, §26.4): freshness, transactional mutations,
// debounced autosave, and save/reopen behavior. All persistence is captured
// through the injected `projectsPersistence` closure — no disk I/O and no
// debounce-timing sleeps (the autosave interval is injected at 600 s so only
// explicit flushes can write).
@MainActor
@Suite("DocumentEditingCoordinator (PRD §14, §15, §26.4)")
struct DocumentEditingCoordinatorTests {
    private let sourceText = "Source paragraph"
    private let translatedText = "Переведенный абзац"

    private func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func makeSession() -> SessionState {
        let block = DocumentBlock(
            id: "b1",
            location: DocumentLocation(paragraphOrdinal: 0),
            kind: .paragraph,
            spans: [RichTextSpan(id: "s1", text: sourceText)],
            sourceHash: hash(sourceText)
        )
        let chunk = ChunkData(
            index: 0,
            filePath: "/tmp/doc.docx",
            durationSec: 0,
            startSec: 0,
            endSec: 0,
            original: sourceText,
            translated: translatedText,
            status: .pending,
            approved: false,
            sourceAnchor: .document(DocumentRange(startBlockID: "b1", endBlockID: "b1"))
        )
        let documentState = DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(key: "src", originalFileName: "doc.docx"),
            blocks: [block],
            chunks: [DocumentChunkPlan(id: "p1", blockIDs: ["b1"])],
            translationsByLanguage: [
                "russian": [
                    "b1": TranslatedBlock(
                        id: "tb1",
                        blockID: "b1",
                        text: translatedText,
                        sourceHash: hash(sourceText),
                        reviewDisposition: .autoApproved
                    ),
                ],
            ]
        )
        var session = SessionState(
            sourceFile: "/tmp/doc.docx",
            sourceFileName: "doc.docx",
            durationSec: 0,
            metadata: .empty,
            sourceLang: "auto",
            targetLang: "Russian",
            transcriptionProvider: "coreml-whisperkit",
            translationProvider: "mlx-native",
            outputFormats: [.txt],
            chunks: [chunk],
            currentChunkIndex: 0,
            sourceKind: .document,
            documentState: documentState,
            approvalMode: .manual
        )
        session.activeTranslationLanguage = "Russian"
        return session
    }

    private func makeStore(
        session: SessionState,
        projectID: String = "proj-1",
        persistence: (@Sendable ([ProjectRecord]) throws -> Void)? = nil
    ) -> WorkflowStore {
        let record = ProjectRecord(
            id: projectID,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
            session: session
        )
        return WorkflowStore(
            settings: AppSettings.defaults,
            projects: [record],
            settingsPersistence: { _ in },
            projectsPersistence: persistence ?? { _ in },
            autosaveInterval: .seconds(600),
            startInitialModelScan: false
        )
    }

    /// Opens the project and waits for the immediate openProject save to land.
    private func open(_ store: WorkflowStore, recorder: SaveRecorder, id: String = "proj-1") async {
        store.openProject(id: id)
        await recorder.waitForCount(1)
    }

    private func open(_ store: WorkflowStore, id: String = "proj-1") {
        store.openProject(id: id)
    }

    // MARK: - Freshness (PRD §9, §26.4)

    @Test("Source typo changes sourceHash and keeps old translation intact")
    func sourceTypoChangesHashAndKeepsTranslation() {
        let store = makeStore(session: makeSession())
        open(store)
        let originalTranslation = store.workflow.session?.documentState?.translationsByLanguage["russian"]?["b1"]
        #expect(originalTranslation != nil)

        store.updateCurrentDocumentSource(
            blocks: [(blockID: "b1", spans: [RichTextSpan(id: "s1", text: "Source paragraph typo")], text: "Source paragraph typo")],
            text: "Source paragraph typo"
        )

        let block = store.workflow.session?.documentState?.blocks.first(where: { $0.id == "b1" })
        #expect(block?.sourceHash == hash("Source paragraph typo"))
        #expect(block?.sourceHash != hash(sourceText))

        // The translation is never deleted or mutated by a source edit.
        let translation = store.workflow.session?.documentState?.translationsByLanguage["russian"]?["b1"]
        #expect(translation == originalTranslation)
        #expect(translation?.text == translatedText)
    }

    @Test("Stale translation is detected after source edit")
    func staleDetectedAfterSourceEdit() {
        let store = makeStore(session: makeSession())
        open(store)
        #expect(TranslationFreshness.derive(
            documentState: store.workflow.session!.documentState!,
            blockID: "b1",
            languageKey: "russian"
        ) == .fresh)

        store.updateCurrentDocumentSource(
            blocks: [(blockID: "b1", spans: [RichTextSpan(id: "s1", text: "Edited source")], text: "Edited source")],
            text: "Edited source"
        )

        #expect(TranslationFreshness.derive(
            documentState: store.workflow.session!.documentState!,
            blockID: "b1",
            languageKey: "russian"
        ) == .stale)
    }

    @Test("Chunk becomes needsReview when a translated block goes stale")
    func chunkBecomesNeedsReview() {
        let store = makeStore(session: makeSession())
        open(store)
        store.workflow.session?.chunks[0].reviewDisposition = .manuallyApproved
        #expect(store.workflow.session?.chunks[0].approved == true)

        store.updateCurrentDocumentSource(
            blocks: [(blockID: "b1", spans: [RichTextSpan(id: "s1", text: "Edited source")], text: "Edited source")],
            text: "Edited source"
        )

        let chunk = store.workflow.session?.chunks[0]
        #expect(chunk?.reviewDisposition == .needsReview)
        #expect(chunk?.approved == false)
    }

    @Test("Formatting-only source edit does not stale translations")
    func formattingOnlyEditKeepsFreshness() {
        let store = makeStore(session: makeSession())
        open(store)
        store.workflow.session?.chunks[0].reviewDisposition = .manuallyApproved

        // Same text, bold trait added: the text hash must not change.
        store.updateCurrentDocumentSource(
            blocks: [(blockID: "b1", spans: [RichTextSpan(id: "s1", text: sourceText, traits: [.bold])], text: sourceText)],
            text: sourceText
        )

        let block = store.workflow.session?.documentState?.blocks.first(where: { $0.id == "b1" })
        #expect(block?.sourceHash == hash(sourceText))
        #expect(block?.spans.first?.traits == [.bold])
        #expect(TranslationFreshness.derive(
            documentState: store.workflow.session!.documentState!,
            blockID: "b1",
            languageKey: "russian"
        ) == .fresh)
        #expect(store.workflow.session?.chunks[0].reviewDisposition == .manuallyApproved)
    }

    @Test("Retranslating a stale block restores the matching hash")
    func retranslationRestoresFreshness() {
        let store = makeStore(session: makeSession())
        open(store)
        store.updateCurrentDocumentSource(
            blocks: [(blockID: "b1", spans: [RichTextSpan(id: "s1", text: "Edited source")], text: "Edited source")],
            text: "Edited source"
        )
        #expect(TranslationFreshness.derive(
            documentState: store.workflow.session!.documentState!,
            blockID: "b1",
            languageKey: "russian"
        ) == .stale)

        store.updateCurrentDocumentTranslated(
            blocks: [(blockID: "b1", spans: [RichTextSpan(id: "ts1", text: "Новый перевод")], text: "Новый перевод")],
            text: "Новый перевод"
        )

        let translation = store.workflow.session?.documentState?.translationsByLanguage["russian"]?["b1"]
        #expect(translation?.sourceHash == hash("Edited source"))
        #expect(TranslationFreshness.derive(
            documentState: store.workflow.session!.documentState!,
            blockID: "b1",
            languageKey: "russian"
        ) == .fresh)
    }

    @Test("Undoing a source edit restores freshness via derived hash comparison")
    func undoRestoresFreshness() {
        let store = makeStore(session: makeSession())
        open(store)
        store.updateCurrentDocumentSource(
            blocks: [(blockID: "b1", spans: [RichTextSpan(id: "s1", text: "Edited source")], text: "Edited source")],
            text: "Edited source"
        )
        // Restore the original text: freshness returns without any extra state.
        store.updateCurrentDocumentSource(
            blocks: [(blockID: "b1", spans: [RichTextSpan(id: "s1", text: sourceText)], text: sourceText)],
            text: sourceText
        )
        #expect(TranslationFreshness.derive(
            documentState: store.workflow.session!.documentState!,
            blockID: "b1",
            languageKey: "russian"
        ) == .fresh)
    }

    // MARK: - Approval semantics (PRD §23)

    @Test("Manual edit of an autoApproved translation becomes manuallyApproved")
    func manualEditOfApprovedTranslation() {
        let store = makeStore(session: makeSession())
        open(store)
        store.updateCurrentDocumentTranslated(
            blocks: [(blockID: "b1", spans: [RichTextSpan(id: "ts1", text: "Ручная правка")], text: "Ручная правка")],
            text: "Ручная правка"
        )
        let translation = store.workflow.session?.documentState?.translationsByLanguage["russian"]?["b1"]
        #expect(translation?.reviewDisposition == .manuallyApproved)
    }

    @Test("Manual edit of a pending translation keeps its disposition")
    func manualEditOfPendingTranslationKeepsState() {
        var session = makeSession()
        session.documentState?.translationsByLanguage["russian"]?["b1"]?.reviewDisposition = .pending
        let store = makeStore(session: session)
        open(store)
        store.updateCurrentDocumentTranslated(
            blocks: [(blockID: "b1", spans: [RichTextSpan(id: "ts1", text: "Ручная правка")], text: "Ручная правка")],
            text: "Ручная правка"
        )
        let translation = store.workflow.session?.documentState?.translationsByLanguage["russian"]?["b1"]
        #expect(translation?.reviewDisposition == .pending)
    }

    // MARK: - Transactions and undo (PRD §14)

    @Test("One transaction registers exactly one undo step")
    func oneMutationOneUndoStep() {
        let store = makeStore(session: makeSession())
        open(store)
        let undoManager = UndoManager()
        let coordinator = DocumentEditingCoordinator(store: store, undoManager: undoManager)

        let transaction = DocumentEditTransaction(
            reason: .programmatic,
            side: .source,
            before: [DocumentBlockPatch(blockID: "b1", spans: [RichTextSpan(id: "s1", text: sourceText)], text: sourceText)],
            after: [DocumentBlockPatch(blockID: "b1", spans: [RichTextSpan(id: "s1", text: "Replaced text")], text: "Replaced text")]
        )
        coordinator.apply(transaction)

        #expect(undoManager.canUndo)
        #expect(!undoManager.canRedo)
        #expect(store.workflow.session?.documentState?.blocks.first?.spans.first?.text == "Replaced text")

        undoManager.undo()

        // A single undo step restores the canonical model.
        #expect(store.workflow.session?.documentState?.blocks.first?.spans.first?.text == sourceText)
        #expect(!undoManager.canUndo)
        #expect(undoManager.canRedo)

        undoManager.redo()
        #expect(store.workflow.session?.documentState?.blocks.first?.spans.first?.text == "Replaced text")
    }

    @Test("Multi-block transaction is a single undo step restoring the canonical model")
    func multiBlockTransactionSingleUndo() {
        var session = makeSession()
        let secondBlock = DocumentBlock(
            id: "b2",
            location: DocumentLocation(paragraphOrdinal: 1),
            kind: .paragraph,
            spans: [RichTextSpan(id: "s2", text: "Second paragraph")],
            sourceHash: hash("Second paragraph")
        )
        session.documentState?.blocks.append(secondBlock)
        session.documentState?.chunks = [DocumentChunkPlan(id: "p1", blockIDs: ["b1", "b2"])]
        session.chunks[0] = ChunkData(
            index: 0,
            filePath: "/tmp/doc.docx",
            durationSec: 0,
            startSec: 0,
            endSec: 0,
            original: "\(sourceText)\n\nSecond paragraph",
            translated: translatedText,
            status: .pending,
            approved: false,
            sourceAnchor: .document(DocumentRange(startBlockID: "b1", endBlockID: "b2"))
        )
        let store = makeStore(session: session)
        open(store)
        let undoManager = UndoManager()
        let coordinator = DocumentEditingCoordinator(store: store, undoManager: undoManager)

        let transaction = DocumentEditTransaction(
            reason: .replaceEverywhere,
            side: .source,
            before: [
                DocumentBlockPatch(blockID: "b1", spans: [RichTextSpan(id: "s1", text: sourceText)], text: sourceText),
                DocumentBlockPatch(blockID: "b2", spans: [RichTextSpan(id: "s2", text: "Second paragraph")], text: "Second paragraph"),
            ],
            after: [
                DocumentBlockPatch(blockID: "b1", spans: [RichTextSpan(id: "s1", text: "One")], text: "One"),
                DocumentBlockPatch(blockID: "b2", spans: [RichTextSpan(id: "s2", text: "Two")], text: "Two"),
            ]
        )
        coordinator.apply(transaction)

        let blocks = store.workflow.session?.documentState?.blocks ?? []
        #expect(blocks.first(where: { $0.id == "b1" })?.spans.first?.text == "One")
        #expect(blocks.first(where: { $0.id == "b2" })?.spans.first?.text == "Two")

        undoManager.undo()
        let restored = store.workflow.session?.documentState?.blocks ?? []
        #expect(restored.first(where: { $0.id == "b1" })?.spans.first?.text == sourceText)
        #expect(restored.first(where: { $0.id == "b2" })?.spans.first?.text == "Second paragraph")
        #expect(!undoManager.canUndo)
    }

    @Test("Transaction flushes autosave after applying")
    func transactionFlushesAutosave() async {
        let recorder = SaveRecorder()
        let store = makeStore(session: makeSession(), persistence: recorder.save)
        await open(store, recorder: recorder)
        let coordinator = DocumentEditingCoordinator(store: store, undoManager: nil)

        // Seed a pending debounced autosave via the typing path.
        store.updateCurrentDocumentSource(
            blocks: [(blockID: "b1", spans: [RichTextSpan(id: "s1", text: "Typed")], text: "Typed")],
            text: "Typed"
        )
        #expect(recorder.count == 1)

        let transaction = DocumentEditTransaction(
            reason: .programmatic,
            side: .source,
            before: [DocumentBlockPatch(blockID: "b1", spans: [RichTextSpan(id: "s1", text: "Typed")], text: "Typed")],
            after: [DocumentBlockPatch(blockID: "b1", spans: [RichTextSpan(id: "s1", text: "Patched")], text: "Patched")]
        )
        coordinator.apply(transaction)

        #expect(recorder.count == 2)
        let savedSession = recorder.last?.first?.session
        #expect(savedSession?.documentState?.blocks.first?.spans.first?.text == "Patched")
    }

    // MARK: - Debounced autosave and flush points (PRD §15)

    @Test("Typing path debounces: no immediate save, flush persists")
    func typingPathDebounces() async {
        let recorder = SaveRecorder()
        let store = makeStore(session: makeSession(), persistence: recorder.save)
        await open(store, recorder: recorder)

        store.updateCurrentDocumentSource(
            blocks: [(blockID: "b1", spans: [RichTextSpan(id: "s1", text: "Keystroke 1")], text: "Keystroke 1")],
            text: "Keystroke 1"
        )
        store.updateCurrentDocumentSource(
            blocks: [(blockID: "b1", spans: [RichTextSpan(id: "s1", text: "Keystroke 2")], text: "Keystroke 2")],
            text: "Keystroke 2"
        )
        store.updateCurrentDocumentTranslated(
            blocks: [(blockID: "b1", spans: [RichTextSpan(id: "ts1", text: "Перевод 2")], text: "Перевод 2")],
            text: "Перевод 2"
        )
        // Three keystrokes, zero extra disk writes: the autosave is still pending.
        #expect(recorder.count == 1)

        store.flushAutosave()
        #expect(recorder.count == 2)
        let savedSession = recorder.last?.first?.session
        #expect(savedSession?.documentState?.blocks.first?.spans.first?.text == "Keystroke 2")
        #expect(savedSession?.documentState?.translationsByLanguage["russian"]?["b1"]?.text == "Перевод 2")

        // A second flush with no pending edits does not rewrite the file.
        store.flushAutosave()
        #expect(recorder.count == 2)
    }

    @Test("Chunk change flushes pending autosave")
    func chunkChangeFlushes() async {
        var session = makeSession()
        let secondChunk = ChunkData(
            index: 1,
            filePath: "/tmp/doc.docx",
            durationSec: 0,
            startSec: 0,
            endSec: 0,
            original: "Second chunk",
            translated: "",
            status: .pending,
            approved: false,
            sourceAnchor: .media(startSec: 0, endSec: 0)
        )
        session.chunks.append(secondChunk)
        let recorder = SaveRecorder()
        let store = makeStore(session: session, persistence: recorder.save)
        await open(store, recorder: recorder)

        store.updateCurrentDocumentSource(
            blocks: [(blockID: "b1", spans: [RichTextSpan(id: "s1", text: "Typed")], text: "Typed")],
            text: "Typed"
        )
        #expect(recorder.count == 1)

        store.selectChunkIndex(1)
        #expect(recorder.count == 2)
        #expect(recorder.last?.first?.session.documentState?.blocks.first?.spans.first?.text == "Typed")
    }

    @Test("Project switch flushes pending autosave")
    func projectSwitchFlushes() async {
        let recorder = SaveRecorder()
        let store = makeStore(session: makeSession(), persistence: recorder.save)
        await open(store, recorder: recorder)

        store.updateCurrentDocumentSource(
            blocks: [(blockID: "b1", spans: [RichTextSpan(id: "s1", text: "Typed")], text: "Typed")],
            text: "Typed"
        )
        #expect(recorder.count == 1)

        let otherSession = makeSession()
        store.projects.append(ProjectRecord(
            id: "proj-2",
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
            session: otherSession
        ))
        store.openProject(id: "proj-2")
        // The flush is synchronous; openProject's own immediate save may follow.
        #expect(recorder.count >= 2)
        #expect(recorder.snapshotsContain(projectID: "proj-1", blockText: "Typed"))
    }

    // MARK: - Save failure semantics (PRD §24)

    @Test("Save failure keeps in-memory edits and surfaces a retryable error")
    func saveFailureKeepsEditsAndRetries() async {
        let recorder = SaveRecorder()
        let store = makeStore(session: makeSession(), persistence: recorder.save)
        await open(store, recorder: recorder)

        store.updateCurrentDocumentSource(
            blocks: [(blockID: "b1", spans: [RichTextSpan(id: "s1", text: "Typed")], text: "Typed")],
            text: "Typed"
        )
        recorder.shouldFail = true
        store.flushAutosave()

        // The failed attempt is not recorded as a successful save.
        #expect(recorder.count == 1)
        #expect(store.projectSaveFailure != nil)
        // In-memory edits survive the failed save.
        #expect(store.workflow.session?.documentState?.blocks.first?.spans.first?.text == "Typed")

        // The next flush retries automatically and clears the error.
        recorder.shouldFail = false
        store.flushAutosave()
        #expect(recorder.count == 2)
        #expect(store.projectSaveFailure == nil)
        #expect(recorder.last?.first?.session.documentState?.blocks.first?.spans.first?.text == "Typed")
    }

    // MARK: - Save and reopen (PRD §15)

    @Test("Reopen restores edited state from the persisted archive")
    func reopenRestoresEditedState() async {
        let recorder = SaveRecorder()
        let store = makeStore(session: makeSession(), persistence: recorder.save)
        await open(store, recorder: recorder)

        store.updateCurrentDocumentSource(
            blocks: [(blockID: "b1", spans: [RichTextSpan(id: "s1", text: "Edited before save")], text: "Edited before save")],
            text: "Edited before save"
        )
        store.flushAutosave()
        let persisted = recorder.last
        #expect(persisted != nil)

        // Simulate a relaunch: a fresh store loads the persisted archive.
        let reopened = makeStore(session: makeSession(), persistence: recorder.save)
        reopened.projects = persisted ?? []
        reopened.openProject(id: "proj-1")

        let block = reopened.workflow.session?.documentState?.blocks.first(where: { $0.id == "b1" })
        #expect(block?.spans.first?.text == "Edited before save")
        #expect(block?.sourceHash == hash("Edited before save"))
        #expect(reopened.workflow.session?.documentState?.translationsByLanguage["russian"]?["b1"]?.text == translatedText)
    }
}

/// Deterministic save capture for autosave tests.
final class SaveRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [[ProjectRecord]] = []
    private var failing = false

    var shouldFail: Bool {
        get { lock.lock(); defer { lock.unlock() }; return failing }
        set { lock.lock(); failing = newValue; lock.unlock() }
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return snapshots.count }
    var last: [ProjectRecord]? { lock.lock(); defer { lock.unlock() }; return snapshots.last }

    /// True if any captured snapshot contains the project with the given block text.
    func snapshotsContain(projectID: String, blockText: String) -> Bool {
        lock.lock()
        let copy = snapshots
        lock.unlock()
        return copy.contains { records in
            records.first(where: { $0.id == projectID })?
                .session.documentState?.blocks
                .contains(where: { $0.spans.map(\.text).joined() == blockText }) ?? false
        }
    }

    /// Bounded wait for background (openProject) saves to land. This only
    /// synchronizes with the pre-existing immediate save path; debounce timing
    /// itself is never waited on (the interval is injected at 600 s).
    func waitForCount(_ target: Int, timeoutSeconds: Double = 5) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while count < target, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    var save: @Sendable ([ProjectRecord]) throws -> Void {
        { [weak self] records in
            guard let self else { return }
            if self.shouldFail {
                throw NSError(domain: "SaveRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated disk failure"])
            }
            self.lock.lock()
            self.snapshots.append(records)
            self.lock.unlock()
        }
    }
}
