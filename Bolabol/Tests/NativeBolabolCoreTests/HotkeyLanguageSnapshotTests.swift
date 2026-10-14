import Foundation
import NativeBolabolCore
import Testing

// ADR-029 capability-truthful snapshot table:
// {Raw, V1, V2} × {Parakeet, Whisper-full, Whisper-turbo, Gemini} × {E, A} × {cloud, MLX, rule}.

private func resolveSnapshot(
    target: HotkeyTarget,
    wantsTarget: Bool,
    targetCode: String? = "en",
    modelSupportsNativeTranslation: Bool = false,
    isGeminiCloud: Bool = false,
    polishingCanTranslate: Bool = false
) -> HotkeyLanguageSnapshot {
    HotkeyLanguageSnapshotResolver.resolve(
        hotkeyTarget: target,
        wantsTargetOutput: wantsTarget,
        requestedTargetCode: targetCode,
        backend: .whisperKitCoreML,
        modelSupportsNativeTranslation: modelSupportsNativeTranslation,
        isGeminiCloud: isGeminiCloud,
        polishingCanTranslate: polishingCanTranslate
    )
}

@Test
func snapshotTurboRawEIsInactive() {
    // Turbo is multilingual but NOT trained for translation: Raw+E is inactive.
    let snapshot = resolveSnapshot(target: .raw, wantsTarget: true, modelSupportsNativeTranslation: false)
    #expect(!snapshot.wantsTarget)
    #expect(snapshot.targetCode == nil)
    #expect(snapshot.mechanism == .none)
    #expect(snapshot.hudLetter == "A")
    #expect(!snapshot.letterEnabled)
}

@Test
func snapshotFullWhisperRawEToEnglishIsNative() {
    let snapshot = resolveSnapshot(target: .raw, wantsTarget: true, modelSupportsNativeTranslation: true)
    #expect(snapshot.wantsTarget)
    #expect(snapshot.targetCode == "en")
    #expect(snapshot.mechanism == .nativeASR)
    #expect(snapshot.hudLetter == "E")
    #expect(snapshot.letterEnabled)
}

@Test
func snapshotFullWhisperRawENonEnglishIsInactive() {
    // Native ASR translation is English-only; Spanish Raw+E has no native path.
    let snapshot = resolveSnapshot(
        target: .raw, wantsTarget: true, targetCode: "es", modelSupportsNativeTranslation: true
    )
    #expect(!snapshot.wantsTarget)
    #expect(snapshot.mechanism == .none)
    #expect(!snapshot.letterEnabled)
}

@Test
func snapshotParakeetRawIsAlwaysInactive() {
    let snapshot = resolveSnapshot(target: .raw, wantsTarget: true)
    #expect(!snapshot.wantsTarget)
    #expect(snapshot.mechanism == .none)
    #expect(!snapshot.letterEnabled)
}

@Test
func snapshotGeminiRawTranslatesToAnyLanguage() {
    let snapshot = resolveSnapshot(target: .raw, wantsTarget: true, targetCode: "es", isGeminiCloud: true)
    #expect(snapshot.wantsTarget)
    #expect(snapshot.targetCode == "es")
    #expect(snapshot.mechanism == .nativeASR)
    #expect(snapshot.letterEnabled)
}

@Test
func snapshotPolishingNeedsTranslationCapableEngine() {
    let rule = resolveSnapshot(target: .x2, wantsTarget: true, polishingCanTranslate: false)
    #expect(!rule.wantsTarget)
    #expect(rule.mechanism == .none)
    #expect(!rule.letterEnabled)

    let cloud = resolveSnapshot(target: .x2, wantsTarget: true, polishingCanTranslate: true)
    #expect(cloud.wantsTarget)
    #expect(cloud.targetCode == "en")
    #expect(cloud.mechanism == .polishing)
    #expect(cloud.hudLetter == "E")
    #expect(cloud.letterEnabled)

    let v1 = resolveSnapshot(target: .note, wantsTarget: true, targetCode: "es", polishingCanTranslate: true)
    #expect(v1.wantsTarget)
    #expect(v1.targetCode == "es")
    #expect(v1.mechanism == .polishing)
    #expect(v1.hudLetter == "S")
}

@Test
func snapshotAutoIsAlwaysInactive() {
    for target in [HotkeyTarget.raw, .note, .x2] {
        let snapshot = resolveSnapshot(
            target: target, wantsTarget: false, modelSupportsNativeTranslation: true,
            isGeminiCloud: true, polishingCanTranslate: true
        )
        #expect(!snapshot.wantsTarget, "target \(target) with A must be inactive")
        #expect(snapshot.mechanism == .none)
        #expect(snapshot.hudLetter == "A")
    }
}

@Test
func snapshotFrozenValueIgnoresLaterAmbientChanges() {
    // Freezing is a value capture: flipping the persisted flag afterwards
    // produces a different resolution but never mutates the frozen snapshot.
    let frozen = resolveSnapshot(target: .x2, wantsTarget: true, polishingCanTranslate: true)
    #expect(frozen.wantsTarget)

    let laterAmbient = resolveSnapshot(target: .x2, wantsTarget: false, polishingCanTranslate: true)
    #expect(!laterAmbient.wantsTarget)
    #expect(frozen.wantsTarget, "frozen snapshot must not change with ambient state")
    #expect(frozen.targetCode == "en")

    // Only an explicit HUD action (new resolution) replaces it.
    let explicitTap = resolveSnapshot(target: .x2, wantsTarget: true, targetCode: "es", polishingCanTranslate: true)
    #expect(explicitTap.targetCode == "es")
}

@Test
func snapshotExplicitETapReplacesStaleSnapshotWithoutLocalSession() {
    // ADR-029/J1: Gemini cloud dictation has no local session
    // (session resolution is `.unavailable`), yet an explicit E tap during
    // recording must flip the frozen snapshot — and stop must use it.
    let current = HotkeyLanguageSnapshotResolver.resolve(
        hotkeyTarget: .x2, wantsTargetOutput: false, requestedTargetCode: "en",
        backend: nil, modelSupportsNativeTranslation: false,
        isGeminiCloud: true, polishingCanTranslate: true
    )
    #expect(!current.wantsTarget)
    let refreshed = HotkeyLanguageSnapshotResolver.resolve(
        hotkeyTarget: .x2, wantsTargetOutput: true, requestedTargetCode: "en",
        backend: nil, modelSupportsNativeTranslation: false,
        isGeminiCloud: true, polishingCanTranslate: true
    )
    #expect(refreshed.wantsTarget)
    #expect(refreshed.targetCode == "en")
    let replaced = HotkeyLanguageSnapshot.snapshotAfterExplicitHUDAction(
        current: current, refreshed: refreshed, localSessionAvailable: false
    )
    #expect(replaced.wantsTarget, "E tap must flip wantsTarget with no local session")
    #expect(replaced == refreshed)
    // Stop hands the frozen snapshot unchanged: pending wins over re-derivation.
    let pending: HotkeyLanguageSnapshot? = replaced
    #expect((pending ?? current) == refreshed, "stop must use the replacement")
}

@Test
func snapshotExplicitTargetPickReplacesStaleSnapshotWithoutLocalSession() {
    // ADR-029/J1: an auto → target picker choice during a Gemini recording
    // replaces the frozen snapshot even though no local session exists.
    let current = HotkeyLanguageSnapshotResolver.resolve(
        hotkeyTarget: .x2, wantsTargetOutput: false, requestedTargetCode: "auto",
        backend: nil, modelSupportsNativeTranslation: false,
        isGeminiCloud: true, polishingCanTranslate: true
    )
    #expect(!current.wantsTarget)
    let refreshed = HotkeyLanguageSnapshotResolver.resolve(
        hotkeyTarget: .x2, wantsTargetOutput: true, requestedTargetCode: "es",
        backend: nil, modelSupportsNativeTranslation: false,
        isGeminiCloud: true, polishingCanTranslate: true
    )
    let replaced = HotkeyLanguageSnapshot.snapshotAfterExplicitHUDAction(
        current: current, refreshed: refreshed, localSessionAvailable: false
    )
    #expect(replaced.wantsTarget, "target pick must flip wantsTarget with no local session")
    #expect(replaced.targetCode == "es")
    let pending: HotkeyLanguageSnapshot? = replaced
    #expect((pending ?? current) == refreshed, "stop must use the replacement")
}

@Test
func snapshotUserWantsTargetFormulaKeepsRawE() {
    // ADR-029 (J1): call sites pass the raw E choice; Raw exclusion lives
    // in `resolve` capability checks, never in `target != .raw && …`.
    // The old per-site formula `target != .raw && flag` freezes Raw+E as
    // inactive and breaks Gemini/Whisper dictation `forceTargetLanguage`.
    for target in [HotkeyTarget.raw, .note, .x2] {
        #expect(
            HotkeyLanguageSnapshotResolver.userWantsTargetOutput(for: target, forceTargetLanguage: true),
            "E on must survive the formula for \(target)"
        )
        #expect(
            !HotkeyLanguageSnapshotResolver.userWantsTargetOutput(for: target, forceTargetLanguage: false),
            "E off must stay inactive for \(target)"
        )
    }
    #expect(
        HotkeyLanguageSnapshotResolver.userWantsTargetOutput(for: .raw, forceTargetLanguage: true)
            != (HotkeyTarget.raw != HotkeyTarget.raw && true),
        "Raw+E must not be excluded at the call site"
    )
    // Capability truth table through the helper: Raw+Gemini+E → active
    // nativeASR (any language); Raw+Whisper large-v3+E → active English;
    // Raw+turbo/Parakeet+E → inactive.
    let geminiRaw = HotkeyLanguageSnapshotResolver.resolve(
        hotkeyTarget: .raw,
        wantsTargetOutput: HotkeyLanguageSnapshotResolver.userWantsTargetOutput(for: .raw, forceTargetLanguage: true),
        requestedTargetCode: "en",
        backend: nil,
        modelSupportsNativeTranslation: false,
        isGeminiCloud: true,
        polishingCanTranslate: false
    )
    #expect(geminiRaw.wantsTarget)
    #expect(geminiRaw.mechanism == .nativeASR)
    let whisperRaw = HotkeyLanguageSnapshotResolver.resolve(
        hotkeyTarget: .raw,
        wantsTargetOutput: HotkeyLanguageSnapshotResolver.userWantsTargetOutput(for: .raw, forceTargetLanguage: true),
        requestedTargetCode: "en",
        backend: .whisperKitCoreML,
        modelSupportsNativeTranslation: true,
        isGeminiCloud: false,
        polishingCanTranslate: false
    )
    #expect(whisperRaw.wantsTarget)
    #expect(whisperRaw.mechanism == .nativeASR)
    #expect(whisperRaw.targetCode == "en")
    let turboRaw = HotkeyLanguageSnapshotResolver.resolve(
        hotkeyTarget: .raw,
        wantsTargetOutput: HotkeyLanguageSnapshotResolver.userWantsTargetOutput(for: .raw, forceTargetLanguage: true),
        requestedTargetCode: "en",
        backend: .whisperKitCoreML,
        modelSupportsNativeTranslation: false,
        isGeminiCloud: false,
        polishingCanTranslate: false
    )
    #expect(!turboRaw.wantsTarget)
    #expect(turboRaw.mechanism == .none)
    let parakeetRaw = HotkeyLanguageSnapshotResolver.resolve(
        hotkeyTarget: .raw,
        wantsTargetOutput: HotkeyLanguageSnapshotResolver.userWantsTargetOutput(for: .raw, forceTargetLanguage: true),
        requestedTargetCode: "en",
        backend: nil,
        modelSupportsNativeTranslation: false,
        isGeminiCloud: false,
        polishingCanTranslate: false
    )
    #expect(!parakeetRaw.wantsTarget)
    #expect(parakeetRaw.mechanism == .none)
}
