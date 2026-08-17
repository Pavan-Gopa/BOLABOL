import AppKit
import Carbon
import Foundation
import NativeBolabolCore

// MARK: - Hotkey Key Catalog

/// Bidirectional key catalog mapping between Carbon/AppKit virtual key codes and canonical string tokens.
enum HotkeyKeyCatalog: Sendable {
    /// Canonical tokens indexed by Carbon virtual key code.
    private static let canonicalTokensByCode: [UInt16: String] = [
        // Letters (ANSI)
        UInt16(kVK_ANSI_A): "A",
        UInt16(kVK_ANSI_B): "B",
        UInt16(kVK_ANSI_C): "C",
        UInt16(kVK_ANSI_D): "D",
        UInt16(kVK_ANSI_E): "E",
        UInt16(kVK_ANSI_F): "F",
        UInt16(kVK_ANSI_G): "G",
        UInt16(kVK_ANSI_H): "H",
        UInt16(kVK_ANSI_I): "I",
        UInt16(kVK_ANSI_J): "J",
        UInt16(kVK_ANSI_K): "K",
        UInt16(kVK_ANSI_L): "L",
        UInt16(kVK_ANSI_M): "M",
        UInt16(kVK_ANSI_N): "N",
        UInt16(kVK_ANSI_O): "O",
        UInt16(kVK_ANSI_P): "P",
        UInt16(kVK_ANSI_Q): "Q",
        UInt16(kVK_ANSI_R): "R",
        UInt16(kVK_ANSI_S): "S",
        UInt16(kVK_ANSI_T): "T",
        UInt16(kVK_ANSI_U): "U",
        UInt16(kVK_ANSI_V): "V",
        UInt16(kVK_ANSI_W): "W",
        UInt16(kVK_ANSI_X): "X",
        UInt16(kVK_ANSI_Y): "Y",
        UInt16(kVK_ANSI_Z): "Z",

        // Digits (ANSI)
        UInt16(kVK_ANSI_0): "0",
        UInt16(kVK_ANSI_1): "1",
        UInt16(kVK_ANSI_2): "2",
        UInt16(kVK_ANSI_3): "3",
        UInt16(kVK_ANSI_4): "4",
        UInt16(kVK_ANSI_5): "5",
        UInt16(kVK_ANSI_6): "6",
        UInt16(kVK_ANSI_7): "7",
        UInt16(kVK_ANSI_8): "8",
        UInt16(kVK_ANSI_9): "9",

        // Function Keys
        UInt16(kVK_F1): "F1",
        UInt16(kVK_F2): "F2",
        UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5",
        UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7",
        UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11",
        UInt16(kVK_F12): "F12",

        // Standard Control Keys
        UInt16(kVK_Space): "SPACE",
        UInt16(kVK_Return): "RETURN",
        UInt16(kVK_Tab): "TAB",
        UInt16(kVK_Delete): "DELETE",
        UInt16(kVK_Escape): "ESCAPE",

        // Punctuation and Symbols (ANSI)
        UInt16(kVK_ANSI_Grave): "~",
        UInt16(kVK_ANSI_Minus): "-",
        UInt16(kVK_ANSI_Equal): "=",
        UInt16(kVK_ANSI_LeftBracket): "[",
        UInt16(kVK_ANSI_RightBracket): "]",
        UInt16(kVK_ANSI_Backslash): "\\",
        UInt16(kVK_ANSI_Semicolon): ";",
        UInt16(kVK_ANSI_Quote): "'",
        UInt16(kVK_ANSI_Comma): ",",
        UInt16(kVK_ANSI_Period): ".",
        UInt16(kVK_ANSI_Slash): "/"
    ]

    /// Key code lookup by canonical token or known alias.
    private static let keyCodesByToken: [String: UInt16] = {
        var map: [String: UInt16] = [:]

        // Insert canonical entries
        for (code, token) in canonicalTokensByCode {
            map[token] = code
            map[token.uppercased()] = code
        }

        // Aliases for Grave/Tilde
        map["`"] = UInt16(kVK_ANSI_Grave)
        map["TILDE"] = UInt16(kVK_ANSI_Grave)
        map["GRAVE"] = UInt16(kVK_ANSI_Grave)
        map["BACKTICK"] = UInt16(kVK_ANSI_Grave)

        // Aliases for Delete / Control keys
        map["BACKSPACE"] = UInt16(kVK_Delete)

        // Punctuation aliases
        map["MINUS"] = UInt16(kVK_ANSI_Minus)
        map["EQUAL"] = UInt16(kVK_ANSI_Equal)
        map["EQUALS"] = UInt16(kVK_ANSI_Equal)
        map["LEFTBRACKET"] = UInt16(kVK_ANSI_LeftBracket)
        map["RIGHTBRACKET"] = UInt16(kVK_ANSI_RightBracket)
        map["BACKSLASH"] = UInt16(kVK_ANSI_Backslash)
        map["SEMICOLON"] = UInt16(kVK_ANSI_Semicolon)
        map["QUOTE"] = UInt16(kVK_ANSI_Quote)
        map["APOSTROPHE"] = UInt16(kVK_ANSI_Quote)
        map["COMMA"] = UInt16(kVK_ANSI_Comma)
        map["PERIOD"] = UInt16(kVK_ANSI_Period)
        map["DOT"] = UInt16(kVK_ANSI_Period)
        map["SLASH"] = UInt16(kVK_ANSI_Slash)

        // Cyrillic physical layout aliases
        let cyrillicAliases: [String: UInt16] = [
            "Ё": UInt16(kVK_ANSI_Grave), "ё": UInt16(kVK_ANSI_Grave),
            "Й": UInt16(kVK_ANSI_Q), "й": UInt16(kVK_ANSI_Q),
            "Ц": UInt16(kVK_ANSI_W), "ц": UInt16(kVK_ANSI_W),
            "У": UInt16(kVK_ANSI_E), "у": UInt16(kVK_ANSI_E),
            "К": UInt16(kVK_ANSI_R), "к": UInt16(kVK_ANSI_R),
            "Е": UInt16(kVK_ANSI_T), "е": UInt16(kVK_ANSI_T),
            "Н": UInt16(kVK_ANSI_Y), "н": UInt16(kVK_ANSI_Y),
            "Г": UInt16(kVK_ANSI_U), "г": UInt16(kVK_ANSI_U),
            "Ш": UInt16(kVK_ANSI_I), "ш": UInt16(kVK_ANSI_I),
            "Щ": UInt16(kVK_ANSI_O), "щ": UInt16(kVK_ANSI_O),
            "З": UInt16(kVK_ANSI_P), "з": UInt16(kVK_ANSI_P),
            "Х": UInt16(kVK_ANSI_LeftBracket), "х": UInt16(kVK_ANSI_LeftBracket),
            "Ъ": UInt16(kVK_ANSI_RightBracket), "ъ": UInt16(kVK_ANSI_RightBracket),
            "Ф": UInt16(kVK_ANSI_A), "ф": UInt16(kVK_ANSI_A),
            "Ы": UInt16(kVK_ANSI_S), "ы": UInt16(kVK_ANSI_S),
            "В": UInt16(kVK_ANSI_D), "в": UInt16(kVK_ANSI_D),
            "А": UInt16(kVK_ANSI_F), "а": UInt16(kVK_ANSI_F),
            "П": UInt16(kVK_ANSI_G), "п": UInt16(kVK_ANSI_G),
            "Р": UInt16(kVK_ANSI_H), "р": UInt16(kVK_ANSI_H),
            "О": UInt16(kVK_ANSI_J), "о": UInt16(kVK_ANSI_J),
            "Л": UInt16(kVK_ANSI_K), "л": UInt16(kVK_ANSI_K),
            "Д": UInt16(kVK_ANSI_L), "д": UInt16(kVK_ANSI_L),
            "Ж": UInt16(kVK_ANSI_Semicolon), "ж": UInt16(kVK_ANSI_Semicolon),
            "Э": UInt16(kVK_ANSI_Quote), "э": UInt16(kVK_ANSI_Quote),
            "Я": UInt16(kVK_ANSI_Z), "я": UInt16(kVK_ANSI_Z),
            "Ч": UInt16(kVK_ANSI_X), "ч": UInt16(kVK_ANSI_X),
            "С": UInt16(kVK_ANSI_C), "с": UInt16(kVK_ANSI_C),
            "М": UInt16(kVK_ANSI_V), "м": UInt16(kVK_ANSI_V),
            "И": UInt16(kVK_ANSI_B), "и": UInt16(kVK_ANSI_B),
            "Т": UInt16(kVK_ANSI_N), "т": UInt16(kVK_ANSI_N),
            "Ь": UInt16(kVK_ANSI_M), "ь": UInt16(kVK_ANSI_M),
            "Б": UInt16(kVK_ANSI_Comma), "б": UInt16(kVK_ANSI_Comma),
            "Ю": UInt16(kVK_ANSI_Period), "ю": UInt16(kVK_ANSI_Period)
        ]

        for (alias, code) in cyrillicAliases {
            map[alias] = code
        }

        return map
    }()

    /// Returns the canonical token for a given key code if supported for shortcut capture and parsing.
    /// Note: Escape is parser-compatible ("ESCAPE"), but the recorder reserves Escape to cancel.
    static func canonicalToken(for keyCode: UInt16) -> String? {
        canonicalTokensByCode[keyCode]
    }

    /// Returns the Carbon virtual key code for a given canonical token or alias.
    static func keyCode(forToken token: String) -> UInt16? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = keyCodesByToken[trimmed] {
            return direct
        }
        return keyCodesByToken[trimmed.uppercased()]
    }

    /// Set of all key codes supported by the catalog.
    static var allSupportedKeyCodes: Set<UInt16> {
        Set(canonicalTokensByCode.keys)
    }
}

/// Pure representation of modifier flags capturing physical side-bits and device-independent family masks.
struct PhysicalModifierSnapshot: Equatable, Sendable {
    // Physical modifier bitmask (excluding CapsLock):
    // Left Ctrl: 0x0001, Right Ctrl: 0x2000
    // Left Shift: 0x0002, Right Shift: 0x0004
    // Left Cmd: 0x0008, Right Cmd: 0x0010
    // Left Alt: 0x0020, Right Alt: 0x0040
    static let allPhysicalModifiersMask: UInt = 0x207F

    // Device-independent modifier bitmask (excluding CapsLock 0x00010000 and NumericPad/Help):
    // Shift: 0x00020000, Control: 0x00040000, Option: 0x00080000, Command: 0x00100000, Function: 0x00800000
    static let allIndependentMask: UInt = 0x009E0000

    static let rightOptionKeyCode: UInt16 = UInt16(kVK_RightOption)
    static let rightOptionSideMask: UInt = 0x0040
    static let rightOptionIndependentMask: UInt = 0x00080000

    static let rightCommandKeyCode: UInt16 = UInt16(kVK_RightCommand)
    static let rightCommandSideMask: UInt = 0x0010
    static let rightCommandIndependentMask: UInt = 0x00100000

    let rawFlags: UInt
    let heldPhysical: UInt
    let heldIndependent: UInt

    init(rawFlags: UInt) {
        self.rawFlags = rawFlags
        self.heldPhysical = rawFlags & Self.allPhysicalModifiersMask
        self.heldIndependent = rawFlags & Self.allIndependentMask
    }

    var isRightOptionSoleModifierHeld: Bool {
        heldPhysical == Self.rightOptionSideMask && heldIndependent == Self.rightOptionIndependentMask
    }

    var isRightCommandSoleModifierHeld: Bool {
        heldPhysical == Self.rightCommandSideMask && heldIndependent == Self.rightCommandIndependentMask
    }

    var areAllModifiersReleased: Bool {
        heldPhysical == 0 && heldIndependent == 0
    }

    var hasAnyModifierHeld: Bool {
        heldPhysical != 0 || heldIndependent != 0
    }

    var hasCommand: Bool {
        (heldIndependent & 0x00100000) != 0
    }

    var hasOption: Bool {
        (heldIndependent & 0x00080000) != 0
    }

    var hasControl: Bool {
        (heldIndependent & 0x00040000) != 0
    }

    var hasShift: Bool {
        (heldIndependent & 0x00020000) != 0
    }

    var hasFunction: Bool {
        (heldIndependent & 0x00800000) != 0
    }

    /// At least one of Command, Option, Control, or Shift is held.
    var hasStandardModifier: Bool {
        hasCommand || hasOption || hasControl || hasShift
    }
}

// MARK: - Shortcut Capture Types

struct HotkeyCapturePolicy: Equatable, Sendable {
    var allowsRightModifierOnly: Bool

    init(allowsRightModifierOnly: Bool) {
        self.allowsRightModifierOnly = allowsRightModifierOnly
    }
}

enum RecordedHotkey: Equatable, Sendable {
    case combination(String)
    case rightOption
    case rightCommand

    /// Returns the canonical persisted string representation.
    var settingsValue: String {
        switch self {
        case .combination(let s):
            return s
        case .rightOption:
            return HotkeySettings.rightOptionHotkey
        case .rightCommand:
            return HotkeySettings.rightCommandHotkey
        }
    }
}

enum HotkeyCaptureRejectionReason: Equatable, Sendable {
    case modifierRequired
    case unsupportedKey
    case modifierOnlyPrimary
}

enum HotkeyCaptureEffect: Equatable, Sendable {
    case committed(RecordedHotkey)
    case cancelled
    case rejected(HotkeyCaptureRejectionReason)
}

enum HotkeyCaptureInput: Equatable, Sendable {
    case start(HotkeyCapturePolicy)
    case keyDown(keyCode: UInt16, rawFlags: UInt, isRepeat: Bool)
    case flagsChanged(keyCode: UInt16, rawFlags: UInt)
    case cancel
    case focusLost
}

enum RightModifierCandidateKind: Equatable, Sendable {
    case rightOption
    case rightCommand
}

enum RightModifierCandidateState: Equatable, Sendable {
    case clean
    case contaminated
}

struct RightModifierCandidate: Equatable, Sendable {
    var kind: RightModifierCandidateKind
    var state: RightModifierCandidateState

    init(kind: RightModifierCandidateKind, state: RightModifierCandidateState) {
        self.kind = kind
        self.state = state
    }
}

enum ShortcutCapturePhase: Equatable, Sendable {
    case idle
    case recording(policy: HotkeyCapturePolicy, candidate: RightModifierCandidate?)
}

// MARK: - Shortcut Capture State Machine

/// Pure reducer governing shortcut recording, modifier validation, and physical right-modifier tap cycles.
struct ShortcutCaptureStateMachine: Sendable {
    private(set) var phase: ShortcutCapturePhase

    init(phase: ShortcutCapturePhase = .idle) {
        self.phase = phase
    }

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    mutating func handle(_ input: HotkeyCaptureInput) -> HotkeyCaptureEffect? {
        switch input {
        case .start(let policy):
            phase = .recording(policy: policy, candidate: nil)
            return nil

        case .cancel, .focusLost:
            switch phase {
            case .idle:
                return nil
            case .recording:
                phase = .idle
                return .cancelled
            }

        case .keyDown(let keyCode, let rawFlags, let isRepeat):
            guard case .recording(let policy, let candidate) = phase else {
                return nil
            }

            // Escape always cancels immediately regardless of modifiers or repeat
            if keyCode == UInt16(kVK_Escape) {
                phase = .idle
                return .cancelled
            }

            // Key repeat cannot commit and permanently contaminates any pending right-modifier tap
            if isRepeat {
                if let candidate {
                    phase = .recording(
                        policy: policy,
                        candidate: RightModifierCandidate(kind: candidate.kind, state: .contaminated)
                    )
                }
                return nil
            }

            // Check if key is in the supported catalog
            guard let keyToken = HotkeyKeyCatalog.canonicalToken(for: keyCode), keyCode != UInt16(kVK_Escape) else {
                if let candidate {
                    phase = .recording(
                        policy: policy,
                        candidate: RightModifierCandidate(kind: candidate.kind, state: .contaminated)
                    )
                }
                return .rejected(.unsupportedKey)
            }

            let snapshot = PhysicalModifierSnapshot(rawFlags: rawFlags)

            // Must have at least one standard modifier (Command, Option, Control, Shift)
            guard snapshot.hasStandardModifier else {
                if let candidate {
                    phase = .recording(
                        policy: policy,
                        candidate: RightModifierCandidate(kind: candidate.kind, state: .contaminated)
                    )
                }
                return .rejected(.modifierRequired)
            }

            // Build canonical combination string in fixed Command, Option, Control, Shift order
            var parts: [String] = []
            if snapshot.hasCommand { parts.append("Command") }
            if snapshot.hasOption { parts.append("Option") }
            if snapshot.hasControl { parts.append("Control") }
            if snapshot.hasShift { parts.append("Shift") }
            parts.append(keyToken)

            let combinationString = parts.joined(separator: "+")
            phase = .idle
            return .committed(.combination(combinationString))

        case .flagsChanged(let keyCode, let rawFlags):
            guard case .recording(let policy, let candidate) = phase else {
                return nil
            }

            let snapshot = PhysicalModifierSnapshot(rawFlags: rawFlags)

            if let currentCandidate = candidate {
                switch currentCandidate.state {
                case .clean:
                    // Check for matching target release
                    let isTargetRelease: Bool
                    switch currentCandidate.kind {
                    case .rightOption:
                        isTargetRelease = (keyCode == PhysicalModifierSnapshot.rightOptionKeyCode) &&
                            ((snapshot.heldPhysical & PhysicalModifierSnapshot.rightOptionSideMask) == 0)
                    case .rightCommand:
                        isTargetRelease = (keyCode == PhysicalModifierSnapshot.rightCommandKeyCode) &&
                            ((snapshot.heldPhysical & PhysicalModifierSnapshot.rightCommandSideMask) == 0)
                    }

                    if isTargetRelease {
                        // Check if release was clean (all modifiers released)
                        if snapshot.areAllModifiersReleased {
                            if policy.allowsRightModifierOnly {
                                phase = .idle
                                switch currentCandidate.kind {
                                case .rightOption:
                                    return .committed(.rightOption)
                                case .rightCommand:
                                    return .committed(.rightCommand)
                                }
                            } else {
                                phase = .recording(policy: policy, candidate: nil)
                                return .rejected(.modifierOnlyPrimary)
                            }
                        } else {
                            // Target released but another modifier is still held -> contaminated release
                            phase = .recording(policy: policy, candidate: nil)
                            return nil
                        }
                    } else {
                        // Deduplicate ONLY when keyCode is the exact target AND snapshot is exact sole-target-down
                        let isExactSameTargetDown: Bool
                        switch currentCandidate.kind {
                        case .rightOption:
                            isExactSameTargetDown = (keyCode == PhysicalModifierSnapshot.rightOptionKeyCode) &&
                                snapshot.isRightOptionSoleModifierHeld
                        case .rightCommand:
                            isExactSameTargetDown = (keyCode == PhysicalModifierSnapshot.rightCommandKeyCode) &&
                                snapshot.isRightCommandSoleModifierHeld
                        }

                        if isExactSameTargetDown {
                            // Deduplicate duplicate flags changed event
                            return nil
                        }

                        // Any other keyCode, side/family disagreement, malformed snapshot, or other transition
                        // contaminates permanently until target release
                        phase = .recording(
                            policy: policy,
                            candidate: RightModifierCandidate(kind: currentCandidate.kind, state: .contaminated)
                        )
                        return nil
                    }

                case .contaminated:
                    // While contaminated, wait for target release to clear the candidate
                    let isTargetRelease: Bool
                    switch currentCandidate.kind {
                    case .rightOption:
                        isTargetRelease = (keyCode == PhysicalModifierSnapshot.rightOptionKeyCode) &&
                            ((snapshot.heldPhysical & PhysicalModifierSnapshot.rightOptionSideMask) == 0)
                    case .rightCommand:
                        isTargetRelease = (keyCode == PhysicalModifierSnapshot.rightCommandKeyCode) &&
                            ((snapshot.heldPhysical & PhysicalModifierSnapshot.rightCommandSideMask) == 0)
                    }

                    if isTargetRelease {
                        phase = .recording(policy: policy, candidate: nil)
                    }
                    return nil
                }
            } else {
                // No candidate yet: check if exact sole target is pressed down
                if keyCode == PhysicalModifierSnapshot.rightOptionKeyCode && snapshot.isRightOptionSoleModifierHeld {
                    phase = .recording(
                        policy: policy,
                        candidate: RightModifierCandidate(kind: .rightOption, state: .clean)
                    )
                    return nil
                } else if keyCode == PhysicalModifierSnapshot.rightCommandKeyCode && snapshot.isRightCommandSoleModifierHeld {
                    phase = .recording(
                        policy: policy,
                        candidate: RightModifierCandidate(kind: .rightCommand, state: .clean)
                    )
                    return nil
                } else {
                    // Any other modifier transition creates no candidate
                    return nil
                }
            }
        }
    }
}
