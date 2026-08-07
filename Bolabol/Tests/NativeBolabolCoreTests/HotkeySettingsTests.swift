import Foundation
import NativeBolabolCore
import Testing

@Test
func hotkeySettingsMatchElectronDefaults() {
    let settings = HotkeySettings()

    #expect(settings.enabled == false)
    #expect(settings.target == .note)
    #expect(settings.mode == .typing)
    #expect(settings.holdToRecord == false)
    #expect(settings.hotkey == "Option+S")
    #expect(settings.secondaryHotkey == "Option+1")
    #expect(settings.humorSliderEnabled == false)
    #expect(settings.humorLevel.rawValue == 0)
    #expect(settings.humorPromptMode == .playful)
}

@Test
func hotkeySettingsDecodesLegacyPayloadWithoutSecondaryHotkey() throws {
    let json = """
    {
        "enabled": true,
        "target": "raw",
        "mode": "clipboard",
        "hotkey": "Cmd+Alt+X"
    }
    """.data(using: .utf8)!

    let settings = try JSONDecoder().decode(HotkeySettings.self, from: json)
    #expect(settings.enabled == true)
    #expect(settings.target == .raw)
    #expect(settings.mode == .clipboard)
    #expect(settings.holdToRecord == false)
    #expect(settings.humorSliderEnabled == false)
    #expect(settings.humorLevel.rawValue == 0)
    #expect(settings.humorPromptMode == .playful)
    // Legacy Alt / Cmd tokens are normalized to Mac Option / Command wording.
    #expect(settings.hotkey == "Command+Option+X")
    #expect(settings.secondaryHotkey == "Option+1")
}

@Test
func hotkeySettingsMigratesTheInitialVariantTwoHumorLevelKey() throws {
    let json = """
    {
        "enabled": true,
        "target": "x2",
        "mode": "typing",
        "hotkey": "Option+S",
        "humorSliderEnabled": true,
        "variantTwoHumorLevel": 63
    }
    """.data(using: .utf8)!

    let settings = try JSONDecoder().decode(HotkeySettings.self, from: json)
    #expect(settings.humorSliderEnabled)
    #expect(settings.humorLevel.rawValue == 63)
    #expect(settings.variantTwoHumorLevel.rawValue == 63)
}

@Test
func hotkeySettingsEncodesAndDecodesHoldToRecord() throws {
    var settings = HotkeySettings()
    settings.holdToRecord = true
    settings.humorSliderEnabled = true
    settings.humorLevel = HumorLevel(clamping: 63)
    settings.humorPromptMode = .warmRespectful
    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(HotkeySettings.self, from: data)
    #expect(decoded.holdToRecord == true)
    #expect(decoded.humorSliderEnabled == true)
    #expect(decoded.humorLevel.rawValue == 63)
    #expect(decoded.humorPromptMode == .warmRespectful)
}

@Test
func hotkeyHumorUsesLivePreferenceWithoutChangingAnEnqueuedSnapshot() {
    var settings = HotkeySettings(
        humorSliderEnabled: true,
        humorLevel: .playful,
        humorPromptMode: .casualHumor
    )
    let prompt = PromptTemplate(
        id: "session-prompt",
        title: "Session Prompt",
        body: "Rewrite ${transcription}"
    )
    let session = HumorSessionState(
        sliderEnabled: settings.humorSliderEnabled,
        level: settings.humorLevel,
        promptMode: settings.humorPromptMode,
        selectedVariant: .variantTwo,
        selectedPromptSlot: .default,
        selectedPrompt: prompt
    )
    let enqueued = session.freeze()

    // Live preference semantics: a later/cancelled HUD drag remains saved, but
    // the already enqueued request retains its frozen value.
    settings.humorLevel = .standUp
    #expect(settings.humorLevel == .standUp)
    #expect(enqueued.level == .playful)
    #expect(enqueued.promptMode == .casualHumor)
}

@Test
func hotkeySettingsNormalizesAltToOptionAndDisplaysGlyph() {
    #expect(HotkeySettings.normalizeMacModifiers("Alt+S") == "Option+S")
    #expect(HotkeySettings.normalizeMacModifiers("alt+~") == "Option+~")
    #expect(HotkeySettings.normalizeMacModifiers("⌥+S") == "Option+S")
    #expect(HotkeySettings.displayString(for: "Option+S") == "⌥S")
    #expect(HotkeySettings.displayString(for: "Option+~") == "⌥~")
    #expect(HotkeySettings.displayString(for: "Command+Option+S") == "⌘⌥S")
}

@Test
func hotkeyTargetsMapToProcessingVariants() {
    #expect(HotkeyTarget.raw.processingVariant == .raw)
    #expect(HotkeyTarget.note.processingVariant == .variantOne)
    #expect(HotkeyTarget.x2.processingVariant == .variantTwo)
    #expect(HotkeyTarget.raw.requestedPolishingVariants.isEmpty)
    #expect(HotkeyTarget.note.requestedPolishingVariants == [.variantOne])
    #expect(HotkeyTarget.x2.requestedPolishingVariants == [.variantTwo])
}

@Test
func hotkeyTargetsCycleThroughHUDLabels() {
    #expect(HotkeyTarget.raw.hudLabel == "R")
    #expect(HotkeyTarget.note.hudLabel == "1")
    #expect(HotkeyTarget.x2.hudLabel == "2")

    #expect(HotkeyTarget.raw.next() == .note)
    #expect(HotkeyTarget.note.next() == .x2)
    #expect(HotkeyTarget.x2.next() == .raw)
}
@Test
func hotkeyTargetVariantTransitionPreservesHUDLabels() {
    let initialTarget = HotkeyTarget.note
    #expect(initialTarget.hudLabel == "1")

    let nextTarget = initialTarget.next()
    #expect(nextTarget == .x2)
    #expect(nextTarget.hudLabel == "2")

    let cycleTarget = nextTarget.next()
    #expect(cycleTarget == .raw)
    #expect(cycleTarget.hudLabel == "R")
}

@Test
func hotkeyOutputTextResolverSelectsRequestedNoteText() {
    let note = BolabolNote(
        title: "Test",
        rawText: "raw text",
        polishedVariantOne: "variant one",
        polishedVariantTwo: "variant two"
    )

    #expect(HotkeyOutputTextResolver.text(from: note, target: .raw) == "raw text")
    #expect(HotkeyOutputTextResolver.text(from: note, target: .note) == "variant one")
    #expect(HotkeyOutputTextResolver.text(from: note, target: .x2) == "variant two")
}

@Test
func hotkeyOutputTextResolverFallsBackToRawTextWhenVariantIsEmpty() {
    let note = BolabolNote(
        title: "Test",
        rawText: "raw text",
        polishedVariantOne: "",
        polishedVariantTwo: ""
    )

    #expect(HotkeyOutputTextResolver.text(from: note, target: .raw) == "raw text")
    #expect(HotkeyOutputTextResolver.text(from: note, target: .note) == "raw text")
    #expect(HotkeyOutputTextResolver.text(from: note, target: .x2) == "raw text")
}
