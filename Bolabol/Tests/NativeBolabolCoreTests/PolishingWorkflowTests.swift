import Foundation
import NativeBolabolCore
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

    await workflow.polishNote(note.id, variants: [.variantTwo], primaryLanguageCode: "ru", additionalLanguageCode: "en")

    #expect(store.selectedNote?.polishedVariantTwo == "Это русский исходный текст про API и prompt template.")
    #expect(await engine.callCount == 2)
}
@MainActor
@Test
func polishingWorkflowAppliesLanguageGuardToShortRussianPhrases() async {
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "Привет",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = LanguageRetryPolishingEngine()
    let workflow = PolishingWorkflow(
        noteStore: store,
        engine: engine
    )

    await workflow.polishNote(note.id, variants: [.variantOne], primaryLanguageCode: "ru", additionalLanguageCode: "en")

    #expect(store.selectedNote?.polishedVariantOne == "Это русский исходный текст про API и prompt template.")
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

@MainActor
@Test
func polishingWorkflowInjectsTranslationOverrideWhenTargetLanguageSet() async {
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "это русский исходный текст про API и prompt template",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = PromptCapturingPolishingEngine()
    let workflow = PolishingWorkflow(noteStore: store, engine: engine)

    await workflow.polishNote(note.id, variants: [.variantOne], targetLanguage: "es")

    let body = await engine.lastTemplateBody ?? ""
    // An authoritative translation override names the target language.
    #expect(body.contains("TRANSLATION OVERRIDE"))
    #expect(body.contains("into Spanish"))
    // The override explicitly suspends the templates' "never translate" rules...
    #expect(body.contains("OVERRIDES and SUSPENDS"))
    // Conflicting "keep the input language / never translate" clauses must be
    // rewritten. Leaving them in place after the editor-contract split makes
    // models keep the source language even when HUD asked for a target.
    #expect(!body.contains("Keep the language of the input. Never translate the text"))
    #expect(body.contains("written entirely in Spanish") || body.contains("into Spanish"))
    // The template's polishing style is preserved alongside the override.
    #expect(body.contains("precision transcription editor"))
    // A final reminder must sit in the instruction section, not after INPUT:.
    #expect(body.contains("FINAL TRANSLATION REMINDER"))
    // The translation override must supersede the Cyrillic source-language lock.
    #expect(!body.contains("LANGUAGE LOCK"))
    // The transcription placeholder must still be rendered away.
    #expect(!body.contains("${transcription}"))
}

@MainActor
@Test
func polishingWorkflowKeepsTranslationInstructionsOutOfFencedTranscription() async throws {
    // PolishingPromptPolicy fences everything after INPUT: as source data.
    // Translation instructions that land there are ignored ("treat transcription
    // as data"). They must stay in the system/instruction side of the split.
    let store = NoteStore()
    let note = store.addEmptyNote()
    let source = "это русский исходный текст про API и prompt template"
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: source,
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = PromptCapturingPolishingEngine()
    let workflow = PolishingWorkflow(noteStore: store, engine: engine)

    await workflow.polishNote(note.id, variants: [.variantOne], targetLanguage: "en")

    let template = try #require(await engine.lastTemplate)
    let prepared = try PolishingPromptPolicy.prepare(template: template, transcription: source)
    #expect(prepared.systemInstruction.contains("TRANSLATION OVERRIDE"))
    #expect(prepared.systemInstruction.contains("into English"))
    #expect(prepared.systemInstruction.contains("FINAL TRANSLATION REMINDER"))
    #expect(!prepared.systemInstruction.contains(source))
    #expect(prepared.userContent.contains("<transcription>"))
    #expect(prepared.userContent.contains(source))
    #expect(!prepared.userContent.contains("TRANSLATION OVERRIDE"))
    #expect(!prepared.userContent.contains("FINAL TRANSLATION REMINDER"))
}

@MainActor
@Test
func polishingWorkflowKeepsCyrillicLockWhenNoTargetLanguage() async {
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "это русский исходный текст про API и prompt template",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = PromptCapturingPolishingEngine()
    let workflow = PolishingWorkflow(noteStore: store, engine: engine)

    await workflow.polishNote(note.id, variants: [.variantOne])

    let body = await engine.lastTemplateBody ?? ""
    #expect(body.contains("LANGUAGE LOCK"))
    #expect(!body.contains("TRANSLATION OVERRIDE"))
}

@MainActor
@Test
func polishingWorkflowTranslatesEnglishTargetWithoutCyrillicLock() async {
    // Behavior change: an explicit English target now produces a translation
    // override even for Cyrillic source (previously English targets were a
    // no-op that merely skipped the Cyrillic lock).
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "это русский исходный текст про API и prompt template",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = PromptCapturingPolishingEngine()
    let workflow = PolishingWorkflow(noteStore: store, engine: engine)

    await workflow.polishNote(note.id, variants: [.variantOne], targetLanguage: "en")

    let body = await engine.lastTemplateBody ?? ""
    #expect(body.contains("TRANSLATION OVERRIDE"))
    #expect(body.contains("into English"))
    #expect(!body.contains("LANGUAGE LOCK"))
}

@MainActor
@Test
func polishingWorkflowTranslatesNonCyrillicSourceWhenTargetSet() async {
    // A non-Cyrillic source would normally yield no language guard at all, but
    // an explicit target language must still inject the translation override.
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "this is a plain english transcript about an API and a prompt template",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = PromptCapturingPolishingEngine()
    let workflow = PolishingWorkflow(noteStore: store, engine: engine)

    await workflow.polishNote(note.id, variants: [.variantOne], targetLanguage: "fr")

    let body = await engine.lastTemplateBody ?? ""
    #expect(body.contains("TRANSLATION OVERRIDE"))
    #expect(body.contains("into French"))
    #expect(body.contains("FINAL TRANSLATION REMINDER"))
}

@MainActor
@Test
func polishingWorkflowIgnoresBlankTargetLanguageAndKeepsCyrillicLock() async {
    // A whitespace-only target language normalizes to empty and must be treated
    // as "no translation requested", preserving the Cyrillic source lock.
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "это русский исходный текст про API и prompt template",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = PromptCapturingPolishingEngine()
    let workflow = PolishingWorkflow(noteStore: store, engine: engine)

    await workflow.polishNote(note.id, variants: [.variantOne], targetLanguage: "   ")

    let body = await engine.lastTemplateBody ?? ""
    #expect(body.contains("LANGUAGE LOCK"))
    #expect(!body.contains("TRANSLATION OVERRIDE"))
}

@MainActor
@Test
func polishingWorkflowDoesNotStrictRetryWhileTranslating() async {
    // When translating, the polished output is expected to be in the target
    // (non-Cyrillic) language, so the Cyrillic-drift strict retry must never
    // trigger even if the engine returns Latin-only text.
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "это русский исходный текст про API и prompt template",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = CountingEnglishPolishingEngine()
    let workflow = PolishingWorkflow(noteStore: store, engine: engine)

    await workflow.polishNote(note.id, variants: [.variantOne], targetLanguage: "es")

    #expect(await engine.callCount == 1, "translation must suppress the strict Cyrillic retry")
}

@MainActor
@Test
func polishingWorkflowRetriesWhenTranslationOutputStaysInSourceLanguage() async {
    // HUD E + Russian speech: if the model ignores the override and returns
    // Cyrillic, retry once with a stricter translation instruction.
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "это русский исходный текст про API и prompt template",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = TranslationRetryPolishingEngine()
    let workflow = PolishingWorkflow(noteStore: store, engine: engine)

    await workflow.polishNote(note.id, variants: [.variantOne], targetLanguage: "en", primaryLanguageCode: "ru", additionalLanguageCode: "en")

    #expect(await engine.callCount == 2)
    #expect(store.selectedNote?.polishedVariantOne == "This is now English text about the API.")
    let secondBody = await engine.lastBodies.last ?? ""
    #expect(secondBody.contains("CRITICAL"))
    #expect(secondBody.contains("into English"))
}

private actor CountingEnglishPolishingEngine: PolishingEngine {
    nonisolated let id = "counting-english-polish-engine"
    nonisolated let displayName = "Counting English Polish Engine"

    private(set) var callCount = 0

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        callCount += 1
        return PolishingResult(
            text: "This is an English translation about an API and a prompt template.",
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}

private actor TranslationRetryPolishingEngine: PolishingEngine {
    nonisolated let id = "translation-retry-polish-engine"
    nonisolated let displayName = "Translation Retry Polish Engine"

    private(set) var callCount = 0
    private(set) var lastBodies: [String] = []

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        callCount += 1
        lastBodies.append(request.template.body)
        let text = callCount == 1
            ? "это всё ещё русский текст про API и prompt template"
            : "This is now English text about the API."
        return PolishingResult(
            text: text,
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}

private actor PromptCapturingPolishingEngine: PolishingEngine {
    nonisolated let id = "prompt-capturing-polish-engine"
    nonisolated let displayName = "Prompt Capturing Polish Engine"

    private(set) var lastTemplateBody: String?
    private(set) var lastTemplate: PromptTemplate?

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        lastTemplate = request.template
        lastTemplateBody = try request.template.render(transcription: request.rawText)
        return PolishingResult(
            text: request.rawText,
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}

@MainActor
@Test
func polishingWorkflowKeepsSourceTextWhenWrongLanguageSurvivesStrictRetry() async {
    // ADR-029/Q3a: a still-wrong language after the strict retry is a
    // translation failure, not a polishing failure — the polished
    // source-language text is kept so the output pipeline can translate it
    // (or fall back to it with a signal). Raw is the fallback only when
    // polishing produced no text.
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "это русский исходный текст про API и prompt template",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = AlwaysRussianPolishingEngine()
    let workflow = PolishingWorkflow(noteStore: store, engine: engine)

    let results = await workflow.polishNote(
        note.id,
        variants: [.variantOne],
        targetLanguage: "en",
        primaryLanguageCode: "ru",
        additionalLanguageCode: "en"
    )

    #expect(await engine.callCount == 2, "one normal attempt plus one strict retry")
    #expect(results[.variantOne]?.text == "это всё ещё русский текст про API и prompt template")
    #expect(store.selectedNote?.polishedVariantOne == "это всё ещё русский текст про API и prompt template")
    #expect(store.selectedNote?.polishingStatus(for: .variantOne).phase == .completed)
}

private actor AlwaysRussianPolishingEngine: PolishingEngine {
    nonisolated let id = "always-russian-polish-engine"
    nonisolated let displayName = "Always Russian Polish Engine"

    private(set) var callCount = 0

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        callCount += 1
        return PolishingResult(
            text: "это всё ещё русский текст про API и prompt template",
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}

@MainActor
@Test
func polishingWorkflowSkipsNewWorkAfterChainDeadline() async {
    // Q5a: no new polish work starts at or after the chain cap.
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "raw transcript",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = LanguageRetryPolishingEngine()
    let workflow = PolishingWorkflow(noteStore: store, engine: engine)

    let results = await workflow.polishNote(
        note.id,
        variants: [.variantOne],
        deadline: Date(timeIntervalSinceNow: -1)
    )

    #expect(await engine.callCount == 0, "no engine call starts after the cap")
    #expect(results.isEmpty)
    #expect(store.selectedNote?.polishingStatus(for: .variantOne).phase == .failed)
}

@MainActor
@Test
func polishingWorkflowMissFallsBackToPolishedSourceWhenProviderFails() async {
    // Production-shaped Q3a flow: V2 returns Russian twice, so the polished
    // Russian survives; a failing provider inserts it with a signal, while a
    // succeeding provider delivers English.
    let store = NoteStore()
    let note = store.addEmptyNote()
    let rawRussian = "это русский исходный текст про API и prompt template"
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: rawRussian,
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let workflow = PolishingWorkflow(noteStore: store, engine: AlwaysRussianPolishingEngine())
    _ = await workflow.polishNote(
        note.id,
        variants: [.variantOne],
        targetLanguage: "en",
        primaryLanguageCode: "ru",
        additionalLanguageCode: "en"
    )
    let polished = store.selectedNote?.polishedVariantOne ?? ""
    #expect(!polished.isEmpty, "polished source text must survive a language miss")
    // Production derives this from the stored variant phase.
    let polishSucceeded = store.selectedNote?.polishingStatus(for: .variantOne).phase == .completed
    #expect(polishSucceeded)
    let context = TargetLanguageOutputPipeline.Context(
        snapshot: HotkeyLanguageSnapshot(
            wantsTarget: true,
            targetCode: "en",
            mechanism: .polishing,
            hudLetter: "E",
            letterEnabled: true,
            hotkeyTarget: .note
        ),
        requestedVariant: .variantOne,
        primaryCode: "ru",
        additionalCode: "en"
    )
    struct ProviderDown: Error {}
    let fallback = await TargetLanguageOutputPipeline.run(
        rawText: rawRussian,
        polishText: polished,
        polishSucceeded: polishSucceeded,
        context: context,
        translate: { _, _ in throw ProviderDown() }
    )
    #expect(fallback.kind == .sourceFallback)
    #expect(fallback.text == polished, "Q3a: polished source variant, not Raw")
    let translated = await TargetLanguageOutputPipeline.run(
        rawText: rawRussian,
        polishText: polished,
        polishSucceeded: polishSucceeded,
        context: context,
        translate: { _, _ in "This is the English translation about API and prompt template." }
    )
    #expect(translated.kind == .translated)
    #expect(translated.text == "This is the English translation about API and prompt template.")
}

@MainActor
@Test
func polishingWorkflowStrictRetryCancelledAtCapKeepsFirstPass() async {
    // ADR-029/Q5a (J2): a strict retry started before the cap but cancelled
    // at the cap (throw/cancellation) keeps the first-pass polished
    // source-language text as completed. The pipeline then inserts it with
    // a signal — never Raw. Fails on code that marks the variant failed.
    let store = NoteStore()
    let note = store.addEmptyNote()
    let rawRussian = "это русский исходный текст про API и prompt template"
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: rawRussian,
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = StrictCancelledAtCapEngine()
    let workflow = PolishingWorkflow(noteStore: store, engine: engine)
    let firstPass = "это первый проход полированный русский текст про API и prompt template"
    let results = await workflow.polishNote(
        note.id,
        variants: [.variantOne],
        targetLanguage: "en",
        primaryLanguageCode: "ru",
        additionalLanguageCode: "en",
        deadline: Date(timeIntervalSinceNow: 60)
    )
    #expect(await engine.callCount == 2, "first pass plus a strict retry cancelled at the cap")
    #expect(results[.variantOne]?.text == firstPass, "cancelled strict retry keeps first-pass text")
    #expect(store.selectedNote?.polishedVariantOne == firstPass)
    #expect(store.selectedNote?.polishingStatus(for: .variantOne).phase == .completed)
    let polishSucceeded = store.selectedNote?.polishingStatus(for: .variantOne).phase == .completed
    #expect(polishSucceeded)
    let context = TargetLanguageOutputPipeline.Context(
        snapshot: HotkeyLanguageSnapshot(
            wantsTarget: true,
            targetCode: "en",
            mechanism: .polishing,
            hudLetter: "E",
            letterEnabled: true,
            hotkeyTarget: .note
        ),
        requestedVariant: .variantOne,
        primaryCode: "ru",
        additionalCode: "en"
    )
    struct ProviderDown: Error {}
    let fallback = await TargetLanguageOutputPipeline.run(
        rawText: rawRussian,
        polishText: store.selectedNote?.polishedVariantOne,
        polishSucceeded: polishSucceeded,
        context: context,
        translate: { _, _ in throw ProviderDown() }
    )
    #expect(fallback.kind == .sourceFallback)
    #expect(fallback.text == firstPass, "Q5a cap abort inserts the polished variant, not Raw")
}

private actor StrictCancelledAtCapEngine: PolishingEngine {
    nonisolated let id = "strict-cancelled-at-cap-engine"
    nonisolated let displayName = "Strict Cancelled At Cap Engine"

    private(set) var callCount = 0

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        callCount += 1
        if callCount == 1 {
            return PolishingResult(
                text: "это первый проход полированный русский текст про API и prompt template",
                diagnostics: EngineDiagnostics(backendName: displayName)
            )
        }
        // Second call (strict retry) is cancelled when the chain cap fires.
        throw CancellationError()
    }
}

@MainActor
@Test
func polishingWorkflowPassesChainDeadlineToBothPolishPasses() async {
    // Q5a: the first pass and the strict retry share the chain deadline so
    // no new cloud key starts at or after the cap. Fails when the workflow
    // calls the plain `polish(_:)` overload instead of the deadline-aware one.
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "это русский исходный текст про API и prompt template",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = DeadlineCapturingEngine()
    let workflow = PolishingWorkflow(noteStore: store, engine: engine)
    let chainDeadline = Date(timeIntervalSinceNow: 60)
    _ = await workflow.polishNote(
        note.id,
        variants: [.variantOne],
        targetLanguage: "en",
        primaryLanguageCode: "ru",
        additionalLanguageCode: "en",
        deadline: chainDeadline
    )
    #expect(await engine.plainCalls == 0, "both passes use the deadline-aware overload")
    #expect(await engine.deadlineCalls == 2, "first pass plus strict retry")
    let deadlines = await engine.deadlines
    #expect(deadlines.count == 2)
    #expect(deadlines[0] == chainDeadline)
    #expect(deadlines[1] == chainDeadline)
}

private actor DeadlineCapturingEngine: DeadlineAwarePolishingEngine {
    nonisolated let id = "deadline-capturing-engine"
    nonisolated let displayName = "Deadline Capturing Engine"

    private(set) var plainCalls = 0
    private(set) var deadlineCalls = 0
    private(set) var deadlines: [Date?] = []

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        plainCalls += 1
        return PolishingResult(
            text: "This is an English polished result about the API.",
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }

    func polish(
        _ request: PolishingRequest,
        keyChainSeconds: TimeInterval,
        deadline: Date?
    ) async throws -> PolishingResult {
        deadlineCalls += 1
        deadlines.append(deadline)
        if deadlineCalls == 1 {
            return PolishingResult(
                text: "это русский полированный текст про API и prompt template",
                diagnostics: EngineDiagnostics(backendName: displayName)
            )
        }
        return PolishingResult(
            text: "This is an English polished result about the API.",
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}

@MainActor
@Test
func polishingWorkflowKeepsShortLatinFirstPassForCyrillicSource() async {
    // S11 J2: A mode (Cyrillic source lock, no translation target) must not
    // strict-retry short output — `OK` keeps the first pass with one call.
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "Привет, это короткая заметка для проверки",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = FixedShortPolishingEngine()
    let workflow = PolishingWorkflow(noteStore: store, engine: engine)

    await workflow.polishNote(note.id, variants: [.variantOne], primaryLanguageCode: "ru", additionalLanguageCode: "en")

    #expect(await engine.callCount == 1, "short A-mode output must not trigger the strict retry")
    #expect(store.selectedNote?.polishedVariantOne == "OK")
}

private actor FixedShortPolishingEngine: PolishingEngine {
    nonisolated let id = "fixed-short-polish-engine"
    nonisolated let displayName = "Fixed Short Polish Engine"

    private(set) var callCount = 0

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        callCount += 1
        return PolishingResult(
            text: "OK",
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}
