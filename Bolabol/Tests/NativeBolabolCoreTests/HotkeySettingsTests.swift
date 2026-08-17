import Foundation
import NativeBolabolCore
@testable import NativeBolabol
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

// MARK: - S3 / ADR-024: model persistence, display, and compatibility

/// ADR-024 §1: canonical persisted values are locale-independent sentinels.
@Test
func rightModifierPrimaryHotkeyUsesCanonicalPersistedValues() {
    #expect(HotkeySettings.rightOptionHotkey == "RightOption")
    #expect(HotkeySettings.rightCommandHotkey == "RightCommand")
    #expect(HotkeySettings.classifyPrimaryHotkey("RightOption") == .rightOption)
    #expect(HotkeySettings.classifyPrimaryHotkey("RightCommand") == .rightCommand)
    #expect(HotkeySettings.classifyPrimaryHotkey("Option+S") == .combination("Option+S"))
    #expect(HotkeySettings.isRightModifierOnlyPrimaryHotkey("RightOption"))
    #expect(HotkeySettings.isRightModifierOnlyPrimaryHotkey("RightCommand"))
    #expect(!HotkeySettings.isRightModifierOnlyPrimaryHotkey("Option+S"))
    #expect(!HotkeySettings.isRightModifierOnlyPrimaryHotkey(""))
}

/// ADR-024 §1: documented aliases normalize to the canonical sentinel
/// regardless of spaces, dashes, underscores, or case.
@Test
func rightModifierPrimaryHotkeyNormalizesAllDocumentedAliases() {
    let rightOptionAliases = [
        "RightOption", "rightoption", "RIGHTOPTION",
        "Right Option", "right option", "RIGHT OPTION",
        "Right-Option", "right-option", "right_Option",
        "Right Alt", "right_alt", "RIGHT-ALT",
        "Right Opt", "right-opt", "RIGHT OPT",
        "  Right   Option  "
    ]
    for alias in rightOptionAliases {
        #expect(
            HotkeySettings.normalizePrimaryHotkey(alias) == "RightOption",
            "alias \(alias.debugDescription) must normalize to RightOption"
        )
        #expect(HotkeySettings.classifyPrimaryHotkey(alias) == .rightOption)
    }

    let rightCommandAliases = [
        "RightCommand", "rightcommand", "RIGHTCOMMAND",
        "Right Command", "right command", "RIGHT COMMAND",
        "Right-Command", "right_command",
        "Right Cmd", "right_cmd", "RIGHT-CMD",
        "  Right   Cmd "
    ]
    for alias in rightCommandAliases {
        #expect(
            HotkeySettings.normalizePrimaryHotkey(alias) == "RightCommand",
            "alias \(alias.debugDescription) must normalize to RightCommand"
        )
        #expect(HotkeySettings.classifyPrimaryHotkey(alias) == .rightCommand)
    }
}

/// ADR-024 §1: persisted sentinel values survive an exact Codable round trip.
@Test
func rightModifierPrimaryHotkeyPersistsThroughCodableRoundTrip() throws {
    var settings = HotkeySettings()
    settings.enabled = true
    settings.hotkey = "RightOption"
    let optionData = try JSONEncoder().encode(settings)
    let optionDecoded = try JSONDecoder().decode(HotkeySettings.self, from: optionData)
    #expect(optionDecoded.hotkey == "RightOption")
    #expect(optionDecoded.primaryHotkeyKind == .rightOption)

    settings.hotkey = "right command" // alias must persist canonically
    let commandData = try JSONEncoder().encode(settings)
    let commandDecoded = try JSONDecoder().decode(HotkeySettings.self, from: commandData)
    #expect(commandDecoded.hotkey == "RightCommand")
    #expect(commandDecoded.primaryHotkeyKind == .rightCommand)
}

/// ADR-024 §7: sentinel choices render unambiguously and remain distinct
/// from any combination display.
@Test
func rightModifierPrimaryDisplayIsUnambiguousAndDistinctFromCombinations() {
    let rightOption = HotkeySettings.displayString(for: "RightOption")
    let rightCommand = HotkeySettings.displayString(for: "RightCommand")
    #expect(rightOption == HotkeySettings.displayString(for: "right option"))
    #expect(rightCommand == HotkeySettings.displayString(for: "right command"))
    #expect(rightOption.contains("⌥"))
    #expect(rightCommand.contains("⌘"))
    #expect(rightOption.contains("Right"))
    #expect(rightCommand.contains("Right"))
    #expect(!rightOption.isEmpty)
    #expect(!rightCommand.isEmpty)
    #expect(rightOption != rightCommand)
    // Combination rendering must not collide with sentinel badges.
    for combination in ["Option+S", "Command+S", "Option+1", "Shift+Option+S", "Control+X"] {
        let display = HotkeySettings.displayString(for: combination)
        #expect(display != rightOption)
        #expect(display != rightCommand)
    }
    // Unknown / free-form strings stay combinations and render without
    // downgrading to empty or to a sentinel badge.
    for unknown in ["hyper key", "left option", "someword", "f17"] {
        if case .rightOption = HotkeySettings.classifyPrimaryHotkey(unknown) {
            Issue.record("unknown string \(unknown.debugDescription) must not classify as rightOption")
        }
        if case .rightCommand = HotkeySettings.classifyPrimaryHotkey(unknown) {
            Issue.record("unknown string \(unknown.debugDescription) must not classify as rightCommand")
        }
        let display = HotkeySettings.displayString(for: unknown)
        #expect(!display.isEmpty)
        #expect(display != rightOption)
        #expect(display != rightCommand)
    }
}

/// ADR-024 platform scope: left-side single-key spellings are NOT valid
/// right-modifier values and remain ordinary text/combinations.
@Test
func leftSideModifierSpellingsNeverClassifyAsRightModifiers() {
    for leftSpelling in ["Left Option", "left-option", "Left Command", "left cmd", "LeftAlt", "Left Command"] {
        #expect(!HotkeySettings.isRightModifierOnlyPrimaryHotkey(leftSpelling))
    }
}

/// ADR-024 decision §1: sentinel values remain reserved for the primary
/// action; secondary/tertiary/settings keep pure combination normalization
/// and never route a primary-only sentinel into a combination channel.
@Test
func nonPrimaryHotkeysKeepCombinationNormalizationAndRejectPrimarySentinels() {
    // Sentinel spellings pass through combination normalization unchanged and
    // are still classified as primary-only sentinels (never combinations).
    for sentinel in ["RightOption", "right option", "RightCommand", "Right Cmd"] {
        #expect(HotkeySettings.normalizeMacModifiers(sentinel) == sentinel)
        #expect(HotkeySettings.isRightModifierOnlyPrimaryHotkey(sentinel))
    }
    let initialized = HotkeySettings(
        enabled: true,
        holdToRecord: true,
        hotkey: "RightOption",
        secondaryHotkey: "right option",
        tertiaryHotkey: "RightCommand",
        settingsHotkey: "right cmd"
    )
    #expect(initialized.primaryHotkeyKind == .rightOption)
    #expect(initialized.secondaryHotkey == "right option")
    #expect(initialized.tertiaryHotkey == "RightCommand")
    #expect(initialized.settingsHotkey == "right cmd")

    // Pre-S3 combination normalization contracts are unchanged: Mac modifier
    // tokens normalize to canonical wording, unknown tokens pass through
    // verbatim, and token order is preserved.
    #expect(HotkeySettings.normalizeMacModifiers("Option+Shift+F") == "Option+Shift+F")
    #expect(HotkeySettings.normalizeMacModifiers("cmd+opt+k") == "Command+Option+k")
    #expect(HotkeySettings.normalizeMacModifiers("rightoption+f") == "rightoption+f")
    #expect(HotkeySettings.displayString(for: "Option+Shift+F") == "⌥⇧F")
    #expect(HotkeySettings.normalizePrimaryHotkey("Alt+S") == "Option+S")
    #expect(HotkeySettings.normalizePrimaryHotkey("cmd+alt+x") == "Command+Option+x")
    #expect(HotkeySettings.classifyPrimaryHotkey("Option+Left") == .combination("Option+Left"))

    // Documented Mac modifier glyph order remains stable for the decoder path
    // covered above (legacy payload normalizes to Command+Option+X).
    let saved = HotkeySettings(enabled: true, hotkey: "RightOption")
    #expect(saved.secondaryHotkey == "Option+1")
    #expect(saved.tertiaryHotkey == "Option+2")
    #expect(saved.settingsHotkey == "Option+~")
}

/// Default remains the documented Electron successor default.
@Test
func defaultPrimaryHotkeyRemainsOptionPlusS() {
    #expect(HotkeySettings.defaultPrimaryHotkey == "Option+S")
    #expect(HotkeySettings().hotkey == "Option+S")
    #expect(!HotkeySettings.isRightModifierOnlyPrimaryHotkey(HotkeySettings().hotkey))
}

// MARK: - S3 / ADR-024: persistence through the full coding surface

/// The decoder path (used on launch for persisted preferences) classifies
/// sentinel values identically to the in-memory path.
@Test
func decodedRightModifierSettingsClassifyExactlyAsInMemory() throws {
    let json = """
    {
        "enabled": true,
        "target": "note",
        "mode": "typing",
        "hotkey": "RightOption",
        "holdToRecord": true
    }
    """.data(using: .utf8)!
    let settings = try JSONDecoder().decode(HotkeySettings.self, from: json)
    #expect(settings.hotkey == "RightOption")
    #expect(settings.primaryHotkeyKind == .rightOption)
    #expect(settings.holdToRecord)
}

// MARK: - Pre-existing behavior (unchanged by S3)

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

// MARK: - S4 / ADR-025: capture ownership through HotkeySettingsStore

/// Deterministic spy recording every HotkeyManaging call in order.
@MainActor
private final class HotkeyManagerSpy: HotkeyManaging {
    enum Call: Equatable {
        case apply(HotkeySettings)
        case suspend
        case resume
        case teardown
    }

    private(set) var calls: [Call] = []

    func apply(settings: HotkeySettings) {
        calls.append(.apply(settings))
    }

    func suspendForShortcutCapture() {
        calls.append(.suspend)
    }

    func resumeAfterShortcutCapture() {
        calls.append(.resume)
    }

    func teardown() {
        calls.append(.teardown)
    }

    var suspendCount: Int { calls.filter { $0 == .suspend }.count }
    var resumeCount: Int { calls.filter { $0 == .resume }.count }
}

@MainActor
private func makeStoreWithSpy() -> (HotkeySettingsStore, HotkeyManagerSpy, String) {
    let suiteName = "bolabol-hotkey-store-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let spy = HotkeyManagerSpy()
    let store = HotkeySettingsStore(userDefaults: defaults, hotkeyManager: spy)
    return (store, spy, suiteName)
}

/// The initial apply on construction is accounted for exactly once with the
/// loaded settings.
@MainActor
@Test
func hotkeySettingsStoreAppliesInitialSettingsExactlyOnce() {
    let (store, spy, suiteName) = makeStoreWithSpy()
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    #expect(spy.calls == [.apply(store.settings)])
    #expect(spy.suspendCount == 0)
    #expect(spy.resumeCount == 0)
}

/// The same owner may begin capture repeatedly without extra suspends.
@MainActor
@Test
func hotkeySettingsStoreSameOwnerBeginIsIdempotent() {
    let (store, spy, suiteName) = makeStoreWithSpy()
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let owner = UUID()

    #expect(store.beginShortcutCapture(owner: owner))
    #expect(store.beginShortcutCapture(owner: owner))
    #expect(store.beginShortcutCapture(owner: owner))
    #expect(spy.suspendCount == 1)
}

/// A foreign owner cannot begin capture while another owner holds it.
@MainActor
@Test
func hotkeySettingsStoreForeignBeginReturnsFalseWithoutSuspending() {
    let (store, spy, suiteName) = makeStoreWithSpy()
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let owner = UUID()
    let foreign = UUID()

    #expect(store.beginShortcutCapture(owner: owner))
    #expect(!store.beginShortcutCapture(owner: foreign))
    #expect(spy.suspendCount == 1)
}

/// A foreign owner cannot end capture or trigger a resume.
@MainActor
@Test
func hotkeySettingsStoreForeignEndDoesNothing() {
    let (store, spy, suiteName) = makeStoreWithSpy()
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let owner = UUID()
    let foreign = UUID()

    #expect(store.beginShortcutCapture(owner: owner))
    store.endShortcutCapture(owner: foreign)
    #expect(spy.resumeCount == 0)

    // The original owner still owns the capture.
    #expect(store.beginShortcutCapture(owner: owner))
    #expect(spy.suspendCount == 1)
}

/// The owning end resumes exactly once and releases the capture.
@MainActor
@Test
func hotkeySettingsStoreOwningEndResumesOnce() {
    let (store, spy, suiteName) = makeStoreWithSpy()
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let owner = UUID()

    #expect(store.beginShortcutCapture(owner: owner))
    store.endShortcutCapture(owner: owner)
    store.endShortcutCapture(owner: owner)
    #expect(spy.resumeCount == 1)
}

/// Reacquiring capture after an end suspends again.
@MainActor
@Test
func hotkeySettingsStoreReacquisitionAfterEndSuspendsAgain() {
    let (store, spy, suiteName) = makeStoreWithSpy()
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let owner = UUID()

    #expect(store.beginShortcutCapture(owner: owner))
    store.endShortcutCapture(owner: owner)
    #expect(store.beginShortcutCapture(owner: owner))
    #expect(spy.suspendCount == 2)
    store.endShortcutCapture(owner: owner)
    #expect(spy.resumeCount == 2)
}

/// Settings changes apply through the manager and persist to the injected
/// defaults.
@MainActor
@Test
func hotkeySettingsStoreAppliesSettingsChangesThroughManager() throws {
    let (store, spy, suiteName) = makeStoreWithSpy()
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    store.settings.hotkey = "Command+Option+X"
    // Initial apply (defaults) + change apply = two applies; the last one
    // carries the new settings.
    #expect(spy.calls.filter { if case .apply = $0 { return true } else { return false } }.count == 2)
    #expect(spy.calls.last == .apply(store.settings))

    let defaults = UserDefaults(suiteName: suiteName)!
    let data = try #require(defaults.data(forKey: "hotkey.settings"))
    let decoded = try JSONDecoder().decode(HotkeySettings.self, from: data)
    #expect(decoded.hotkey == "Command+Option+X")
}
