import CryptoKit
import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

// S16 (PRD §11, §12, §26.6, ADR-E2/E6): document-wide Replace Everywhere at
// the store level. Deterministic: no disk I/O (injected persistence), no
// debounce waits (autosave interval injected at 600 s), no real model weights.
//
// TEST-ISOLATION CONTRACT: every WorkflowStore construction injects a no-op
// (or recording) projectsPersistence. The default persistence writes the
// user's REAL ~/Library/Application Support/VaniScript/projects.json.
@MainActor
@Suite("Document Replace Everywhere (PRD §11, §12, §26.6)")
struct DocumentReplaceEverywhereTests {

    private func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Three-chunk document session. Every block contains the word "cat"; the
    /// Russian translations carry the three review dispositions.
    private func makeDocumentSession() -> SessionState {
        let blocks = [
            DocumentBlock(
                id: "b1",
                location: DocumentLocation(paragraphOrdinal: 0),
                kind: .paragraph,
                spans: [RichTextSpan(id: "s1", text: "cat one")],
                sourceHash: hash("cat one")
            ),
            DocumentBlock(
                id: "b2",
                location: DocumentLocation(paragraphOrdinal: 1),
                kind: .paragraph,
                spans: [RichTextSpan(id: "s2", text: "cat two")],
                sourceHash: hash("cat two")
            ),
            DocumentBlock(
                id: "b3",
                location: DocumentLocation(paragraphOrdinal: 2),
                kind: .paragraph,
                spans: [RichTextSpan(id: "s3", text: "cat three")],
                sourceHash: hash("cat three")
            ),
        ]
        let chunks = [
            ChunkData(
                index: 0,
                filePath: "/tmp/doc.docx",
                durationSec: 0,
                startSec: 0,
                endSec: 0,
                original: "cat one",
                translated: "Кот раз",
                status: .pending,
                approved: false,
                sourceAnchor: .document(DocumentRange(startBlockID: "b1", endBlockID: "b1"))
            ),
            ChunkData(
                index: 1,
                filePath: "/tmp/doc.docx",
                durationSec: 0,
                startSec: 0,
                endSec: 0,
                original: "cat two",
                translated: "Кот два",
                status: .pending,
                approved: false,
                sourceAnchor: .document(DocumentRange(startBlockID: "b2", endBlockID: "b2"))
            ),
            ChunkData(
                index: 2,
                filePath: "/tmp/doc.docx",
                durationSec: 0,
                startSec: 0,
                endSec: 0,
                original: "cat three",
                translated: "Кот три",
                status: .pending,
                approved: false,
                sourceAnchor: .document(DocumentRange(startBlockID: "b3", endBlockID: "b3"))
            ),
        ]
        let documentState = DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(key: "src", originalFileName: "doc.docx"),
            blocks: blocks,
            chunks: [
                DocumentChunkPlan(id: "p1", blockIDs: ["b1"]),
                DocumentChunkPlan(id: "p2", blockIDs: ["b2"]),
                DocumentChunkPlan(id: "p3", blockIDs: ["b3"]),
            ],
            translationsByLanguage: [
                "russian": [
                    "b1": TranslatedBlock(
                        id: "tb1",
                        blockID: "b1",
                        text: "Кот раз",
                        spans: [RichTextSpan(id: "ts1", text: "Кот раз")],
                        sourceHash: hash("cat one"),
                        reviewDisposition: .autoApproved
                    ),
                    "b2": TranslatedBlock(
                        id: "tb2",
                        blockID: "b2",
                        text: "Кот два",
                        spans: [RichTextSpan(id: "ts2", text: "Кот два")],
                        sourceHash: hash("cat two"),
                        reviewDisposition: .pending
                    ),
                    "b3": TranslatedBlock(
                        id: "tb3",
                        blockID: "b3",
                        text: "Кот три",
                        spans: [RichTextSpan(id: "ts3", text: "Кот три")],
                        sourceHash: hash("cat three"),
                        reviewDisposition: .manuallyApproved
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
            chunks: chunks,
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

    // MARK: - 1. All chunks updated through DocumentState

    @Test("Replace updates every affected chunk, current and non-current, through DocumentState")
    func allChunksUpdated() {
        let store = makeStore(session: makeDocumentSession())
        store.openProject(id: "proj-1")
        #expect(store.session?.currentChunkIndex == 0)

        let result = store.replaceEverywhereInDocument(
            query: "cat",
            replacement: "dog",
            side: .source,
            options: .init()
        )
        #expect(result?.replacedCount == 3)
        #expect(result?.touchedBlockCount == 3)

        // Canonical DocumentState carries the replacement in every block.
        let blocks = store.workflow.session?.documentState?.blocks ?? []
        #expect(blocks.first(where: { $0.id == "b1" })?.spans.map(\.text).joined() == "dog one")
        #expect(blocks.first(where: { $0.id == "b2" })?.spans.map(\.text).joined() == "dog two")
        #expect(blocks.first(where: { $0.id == "b3" })?.spans.map(\.text).joined() == "dog three")

        // Aggregate ChunkData strings refreshed for every affected chunk,
        // including the non-current ones.
        let chunks = store.workflow.session?.chunks ?? []
        #expect(chunks[0].original == "dog one")
        #expect(chunks[1].original == "dog two")
        #expect(chunks[2].original == "dog three")
    }

    // MARK: - 2. Source-side replace stales dependent translations

    @Test("Source-side replace stales translations without deleting them")
    func sourceReplaceStalesTranslations() {
        let store = makeStore(session: makeDocumentSession())
        store.openProject(id: "proj-1")
        #expect(store.staleDocumentChunkIndices == [])

        let result = store.replaceEverywhereInDocument(
            query: "cat",
            replacement: "dog",
            side: .source,
            options: .init()
        )
        #expect(result?.replacedCount == 3)

        // Every affected chunk is provably stale and flagged needsReview.
        #expect(store.staleDocumentChunkIndices == [0, 1, 2])
        let chunks = store.workflow.session?.chunks ?? []
        #expect(chunks[0].reviewDisposition == .needsReview)
        #expect(chunks[1].reviewDisposition == .needsReview)
        #expect(chunks[2].reviewDisposition == .needsReview)

        // Translations are NEVER deleted: text stays intact, only the source
        // hash now mismatches.
        let translations = store.workflow.session?.documentState?.translationsByLanguage["russian"] ?? [:]
        #expect(translations["b1"]?.text == "Кот раз")
        #expect(translations["b2"]?.text == "Кот два")
        #expect(translations["b3"]?.text == "Кот три")
        let blocks = store.workflow.session?.documentState?.blocks ?? []
        #expect(translations["b1"]?.sourceHash != blocks.first(where: { $0.id == "b1" })?.sourceHash)
    }

    // MARK: - 3. Translation-side replace semantics

    @Test("Translation-side replace keeps source intact and re-approves only autoApproved blocks")
    func translationSideReplaceSemantics() {
        let store = makeStore(session: makeDocumentSession())
        store.openProject(id: "proj-1")
        let sourceHashesBefore = (store.workflow.session?.documentState?.blocks ?? [])
            .reduce(into: [String: String]()) { $0[$1.id] = $1.sourceHash }
        let translationHashesBefore = (store.workflow.session?.documentState?.translationsByLanguage["russian"] ?? [:])
            .mapValues { $0.sourceHash }

        let result = store.replaceEverywhereInDocument(
            query: "Кот",
            replacement: "Пёс",
            side: .translation,
            options: .init()
        )
        #expect(result?.replacedCount == 3)

        // Source blocks are untouched: spans, text, and hashes unchanged.
        let blocksAfter = store.workflow.session?.documentState?.blocks ?? []
        for block in blocksAfter {
            #expect(block.sourceHash == sourceHashesBefore[block.id])
        }
        #expect(blocksAfter.first(where: { $0.id == "b1" })?.spans.map(\.text).joined() == "cat one")

        let translations = store.workflow.session?.documentState?.translationsByLanguage["russian"] ?? [:]
        // TranslatedBlock.sourceHash is preserved (no staling from this side).
        for (blockID, trans) in translations {
            #expect(trans.sourceHash == translationHashesBefore[blockID])
        }
        #expect(translations["b1"]?.text == "Пёс раз")
        #expect(translations["b2"]?.text == "Пёс два")
        #expect(translations["b3"]?.text == "Пёс три")

        // PRD §11.6.4/§11.6.5: autoApproved becomes manuallyApproved;
        // pending and manuallyApproved keep their disposition.
        #expect(translations["b1"]?.reviewDisposition == .manuallyApproved)
        #expect(translations["b2"]?.reviewDisposition == .pending)
        #expect(translations["b3"]?.reviewDisposition == .manuallyApproved)

        // Aggregate chunk translation strings refreshed.
        let chunks = store.workflow.session?.chunks ?? []
        #expect(chunks[0].translated == "Пёс раз")
        #expect(chunks[1].translated == "Пёс два")
        #expect(chunks[2].translated == "Пёс три")

        // Nothing staled from the translation side.
        #expect(store.staleDocumentChunkIndices == [])
    }

    // MARK: - 4. One transaction, one Undo, one Redo

    @Test("One replace is one Undo step restoring every touched block; redo re-applies")
    func oneTransactionOneUndo() {
        let store = makeStore(session: makeDocumentSession())
        store.openProject(id: "proj-1")
        let undoManager = UndoManager()
        store.documentUndoManager = undoManager

        let result = store.replaceEverywhereInDocument(
            query: "cat",
            replacement: "dog",
            side: .source,
            options: .init()
        )
        #expect(result?.replacedCount == 3)
        #expect(undoManager.canUndo)
        #expect(!undoManager.canRedo)

        undoManager.undo()

        // A single undo step restores every touched block and clears staleness.
        let restored = store.workflow.session?.documentState?.blocks ?? []
        #expect(restored.first(where: { $0.id == "b1" })?.spans.map(\.text).joined() == "cat one")
        #expect(restored.first(where: { $0.id == "b2" })?.spans.map(\.text).joined() == "cat two")
        #expect(restored.first(where: { $0.id == "b3" })?.spans.map(\.text).joined() == "cat three")
        let chunks = store.workflow.session?.chunks ?? []
        #expect(chunks[0].original == "cat one")
        #expect(chunks[1].original == "cat two")
        #expect(chunks[2].original == "cat three")
        #expect(store.staleDocumentChunkIndices == [])
        #expect(chunks.allSatisfy { $0.reviewDisposition != .needsReview })
        #expect(!undoManager.canUndo)
        #expect(undoManager.canRedo)

        undoManager.redo()

        let redone = store.workflow.session?.documentState?.blocks ?? []
        #expect(redone.first(where: { $0.id == "b1" })?.spans.map(\.text).joined() == "dog one")
        #expect(redone.first(where: { $0.id == "b2" })?.spans.map(\.text).joined() == "dog two")
        #expect(redone.first(where: { $0.id == "b3" })?.spans.map(\.text).joined() == "dog three")
        #expect(undoManager.canUndo)
    }

    @Test("Translation-side replace is one Undo step restoring the translations")
    func translationSideOneUndo() {
        let store = makeStore(session: makeDocumentSession())
        store.openProject(id: "proj-1")
        let undoManager = UndoManager()
        store.documentUndoManager = undoManager

        _ = store.replaceEverywhereInDocument(
            query: "Кот",
            replacement: "Пёс",
            side: .translation,
            options: .init()
        )
        #expect(store.workflow.session?.documentState?.translationsByLanguage["russian"]?["b1"]?.text == "Пёс раз")

        undoManager.undo()

        let translations = store.workflow.session?.documentState?.translationsByLanguage["russian"] ?? [:]
        #expect(translations["b1"]?.text == "Кот раз")
        #expect(translations["b2"]?.text == "Кот два")
        #expect(translations["b3"]?.text == "Кот три")
        // The undo restores the original autoApproved disposition.
        #expect(translations["b1"]?.reviewDisposition == .autoApproved)
        let chunks = store.workflow.session?.chunks ?? []
        #expect(chunks[0].translated == "Кот раз")
    }

    // MARK: - 5. One save, not N

    @Test("A multi-block replace produces exactly one disk write")
    func oneSaveNotMany() async {
        let recorder = ReplaceSaveRecorder()
        let store = makeStore(session: makeDocumentSession(), persistence: recorder.save)
        store.openProject(id: "proj-1")
        await recorder.waitForCount(1)

        let result = store.replaceEverywhereInDocument(
            query: "cat",
            replacement: "dog",
            side: .source,
            options: .init()
        )
        #expect(result?.touchedBlockCount == 3)

        // Exactly one additional write for the whole multi-block operation.
        #expect(recorder.count == 2)
        let savedBlocks = recorder.last?.first?.session.documentState?.blocks ?? []
        #expect(savedBlocks.first(where: { $0.id == "b3" })?.spans.map(\.text).joined() == "dog three")
    }

    // MARK: - 6. Zero-match no-op

    @Test("A 0-match replace is a no-op: no transaction, no save, no Undo")
    func zeroMatchIsNoOp() async {
        let recorder = ReplaceSaveRecorder()
        let store = makeStore(session: makeDocumentSession(), persistence: recorder.save)
        store.openProject(id: "proj-1")
        await recorder.waitForCount(1)
        let undoManager = UndoManager()
        store.documentUndoManager = undoManager

        let result = store.replaceEverywhereInDocument(
            query: "zebra",
            replacement: "dog",
            side: .source,
            options: .init()
        )
        #expect(result?.replacedCount == 0)
        #expect(result?.touchedBlockCount == 0)

        // No save, no Undo registered, document untouched.
        #expect(recorder.count == 1)
        #expect(!undoManager.canUndo)
        let blocks = store.workflow.session?.documentState?.blocks ?? []
        #expect(blocks.first(where: { $0.id == "b1" })?.spans.map(\.text).joined() == "cat one")
    }

    // MARK: - 7. Glossary option (PRD §12)

    @Test("Glossary save creates an entry on the source side and none on the translation side")
    func glossarySaveOption() {
        let store = makeStore(session: makeDocumentSession())
        store.openProject(id: "proj-1")
        // AppSettings.defaults ships starter glossary entries; the new rule is
        // inserted at index 0, so compare counts and inspect the head.
        let starterCount = store.settings.glossary.count

        let sourceResult = store.replaceEverywhereInDocument(
            query: "cat",
            replacement: "dog",
            side: .source,
            options: .init(saveAsGlossary: true)
        )
        #expect(sourceResult?.glossarySaved == true)
        #expect(store.settings.glossary.count == starterCount + 1)

        let entry = store.settings.glossary.first
        #expect(entry != nil)
        #expect(entry?.source == "dog")
        #expect(entry?.translation == "dog")
        #expect(entry?.variants == ["cat"])
        #expect(entry?.translations == ["Russian": "dog"])
        #expect(entry?.remember == true)

        // Translation side: the source term is ambiguous (PRD §12.2), so no
        // entry is created; the sheet opens a glossary draft instead.
        let translationStore = makeStore(session: makeDocumentSession())
        translationStore.openProject(id: "proj-1")
        let translationStarterCount = translationStore.settings.glossary.count
        let translationResult = translationStore.replaceEverywhereInDocument(
            query: "Кот",
            replacement: "Пёс",
            side: .translation,
            options: .init(saveAsGlossary: true)
        )
        #expect(translationResult?.glossarySaved == true)
        #expect(translationStore.settings.glossary.count == translationStarterCount)
    }

    // MARK: - 8. Store-level skip counts (PRD §26.6)

    @Test("Replace result surfaces protected and mixed-style skip counts from the plan report")
    func skipCountsSurfaceInResult() {
        var session = makeDocumentSession()
        // Block b2: fully protected span → replaceable 0, protected-skipped 1.
        // Block b3: "cat" split across bold/plain spans → mixed-style-skipped 1.
        if var documentState = session.documentState {
            documentState.blocks = documentState.blocks.map { block in
                switch block.id {
                case "b2":
                    var copy = block
                    copy.spans = [RichTextSpan(id: "s2", text: "cat two", translationPolicy: .protect)]
                    return copy
                case "b3":
                    var copy = block
                    copy.spans = [
                        RichTextSpan(id: "s3a", text: "ca", traits: [.bold]),
                        RichTextSpan(id: "s3b", text: "t three"),
                    ]
                    return copy
                default:
                    return block
                }
            }
            session.documentState = documentState
        }
        let store = makeStore(session: session)
        store.openProject(id: "proj-1")

        let result = store.replaceEverywhereInDocument(
            query: "cat",
            replacement: "dog",
            side: .source,
            options: .init()
        )
        #expect(result?.replacedCount == 1)
        #expect(result?.touchedBlockCount == 1)
        #expect(result?.skippedProtectedCount == 1)
        #expect(result?.skippedMixedStyleCount == 1)

        // Only b1 was replaced; b2 stays protected, b3 stays mixed.
        let blocks = store.workflow.session?.documentState?.blocks ?? []
        #expect(blocks.first(where: { $0.id == "b1" })?.spans.map(\.text).joined() == "dog one")
        #expect(blocks.first(where: { $0.id == "b2" })?.spans.map(\.text).joined() == "cat two")
        #expect(blocks.first(where: { $0.id == "b3" })?.spans.map(\.text).joined() == "cat three")
    }

    // MARK: - 9. Media isolation

    @Test("Replace Everywhere on a media session returns nil and touches nothing")
    func mediaSessionUnaffected() {
        let mediaSession = SessionState(
            sourceFile: "/tmp/video.mp4",
            sourceFileName: "video.mp4",
            durationSec: 60,
            metadata: .empty,
            sourceLang: "auto",
            targetLang: "Russian",
            transcriptionProvider: "",
            translationProvider: "",
            outputFormats: [.txt],
            chunks: [
                ChunkData(
                    index: 0,
                    filePath: "/tmp/video.mp4",
                    durationSec: 60,
                    startSec: 0,
                    endSec: 60,
                    original: "cat says hello",
                    translated: "кот говорит привет",
                    status: .pending,
                    approved: false,
                    sourceAnchor: .media(startSec: 0, endSec: 60)
                ),
            ],
            currentChunkIndex: 0
        )
        let store = makeStore(session: mediaSession)
        store.openProject(id: "proj-1")

        let result = store.replaceEverywhereInDocument(
            query: "cat",
            replacement: "dog",
            side: .source,
            options: .init()
        )
        #expect(result == nil)
        #expect(store.workflow.session?.chunks[0].original == "cat says hello")
    }
}

/// Deterministic save capture for Replace Everywhere tests (same pattern as
/// DocumentEditingCoordinatorTests.SaveRecorder).
private final class ReplaceSaveRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [[ProjectRecord]] = []

    var count: Int { lock.lock(); defer { lock.unlock() }; return snapshots.count }
    var last: [ProjectRecord]? { lock.lock(); defer { lock.unlock() }; return snapshots.last }

    /// Bounded wait for the background openProject save to land. Debounce
    /// timing itself is never waited on (interval injected at 600 s).
    func waitForCount(_ target: Int, timeoutSeconds: Double = 5) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while count < target, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    var save: @Sendable ([ProjectRecord]) throws -> Void {
        { [weak self] records in
            guard let self else { return }
            self.lock.lock()
            self.snapshots.append(records)
            self.lock.unlock()
        }
    }
}
