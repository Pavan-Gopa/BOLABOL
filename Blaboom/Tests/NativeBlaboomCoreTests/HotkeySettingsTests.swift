import Foundation
import NativeBlaboomCore
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
    // Legacy Alt / Cmd tokens are normalized to Mac Option / Command wording.
    #expect(settings.hotkey == "Command+Option+X")
    #expect(settings.secondaryHotkey == "Option+1")
}

@Test
func hotkeySettingsEncodesAndDecodesHoldToRecord() throws {
    var settings = HotkeySettings()
    settings.holdToRecord = true
    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(HotkeySettings.self, from: data)
    #expect(decoded.holdToRecord == true)
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
func hotkeyOutputTextResolverSelectsRequestedNoteText() {
    let note = BlaboomNote(
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
    let note = BlaboomNote(
        title: "Test",
        rawText: "raw text",
        polishedVariantOne: "",
        polishedVariantTwo: ""
    )

    #expect(HotkeyOutputTextResolver.text(from: note, target: .raw) == "raw text")
    #expect(HotkeyOutputTextResolver.text(from: note, target: .note) == "raw text")
    #expect(HotkeyOutputTextResolver.text(from: note, target: .x2) == "raw text")
}
