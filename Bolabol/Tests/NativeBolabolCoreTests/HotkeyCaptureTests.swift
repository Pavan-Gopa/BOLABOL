import AppKit
import Carbon
import Foundation
import NativeBolabolCore
@testable import NativeBolabol
import Testing

// S4 / ADR-025 deterministic regression coverage for the shortcut capture
// pipeline: the bidirectional key catalog, the pure modifier snapshot, the
// capture state machine reducer, and the AppKit NSView event path.
// Hardware-facing macOS constants are pinned literally so a silent constant
// drift in any dependency cannot green these tests.

// MARK: - Hardware identity contract

private let keyCodeRightOption: UInt16 = 61 // kVK_RightOption
private let keyCodeRightCommand: UInt16 = 54 // kVK_RightCommand
private let keyCodeLeftOption: UInt16 = 58 // kVK_Option
private let keyCodeLeftCommand: UInt16 = 55 // kVK_Command
private let keyCodeLeftShift: UInt16 = 56 // kVK_Shift
private let keyCodeLeftControl: UInt16 = 59 // kVK_Control
private let keyCodeCapsLock: UInt16 = 57 // kVK_CapsLock
private let keyCodeFunction: UInt16 = 63 // kVK_Function
private let keyCodeEscape: UInt16 = 53 // kVK_Escape
private let keyCodeUnsupported: UInt16 = 0x7FFE // outside any catalog

// Raw NSEvent.ModifierFlags bit values (post-state snapshots).
private let bitRightOptionSide: UInt = 0x0040
private let bitRightCommandSide: UInt = 0x0010
private let bitLeftOptionSide: UInt = 0x0020
private let bitLeftCommandSide: UInt = 0x0008
private let bitLeftShiftSide: UInt = 0x0002
private let bitLeftControlSide: UInt = 0x0001
private let bitIndependentOption: UInt = 0x0008_0000
private let bitIndependentCommand: UInt = 0x0010_0000
private let bitIndependentShift: UInt = 0x0002_0000
private let bitIndependentControl: UInt = 0x0004_0000
private let bitIndependentFunction: UInt = 0x0080_0000
private let bitCapsLock: UInt = 0x0001_0000

private let pinnedAllPhysicalModifiersMask: UInt = 0x207F
private let pinnedAllIndependentMask: UInt = 0x009E_0000

@Test
func hotkeyCaptureHardwareIdentityConstantsArePinned() {
    // The capture pipeline compares NSEvent keyCodes and raw flag bits against
    // these values; pinning the literals guards the documented macOS identity.
    #expect(keyCodeRightOption == UInt16(kVK_RightOption))
    #expect(keyCodeRightCommand == UInt16(kVK_RightCommand))
    #expect(keyCodeLeftOption == UInt16(kVK_Option))
    #expect(keyCodeLeftCommand == UInt16(kVK_Command))
    #expect(keyCodeLeftShift == UInt16(kVK_Shift))
    #expect(keyCodeLeftControl == UInt16(kVK_Control))
    #expect(keyCodeCapsLock == UInt16(kVK_CapsLock))
    #expect(keyCodeFunction == UInt16(kVK_Function))
    #expect(keyCodeEscape == UInt16(kVK_Escape))

    // The snapshot type must agree with the pinned masks and key identities.
    #expect(PhysicalModifierSnapshot.rightOptionKeyCode == keyCodeRightOption)
    #expect(PhysicalModifierSnapshot.rightCommandKeyCode == keyCodeRightCommand)
    #expect(PhysicalModifierSnapshot.rightOptionSideMask == bitRightOptionSide)
    #expect(PhysicalModifierSnapshot.rightCommandSideMask == bitRightCommandSide)
    #expect(PhysicalModifierSnapshot.rightOptionIndependentMask == bitIndependentOption)
    #expect(PhysicalModifierSnapshot.rightCommandIndependentMask == bitIndependentCommand)
    #expect(PhysicalModifierSnapshot.allPhysicalModifiersMask == pinnedAllPhysicalModifiersMask)
    #expect(PhysicalModifierSnapshot.allIndependentMask == pinnedAllIndependentMask)
}

// MARK: - HotkeyKeyCatalog

/// Every supported key code round-trips through its canonical token and back
/// to exactly the same key code.
@Test
func hotkeyKeyCatalogRoundTripsEverySupportedKeyCode() throws {
    let allCodes = HotkeyKeyCatalog.allSupportedKeyCodes
    #expect(!allCodes.isEmpty)
    for keyCode in allCodes.sorted() {
        let token = try #require(
            HotkeyKeyCatalog.canonicalToken(for: keyCode),
            "keyCode \(keyCode) has no canonical token"
        )
        #expect(
            HotkeyKeyCatalog.keyCode(forToken: token) == keyCode,
            "token \(token) does not round-trip to keyCode \(keyCode)"
        )
    }
}

/// Canonical tokens are the persisted shortcut contract: drift here breaks
/// every stored hotkey string.
@Test
func hotkeyKeyCatalogCanonicalTokensArePinned() {
    // Letters, digits, function keys.
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_ANSI_A)) == "A")
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_ANSI_S)) == "S")
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_ANSI_Z)) == "Z")
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_ANSI_0)) == "0")
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_ANSI_9)) == "9")
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_F1)) == "F1")
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_F12)) == "F12")

    // Standard control keys.
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_Space)) == "SPACE")
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_Return)) == "RETURN")
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_Tab)) == "TAB")
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_Delete)) == "DELETE")
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_Escape)) == "ESCAPE")

    // Punctuation and symbols.
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_ANSI_Grave)) == "~")
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_ANSI_Minus)) == "-")
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_ANSI_Equal)) == "=")
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_ANSI_LeftBracket)) == "[")
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_ANSI_RightBracket)) == "]")
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_ANSI_Backslash)) == "\\")
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_ANSI_Semicolon)) == ";")
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_ANSI_Quote)) == "'")
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_ANSI_Comma)) == ",")
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_ANSI_Period)) == ".")
    #expect(HotkeyKeyCatalog.canonicalToken(for: UInt16(kVK_ANSI_Slash)) == "/")
}

/// Documented aliases (case-insensitive canonical spellings, punctuation
/// names, and Cyrillic physical-layout letters) resolve to the same key code
/// as their canonical token.
@Test
func hotkeyKeyCatalogAliasesResolveToCanonicalKeyCodes() {
    // Canonical spellings are case-insensitive.
    #expect(HotkeyKeyCatalog.keyCode(forToken: "a") == UInt16(kVK_ANSI_A))
    #expect(HotkeyKeyCatalog.keyCode(forToken: "SPACE") == UInt16(kVK_Space))
    #expect(HotkeyKeyCatalog.keyCode(forToken: "space") == UInt16(kVK_Space))
    #expect(HotkeyKeyCatalog.keyCode(forToken: "escape") == UInt16(kVK_Escape))

    // Grave/tilde family.
    let grave = UInt16(kVK_ANSI_Grave)
    #expect(HotkeyKeyCatalog.keyCode(forToken: "~") == grave)
    #expect(HotkeyKeyCatalog.keyCode(forToken: "`") == grave)
    #expect(HotkeyKeyCatalog.keyCode(forToken: "TILDE") == grave)
    #expect(HotkeyKeyCatalog.keyCode(forToken: "GRAVE") == grave)
    #expect(HotkeyKeyCatalog.keyCode(forToken: "BACKTICK") == grave)

    // Control-key and punctuation aliases.
    #expect(HotkeyKeyCatalog.keyCode(forToken: "BACKSPACE") == UInt16(kVK_Delete))
    #expect(HotkeyKeyCatalog.keyCode(forToken: "MINUS") == UInt16(kVK_ANSI_Minus))
    #expect(HotkeyKeyCatalog.keyCode(forToken: "EQUAL") == UInt16(kVK_ANSI_Equal))
    #expect(HotkeyKeyCatalog.keyCode(forToken: "EQUALS") == UInt16(kVK_ANSI_Equal))
    #expect(HotkeyKeyCatalog.keyCode(forToken: "LEFTBRACKET") == UInt16(kVK_ANSI_LeftBracket))
    #expect(HotkeyKeyCatalog.keyCode(forToken: "RIGHTBRACKET") == UInt16(kVK_ANSI_RightBracket))
    #expect(HotkeyKeyCatalog.keyCode(forToken: "BACKSLASH") == UInt16(kVK_ANSI_Backslash))
    #expect(HotkeyKeyCatalog.keyCode(forToken: "SEMICOLON") == UInt16(kVK_ANSI_Semicolon))
    #expect(HotkeyKeyCatalog.keyCode(forToken: "QUOTE") == UInt16(kVK_ANSI_Quote))
    #expect(HotkeyKeyCatalog.keyCode(forToken: "APOSTROPHE") == UInt16(kVK_ANSI_Quote))
    #expect(HotkeyKeyCatalog.keyCode(forToken: "COMMA") == UInt16(kVK_ANSI_Comma))
    #expect(HotkeyKeyCatalog.keyCode(forToken: "PERIOD") == UInt16(kVK_ANSI_Period))
    #expect(HotkeyKeyCatalog.keyCode(forToken: "DOT") == UInt16(kVK_ANSI_Period))
    #expect(HotkeyKeyCatalog.keyCode(forToken: "SLASH") == UInt16(kVK_ANSI_Slash))

    // Cyrillic physical-layout aliases map to the ANSI physical key that
    // produces that letter on a ЙЦУКЕН layout (Ф sits on the ANSI "A" key).
    #expect(HotkeyKeyCatalog.keyCode(forToken: "Ф") == UInt16(kVK_ANSI_A))
    #expect(HotkeyKeyCatalog.keyCode(forToken: "ф") == UInt16(kVK_ANSI_A))
    #expect(HotkeyKeyCatalog.keyCode(forToken: "Ы") == UInt16(kVK_ANSI_S))
    #expect(HotkeyKeyCatalog.keyCode(forToken: "Ё") == grave)
    #expect(HotkeyKeyCatalog.keyCode(forToken: "Ю") == UInt16(kVK_ANSI_Period))
}

/// Modifier keys, system keys, and unknown tokens are never catalog entries.
@Test
func hotkeyKeyCatalogRejectsUnsupportedAndUnknownKeys() {
    // Modifier and system keys are not catalog keys.
    #expect(HotkeyKeyCatalog.canonicalToken(for: keyCodeRightOption) == nil)
    #expect(HotkeyKeyCatalog.canonicalToken(for: keyCodeRightCommand) == nil)
    #expect(HotkeyKeyCatalog.canonicalToken(for: keyCodeLeftOption) == nil)
    #expect(HotkeyKeyCatalog.canonicalToken(for: keyCodeLeftCommand) == nil)
    #expect(HotkeyKeyCatalog.canonicalToken(for: keyCodeLeftShift) == nil)
    #expect(HotkeyKeyCatalog.canonicalToken(for: keyCodeLeftControl) == nil)
    #expect(HotkeyKeyCatalog.canonicalToken(for: keyCodeCapsLock) == nil)
    #expect(HotkeyKeyCatalog.canonicalToken(for: keyCodeFunction) == nil)
    #expect(HotkeyKeyCatalog.canonicalToken(for: keyCodeUnsupported) == nil)

    // Unknown tokens never resolve to a key code.
    #expect(HotkeyKeyCatalog.keyCode(forToken: "") == nil)
    #expect(HotkeyKeyCatalog.keyCode(forToken: "NOTAKEY") == nil)
    #expect(HotkeyKeyCatalog.keyCode(forToken: "F13") == nil)

    // The supported set never claims modifier key codes.
    #expect(!HotkeyKeyCatalog.allSupportedKeyCodes.contains(keyCodeRightOption))
    #expect(!HotkeyKeyCatalog.allSupportedKeyCodes.contains(keyCodeRightCommand))
    #expect(!HotkeyKeyCatalog.allSupportedKeyCodes.contains(keyCodeCapsLock))
}

// MARK: - PhysicalModifierSnapshot

@Test
func physicalModifierSnapshotMasksCapsLockAndClassifiesModifiers() {
    let rightOptionOnly = PhysicalModifierSnapshot(rawFlags: bitRightOptionSide | bitIndependentOption)
    #expect(rightOptionOnly.heldPhysical == bitRightOptionSide)
    #expect(rightOptionOnly.heldIndependent == bitIndependentOption)
    #expect(rightOptionOnly.isRightOptionSoleModifierHeld)
    #expect(!rightOptionOnly.isRightCommandSoleModifierHeld)
    #expect(rightOptionOnly.hasStandardModifier)
    #expect(rightOptionOnly.hasOption)
    #expect(!rightOptionOnly.hasCommand)

    // Caps Lock must never count as a held modifier.
    let withCapsLock = PhysicalModifierSnapshot(rawFlags: bitRightOptionSide | bitIndependentOption | bitCapsLock)
    #expect(withCapsLock.heldPhysical == bitRightOptionSide)
    #expect(withCapsLock.heldIndependent == bitIndependentOption)
    #expect(withCapsLock.isRightOptionSoleModifierHeld)

    // Function is tracked but is not a standard shortcut modifier.
    let functionOnly = PhysicalModifierSnapshot(rawFlags: bitIndependentFunction)
    #expect(functionOnly.hasFunction)
    #expect(!functionOnly.hasStandardModifier)
    #expect(!functionOnly.isRightOptionSoleModifierHeld)
    #expect(!functionOnly.isRightCommandSoleModifierHeld)
}

@Test
func physicalModifierSnapshotSoleTargetChecksRejectContamination() {
    // Left counterpart of the same family.
    let leftOption = PhysicalModifierSnapshot(rawFlags: bitLeftOptionSide | bitIndependentOption)
    #expect(!leftOption.isRightOptionSoleModifierHeld)
    let leftCommand = PhysicalModifierSnapshot(rawFlags: bitLeftCommandSide | bitIndependentCommand)
    #expect(!leftCommand.isRightCommandSoleModifierHeld)

    // Left + right of the same family.
    let bothOptions = PhysicalModifierSnapshot(rawFlags: bitLeftOptionSide | bitRightOptionSide | bitIndependentOption)
    #expect(!bothOptions.isRightOptionSoleModifierHeld)

    // Side bit without the device-independent family bit (malformed snapshot).
    #expect(!PhysicalModifierSnapshot(rawFlags: bitRightOptionSide).isRightOptionSoleModifierHeld)
    // Family bit without the side bit (malformed snapshot).
    #expect(!PhysicalModifierSnapshot(rawFlags: bitIndependentOption).isRightOptionSoleModifierHeld)

    // Right Option plus another modifier family.
    let optionPlusShift = PhysicalModifierSnapshot(
        rawFlags: bitRightOptionSide | bitIndependentOption | bitLeftShiftSide | bitIndependentShift
    )
    #expect(!optionPlusShift.isRightOptionSoleModifierHeld)

    // Right Command mirrors the same rules.
    let rightCommandOnly = PhysicalModifierSnapshot(rawFlags: bitRightCommandSide | bitIndependentCommand)
    #expect(rightCommandOnly.isRightCommandSoleModifierHeld)
    #expect(!rightCommandOnly.isRightOptionSoleModifierHeld)
    let commandPlusControl = PhysicalModifierSnapshot(
        rawFlags: bitRightCommandSide | bitIndependentCommand | bitLeftControlSide | bitIndependentControl
    )
    #expect(!commandPlusControl.isRightCommandSoleModifierHeld)
}

@Test
func physicalModifierSnapshotReleaseDetection() {
    #expect(PhysicalModifierSnapshot(rawFlags: 0).areAllModifiersReleased)
    // Caps Lock alone still counts as fully released.
    #expect(PhysicalModifierSnapshot(rawFlags: bitCapsLock).areAllModifiersReleased)
    #expect(!PhysicalModifierSnapshot(rawFlags: bitLeftControlSide | bitIndependentControl).areAllModifiersReleased)
    #expect(!PhysicalModifierSnapshot(rawFlags: 0).hasAnyModifierHeld)
    #expect(PhysicalModifierSnapshot(rawFlags: bitLeftShiftSide | bitIndependentShift).hasAnyModifierHeld)
}

// MARK: - ShortcutCaptureStateMachine helpers

private func recordingMachine(allowsRightModifierOnly: Bool = false) -> ShortcutCaptureStateMachine {
    var machine = ShortcutCaptureStateMachine()
    #expect(machine.phase == .idle)
    #expect(!machine.isRecording)
    #expect(machine.handle(.start(HotkeyCapturePolicy(allowsRightModifierOnly: allowsRightModifierOnly))) == nil)
    #expect(machine.isRecording)
    return machine
}

// MARK: - Combination commits

struct ComboCase: Sendable, CustomTestStringConvertible {
    let name: String
    let keyCode: UInt16
    let rawFlags: UInt
    let expected: String

    var testDescription: String { name }
}

private let comboCases: [ComboCase] = [
    ComboCase(name: "Option+S", keyCode: UInt16(kVK_ANSI_S), rawFlags: bitIndependentOption, expected: "Option+S"),
    ComboCase(
        name: "Command+Option+S",
        keyCode: UInt16(kVK_ANSI_S),
        rawFlags: bitIndependentCommand | bitIndependentOption,
        expected: "Command+Option+S"
    ),
    ComboCase(
        name: "all four modifiers fixed order",
        keyCode: UInt16(kVK_ANSI_A),
        rawFlags: bitIndependentCommand | bitIndependentOption | bitIndependentControl | bitIndependentShift,
        expected: "Command+Option+Control+Shift+A"
    ),
    ComboCase(name: "Shift+SPACE", keyCode: UInt16(kVK_Space), rawFlags: bitIndependentShift, expected: "Shift+SPACE"),
    ComboCase(name: "Control+RETURN", keyCode: UInt16(kVK_Return), rawFlags: bitIndependentControl, expected: "Control+RETURN"),
    ComboCase(name: "Command+TAB", keyCode: UInt16(kVK_Tab), rawFlags: bitIndependentCommand, expected: "Command+TAB"),
    ComboCase(name: "Option+DELETE", keyCode: UInt16(kVK_Delete), rawFlags: bitIndependentOption, expected: "Option+DELETE"),
    ComboCase(name: "Command+F5", keyCode: UInt16(kVK_F5), rawFlags: bitIndependentCommand, expected: "Command+F5"),
    ComboCase(name: "Option+~", keyCode: UInt16(kVK_ANSI_Grave), rawFlags: bitIndependentOption, expected: "Option+~"),
    ComboCase(name: "Command+-", keyCode: UInt16(kVK_ANSI_Minus), rawFlags: bitIndependentCommand, expected: "Command+-"),
    ComboCase(name: "Option+=", keyCode: UInt16(kVK_ANSI_Equal), rawFlags: bitIndependentOption, expected: "Option+="),
    ComboCase(name: "Command+[", keyCode: UInt16(kVK_ANSI_LeftBracket), rawFlags: bitIndependentCommand, expected: "Command+["),
    ComboCase(name: "Command+]", keyCode: UInt16(kVK_ANSI_RightBracket), rawFlags: bitIndependentCommand, expected: "Command+]"),
    ComboCase(name: "Option+\\", keyCode: UInt16(kVK_ANSI_Backslash), rawFlags: bitIndependentOption, expected: "Option+\\"),
    ComboCase(name: "Command+;", keyCode: UInt16(kVK_ANSI_Semicolon), rawFlags: bitIndependentCommand, expected: "Command+;"),
    ComboCase(name: "Option+'", keyCode: UInt16(kVK_ANSI_Quote), rawFlags: bitIndependentOption, expected: "Option+'"),
    ComboCase(name: "Command+,", keyCode: UInt16(kVK_ANSI_Comma), rawFlags: bitIndependentCommand, expected: "Command+,"),
    ComboCase(name: "Option+.", keyCode: UInt16(kVK_ANSI_Period), rawFlags: bitIndependentOption, expected: "Option+."),
    ComboCase(name: "Command+/", keyCode: UInt16(kVK_ANSI_Slash), rawFlags: bitIndependentCommand, expected: "Command+/"),
]

/// A clean keyDown with at least one standard modifier commits the canonical
/// combination string in fixed Command, Option, Control, Shift order and ends
/// recording.
@Test(arguments: comboCases)
func cleanComboKeyDownCommitsCanonicalCombination(combo: ComboCase) {
    var machine = recordingMachine()
    let effect = machine.handle(.keyDown(keyCode: combo.keyCode, rawFlags: combo.rawFlags, isRepeat: false))
    #expect(effect == .committed(.combination(combo.expected)))
    #expect(machine.phase == .idle)
    #expect(!machine.isRecording)
}

// MARK: - Rejections

struct RejectionCase: Sendable, CustomTestStringConvertible {
    let name: String
    let keyCode: UInt16
    let rawFlags: UInt
    let expected: HotkeyCaptureRejectionReason

    var testDescription: String { name }
}

private let rejectionCases: [RejectionCase] = [
    // Bare non-modifier keys.
    RejectionCase(name: "bare letter", keyCode: UInt16(kVK_ANSI_A), rawFlags: 0, expected: .modifierRequired),
    RejectionCase(name: "bare digit", keyCode: UInt16(kVK_ANSI_1), rawFlags: 0, expected: .modifierRequired),
    RejectionCase(name: "bare space", keyCode: UInt16(kVK_Space), rawFlags: 0, expected: .modifierRequired),
    RejectionCase(name: "bare punctuation", keyCode: UInt16(kVK_ANSI_Semicolon), rawFlags: 0, expected: .modifierRequired),
    // Function alone is not a standard modifier.
    RejectionCase(name: "function-only modifier", keyCode: UInt16(kVK_ANSI_A), rawFlags: bitIndependentFunction, expected: .modifierRequired),
    // Caps Lock alone is not a modifier.
    RejectionCase(name: "caps-lock-only modifier", keyCode: UInt16(kVK_ANSI_A), rawFlags: bitCapsLock, expected: .modifierRequired),
    // Keys outside the catalog.
    RejectionCase(name: "unknown key code", keyCode: keyCodeUnsupported, rawFlags: bitIndependentCommand, expected: .unsupportedKey),
    RejectionCase(
        name: "right option used as the key",
        keyCode: keyCodeRightOption,
        rawFlags: bitIndependentCommand | bitIndependentOption,
        expected: .unsupportedKey
    ),
    RejectionCase(name: "left command used as the key", keyCode: keyCodeLeftCommand, rawFlags: bitIndependentCommand, expected: .unsupportedKey),
]

/// Bare keys, non-standard modifiers, and uncataloged keys reject with the
/// matching reason and keep the recorder active for the next attempt.
@Test(arguments: rejectionCases)
func unsupportedAndBareKeysRejectWithoutCommitting(rejection: RejectionCase) {
    var machine = recordingMachine()
    let effect = machine.handle(.keyDown(keyCode: rejection.keyCode, rawFlags: rejection.rawFlags, isRepeat: false))
    #expect(effect == .rejected(rejection.expected))
    #expect(machine.isRecording)
}

// MARK: - Escape, cancel, focus

/// Escape cancels recording immediately, with or without modifiers, and even
/// as a key repeat.
@Test
func escapeAlwaysCancelsRecording() {
    for rawFlags in [UInt(0), bitIndependentCommand | bitIndependentOption, bitCapsLock] {
        var machine = recordingMachine()
        let effect = machine.handle(.keyDown(keyCode: keyCodeEscape, rawFlags: rawFlags, isRepeat: false))
        #expect(effect == .cancelled)
        #expect(machine.phase == .idle)
    }

    var repeatMachine = recordingMachine()
    #expect(repeatMachine.handle(.keyDown(keyCode: keyCodeEscape, rawFlags: 0, isRepeat: true)) == .cancelled)
    #expect(repeatMachine.phase == .idle)
}

@Test
func cancelAndFocusLostEndRecordingOnlyWhenActive() {
    var machine = recordingMachine()
    #expect(machine.handle(.cancel) == .cancelled)
    #expect(machine.phase == .idle)
    // Already idle: no effect.
    #expect(machine.handle(.cancel) == nil)
    #expect(machine.handle(.focusLost) == nil)

    var focusMachine = recordingMachine()
    #expect(focusMachine.handle(.focusLost) == .cancelled)
    #expect(focusMachine.phase == .idle)
}

@Test
func inputsWhileIdleProduceNoEffects() {
    var machine = ShortcutCaptureStateMachine()
    #expect(machine.handle(.keyDown(keyCode: UInt16(kVK_ANSI_A), rawFlags: bitIndependentOption, isRepeat: false)) == nil)
    #expect(machine.handle(.flagsChanged(keyCode: keyCodeRightOption, rawFlags: bitRightOptionSide | bitIndependentOption)) == nil)
    #expect(machine.handle(.cancel) == nil)
    #expect(machine.handle(.focusLost) == nil)
    #expect(machine.phase == .idle)
}

// MARK: - Right-modifier tap cycle

struct RightTapTarget: Sendable, CustomTestStringConvertible {
    let name: String
    let kind: RightModifierCandidateKind
    let keyCode: UInt16
    let sideMask: UInt
    let independentMask: UInt
    let expected: RecordedHotkey
    let settingsValue: String

    var pressFlags: UInt { sideMask | independentMask }

    var testDescription: String { name }
}

private let rightTapTargets: [RightTapTarget] = [
    RightTapTarget(
        name: "Right Option",
        kind: .rightOption,
        keyCode: keyCodeRightOption,
        sideMask: bitRightOptionSide,
        independentMask: bitIndependentOption,
        expected: .rightOption,
        settingsValue: HotkeySettings.rightOptionHotkey
    ),
    RightTapTarget(
        name: "Right Command",
        kind: .rightCommand,
        keyCode: keyCodeRightCommand,
        sideMask: bitRightCommandSide,
        independentMask: bitIndependentCommand,
        expected: .rightCommand,
        settingsValue: HotkeySettings.rightCommandHotkey
    ),
]

/// A clean press+release of the exact sole physical right modifier commits
/// the sentinel only when the policy allows right-modifier-only shortcuts;
/// otherwise it rejects with modifierOnlyPrimary and keeps recording.
@Test(arguments: rightTapTargets)
func cleanRightModifierTapCommitsOnlyWhenAllowed(target: RightTapTarget) {
    // Allowed: commits the sentinel settings value.
    var allowed = ShortcutCaptureStateMachine()
    _ = allowed.handle(.start(HotkeyCapturePolicy(allowsRightModifierOnly: true)))
    #expect(allowed.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags)) == nil)
    let effect = allowed.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: 0))
    #expect(effect == .committed(target.expected))
    #expect(allowed.phase == .idle)
    if case .committed(let recorded)? = effect {
        #expect(recorded.settingsValue == target.settingsValue)
    }

    // Not allowed: rejects and keeps recording with no candidate.
    let policy = HotkeyCapturePolicy(allowsRightModifierOnly: false)
    var rejected = ShortcutCaptureStateMachine()
    _ = rejected.handle(.start(policy))
    #expect(rejected.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags)) == nil)
    #expect(rejected.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: 0)) == .rejected(.modifierOnlyPrimary))
    #expect(rejected.phase == .recording(policy: policy, candidate: nil))
}

/// Caps Lock state must not disturb an otherwise exact right-modifier tap.
@Test(arguments: rightTapTargets)
func capsLockDoesNotDisturbRightModifierTap(target: RightTapTarget) {
    var machine = ShortcutCaptureStateMachine()
    _ = machine.handle(.start(HotkeyCapturePolicy(allowsRightModifierOnly: true)))
    // Press with Caps Lock already on.
    #expect(machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags | bitCapsLock)) == nil)
    // Release while Caps Lock stays on.
    #expect(machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: bitCapsLock)) == .committed(target.expected))
}

/// Duplicate flagsChanged events for the exact same sole-target state are
/// deduplicated and keep the candidate clean for a later commit.
@Test(arguments: rightTapTargets)
func duplicateSoleTargetFlagsAreDeduplicated(target: RightTapTarget) {
    let policy = HotkeyCapturePolicy(allowsRightModifierOnly: true)
    var machine = ShortcutCaptureStateMachine()
    _ = machine.handle(.start(policy))
    _ = machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags))
    #expect(machine.phase == .recording(policy: policy, candidate: RightModifierCandidate(kind: target.kind, state: .clean)))

    #expect(machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags)) == nil)
    #expect(machine.phase == .recording(policy: policy, candidate: RightModifierCandidate(kind: target.kind, state: .clean)))

    #expect(machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: 0)) == .committed(target.expected))
}

struct ContaminationCase: Sendable, CustomTestStringConvertible {
    let name: String
    let event: HotkeyCaptureInput

    var testDescription: String { name }
}

private func contaminationEvents(for target: RightTapTarget) -> [ContaminationCase] {
    let otherTarget = rightTapTargets.first { $0.kind != target.kind }!
    let leftKeyCode: UInt16 = target.kind == .rightOption ? keyCodeLeftOption : keyCodeLeftCommand
    let leftSideMask: UInt = target.kind == .rightOption ? bitLeftOptionSide : bitLeftCommandSide
    return [
        ContaminationCase(
            name: "left counterpart press",
            event: .flagsChanged(keyCode: leftKeyCode, rawFlags: leftSideMask | target.independentMask)
        ),
        ContaminationCase(
            name: "other family right modifier press",
            event: .flagsChanged(keyCode: otherTarget.keyCode, rawFlags: otherTarget.pressFlags)
        ),
        ContaminationCase(
            name: "left shift added",
            event: .flagsChanged(keyCode: keyCodeLeftShift, rawFlags: target.pressFlags | bitLeftShiftSide | bitIndependentShift)
        ),
        ContaminationCase(
            name: "left control added",
            event: .flagsChanged(keyCode: keyCodeLeftControl, rawFlags: target.pressFlags | bitLeftControlSide | bitIndependentControl)
        ),
        ContaminationCase(
            name: "function added",
            event: .flagsChanged(keyCode: keyCodeFunction, rawFlags: target.pressFlags | bitIndependentFunction)
        ),
        ContaminationCase(
            name: "side bit without family bit",
            event: .flagsChanged(keyCode: target.keyCode, rawFlags: target.sideMask)
        ),
        ContaminationCase(
            name: "family bit without side bit",
            event: .flagsChanged(keyCode: target.keyCode, rawFlags: target.independentMask)
        ),
        ContaminationCase(
            name: "key repeat while held",
            event: .keyDown(keyCode: target.keyCode, rawFlags: target.pressFlags, isRepeat: true)
        ),
        ContaminationCase(
            name: "bare key down while held",
            event: .keyDown(keyCode: UInt16(kVK_ANSI_A), rawFlags: 0, isRepeat: false)
        ),
        ContaminationCase(
            name: "unsupported key down while held",
            event: .keyDown(keyCode: keyCodeUnsupported, rawFlags: bitIndependentCommand, isRepeat: false)
        ),
    ]
}

/// Any foreign, mixed, malformed, or repeat event while a clean candidate is
/// held prevents the tap from ever committing; afterwards a fresh clean tap
/// works again.
@Test(arguments: rightTapTargets)
func contaminationPreventsRightModifierCommit(target: RightTapTarget) {
    for contamination in contaminationEvents(for: target) {
        let policy = HotkeyCapturePolicy(allowsRightModifierOnly: true)
        var machine = ShortcutCaptureStateMachine()
        _ = machine.handle(.start(policy))
        _ = machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags))

        // The contaminating event itself never commits.
        #expect(
            machine.handle(contamination.event) != .committed(target.expected),
            "\(contamination.name) must not commit"
        )

        // The target release after contamination never commits and leaves no
        // candidate behind.
        let release = machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: 0))
        #expect(release != .committed(target.expected), "release after \(contamination.name) must not commit")
        #expect(
            machine.phase == .recording(policy: policy, candidate: nil),
            "\(contamination.name) must leave no live candidate"
        )

        // Recovery: a fresh clean tap commits again.
        #expect(machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags)) == nil)
        #expect(
            machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: 0)) == .committed(target.expected),
            "clean tap after \(contamination.name) must commit"
        )
    }
}

/// Releasing the target while another modifier is still held never commits;
/// the candidate is dropped.
@Test(arguments: rightTapTargets)
func targetReleaseWithAnotherModifierHeldNeverCommits(target: RightTapTarget) {
    let policy = HotkeyCapturePolicy(allowsRightModifierOnly: true)
    var machine = ShortcutCaptureStateMachine()
    _ = machine.handle(.start(policy))
    _ = machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags))

    let leftShiftStillHeld = bitLeftShiftSide | bitIndependentShift
    #expect(machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: leftShiftStillHeld)) == nil)
    #expect(machine.phase == .recording(policy: policy, candidate: nil))
}

/// Modifier transitions that are not an exact sole right-target press create
/// no candidate.
@Test
func nonTargetModifierTransitionsCreateNoCandidate() {
    let policy = HotkeyCapturePolicy(allowsRightModifierOnly: true)
    var machine = ShortcutCaptureStateMachine()
    _ = machine.handle(.start(policy))
    let noCandidate = ShortcutCapturePhase.recording(policy: policy, candidate: nil)

    #expect(machine.handle(.flagsChanged(keyCode: keyCodeLeftOption, rawFlags: bitLeftOptionSide | bitIndependentOption)) == nil)
    #expect(machine.phase == noCandidate)
    #expect(machine.handle(.flagsChanged(keyCode: keyCodeLeftCommand, rawFlags: bitLeftCommandSide | bitIndependentCommand)) == nil)
    #expect(machine.phase == noCandidate)
    #expect(machine.handle(.flagsChanged(keyCode: keyCodeLeftShift, rawFlags: bitLeftShiftSide | bitIndependentShift)) == nil)
    #expect(machine.phase == noCandidate)
    // Right Option combined with another modifier is not a sole-target press.
    #expect(
        machine.handle(
            .flagsChanged(keyCode: keyCodeRightOption, rawFlags: bitRightOptionSide | bitIndependentOption | bitLeftShiftSide | bitIndependentShift)
        ) == nil
    )
    #expect(machine.phase == noCandidate)
}

/// A combo keyDown wins over a pending right-modifier tap candidate.
@Test(arguments: rightTapTargets)
func comboKeyDownWinsOverPendingRightModifierCandidate(target: RightTapTarget) {
    var machine = ShortcutCaptureStateMachine()
    _ = machine.handle(.start(HotkeyCapturePolicy(allowsRightModifierOnly: true)))
    _ = machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags))

    let effect = machine.handle(.keyDown(keyCode: UInt16(kVK_ANSI_S), rawFlags: target.pressFlags, isRepeat: false))
    let expected = target.kind == .rightOption ? "Option+S" : "Command+S"
    #expect(effect == .committed(.combination(expected)))
    #expect(machine.phase == .idle)
}

/// Key repeats can never commit and permanently contaminate a pending
/// right-modifier tap candidate.
@Test
func keyRepeatNeverCommitsAndContaminatesCandidate() {
    let policy = HotkeyCapturePolicy(allowsRightModifierOnly: true)
    var machine = ShortcutCaptureStateMachine()
    _ = machine.handle(.start(policy))
    _ = machine.handle(.flagsChanged(keyCode: keyCodeRightOption, rawFlags: bitRightOptionSide | bitIndependentOption))
    #expect(machine.phase == .recording(policy: policy, candidate: RightModifierCandidate(kind: .rightOption, state: .clean)))

    // A repeat of the target key itself contaminates the tap.
    #expect(machine.handle(.keyDown(keyCode: keyCodeRightOption, rawFlags: bitRightOptionSide | bitIndependentOption, isRepeat: true)) == nil)
    #expect(machine.phase == .recording(policy: policy, candidate: RightModifierCandidate(kind: .rightOption, state: .contaminated)))

    // The later clean release no longer commits.
    #expect(machine.handle(.flagsChanged(keyCode: keyCodeRightOption, rawFlags: 0)) == nil)
    #expect(machine.phase == .recording(policy: policy, candidate: nil))

    // Repeats without a candidate are simply ignored.
    var bare = recordingMachine()
    #expect(bare.handle(.keyDown(keyCode: UInt16(kVK_ANSI_A), rawFlags: bitIndependentOption, isRepeat: true)) == nil)
    #expect(bare.isRecording)
}

/// Recorded hotkeys persist the canonical settings contract.
@Test
func recordedHotkeySettingsValuesMatchThePersistenceContract() {
    #expect(RecordedHotkey.combination("Option+S").settingsValue == "Option+S")
    #expect(RecordedHotkey.rightOption.settingsValue == HotkeySettings.rightOptionHotkey)
    #expect(RecordedHotkey.rightCommand.settingsValue == HotkeySettings.rightCommandHotkey)
    #expect(HotkeySettings.rightOptionHotkey == "RightOption")
    #expect(HotkeySettings.rightCommandHotkey == "RightCommand")
}

// MARK: - HotkeyCaptureNSView event path

@MainActor
private func makeActiveCaptureView(allowsRightModifierOnly: Bool = false) -> HotkeyCaptureNSView {
    let view = HotkeyCaptureNSView()
    view.allowsRightModifierOnly = allowsRightModifierOnly
    view.activateCapture()
    #expect(view.acceptsFirstResponder)
    return view
}

@MainActor
private func syntheticKeyDown(keyCode: UInt16, flags: NSEvent.ModifierFlags, isRepeat: Bool = false) throws -> NSEvent {
    try #require(
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: isRepeat,
            keyCode: keyCode
        ),
        "synthetic keyDown construction must be stable"
    )
}

@MainActor
private func syntheticFlagsChanged(keyCode: UInt16, rawFlags: UInt) throws -> NSEvent {
    try #require(
        NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: rawFlags),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ),
        "synthetic flagsChanged construction must be stable"
    )
}

/// The production NSView keyDown path commits the canonical combination
/// string through the onCommit callback and deactivates capture.
@MainActor
@Test
func captureViewCommitsComboThroughKeyDownEvent() throws {
    let view = makeActiveCaptureView()
    var committed: [String] = []
    var cancelled = 0
    view.onCommit = { committed.append($0) }
    view.onCancel = { cancelled += 1 }

    try view.keyDown(with: syntheticKeyDown(keyCode: UInt16(kVK_ANSI_S), flags: [.option]))

    #expect(committed == ["Option+S"])
    #expect(cancelled == 0)
    #expect(!view.acceptsFirstResponder)
}

/// Physical device-dependent side bits ride along on the event without
/// changing the canonical committed string.
@MainActor
@Test
func captureViewCommitIgnoresPhysicalSideBitsInFlags() throws {
    let view = makeActiveCaptureView()
    var committed: [String] = []
    view.onCommit = { committed.append($0) }

    try view.keyDown(
        with: syntheticKeyDown(
            keyCode: UInt16(kVK_ANSI_S),
            flags: NSEvent.ModifierFlags(rawValue: bitLeftOptionSide | bitIndependentOption)
        )
    )

    #expect(committed == ["Option+S"])
}

/// Escape through the production keyDown path cancels via onCancel.
@MainActor
@Test
func captureViewEscapeKeyDownCancelsThroughCallback() throws {
    let view = makeActiveCaptureView()
    var committed: [String] = []
    var cancelled = 0
    view.onCommit = { committed.append($0) }
    view.onCancel = { cancelled += 1 }

    try view.keyDown(with: syntheticKeyDown(keyCode: keyCodeEscape, flags: []))

    #expect(cancelled == 1)
    #expect(committed.isEmpty)
    #expect(!view.acceptsFirstResponder)
}

/// Rejections surface through onReject with the exact reason and keep the
/// capture active for the next attempt.
@MainActor
@Test
func captureViewReportsRejectionReasonsWithoutEndingCapture() throws {
    let view = makeActiveCaptureView()
    var committed: [String] = []
    var cancelled = 0
    var rejections: [HotkeyCaptureRejectionReason] = []
    view.onCommit = { committed.append($0) }
    view.onCancel = { cancelled += 1 }
    view.onReject = { rejections.append($0) }

    // Bare key: modifier required; capture stays active.
    try view.keyDown(with: syntheticKeyDown(keyCode: UInt16(kVK_ANSI_A), flags: []))
    #expect(rejections == [.modifierRequired])
    #expect(committed.isEmpty)
    #expect(view.acceptsFirstResponder)

    // A valid combo afterwards still commits.
    try view.keyDown(with: syntheticKeyDown(keyCode: UInt16(kVK_ANSI_S), flags: [.option]))
    #expect(committed == ["Option+S"])
    #expect(cancelled == 0)
}

/// The production flagsChanged path commits a clean physical right-modifier
/// tap when the policy allows it, and rejects it otherwise.
@MainActor
@Test
func captureViewRightModifierFlagsPathCommitsAndRejects() throws {
    // Allowed: clean tap commits the sentinel.
    let allowedView = makeActiveCaptureView(allowsRightModifierOnly: true)
    var committed: [String] = []
    var cancelled = 0
    allowedView.onCommit = { committed.append($0) }
    allowedView.onCancel = { cancelled += 1 }

    try allowedView.flagsChanged(with: syntheticFlagsChanged(keyCode: keyCodeRightOption, rawFlags: bitRightOptionSide | bitIndependentOption))
    try allowedView.flagsChanged(with: syntheticFlagsChanged(keyCode: keyCodeRightOption, rawFlags: 0))

    #expect(committed == [HotkeySettings.rightOptionHotkey])
    #expect(cancelled == 0)
    #expect(!allowedView.acceptsFirstResponder)

    // Not allowed: clean tap rejects with modifierOnlyPrimary and keeps recording.
    let rejectedView = makeActiveCaptureView(allowsRightModifierOnly: false)
    var rejections: [HotkeyCaptureRejectionReason] = []
    var rejectedCancelled = 0
    rejectedView.onReject = { rejections.append($0) }
    rejectedView.onCancel = { rejectedCancelled += 1 }

    try rejectedView.flagsChanged(with: syntheticFlagsChanged(keyCode: keyCodeRightCommand, rawFlags: bitRightCommandSide | bitIndependentCommand))
    try rejectedView.flagsChanged(with: syntheticFlagsChanged(keyCode: keyCodeRightCommand, rawFlags: 0))

    #expect(rejections == [.modifierOnlyPrimary])
    #expect(rejectedCancelled == 0)
    #expect(rejectedView.acceptsFirstResponder)
}

/// Deactivating an active capture cancels it exactly once; deactivating an
/// inactive view is a no-op.
@MainActor
@Test
func captureViewDeactivationCancelsActiveCaptureOnce() {
    let view = makeActiveCaptureView()
    var cancelled = 0
    view.onCancel = { cancelled += 1 }

    view.deactivateCapture()
    #expect(cancelled == 1)
    #expect(!view.acceptsFirstResponder)

    view.deactivateCapture()
    #expect(cancelled == 1)
}

/// Activation is idempotent: a double activation still yields exactly one
/// cancellation on deactivation.
@MainActor
@Test
func captureViewActivationIsIdempotent() {
    let view = HotkeyCaptureNSView()
    view.activateCapture()
    view.activateCapture()
    #expect(view.acceptsFirstResponder)

    var cancelled = 0
    view.onCancel = { cancelled += 1 }
    view.deactivateCapture()
    #expect(cancelled == 1)
}

/// Events on a never-activated view produce no capture callbacks.
@MainActor
@Test
func captureViewIgnoresFlagsWhileInactive() throws {
    let view = HotkeyCaptureNSView()
    var committed: [String] = []
    var cancelled = 0
    var rejections: [HotkeyCaptureRejectionReason] = []
    view.onCommit = { committed.append($0) }
    view.onCancel = { cancelled += 1 }
    view.onReject = { rejections.append($0) }

    try view.flagsChanged(with: syntheticFlagsChanged(keyCode: keyCodeRightOption, rawFlags: bitRightOptionSide | bitIndependentOption))
    try view.flagsChanged(with: syntheticFlagsChanged(keyCode: keyCodeRightOption, rawFlags: 0))

    #expect(committed.isEmpty)
    #expect(cancelled == 0)
    #expect(rejections.isEmpty)
    #expect(!view.acceptsFirstResponder)
}
