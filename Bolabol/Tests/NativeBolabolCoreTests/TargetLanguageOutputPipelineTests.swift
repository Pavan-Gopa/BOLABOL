import Foundation
import NativeBolabolCore
import Testing

// ADR-029/Q3a/Q5a pipeline chain per mechanism:
// polish(target) → verify → strict polish → verify → translation provider
// on polished text (else Raw) → verify → source fallback (requested polished
// variant if polishing succeeded, otherwise Raw).

private let pipelineEnglish = "This is an English polished result about the API."
private let pipelineRussian = "Привет! Это тестовая заметка на русском языке для проверки."

private func pipelineContext(
    target: HotkeyTarget = .x2,
    mechanism: HotkeyTranslationMechanism = .polishing,
    targetCode: String? = "en",
    startedAt: Date = Date(),
    translationSeconds: TimeInterval = 20
) -> TargetLanguageOutputPipeline.Context {
    TargetLanguageOutputPipeline.Context(
        snapshot: HotkeyLanguageSnapshot(
            wantsTarget: targetCode != nil,
            targetCode: targetCode,
            mechanism: mechanism,
            hudLetter: "E",
            letterEnabled: true,
            hotkeyTarget: target
        ),
        requestedVariant: target.processingVariant,
        primaryCode: "ru",
        additionalCode: "en",
        budget: CloudKeyFailover.TimeBudget(
            perRequestSeconds: 15,
            keyChainSeconds: 40,
            translationSeconds: translationSeconds,
            hardCapSeconds: 60
        ),
        startedAt: startedAt
    )
}

@Test
func pipelineFirstTrySuccessInsertsPolish() async {
    let outcome = await TargetLanguageOutputPipeline.run(
        rawText: pipelineRussian,
        polishText: pipelineEnglish,
        polishSucceeded: true,
        context: pipelineContext()
    )
    #expect(outcome.kind == .translated)
    #expect(outcome.text == pipelineEnglish)
    #expect(outcome.via == "polish")
    #expect(outcome.verifiedCode == "en")
}

@Test
func pipelineWrongThenStrictRetryOK() async {
    let outcome = await TargetLanguageOutputPipeline.run(
        rawText: pipelineRussian,
        polishText: pipelineRussian,
        polishSucceeded: true,
        context: pipelineContext(),
        polish: { _, strict in
            #expect(strict)
            return pipelineEnglish
        }
    )
    #expect(outcome.kind == .translated)
    #expect(outcome.text == pipelineEnglish)
    #expect(outcome.via == "strict-polish")
}

@Test
func pipelineWrongTwiceThenProviderOK() async {
    let outcome = await TargetLanguageOutputPipeline.run(
        rawText: pipelineRussian,
        polishText: pipelineRussian,
        polishSucceeded: true,
        context: pipelineContext(),
        polish: { _, _ in pipelineRussian },
        translate: { text, target in
            #expect(target == "en")
            #expect(text == pipelineRussian)
            return pipelineEnglish
        }
    )
    #expect(outcome.kind == .translated)
    #expect(outcome.via == "translation-provider")
    #expect(outcome.text == pipelineEnglish)
}

@Test
func pipelineProviderFailureFallsBackToPolishedVariant() async {
    // Q3a: requested polished variant if polishing succeeded.
    struct ProviderDown: Error {}
    let outcome = await TargetLanguageOutputPipeline.run(
        rawText: pipelineRussian,
        polishText: pipelineRussian,
        polishSucceeded: true,
        context: pipelineContext(),
        polish: { _, _ in pipelineRussian },
        translate: { _, _ in throw ProviderDown() }
    )
    #expect(outcome.kind == .sourceFallback)
    #expect(outcome.text == pipelineRussian)
    #expect(outcome.reason == "translation-error")
}

@Test
func pipelineProviderWrongLanguageFallsBackToRaw() async {
    // Q3a: Raw when polishing never succeeded.
    let outcome = await TargetLanguageOutputPipeline.run(
        rawText: pipelineRussian,
        polishText: nil,
        polishSucceeded: false,
        context: pipelineContext(),
        translate: { _, _ in pipelineRussian }
    )
    #expect(outcome.kind == .sourceFallback)
    #expect(outcome.text == pipelineRussian)
    #expect(outcome.reason == "translation-wrong-language")
}

@Test
func pipelineDeadlineFallsBack() async {
    let outcome = await TargetLanguageOutputPipeline.run(
        rawText: pipelineRussian,
        polishText: nil,
        polishSucceeded: false,
        context: pipelineContext(startedAt: Date(timeIntervalSinceNow: -120)),
        translate: { _, _ in pipelineEnglish }
    )
    #expect(outcome.kind == .sourceFallback)
    #expect(outcome.text == pipelineRussian)
    #expect(outcome.reason == "deadline")
}

@Test
func pipelineRawNativeWrongLanguageInsertsASRAndNeverCallsTranslator() async {
    let translatorCalled = CallFlag()
    let outcome = await TargetLanguageOutputPipeline.run(
        rawText: pipelineRussian,
        polishText: nil,
        polishSucceeded: false,
        context: pipelineContext(target: .raw, mechanism: .nativeASR),
        translate: { _, _ in
            await translatorCalled.set()
            return pipelineEnglish
        }
    )
    #expect(await translatorCalled.value == false, "Raw+nativeASR must never call an LLM")
    #expect(outcome.text == pipelineRussian)
    #expect(outcome.kind == .sourceFallback)
    #expect(outcome.reason == "native-asr-wrong-language")
}

@Test
func pipelineRawNativeCorrectLanguageVerifies() async {
    let translatorCalled = CallFlag()
    let outcome = await TargetLanguageOutputPipeline.run(
        rawText: pipelineEnglish,
        polishText: nil,
        polishSucceeded: false,
        context: pipelineContext(target: .raw, mechanism: .nativeASR),
        translate: { _, _ in
            await translatorCalled.set()
            return pipelineEnglish
        }
    )
    #expect(await translatorCalled.value == false, "Raw+nativeASR must never call an LLM")
    #expect(outcome.kind == .verifiedNative)
    #expect(outcome.text == pipelineEnglish)
}

private actor CallFlag {
    var value = false
    func set() { value = true }
}
@Test
func pipelineInactiveSnapshotPassesRawThrough() async {
    let outcome = await TargetLanguageOutputPipeline.run(
        rawText: pipelineRussian,
        polishText: nil,
        polishSucceeded: false,
        context: pipelineContext(targetCode: nil)
    )
    #expect(outcome.kind == .verifiedNative)
    #expect(outcome.text == pipelineRussian)
}

@Test
func pipelineStrictRetryThrowStillRunsProvider() async {
    // J2/Q3a: a post-retry language miss is a translation failure — the
    // provider still runs on the polished source text instead of bailing out.
    struct StrictDown: Error {}
    let outcome = await TargetLanguageOutputPipeline.run(
        rawText: pipelineRussian,
        polishText: pipelineRussian,
        polishSucceeded: true,
        context: pipelineContext(),
        polish: { _, _ in throw StrictDown() },
        translate: { _, _ in pipelineEnglish }
    )
    #expect(outcome.kind == .translated)
    #expect(outcome.text == pipelineEnglish)
    #expect(outcome.via == "translation-provider")
}

@Test
func pipelineExpiredChainCapSkipsNewWorkAndFallsBackToPolishedSource() async {
    // Q5a: polish consumed the 60 s chain before pipeline entry — no strict
    // retry or provider call may start. Q3a keeps the polished source text.
    let polishCalled = CallFlag()
    let translateCalled = CallFlag()
    let outcome = await TargetLanguageOutputPipeline.run(
        rawText: pipelineRussian,
        polishText: pipelineRussian,
        polishSucceeded: true,
        context: pipelineContext(startedAt: Date(timeIntervalSinceNow: -61)),
        polish: { _, _ in
            await polishCalled.set()
            return pipelineEnglish
        },
        translate: { _, _ in
            await translateCalled.set()
            return pipelineEnglish
        }
    )
    #expect(await polishCalled.value == false, "no strict retry starts after the cap")
    #expect(await translateCalled.value == false, "no provider call starts after the cap")
    #expect(outcome.kind == .sourceFallback)
    #expect(outcome.text == pipelineRussian)
    #expect(outcome.reason == "deadline")
}

@Test
func pipelineTranslationStepBoundedByTranslationSeconds() async {
    // Q5a: the provider step (including its key failover) must not run past
    // `translationSeconds` — in-flight work is cancelled at the budget.
    let startedAt = Date()
    let outcome = await TargetLanguageOutputPipeline.run(
        rawText: pipelineRussian,
        polishText: pipelineRussian,
        polishSucceeded: true,
        context: pipelineContext(translationSeconds: 0.2),
        polish: { _, _ in pipelineRussian },
        translate: { _, _ in
            try await Task.sleep(nanoseconds: 30_000_000_000)
            return pipelineEnglish
        }
    )
    #expect(outcome.kind == .sourceFallback)
    #expect(outcome.text == pipelineRussian, "Q3a: polished source text survives a provider timeout")
    #expect(Date().timeIntervalSince(startedAt) < 5, "provider must be cancelled at the budget, not awaited")
}

@Test(arguments: ["Привет", "Ок", "API готово"])
func pipelineShortSourceLanguageMustTryProviderBeforeClaimingEnglish(text: String) async {
    // An inconclusive recognizer result is not an English translation when
    // the short output still contains the source-language script.
    let outcome = await TargetLanguageOutputPipeline.run(
        rawText: text,
        polishText: text,
        polishSucceeded: true,
        context: pipelineContext(),
        translate: { _, _ in pipelineEnglish }
    )
    #expect(outcome.text == pipelineEnglish)
    #expect(outcome.kind == .translated)
    #expect(outcome.via == "translation-provider")
    #expect(outcome.verifiedCode == "en")
}

@Test
func pipelineShortWrongNativeOutputRequiresFallbackSignal() async {
    let outcome = await TargetLanguageOutputPipeline.run(
        rawText: "Привет",
        polishText: nil,
        polishSucceeded: false,
        context: pipelineContext(target: .raw, mechanism: .nativeASR)
    )
    #expect(outcome.text == "Привет", "Raw remains verbatim")
    #expect(outcome.kind == .sourceFallback, "the caller uses this kind to select Funk, amber, and the badge")
    #expect(outcome.reason == "native-asr-wrong-language")
}

@Test(arguments: ["OK", "Hi", "Yes"])
func pipelineShortEnglishOutputDoesNotSpendAnotherProviderCall(text: String) async {
    let outcome = await TargetLanguageOutputPipeline.run(
        rawText: "Привет",
        polishText: text,
        polishSucceeded: true,
        context: pipelineContext(),
        translate: { _, _ in
            Issue.record("short target-script output should not need another provider")
            return pipelineEnglish
        }
    )
    #expect(outcome.text == text)
    #expect(outcome.kind == .translated)
}

@Test
func pipelineZeroProviderBudgetPreservesPolishedSourceWithoutStartingWork() async {
    let outcome = await TargetLanguageOutputPipeline.run(
        rawText: pipelineRussian,
        polishText: pipelineRussian,
        polishSucceeded: true,
        context: pipelineContext(translationSeconds: 0),
        translate: { _, _ in
            Issue.record("no request may start at an exhausted provider deadline")
            return pipelineEnglish
        }
    )
    #expect(outcome.text == pipelineRussian)
    #expect(outcome.kind == .sourceFallback)
}
