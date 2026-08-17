import Carbon
import Foundation
import NativeBolabolCore
@testable import NativeBolabol
import Testing

// S3 / ADR-024 deterministic regression coverage for the pure generation-gated
// primary hotkey state machine and the localized S3 Settings copy.
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

struct RightTarget: Sendable {
    let source: PrimaryHotkeySource
    let keyCode: UInt16
    let sideMask: UInt
    let independentMask: UInt
    let pressFlags: UInt

    init(source: PrimaryHotkeySource, keyCode: UInt16, sideMask: UInt, independentMask: UInt) {
        self.source = source
        self.keyCode = keyCode
        self.sideMask = sideMask
        self.independentMask = independentMask
        self.pressFlags = sideMask | independentMask
    }
}

let targets: [RightTarget] = [
    RightTarget(source: .rightOption, keyCode: keyCodeRightOption, sideMask: bitRightOptionSide, independentMask: bitIndependentOption),
    RightTarget(source: .rightCommand, keyCode: keyCodeRightCommand, sideMask: bitRightCommandSide, independentMask: bitIndependentCommand),
]

let leftCounterpart: [PrimaryHotkeySource: (keyCode: UInt16, sideMask: UInt)] = [
    .rightOption: (keyCodeLeftOption, bitLeftOptionSide),
    .rightCommand: (keyCodeLeftCommand, bitLeftCommandSide),
]

private func makeMachine(
    generation: UInt64 = 1,
    enabled: Bool = true,
    source: PrimaryHotkeySource,
    delivery: PrimaryHotkeyDelivery
) -> PrimaryHotkeyStateMachine {
    PrimaryHotkeyStateMachine(
        configuration: PrimaryHotkeyConfiguration(
            generation: generation,
            enabled: enabled,
            source: source,
            delivery: delivery
        )
    )
}

private func configure(
    _ machine: inout PrimaryHotkeyStateMachine,
    generation: UInt64,
    enabled: Bool = true,
    source: PrimaryHotkeySource,
    delivery: PrimaryHotkeyDelivery
) -> PrimaryHotkeyOutput? {
    machine.handle(
        .configure(
            PrimaryHotkeyConfiguration(
                generation: generation,
                enabled: enabled,
                source: source,
                delivery: delivery
            )
        )
    )
}

// MARK: - Hardware constant pins

@Test
func rightModifierHardwareIdentityConstantsArePinned() {
    // The state machine compares NSEvent keyCodes against these virtual key
    // codes; pinning the literals guards the documented macOS identity.
    #expect(keyCodeRightOption == UInt16(kVK_RightOption))
    #expect(keyCodeRightCommand == UInt16(kVK_RightCommand))
    #expect(keyCodeLeftOption == UInt16(kVK_Option))
    #expect(keyCodeLeftCommand == UInt16(kVK_Command))
    #expect(keyCodeLeftShift == UInt16(kVK_Shift))
    #expect(keyCodeLeftControl == UInt16(kVK_Control))
    #expect(keyCodeCapsLock == UInt16(kVK_CapsLock))
    #expect(keyCodeFunction == UInt16(kVK_Function))
}

// MARK: - Accepted press/release matrix (both right sources x both deliveries)

@Test(arguments: targets)
func acceptedTogglePressEmitsExactlyOneTriggeredAndReleaseIsSilent(target: RightTarget) {
    var machine = makeMachine(source: target.source, delivery: .toggle)

    let press = machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags, generation: 1))
    #expect(press == .triggered)
    #expect(machine.phase == .acceptedToggle)

    let release = machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: 0, generation: 1))
    #expect(release == nil)
    #expect(machine.phase == .idle)

    // After a full release the machine accepts an independent new press.
    let repress = machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags, generation: 1))
    #expect(repress == .triggered)
}

@Test(arguments: targets)
func acceptedHoldPressReleaseEmitsBalancedKeyDownKeyUp(target: RightTarget) {
    var machine = makeMachine(source: target.source, delivery: .hold)

    let press = machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags, generation: 1))
    #expect(press == .keyDown)
    #expect(machine.phase == .acceptedHold)

    let release = machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: 0, generation: 1))
    #expect(release == .keyUp)
    #expect(machine.phase == .idle)

    // A lone release from idle never fabricates output.
    let staleRelease = machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: 0, generation: 1))
    #expect(staleRelease == nil)
    #expect(machine.phase == .idle)
}

@Test(arguments: targets)
func duplicateSnapshotFromLocalAndGlobalScopesDeliversOnce(target: RightTarget) {
    var toggleMachine = makeMachine(source: target.source, delivery: .toggle)
    #expect(toggleMachine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags, generation: 1)) == .triggered)
    // Identical snapshot as observed by the complementary monitor scope.
    #expect(toggleMachine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags, generation: 1)) == nil)
    #expect(toggleMachine.phase == .acceptedToggle)

    var holdMachine = makeMachine(source: target.source, delivery: .hold)
    #expect(holdMachine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags, generation: 1)) == .keyDown)
    #expect(holdMachine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags, generation: 1)) == nil)
    #expect(holdMachine.phase == .acceptedHold)
}

@Test(arguments: targets)
func wrongSourceDisabledAndNoneSuppressFlagsInput(target: RightTarget) {
    // The opposite right key never satisfies this target.
    let wrongTarget = target.source == .rightOption ? targets[1] : targets[0]
    var machine = makeMachine(source: target.source, delivery: .toggle)
    #expect(machine.handle(.flagsChanged(keyCode: wrongTarget.keyCode, rawFlags: wrongTarget.pressFlags, generation: 1)) == nil)
    #expect(machine.phase == .suppressedModifierDown)

    // Disabled configuration never emits anything.
    var disabled = makeMachine(enabled: false, source: target.source, delivery: .toggle)
    #expect(disabled.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags, generation: 1)) == nil)
    #expect(disabled.phase == .idle)

    // .none source routes flags to nothing.
    var none = makeMachine(source: .none, delivery: .toggle)
    #expect(none.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags, generation: 1)) == nil)
    #expect(none.phase == .idle)
}

// MARK: - Exact-one negatives (both right sources)

@Test(arguments: targets)
func leftCounterpartPressIsSuppressed(target: RightTarget) {
    let left = leftCounterpart[target.source]!
    var machine = makeMachine(source: target.source, delivery: .toggle)
    let output = machine.handle(
        .flagsChanged(keyCode: left.keyCode, rawFlags: left.sideMask | target.independentMask, generation: 1)
    )
    #expect(output == nil)
    #expect(machine.phase == .suppressedModifierDown)
}

@Test(arguments: targets)
func sideBitWithoutIndependentBitIsSuppressed(target: RightTarget) {
    var machine = makeMachine(source: target.source, delivery: .toggle)
    let output = machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.sideMask, generation: 1))
    #expect(output == nil)
    #expect(machine.phase == .suppressedModifierDown)
}

@Test(arguments: targets)
func independentBitWithoutSideBitIsSuppressed(target: RightTarget) {
    var machine = makeMachine(source: target.source, delivery: .toggle)
    let output = machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.independentMask, generation: 1))
    #expect(output == nil)
    #expect(machine.phase == .suppressedModifierDown)
}

@Test(arguments: targets)
func inconsistentKeyCodeMaskIdentityIsSuppressed(target: RightTarget) {
    // Bits claim this target is down, but the changed key belongs to the
    // other family (remapped/synthetic driver disagreement fails closed).
    let wrongKey = target.source == .rightOption ? keyCodeRightCommand : keyCodeRightOption
    var machine = makeMachine(source: target.source, delivery: .toggle)
    let output = machine.handle(.flagsChanged(keyCode: wrongKey, rawFlags: target.pressFlags, generation: 1))
    #expect(output == nil)
    #expect(machine.phase == .suppressedModifierDown)
}

@Test(arguments: targets)
func leftPlusRightOfSameFamilyIsSuppressed(target: RightTarget) {
    let left = leftCounterpart[target.source]!
    var machine = makeMachine(source: target.source, delivery: .toggle)
    let bothHeld = target.pressFlags | left.sideMask
    let output = machine.handle(.flagsChanged(keyCode: left.keyCode, rawFlags: bothHeld, generation: 1))
    #expect(output == nil)
    #expect(machine.phase == .suppressedModifierDown)
}

@Test(arguments: targets)
func shiftControlOtherFamilyAndFunctionHeldSuppress(target: RightTarget) {
    let otherFamilyBits: UInt = target.source == .rightOption
        ? bitLeftCommandSide | bitIndependentCommand
        : bitLeftOptionSide | bitIndependentOption
    let contaminants: [UInt] = [
        bitLeftShiftSide | bitIndependentShift,
        bitLeftControlSide | bitIndependentControl,
        otherFamilyBits,
        bitIndependentFunction,
    ]
    for extra in contaminants {
        var machine = makeMachine(source: target.source, delivery: .toggle)
        let output = machine.handle(
            .flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags | extra, generation: 1)
        )
        #expect(output == nil)
        #expect(machine.phase == .suppressedModifierDown)
    }
}

@Test(arguments: targets)
func capsLockAlonePermitsExactTargetPress(target: RightTarget) {
    var machine = makeMachine(source: target.source, delivery: .toggle)
    var holdMachine = makeMachine(source: target.source, delivery: .hold)
    let withCapsLock = target.pressFlags | bitCapsLock

    #expect(machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: withCapsLock, generation: 1)) == .triggered)
    #expect(machine.phase == .acceptedToggle)
    // Caps Lock release while the target stays held produces no extra output.
    #expect(machine.handle(.flagsChanged(keyCode: keyCodeCapsLock, rawFlags: target.pressFlags, generation: 1)) == nil)
    #expect(machine.phase == .acceptedToggle)
    // Full release ends the cycle.
    #expect(machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: 0, generation: 1)) == nil)
    #expect(machine.phase == .idle)

    #expect(holdMachine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: withCapsLock, generation: 1)) == .keyDown)
    #expect(holdMachine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: bitCapsLock, generation: 1)) == .keyUp)
    #expect(holdMachine.phase == .idle)
}

// MARK: - Transition suppression

@Test(arguments: targets)
func removingConflictWhileTargetStaysDownNeverLateTriggers(target: RightTarget) {
    var machine = makeMachine(source: target.source, delivery: .toggle)
    // Target is pressed while Shift is already held: mixed chord suppresses.
    let mixed = target.pressFlags | bitLeftShiftSide | bitIndependentShift
    #expect(machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: mixed, generation: 1)) == nil)
    #expect(machine.phase == .suppressedModifierDown)
    // Shift released while the target stays down: still no late trigger.
    #expect(machine.handle(.flagsChanged(keyCode: keyCodeLeftShift, rawFlags: target.pressFlags, generation: 1)) == nil)
    #expect(machine.phase == .suppressedModifierDown)
    // Clean re-press after full target release is accepted.
    #expect(machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: 0, generation: 1)) == nil)
    #expect(machine.phase == .idle)
    #expect(machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags, generation: 1)) == .triggered)
}

@Test(arguments: targets)
func addingAnotherModifierAfterAcceptedPressEmitsNoExtraOutput(target: RightTarget) {
    var machine = makeMachine(source: target.source, delivery: .toggle)
    #expect(machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags, generation: 1)) == .triggered)

    let withShift = target.pressFlags | bitLeftShiftSide | bitIndependentShift
    #expect(machine.handle(.flagsChanged(keyCode: keyCodeLeftShift, rawFlags: withShift, generation: 1)) == nil)
    #expect(machine.phase == .suppressedModifierDown)

    // The mixed cycle cannot late-trigger when Shift is released again.
    #expect(machine.handle(.flagsChanged(keyCode: keyCodeLeftShift, rawFlags: target.pressFlags, generation: 1)) == nil)
    #expect(machine.phase == .suppressedModifierDown)

    // Full release resets; clean re-press accepted.
    #expect(machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: 0, generation: 1)) == nil)
    #expect(machine.phase == .idle)
    #expect(machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags, generation: 1)) == .triggered)
}

@Test(arguments: targets)
func holdReleaseWithAnotherModifierHeldStillEmitsExactlyOneKeyUp(target: RightTarget) {
    var machine = makeMachine(source: target.source, delivery: .hold)
    #expect(machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags, generation: 1)) == .keyDown)

    // A second modifier is pressed during the accepted hold: extra event is silent.
    let withShift = target.pressFlags | bitLeftShiftSide | bitIndependentShift
    #expect(machine.handle(.flagsChanged(keyCode: keyCodeLeftShift, rawFlags: withShift, generation: 1)) == nil)
    #expect(machine.phase == .acceptedHold)

    // Target release (side bits gone) while Shift is still held balances KeyUp exactly once.
    let afterRelease = bitLeftShiftSide | bitIndependentShift
    #expect(machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: afterRelease, generation: 1)) == .keyUp)
    #expect(machine.phase == .suppressedModifierDown)
    // No second KeyUp from repeated snapshots or remaining modifier events.
    #expect(machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: afterRelease, generation: 1)) == nil)
    // Full release returns to idle.
    #expect(machine.handle(.flagsChanged(keyCode: keyCodeLeftShift, rawFlags: 0, generation: 1)) == nil)
    #expect(machine.phase == .idle)
}

// MARK: - Carbon compatibility

@Test
func carbonToggleAndHoldParityWithModifierOnlySource() {
    var toggle = makeMachine(source: .carbonCombination, delivery: .toggle)
    #expect(toggle.handle(.carbonPressed(generation: 1)) == .triggered)
    #expect(toggle.phase == .acceptedToggle)
    #expect(toggle.handle(.carbonReleased(generation: 1)) == nil)
    #expect(toggle.phase == .idle)

    var hold = makeMachine(source: .carbonCombination, delivery: .hold)
    #expect(hold.handle(.carbonPressed(generation: 1)) == .keyDown)
    #expect(hold.phase == .acceptedHold)
    #expect(hold.handle(.carbonReleased(generation: 1)) == .keyUp)
    #expect(hold.phase == .idle)

    // Raw key-repeat duplicating a Carbon press delivers exactly one output.
    var repeatToggle = makeMachine(source: .carbonCombination, delivery: .toggle)
    #expect(repeatToggle.handle(.carbonPressed(generation: 1)) == .triggered)
    #expect(repeatToggle.handle(.carbonPressed(generation: 1)) == nil)
    #expect(repeatToggle.handle(.carbonPressed(generation: 1)) == nil)
}

@Test
func carbonCombinationSourceIgnoresFlagsChangedStream() {
    var machine = makeMachine(source: .carbonCombination, delivery: .toggle)
    #expect(machine.handle(.flagsChanged(keyCode: keyCodeRightOption, rawFlags: bitRightOptionSide | bitIndependentOption, generation: 1)) == nil)
    #expect(machine.phase == .idle)
}

@Test(arguments: targets)
func rightModifierSourceIgnoresCarbonEvents(target: RightTarget) {
    var machine = makeMachine(source: target.source, delivery: .toggle)
    #expect(machine.handle(.carbonPressed(generation: 1)) == nil)
    #expect(machine.handle(.carbonReleased(generation: 1)) == nil)
    #expect(machine.phase == .idle)
}

// MARK: - Reconfiguration and generation gating

@Test(arguments: targets)
func reconfiguringActiveHoldToDisabledEmitsExactlyOneBalancingKeyUp(target: RightTarget) {
    var machine = makeMachine(source: target.source, delivery: .hold)
    #expect(machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags, generation: 1)) == .keyDown)

    let output = configure(&machine, generation: 2, enabled: false, source: .none, delivery: .hold)
    #expect(output == .keyUp)
    #expect(machine.phase == .idle)
    // No second balancing output on repeated unrelated configuration.
    #expect(configure(&machine, generation: 2, enabled: false, source: .none, delivery: .hold) == nil)

    var machine2 = makeMachine(source: target.source, delivery: .hold)
    #expect(machine2.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags, generation: 1)) == .keyDown)
    #expect(configure(&machine2, generation: 2, source: target.source, delivery: .toggle) == .keyUp)
    #expect(machine2.phase == .idle)

    let otherSource: PrimaryHotkeySource = target.source == .rightOption ? .rightCommand : .rightOption
    var machine3 = makeMachine(source: target.source, delivery: .hold)
    #expect(machine3.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags, generation: 1)) == .keyDown)
    #expect(configure(&machine3, generation: 2, source: otherSource, delivery: .hold) == .keyUp)
    #expect(machine3.phase == .idle)
}

@Test(arguments: targets)
func toggleSuppressedAndIdleStatesResetSilently(target: RightTarget) {
    var toggleMachine = makeMachine(source: target.source, delivery: .toggle)
    #expect(toggleMachine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags, generation: 1)) == .triggered)
    #expect(configure(&toggleMachine, generation: 2, enabled: false, source: .none, delivery: .toggle) == nil)
    #expect(toggleMachine.phase == .idle)

    var suppressed = makeMachine(source: target.source, delivery: .toggle)
    let left = leftCounterpart[target.source]!
    #expect(suppressed.handle(.flagsChanged(keyCode: left.keyCode, rawFlags: left.sideMask | target.independentMask, generation: 1)) == nil)
    #expect(suppressed.phase == .suppressedModifierDown)
    #expect(configure(&suppressed, generation: 2, enabled: false, source: .none, delivery: .toggle) == nil)
    #expect(suppressed.phase == .idle)

    var idle = makeMachine(source: target.source, delivery: .toggle)
    #expect(configure(&idle, generation: 2, source: .rightOption, delivery: .hold) == nil)
    #expect(idle.phase == .idle)
}

@Test(arguments: targets)
func identicalRelevantConfigurationPreservesCycleAndAdoptsNewGeneration(target: RightTarget) {
    var machine = makeMachine(source: target.source, delivery: .hold)
    #expect(machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags, generation: 1)) == .keyDown)

    // Unrelated setting change: only the generation moves; the cycle survives.
    #expect(configure(&machine, generation: 2, source: target.source, delivery: .hold) == nil)
    #expect(machine.phase == .acceptedHold)
    #expect(machine.configuration.generation == 2)

    // Old-generation input is now ignored; current-generation release balances.
    #expect(machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: 0, generation: 1)) == nil)
    #expect(machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: 0, generation: 2)) == .keyUp)
    #expect(machine.phase == .idle)
}

@Test(arguments: targets)
func oldGenerationFlagsAndCarbonCallbacksAreNoOps(target: RightTarget) {
    var machine = makeMachine(generation: 2, source: target.source, delivery: .toggle)
    #expect(machine.handle(.flagsChanged(keyCode: target.keyCode, rawFlags: target.pressFlags, generation: 1)) == nil)
    #expect(machine.phase == .idle)

    var carbon = makeMachine(generation: 2, source: .carbonCombination, delivery: .toggle)
    #expect(carbon.handle(.carbonPressed(generation: 1)) == nil)
    #expect(carbon.handle(.carbonReleased(generation: 1)) == nil)
    #expect(carbon.phase == .idle)
}

@Test
func reconfigurationRelevanceIgnoresGeneration() {
    let base = PrimaryHotkeyConfiguration(generation: 1, enabled: true, source: .rightOption, delivery: .toggle)
    let sameFieldsNewGeneration = PrimaryHotkeyConfiguration(generation: 2, enabled: true, source: .rightOption, delivery: .toggle)
    #expect(!base.isReconfigurationRelevant(comparedTo: sameFieldsNewGeneration))

    let disabled = PrimaryHotkeyConfiguration(generation: 1, enabled: false, source: .rightOption, delivery: .toggle)
    let newSource = PrimaryHotkeyConfiguration(generation: 1, enabled: true, source: .rightCommand, delivery: .toggle)
    let newDelivery = PrimaryHotkeyConfiguration(generation: 1, enabled: true, source: .rightOption, delivery: .hold)
    #expect(base.isReconfigurationRelevant(comparedTo: disabled))
    #expect(base.isReconfigurationRelevant(comparedTo: newSource))
    #expect(base.isReconfigurationRelevant(comparedTo: newDelivery))
}

// MARK: - S4 / ADR-025 localization contract (all 15 concrete languages)

private let concreteLanguages: [UILanguagePreference] = UILanguagePreference.allCases.filter { $0 != .system }

/// S4 recorder copy: idle hint, the two recording prompts, the recording
/// accessibility value, all three rejection reasons, and the secondary
/// hotkey label/description.
private let s4HotkeyKeys: [AppTextKey] = [
    .hotkeyRecorderIdleHint,
    .hotkeyRecorderPrompt,
    .hotkeyRecorderPrimaryPrompt,
    .hotkeyRecorderRecordingAccessibility,
    .hotkeyRejectModifierRequired,
    .hotkeyRejectUnsupportedKey,
    .hotkeyRejectModifierOnlyPrimary,
    .hotkeySecondaryLabel,
    .hotkeySecondaryDesc,
]

/// Explanatory prompt/rejection/description copy that must be translated.
/// Silently copying the English sentence is a localization bug here.
/// Short labels and borrowed tokens (e.g. "Shift", "Escape") may legitimately
/// match across locales and are deliberately not enforced.
private let s4MustTranslateKeys: [AppTextKey] = [
    .hotkeyRecorderIdleHint,
    .hotkeyRecorderPrompt,
    .hotkeyRecorderPrimaryPrompt,
    .hotkeyRecorderRecordingAccessibility,
    .hotkeyRejectModifierRequired,
    .hotkeyRejectUnsupportedKey,
    .hotkeyRejectModifierOnlyPrimary,
    .hotkeySecondaryDesc,
]

@Test
func s4KeySetMatchesFifteenConcreteLanguages() {
    #expect(concreteLanguages.count == 15)
    #expect(s4HotkeyKeys.count == 9)
}

@Test
func everyS4HotkeyKeyResolvesNonRawInEveryConcreteLanguage() {
    for language in concreteLanguages {
        for key in s4HotkeyKeys {
            let value = AppText.localized(key, language: language)
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            // Non-raw: a raw-key fallback means this locale lacks the entry.
            #expect(value != key.rawValue)
        }
    }
}

@Test
func nonEnglishS4RecorderAndRejectionCopyIsTranslated() {
    var mismatches: [String] = []
    for language in concreteLanguages where language != .english {
        for key in s4MustTranslateKeys {
            let english = AppText.localized(key, language: .english)
            let localized = AppText.localized(key, language: language)
            if localized == english {
                mismatches.append("\(language.rawValue): \(key.rawValue)")
            }
        }
    }
    #expect(mismatches.isEmpty, "S4 non-English copy silently copies English: \(mismatches)")
}

@Test
func s4PrimaryPromptKeepsRightModifierGlyphsInEveryLanguage() {
    // The primary recorder prompt advertises the physical right-modifier
    // option; the ⌥/⌘ glyphs keep it unambiguous in every language.
    for language in concreteLanguages {
        let value = AppText.localized(.hotkeyRecorderPrimaryPrompt, language: language)
        #expect(value.contains("⌥"), "\(language.rawValue): ⌥ missing from primary prompt")
        #expect(value.contains("⌘"), "\(language.rawValue): ⌘ missing from primary prompt")
    }
}

@Test
func s4RejectionCopyIsDistinctPerReasonInEveryLanguage() {
    // The three rejection reasons surface as three different user-facing
    // explanations; identical strings would make the reasons
    // indistinguishable in the UI.
    for language in concreteLanguages {
        let modifierRequired = AppText.localized(.hotkeyRejectModifierRequired, language: language)
        let unsupportedKey = AppText.localized(.hotkeyRejectUnsupportedKey, language: language)
        let modifierOnlyPrimary = AppText.localized(.hotkeyRejectModifierOnlyPrimary, language: language)
        #expect(modifierRequired != unsupportedKey, "\(language.rawValue): rejection copy collides")
        #expect(modifierRequired != modifierOnlyPrimary, "\(language.rawValue): rejection copy collides")
        #expect(unsupportedKey != modifierOnlyPrimary, "\(language.rawValue): rejection copy collides")
    }
}

@Test
func englishPermissionCopyDocumentsGlobalRightModifierDetectionSemantics() {
    let text = AppText.localized(.accessibilityPermissionDescription, language: .english).lowercased()
    // Right-modifier global detection is explicitly documented.
    #expect(text.contains("right-modifier"))
    #expect(text.contains("global"))
    // Existing typing and clipboard semantics remain documented.
    #expect(text.contains("type into active app"))
    #expect(text.contains("clipboard"))
}

@Test
func nonEnglishPermissionCopyDoesNotSilentlyCopyTheEnglishSentence() {
    let english = AppText.localized(.accessibilityPermissionDescription, language: .english)
    for language in concreteLanguages where language != .english {
        #expect(AppText.localized(.accessibilityPermissionDescription, language: language) != english)
    }
}
