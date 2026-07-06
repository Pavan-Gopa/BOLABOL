import Foundation
import NativeSmartScribeCore
import Testing

@Test
func hotkeySettingsMatchElectronDefaults() {
    let settings = HotkeySettings()

    #expect(settings.enabled == false)
    #expect(settings.target == .note)
    #expect(settings.mode == .typing)
    #expect(settings.hotkey == "Alt+S")
    #expect(settings.secondaryHotkey == "Alt+Shift+S")
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
    #expect(settings.hotkey == "Cmd+Alt+X")
    #expect(settings.secondaryHotkey == "Alt+Shift+S")
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
func hotkeyOutputTextResolverSelectsRequestedNoteText() {
    let note = SmartScribeNote(
        title: "Test",
        rawText: "raw text",
        polishedVariantOne: "variant one",
        polishedVariantTwo: "variant two"
    )

    #expect(HotkeyOutputTextResolver.text(from: note, target: .raw) == "raw text")
    #expect(HotkeyOutputTextResolver.text(from: note, target: .note) == "variant one")
    #expect(HotkeyOutputTextResolver.text(from: note, target: .x2) == "variant two")
}
