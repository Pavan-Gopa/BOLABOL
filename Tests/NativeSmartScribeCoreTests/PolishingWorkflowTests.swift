import Foundation
import NativeSmartScribeCore
import Testing

@MainActor
@Test
func polishingWorkflowStoresBothPolishedVariants() async {
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "hello from the raw transcript.",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let workflow = PolishingWorkflow(
        noteStore: store,
        engine: SuccessfulPolishingEngine()
    )

    await workflow.polishNote(note.id)

    let updated = store.selectedNote
    #expect(updated?.polishedVariantOne == "Variant 1: hello from the raw transcript.")
    #expect(updated?.polishedVariantTwo == "Variant 2: hello from the raw transcript.")
    #expect(updated?.polishingStatus(for: .variantOne).phase == .completed)
    #expect(updated?.polishingStatus(for: .variantTwo).phase == .completed)
    #expect(updated?.polishingStatus(for: .variantOne).backendName == "Successful Polish Engine")
}

@MainActor
@Test
func polishingWorkflowUsesCustomPromptTemplateProvider() async {
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "raw english text",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let workflow = PolishingWorkflow(
        noteStore: store,
        engine: RenderingPolishingEngine(),
        templateProvider: { variant in
            PromptTemplate(
                id: "\(variant.id)-custom",
                title: "Custom \(variant.title)",
                body: "CUSTOM \(variant.title): \(PromptTemplate.transcriptionPlaceholder)"
            )
        }
    )

    await workflow.polishNote(note.id, variants: [.variantOne])

    #expect(store.selectedNote?.polishedVariantOne == "CUSTOM Variant 1: raw english text")
}

@MainActor
@Test
func polishingWorkflowRetriesVariantTwoWhenRussianSourceReturnsEnglishOutput() async {
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "это русский исходный текст про API и prompt template",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = LanguageRetryPolishingEngine()
    let workflow = PolishingWorkflow(
        noteStore: store,
        engine: engine
    )

    await workflow.polishNote(note.id, variants: [.variantTwo])

    #expect(store.selectedNote?.polishedVariantTwo == "Это русский исходный текст про API и prompt template.")
    #expect(await engine.callCount == 2)
}

@MainActor
@Test
func polishingWorkflowMarksFailureWhenEngineThrows() async {
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "raw transcript",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let workflow = PolishingWorkflow(
        noteStore: store,
        engine: FailingPolishingEngine()
    )

    await workflow.polishNote(note.id, variants: [.variantOne])

    #expect(store.selectedNote?.polishedVariantOne == "")
    #expect(store.selectedNote?.polishingStatus(for: .variantOne).phase == .failed)
    #expect(store.selectedNote?.polishingStatus(for: .variantOne).message == "Polishing failed in test.")
}

@MainActor
@Test
func polishingWorkflowMarksFailureWhenEngineReturnsEmptyText() async {
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "raw transcript",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let workflow = PolishingWorkflow(
        noteStore: store,
        engine: EmptyPolishingEngine()
    )

    await workflow.polishNote(note.id, variants: [.variantOne])

    #expect(store.selectedNote?.polishedVariantOne == "")
    #expect(store.selectedNote?.polishingStatus(for: .variantOne).phase == .failed)
    #expect(
        store.selectedNote?.polishingStatus(for: .variantOne).message
            == AppText.localized(.emptyPolishingResult, language: .english)
    )
}

@MainActor
@Test
func polishingWorkflowMarksFailureWhenRawTextIsEmpty() async {
    let store = NoteStore()
    let note = store.addEmptyNote()
    let workflow = PolishingWorkflow(
        noteStore: store,
        engine: SuccessfulPolishingEngine()
    )

    await workflow.polishNote(note.id, variants: [.variantOne])

    #expect(store.selectedNote?.polishingStatus(for: .variantOne).phase == .failed)
    #expect(
        store.selectedNote?.polishingStatus(for: .variantOne).message
            == AppText.localized(.noTranscriptToPolish, language: .english)
    )
}

private struct SuccessfulPolishingEngine: PolishingEngine {
    let id = "successful-polish-engine"
    let displayName = "Successful Polish Engine"

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        let rendered = try request.template.render(transcription: request.rawText)
        #expect(rendered.contains(request.rawText))

        return PolishingResult(
            text: "\(request.variant.title): \(request.rawText)",
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}

private struct RenderingPolishingEngine: PolishingEngine {
    let id = "rendering-polish-engine"
    let displayName = "Rendering Polish Engine"

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        let rendered = try request.template.render(transcription: request.rawText)
        return PolishingResult(
            text: rendered,
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}

private struct FailingPolishingEngine: PolishingEngine {
    let id = "failing-polish-engine"
    let displayName = "Failing Polish Engine"

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        throw TestPolishingError()
    }
}

private struct EmptyPolishingEngine: PolishingEngine {
    let id = "empty-polish-engine"
    let displayName = "Empty Polish Engine"

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        PolishingResult(
            text: "   ",
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}

private actor LanguageRetryPolishingEngine: PolishingEngine {
    nonisolated let id = "language-retry-engine"
    nonisolated let displayName = "Language Retry Engine"

    private(set) var callCount = 0

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        callCount += 1
        let body = request.template.body
        let text: String
        if body.contains("CRITICAL LANGUAGE LOCK") {
            text = "Это русский исходный текст про API и prompt template."
        } else {
            text = "This is an English rewrite about API and prompt template."
        }

        return PolishingResult(
            text: text,
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}

private struct TestPolishingError: LocalizedError, Sendable {
    var errorDescription: String? {
        "Polishing failed in test."
    }
}
