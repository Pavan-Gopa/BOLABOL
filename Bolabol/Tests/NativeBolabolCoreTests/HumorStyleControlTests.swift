import Foundation
import NativeBolabolCore
import Testing

private func markerCount(_ marker: String, in text: String) -> Int {
    text.components(separatedBy: marker).count - 1
}

@Test
func humorLevelUsesStableReferenceMarks() {
    #expect(HumorLevel.allCases.map(\.rawValue) == [0, 20, 40, 60, 80, 100])
    #expect(HumorLevel.comedic.mode == "comedic")
    #expect(HumorLevel.comedic.density == "high")
    #expect(HumorLevel.comedic.intensity == "high")
    #expect(HumorLevel.comedic.creativeFreedom == "high")
    #expect(HumorLevel.comedic.allowsNewHumor)
}

@Test
func humorLevelSnapsAndClampsSliderValues() {
    #expect(HumorLevel.nearest(-1).rawValue == 0)
    #expect(HumorLevel.nearest(9.4).rawValue == 0)
    #expect(HumorLevel.nearest(11).rawValue == 20)
    #expect(HumorLevel.nearest(77).rawValue == 80)
    #expect(HumorLevel.nearest(101).rawValue == 100)
    #expect(HumorLevel.nearest(.nan) == .none)
    #expect(HumorLevel.nearest(.infinity) == .none)
    #expect(HumorLevel.nearest(-.infinity) == .none)
    #expect(HumorLevel.nearest(-100) == .none)
    #expect(HumorLevel.nearest(1000) == .standUp)
    for mark in HumorLevel.allCases {
        #expect(HumorLevel.nearest(Double(mark.rawValue)) == mark)
    }
    // The documented rule is ties-to-away-from-zero, so every positive
    // midpoint selects the next reference mark.
    #expect([10, 30, 50, 70, 90].map { HumorLevel.nearest(Double($0)).rawValue } == [20, 40, 60, 80, 100])
    #expect(HumorLevel(clamping: 77).rawValue == 77)
}

@Test
func humorRuntimeBlockContainsNumericAndDescriptiveControls() {
    let block = HumorRuntimeStyleControls(
        level: HumorLevel(clamping: 77),
        mode: .casualHumor
    ).promptBlock

    #expect(block.contains("HUMOR_LEVEL: 77"))
    #expect(block.contains("BASE MODE: CASUAL + HUMOR"))
    #expect(block.contains("1-20: use very light, sparse wit."))
    #expect(block.contains("81-100: allow a highly creative"))
    #expect(block.contains("automatically reduce"))
}

@Test
func allHumorPromptModesUseTheSameNumericParameter() {
    for mode in HumorPromptMode.allCases {
        let block = HumorRuntimeStyleControls(
            level: HumorLevel(clamping: 60),
            mode: mode
        ).promptBlock

        #expect(block.contains("HUMOR_LEVEL: 60"))
        #expect(block.contains(mode.runtimeInstruction))
    }
}

@Test
func runtimeControlsAreAddedToATransientTemplateCopy() throws {
    let template = PromptTemplate(
        id: "custom-variant-two",
        title: "Custom Variant 2",
        body: "Rewrite this faithfully.\n\nINPUT:\n${transcription}"
    )

    let configured = template.applying(
        runtimeStyleControls: HumorRuntimeStyleControls(
            level: .comedic,
            mode: .warmRespectful
        )
    )
    let rendered = try configured.renderForChat(transcription: "source text")

    #expect(markerCount("RUNTIME CONTROL:", in: template.body) == 0)
    #expect(markerCount("HUMOR_LEVEL:", in: template.body) == 0)
    #expect(markerCount("RUNTIME CONTROL:", in: configured.body) == 1)
    #expect(markerCount("HUMOR_LEVEL:", in: configured.body) == 1)
    #expect(rendered.systemInstruction.contains("BASE MODE: WARM & RESPECTFUL"))
    #expect(rendered.userContent == "source text")
}

@Test
func runtimeControlsRemainIdempotentWhenAppliedRepeatedly() {
    let template = PromptTemplate(
        id: "idempotent-runtime-controls",
        title: "Idempotent Runtime Controls",
        body: "Rewrite faithfully.\n\nINPUT:\n${transcription}"
    )
    let controls = HumorRuntimeStyleControls(level: .humorous, mode: .playful)

    let configuredOnce = template.applying(runtimeStyleControls: controls)
    let configuredTwice = configuredOnce.applying(runtimeStyleControls: controls)

    #expect(markerCount("RUNTIME CONTROL:", in: configuredTwice.body) == 1)
    #expect(markerCount("HUMOR_LEVEL:", in: configuredTwice.body) == 1)
}

@Test
func runtimeControlsReplaceAnExistingGeneratedBlockWhenLevelOrModeChanges() {
    let template = PromptTemplate(
        id: "replaceable-runtime-controls",
        title: "Replaceable Runtime Controls",
        body: "Prompt prose.\n\nINPUT:\n${transcription}"
    )

    let first = template.applying(
        runtimeStyleControls: .init(level: .subtle, mode: .playful)
    )
    let replaced = first.applying(
        runtimeStyleControls: .init(level: .standUp, mode: .warmRespectful)
    )

    #expect(markerCount("RUNTIME CONTROL:", in: replaced.body) == 1)
    #expect(markerCount("HUMOR_LEVEL:", in: replaced.body) == 1)
    #expect(replaced.body.contains("HUMOR_LEVEL: 100"))
    #expect(replaced.body.contains("BASE MODE: WARM & RESPECTFUL"))
    #expect(!replaced.body.contains("HUMOR_LEVEL: 20"))
    #expect(!replaced.body.contains("BASE MODE: PLAYFUL"))
}

@Test
func removingGeneratedRuntimeControlsDisablesOnlyTheGeneratedBlock() {
    let template = PromptTemplate(
        id: "disable-runtime-controls",
        title: "Disable Runtime Controls",
        body: "Keep user RUNTIME CONTROL: prose.\n\nINPUT:\n${transcription}"
    )
    let enabled = template.applying(
        runtimeStyleControls: .init(level: .comedic, mode: .casualHumor)
    )

    let disabled = enabled.removingGeneratedRuntimeStyleControls()
    let reenabled = disabled.applying(
        runtimeStyleControls: .init(level: .humorous, mode: .playful)
    )

    #expect(disabled.body == template.body)
    #expect(disabled.body.contains("user RUNTIME CONTROL: prose."))
    #expect(markerCount("RUNTIME CONTROL:", in: reenabled.body) == 2)
    #expect(markerCount("HUMOR_LEVEL:", in: reenabled.body) == 1)
    #expect(reenabled.body.contains("HUMOR_LEVEL: 60"))
}

@Test
func runtimeControlsHandleEmptyLongUnicodeAndMarkerLikePromptBodies() {
    let bodies = [
        "",
        String(repeating: "Long prompt section. ", count: 10_000) + "\nINPUT:\n${transcription}",
        "مرحبا мир 😀\nKeep the words RUNTIME CONTROL as ordinary prose.\nINPUT:\n${transcription}",
        "First line\nSecond line\nThird line\nINPUT:\n${transcription}"
    ]

    for (index, body) in bodies.enumerated() {
        let configured = PromptTemplate(
            id: "edge-prompt-\(index)",
            title: "Edge Prompt \(index)",
            body: body
        ).applying(runtimeStyleControls: .init(level: .subtle, mode: .warmRespectful))

        #expect(markerCount("RUNTIME CONTROL:", in: configured.body) == 1)
        #expect(markerCount("HUMOR_LEVEL:", in: configured.body) == 1)
        #expect(configured.body.contains("HUMOR_LEVEL: 20"))
        #expect(configured.body.contains("BASE MODE: WARM & RESPECTFUL"))
    }
}

@MainActor
@Test
func polishingWorkflowAddsHumorControlsOnlyToVariantTwo() async {
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "raw transcript",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = HumorCapturingPolishingEngine()
    let workflow = PolishingWorkflow(
        noteStore: store,
        engine: engine,
        humorLevel: .comedic
    )

    await workflow.polishNote(
        note.id,
        variants: [.variantOne, .variantTwo]
    )

    let requests = await engine.requests
    let variantOneBody = requests.first(where: { $0.variant == .variantOne })?.template.body ?? ""
    let variantTwoBody = requests.first(where: { $0.variant == .variantTwo })?.template.body ?? ""

    #expect(markerCount("RUNTIME CONTROL:", in: variantOneBody) == 0)
    #expect(markerCount("HUMOR_LEVEL:", in: variantOneBody) == 0)
    #expect(markerCount("RUNTIME CONTROL:", in: variantTwoBody) == 1)
    #expect(markerCount("HUMOR_LEVEL:", in: variantTwoBody) == 1)
    #expect(variantTwoBody.contains("BASE MODE: PLAYFUL"))
}

@MainActor
@Test
func polishingWorkflowOmitsRuntimeControlWhenHumorSliderIsDisabled() async {
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "raw transcript",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = HumorCapturingPolishingEngine()
    let workflow = PolishingWorkflow(noteStore: store, engine: engine)

    await workflow.polishNote(note.id, variants: [.variantTwo])

    let requests = await engine.requests
    let body = requests.first?.template.body ?? ""
    #expect(!body.contains("RUNTIME CONTROL:"))
    #expect(!body.contains("HUMOR_LEVEL:"))
}

@MainActor
@Test
func productionPolishingFactorySharesTheHumorContractAcrossHUDEntryPoints() async {
    // ContentView, SidebarView, and AudioPlaybackModalView all call this
    // production factory. Exercise the factory itself with each entry-point
    // contract so dropping a required humor argument cannot stay untested.
    let entryPoints = ["ContentView", "SidebarView", "AudioPlaybackModalView"]
    for entryPoint in entryPoints {
        let store = NoteStore()
        let note = store.addEmptyNote()
        store.applyTranscriptionResult(
            for: note.id,
            result: TranscriptionResult(
                text: "raw transcript",
                diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
            )
        )
        let engine = HumorCapturingPolishingEngine()
        let workflow = PolishingWorkflow.make(
            noteStore: store,
            engine: engine,
            humorSliderEnabled: true,
            humorLevel: .comedic,
            humorPromptMode: .warmRespectful
        )

        await workflow.polishNote(note.id, variants: [.variantOne, .variantTwo])

        let requests = await engine.requests
        let variantOneBody = requests.first(where: { $0.variant == .variantOne })?.template.body ?? ""
        let variantTwoBody = requests.first(where: { $0.variant == .variantTwo })?.template.body ?? ""
        #expect(!entryPoint.isEmpty)
        #expect(markerCount("RUNTIME CONTROL:", in: variantOneBody) == 0)
        #expect(markerCount("HUMOR_LEVEL:", in: variantOneBody) == 0)
        #expect(markerCount("RUNTIME CONTROL:", in: variantTwoBody) == 1)
        #expect(markerCount("HUMOR_LEVEL:", in: variantTwoBody) == 1)
        #expect(variantTwoBody.contains("BASE MODE: WARM & RESPECTFUL"))
    }

    let disabledStore = NoteStore()
    let disabledNote = disabledStore.addEmptyNote()
    disabledStore.applyTranscriptionResult(
        for: disabledNote.id,
        result: TranscriptionResult(
            text: "raw transcript",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let disabledEngine = HumorCapturingPolishingEngine()
    let disabledWorkflow = PolishingWorkflow.make(
        noteStore: disabledStore,
        engine: disabledEngine,
        humorSliderEnabled: false,
        humorLevel: .comedic,
        humorPromptMode: .casualHumor
    )
    await disabledWorkflow.polishNote(disabledNote.id, variants: [.variantTwo])
    let disabledBody = (await disabledEngine.requests).first?.template.body ?? ""
    #expect(!disabledBody.contains("RUNTIME CONTROL:"))
    #expect(!disabledBody.contains("HUMOR_LEVEL:"))

    for mode in HumorPromptMode.allCases {
        let modeStore = NoteStore()
        let modeNote = modeStore.addEmptyNote()
        modeStore.applyTranscriptionResult(
            for: modeNote.id,
            result: TranscriptionResult(
                text: "raw transcript",
                diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
            )
        )
        let modeEngine = HumorCapturingPolishingEngine()
        let modeWorkflow = PolishingWorkflow.make(
            noteStore: modeStore,
            engine: modeEngine,
            humorSliderEnabled: true,
            humorLevel: .humorous,
            humorPromptMode: mode
        )
        await modeWorkflow.polishNote(modeNote.id, variants: [.variantTwo])
        let modeBody = (await modeEngine.requests).first?.template.body ?? ""
        #expect(markerCount("RUNTIME CONTROL:", in: modeBody) == 1)
        #expect(modeBody.contains(mode.runtimeInstruction))
    }
}

@Test
func humorSessionSnapshotFreezesRequestValuesAndStartsFresh() {
    let initialPrompt = PromptTemplate(
        id: "prompt-one",
        title: "Prompt One",
        body: "First ${transcription}"
    )
    var session = HumorSessionState(
        sliderEnabled: true,
        level: .comedic,
        promptMode: .casualHumor,
        selectedVariant: .variantTwo,
        selectedPromptSlot: .customOne,
        selectedPrompt: initialPrompt
    )

    let enqueued = session.freeze()
    session.update(level: .standUp)
    session.updateSelection(
        variant: .variantOne,
        promptSlot: .default,
        prompt: .defaultTemplate(for: .variantOne)
    )

    #expect(enqueued.level == .comedic)
    #expect(enqueued.promptMode == .casualHumor)
    #expect(enqueued.selectedVariant == .variantTwo)
    #expect(enqueued.selectedPromptSlot == .customOne)
    #expect(enqueued.selectedPrompt == initialPrompt)
    #expect(session.freeze().level == .standUp)

    let nextSession = HumorSessionState(
        sliderEnabled: true,
        level: .none,
        promptMode: .playful,
        selectedVariant: .variantTwo,
        selectedPromptSlot: .default,
        selectedPrompt: .defaultTemplate(for: .variantTwo)
    )
    #expect(nextSession.freeze().level == .none)
    #expect(nextSession.freeze().promptMode == .playful)
}

@Test
func humorSessionRunsOneHundredFreezeAndFreshSessionCyclesWithoutStateLeakage() {
    for cycle in 0..<100 {
        let expectedLevel = HumorLevel.allCases[cycle % HumorLevel.allCases.count]
        let expectedMode = HumorPromptMode.allCases[cycle % HumorPromptMode.allCases.count]
        let expectedSlot = PromptSlot.allCases[cycle % PromptSlot.allCases.count]
        var session = HumorSessionState(
            sliderEnabled: cycle.isMultiple(of: 2),
            level: .none,
            promptMode: .playful,
            selectedVariant: .variantOne,
            selectedPromptSlot: .default,
            selectedPrompt: .defaultTemplate(for: .variantOne)
        )
        let prompt = PromptTemplate(
            id: "cycle-\(cycle)",
            title: "Cycle \(cycle)",
            body: "Cycle \(cycle) ${transcription}"
        )
        session.update(level: expectedLevel, promptMode: expectedMode)
        session.updateSelection(
            variant: .variantTwo,
            promptSlot: expectedSlot,
            prompt: prompt
        )

        let snapshot = session.freeze()
        #expect(snapshot.level == expectedLevel)
        #expect(snapshot.promptMode == expectedMode)
        #expect(snapshot.selectedVariant == .variantTwo)
        #expect(snapshot.selectedPromptSlot == expectedSlot)
        #expect(snapshot.selectedPrompt == prompt)
    }
}

@MainActor
@Test
func humorRuntimeControlCoexistsWithTranslationWithoutLeakingIntoRawOrVariantOne() async {
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "Это исходный текст для перевода.",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = HumorCapturingPolishingEngine()
    let workflow = PolishingWorkflow.make(
        noteStore: store,
        engine: engine,
        humorSliderEnabled: true,
        humorLevel: .standUp,
        humorPromptMode: .casualHumor
    )

    await workflow.polishNote(
        note.id,
        variants: [.raw, .variantOne, .variantTwo],
        targetLanguage: "en"
    )

    let requests = await engine.requests
    #expect(requests.count == 2)
    let variantOne = requests.first(where: { $0.variant == .variantOne })?.template.body ?? ""
    let variantTwo = requests.first(where: { $0.variant == .variantTwo })?.template.body ?? ""
    #expect(markerCount("RUNTIME CONTROL:", in: variantOne) == 0)
    #expect(markerCount("HUMOR_LEVEL:", in: variantOne) == 0)
    #expect(markerCount("RUNTIME CONTROL:", in: variantTwo) == 1)
    #expect(markerCount("HUMOR_LEVEL:", in: variantTwo) == 1)
    #expect(variantTwo.contains("TRANSLATION OVERRIDE"))
}

private actor HumorCapturingPolishingEngine: PolishingEngine {
    nonisolated let id = "humor-capturing-polish-engine"
    nonisolated let displayName = "Humor Capturing Polish Engine"

    private(set) var requests: [PolishingRequest] = []

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        requests.append(request)
        return PolishingResult(
            text: request.rawText,
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}
