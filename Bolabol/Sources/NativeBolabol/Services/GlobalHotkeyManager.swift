import AppKit
import Carbon
import Foundation
import NativeBolabolCore

extension Notification.Name {
    static let nativeBolabolHotkeyTriggered = Notification.Name("nativeBolabolHotkeyTriggered")
    static let nativeBolabolHotkeyKeyDown = Notification.Name("nativeBolabolHotkeyKeyDown")
    static let nativeBolabolHotkeyKeyUp = Notification.Name("nativeBolabolHotkeyKeyUp")
    static let nativeBolabolTargetHotkeyTriggered = Notification.Name("nativeBolabolTargetHotkeyTriggered")
    static let nativeBolabolQuickTranslationHotkeyTriggered = Notification.Name("nativeBolabolQuickTranslationHotkeyTriggered")
    static let nativeBolabolSettingsHotkeyTriggered = Notification.Name("nativeBolabolSettingsHotkeyTriggered")
    static let nativeBolabolDismissSheets = Notification.Name("nativeBolabolDismissSheets")
}

@MainActor
final class GlobalHotkeyManager {
    private var primaryHotKeyRef: EventHotKeyRef?
    private var secondaryHotKeyRef: EventHotKeyRef?
    private var tertiaryHotKeyRef: EventHotKeyRef?
    private var settingsHotKeyRef: EventHotKeyRef?
    private var settingsAltHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var localEventMonitor: Any?
    private var currentSettingsHotkey: String = HotkeySettings.defaultSettingsHotkey

    init() {
        installEventHandler()
        installLocalMonitor()
    }

    func apply(settings: HotkeySettings) {
        currentSettingsHotkey = settings.settingsHotkey
        unregister()
        guard settings.enabled else { return }

        register(
            primary: settings.hotkey,
            secondary: settings.secondaryHotkey,
            tertiary: settings.tertiaryHotkey,
            settings: settings.settingsHotkey
        )
    }

    private func register(primary: String, secondary: String, tertiary: String, settings: String) {
        let primaryCombo = try? HotkeyCombination(primary)
        let secondaryCombo = try? HotkeyCombination(secondary)

        // Track registered combinations to prevent duplicate registrations
        // (Carbon silently fails when the same key+modifier combo is registered twice).
        var registeredCombos: Set<HotkeyComboKey> = []

        // Register primary hotkey (ID 1)
        if let primaryCombo {
            let primaryID = EventHotKeyID(signature: OSType("NSSK".fourCharCode), id: 1)
            var primaryRef: EventHotKeyRef?
            let primaryStatus = RegisterEventHotKey(
                primaryCombo.keyCode,
                primaryCombo.carbonModifiers,
                primaryID,
                GetApplicationEventTarget(),
                0,
                &primaryRef
            )
            if primaryStatus == noErr, let primaryRef {
                self.primaryHotKeyRef = primaryRef
                registeredCombos.insert(
                    HotkeyComboKey(keyCode: primaryCombo.keyCode, modifiers: primaryCombo.carbonModifiers)
                )
                NativeBolabolLog.models.info(
                    "Registered primary hotkey \(primary, privacy: .public) keyCode=\(primaryCombo.keyCode) modifiers=\(primaryCombo.carbonModifiers)"
                )
            } else {
                NativeBolabolLog.models.warning(
                    "Failed to register primary hotkey \(primary, privacy: .public): \(primaryStatus)"
                )
            }
        } else {
            NativeBolabolLog.models.warning(
                "Failed to parse primary hotkey: \(primary, privacy: .public)"
            )
        }

        // Register secondary hotkey (ID 2) — full translation modal
        if let secondaryCombo {
            let secondaryID = EventHotKeyID(signature: OSType("NSSK".fourCharCode), id: 2)
            var secondaryRef: EventHotKeyRef?
            let secondaryStatus = RegisterEventHotKey(
                secondaryCombo.keyCode,
                secondaryCombo.carbonModifiers,
                secondaryID,
                GetApplicationEventTarget(),
                0,
                &secondaryRef
            )
            if secondaryStatus == noErr, let secondaryRef {
                self.secondaryHotKeyRef = secondaryRef
                registeredCombos.insert(
                    HotkeyComboKey(keyCode: secondaryCombo.keyCode, modifiers: secondaryCombo.carbonModifiers)
                )
                NativeBolabolLog.models.info(
                    "Registered translation hotkey \(secondary, privacy: .public) keyCode=\(secondaryCombo.keyCode) modifiers=\(secondaryCombo.carbonModifiers)"
                )
            } else {
                NativeBolabolLog.models.warning(
                    "Failed to register secondary hotkey \(secondary, privacy: .public): \(secondaryStatus)"
                )
            }
        } else {
            NativeBolabolLog.models.warning(
                "Failed to parse secondary hotkey: \(secondary, privacy: .public)"
            )
        }

        // Register tertiary hotkey (ID 3) — quick translation
        if let tertiaryCombo = try? HotkeyCombination(tertiary) {
            let tertiaryKey = HotkeyComboKey(keyCode: tertiaryCombo.keyCode, modifiers: tertiaryCombo.carbonModifiers)
            if registeredCombos.contains(tertiaryKey) {
                NativeBolabolLog.models.warning(
                    "Skipped tertiary hotkey \(tertiary, privacy: .public): duplicates an already-registered hotkey"
                )
            } else {
                let tertiaryID = EventHotKeyID(signature: OSType("NSSK".fourCharCode), id: 3)
                var tertiaryRef: EventHotKeyRef?
                let tertiaryStatus = RegisterEventHotKey(
                    tertiaryCombo.keyCode,
                    tertiaryCombo.carbonModifiers,
                    tertiaryID,
                    GetApplicationEventTarget(),
                    0,
                    &tertiaryRef
                )
                if tertiaryStatus == noErr, let tertiaryRef {
                    self.tertiaryHotKeyRef = tertiaryRef
                    registeredCombos.insert(tertiaryKey)
                    NativeBolabolLog.models.info(
                        "Registered quick translation hotkey \(tertiary, privacy: .public) keyCode=\(tertiaryCombo.keyCode) modifiers=\(tertiaryCombo.carbonModifiers)"
                    )
                } else {
                    NativeBolabolLog.models.warning(
                        "Failed to register tertiary hotkey \(tertiary, privacy: .public): \(tertiaryStatus)"
                    )
                }
            }
        } else {
            NativeBolabolLog.models.warning(
                "Failed to parse tertiary hotkey: \(tertiary, privacy: .public)"
            )
        }

        // Register settings hotkey (ID 4)
        if let settingsCombo = try? HotkeyCombination(settings) {
            let settingsKey = HotkeyComboKey(keyCode: settingsCombo.keyCode, modifiers: settingsCombo.carbonModifiers)
            if registeredCombos.contains(settingsKey) {
                NativeBolabolLog.models.warning(
                    "Skipped settings hotkey \(settings, privacy: .public): duplicates an already-registered hotkey"
                )
            } else {
                NativeBolabolLog.models.info(
                    "Registering settings hotkey: \(settings, privacy: .public), keyCode: \(settingsCombo.keyCode), modifiers: \(settingsCombo.carbonModifiers)"
                )
                let settingsID = EventHotKeyID(signature: OSType("NSSK".fourCharCode), id: 4)
                var settingsRef: EventHotKeyRef?
                let settingsStatus = RegisterEventHotKey(
                    settingsCombo.keyCode,
                    settingsCombo.carbonModifiers,
                    settingsID,
                    GetApplicationEventTarget(),
                    0,
                    &settingsRef
                )
                if settingsStatus == noErr, let settingsRef {
                    self.settingsHotKeyRef = settingsRef
                    registeredCombos.insert(settingsKey)
                    NativeBolabolLog.models.info("Settings hotkey registered successfully")
                } else {
                    NativeBolabolLog.models.warning(
                        "Failed to register settings hotkey \(settings, privacy: .public): \(settingsStatus)"
                    )
                }

                // If key is Tilde (kVK_ANSI_Grave), also register alternate modifier variant (without/with Shift)
                // so Option+` and Option+~ both trigger the Settings toggle when pressed.
                if settingsCombo.keyCode == UInt32(kVK_ANSI_Grave) {
                    let altModifiers = (settingsCombo.carbonModifiers & UInt32(shiftKey) != 0)
                        ? (settingsCombo.carbonModifiers & ~UInt32(shiftKey))
                        : (settingsCombo.carbonModifiers | UInt32(shiftKey))

                    let altKey = HotkeyComboKey(keyCode: settingsCombo.keyCode, modifiers: altModifiers)
                    if !registeredCombos.contains(altKey) {
                        var altRef: EventHotKeyRef?
                        let altID = EventHotKeyID(signature: OSType("NSSK".fourCharCode), id: 4)
                        let altStatus = RegisterEventHotKey(
                            settingsCombo.keyCode,
                            altModifiers,
                            altID,
                            GetApplicationEventTarget(),
                            0,
                            &altRef
                        )
                        if altStatus == noErr, let altRef {
                            self.settingsAltHotKeyRef = altRef
                            registeredCombos.insert(altKey)
                        }
                    }
                }
            }
        } else {
            NativeBolabolLog.models.warning(
                "Failed to parse settings hotkey: \(settings, privacy: .public)"
            )
        }
    }

    private func unregister() {
        if let primaryHotKeyRef {
            UnregisterEventHotKey(primaryHotKeyRef)
        }
        if let secondaryHotKeyRef {
            UnregisterEventHotKey(secondaryHotKeyRef)
        }
        if let tertiaryHotKeyRef {
            UnregisterEventHotKey(tertiaryHotKeyRef)
        }
        if let settingsHotKeyRef {
            UnregisterEventHotKey(settingsHotKeyRef)
        }
        if let settingsAltHotKeyRef {
            UnregisterEventHotKey(settingsAltHotKeyRef)
        }
        primaryHotKeyRef = nil
        secondaryHotKeyRef = nil
        tertiaryHotKeyRef = nil
        settingsHotKeyRef = nil
        settingsAltHotKeyRef = nil
    }

    private func installLocalMonitor() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.isSettingsHotkeyEvent(event) {
                Task { @MainActor in
                    NotificationCenter.default.post(name: .nativeBolabolSettingsHotkeyTriggered, object: nil)
                }
                return nil
            }
            return event
        }
    }

    private func isSettingsHotkeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Parse current settings hotkey configuration
        guard let combo = try? HotkeyCombination(currentSettingsHotkey) else {
            return false
        }

        // For Tilde/Grave key (keyCode 50), match Option modifier regardless of Shift across layout variants (US, Russian, ISO)
        if combo.keyCode == UInt32(kVK_ANSI_Grave) {
            let hasOption = flags.contains(.option)
            let hasCommand = flags.contains(.command)
            let hasControl = flags.contains(.control)

            guard hasOption && !hasCommand && !hasControl else { return false }

            // Check physical key codes for Tilde/Grave (50), ISO Section (10), Right Bracket (30), Left Bracket (33)
            if event.keyCode == UInt16(kVK_ANSI_Grave) ||
               event.keyCode == UInt16(kVK_ISO_Section) ||
               event.keyCode == UInt16(kVK_ANSI_RightBracket) ||
               event.keyCode == UInt16(kVK_ANSI_LeftBracket) {
                return true
            }

            // Check characters ignoring modifiers
            if let chars = event.charactersIgnoringModifiers?.lowercased(),
               chars.contains("~") || chars.contains("`") || chars.contains("]") || chars.contains("[") || chars.contains("§") || chars.contains("±") || chars.contains("ё") {
                return true
            }

            // Check generated characters
            if let chars = event.characters?.lowercased(),
               chars.contains("]") || chars.contains("[") || chars.contains("~") || chars.contains("`") {
                return true
            }

            return false
        }

        // For other keys, match exact key code and modifiers
        let hasOption = (combo.carbonModifiers & UInt32(optionKey)) != 0
        let hasCommand = (combo.carbonModifiers & UInt32(cmdKey)) != 0
        let hasControl = (combo.carbonModifiers & UInt32(controlKey)) != 0
        let hasShift = (combo.carbonModifiers & UInt32(shiftKey)) != 0

        guard event.keyCode == UInt16(combo.keyCode) else { return false }
        guard hasOption == flags.contains(.option) else { return false }
        guard hasCommand == flags.contains(.command) else { return false }
        guard hasControl == flags.contains(.control) else { return false }
        guard hasShift == flags.contains(.shift) else { return false }

        return true
    }

    private func installEventHandler() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                let eventKind = GetEventKind(eventRef)

                if hotKeyID.signature == OSType("NSSK".fourCharCode) {
                    if hotKeyID.id == 1 {
                        Task { @MainActor in
                            if eventKind == UInt32(kEventHotKeyPressed) {
                                NotificationCenter.default.post(name: .nativeBolabolHotkeyKeyDown, object: nil)
                                NotificationCenter.default.post(name: .nativeBolabolHotkeyTriggered, object: nil)
                            } else if eventKind == UInt32(kEventHotKeyReleased) {
                                NotificationCenter.default.post(name: .nativeBolabolHotkeyKeyUp, object: nil)
                            }
                        }
                    } else if hotKeyID.id == 2 && eventKind == UInt32(kEventHotKeyPressed) {
                        NativeBolabolLog.hotkey.info("Translation hotkey triggered (ID 2)")
                        Task { @MainActor in
                            NotificationCenter.default.post(name: .nativeBolabolTargetHotkeyTriggered, object: nil)
                        }
                    } else if hotKeyID.id == 3 && eventKind == UInt32(kEventHotKeyPressed) {
                        NativeBolabolLog.hotkey.info("Quick translation hotkey triggered (ID 3)")
                        Task { @MainActor in
                            NotificationCenter.default.post(name: .nativeBolabolQuickTranslationHotkeyTriggered, object: nil)
                        }
                    } else if hotKeyID.id == 4 && eventKind == UInt32(kEventHotKeyPressed) {
                        NativeBolabolLog.models.info("Settings hotkey triggered (ID 4)")
                        Task { @MainActor in
                            NotificationCenter.default.post(name: .nativeBolabolSettingsHotkeyTriggered, object: nil)
                        }
                    }
                }
                return noErr
            },
            2,
            &eventTypes,
            nil,
            &eventHandlerRef
        )

        if status != noErr {
            NativeBolabolLog.models.error("Failed to install global hotkey event handler: \(status)")
        }
    }
}

private struct HotkeyCombination {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    init(_ string: String) throws {
        let parts = string
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let keyPart = parts.last, !keyPart.isEmpty else {
            throw GlobalHotkeyError.invalidHotkey(string)
        }

        var modifiers: UInt32 = 0
        for part in parts.dropLast() {
            let normalized = part.uppercased()
            if normalized == "CMD" || normalized == "COMMAND" || normalized == "⌘" {
                modifiers |= UInt32(cmdKey)
            } else if normalized == "ALT" || normalized == "OPTION" || normalized == "⌥" {
                modifiers |= UInt32(optionKey)
            } else if normalized == "CTRL" || normalized == "CONTROL" || normalized == "⌃" {
                modifiers |= UInt32(controlKey)
            } else if normalized == "SHIFT" || normalized == "⇧" {
                modifiers |= UInt32(shiftKey)
            }
        }

        let key = keyPart.uppercased()

        guard let keyCode = Self.keyCodes[key] ?? Self.keyCodes[keyPart] else {
            throw GlobalHotkeyError.invalidHotkey(string)
        }

        self.keyCode = UInt32(keyCode)
        self.carbonModifiers = modifiers
    }

    private static let keyCodes: [String: Int] = [
        "A": kVK_ANSI_A,
        "B": kVK_ANSI_B,
        "C": kVK_ANSI_C,
        "D": kVK_ANSI_D,
        "E": kVK_ANSI_E,
        "F": kVK_ANSI_F,
        "G": kVK_ANSI_G,
        "H": kVK_ANSI_H,
        "I": kVK_ANSI_I,
        "J": kVK_ANSI_J,
        "K": kVK_ANSI_K,
        "L": kVK_ANSI_L,
        "M": kVK_ANSI_M,
        "N": kVK_ANSI_N,
        "O": kVK_ANSI_O,
        "P": kVK_ANSI_P,
        "Q": kVK_ANSI_Q,
        "R": kVK_ANSI_R,
        "S": kVK_ANSI_S,
        "T": kVK_ANSI_T,
        "U": kVK_ANSI_U,
        "V": kVK_ANSI_V,
        "W": kVK_ANSI_W,
        "X": kVK_ANSI_X,
        "Y": kVK_ANSI_Y,
        "Z": kVK_ANSI_Z,
        "0": kVK_ANSI_0,
        "1": kVK_ANSI_1,
        "2": kVK_ANSI_2,
        "3": kVK_ANSI_3,
        "4": kVK_ANSI_4,
        "5": kVK_ANSI_5,
        "6": kVK_ANSI_6,
        "7": kVK_ANSI_7,
        "8": kVK_ANSI_8,
        "9": kVK_ANSI_9,
        "F1": kVK_F1, "F2": kVK_F2, "F3": kVK_F3, "F4": kVK_F4,
        "F5": kVK_F5, "F6": kVK_F6, "F7": kVK_F7, "F8": kVK_F8,
        "F9": kVK_F9, "F10": kVK_F10, "F11": kVK_F11, "F12": kVK_F12,
        "SPACE": kVK_Space,
        "RETURN": kVK_Return,
        "ESCAPE": kVK_Escape,
        "TAB": kVK_Tab,
        "DELETE": kVK_Delete,
        "BACKSPACE": kVK_Delete,
        "~": kVK_ANSI_Grave,
        "`": kVK_ANSI_Grave,
        "TILDE": kVK_ANSI_Grave,
        "GRAVE": kVK_ANSI_Grave,
        "BACKTICK": kVK_ANSI_Grave,
        "Ё": kVK_ANSI_Grave, "ё": kVK_ANSI_Grave,
        "Й": kVK_ANSI_Q, "й": kVK_ANSI_Q,
        "Ц": kVK_ANSI_W, "ц": kVK_ANSI_W,
        "У": kVK_ANSI_E, "у": kVK_ANSI_E,
        "К": kVK_ANSI_R, "к": kVK_ANSI_R,
        "Е": kVK_ANSI_T, "е": kVK_ANSI_T,
        "Н": kVK_ANSI_Y, "н": kVK_ANSI_Y,
        "Г": kVK_ANSI_U, "г": kVK_ANSI_U,
        "Ш": kVK_ANSI_I, "ш": kVK_ANSI_I,
        "Щ": kVK_ANSI_O, "щ": kVK_ANSI_O,
        "З": kVK_ANSI_P, "з": kVK_ANSI_P,
        "Х": kVK_ANSI_LeftBracket, "х": kVK_ANSI_LeftBracket,
        "Ъ": kVK_ANSI_RightBracket, "ъ": kVK_ANSI_RightBracket,
        "Ф": kVK_ANSI_A, "ф": kVK_ANSI_A,
        "Ы": kVK_ANSI_S, "ы": kVK_ANSI_S,
        "В": kVK_ANSI_D, "в": kVK_ANSI_D,
        "А": kVK_ANSI_F, "а": kVK_ANSI_F,
        "П": kVK_ANSI_G, "п": kVK_ANSI_G,
        "Р": kVK_ANSI_H, "р": kVK_ANSI_H,
        "О": kVK_ANSI_J, "о": kVK_ANSI_J,
        "Л": kVK_ANSI_K, "л": kVK_ANSI_K,
        "Д": kVK_ANSI_L, "д": kVK_ANSI_L,
        "Ж": kVK_ANSI_Semicolon, "ж": kVK_ANSI_Semicolon,
        "Э": kVK_ANSI_Quote, "э": kVK_ANSI_Quote,
        "Я": kVK_ANSI_Z, "я": kVK_ANSI_Z,
        "Ч": kVK_ANSI_X, "ч": kVK_ANSI_X,
        "С": kVK_ANSI_C, "с": kVK_ANSI_C,
        "М": kVK_ANSI_V, "м": kVK_ANSI_V,
        "И": kVK_ANSI_B, "и": kVK_ANSI_B,
        "Т": kVK_ANSI_N, "т": kVK_ANSI_N,
        "Ь": kVK_ANSI_M, "ь": kVK_ANSI_M,
        "Б": kVK_ANSI_Comma, "б": kVK_ANSI_Comma,
        "Ю": kVK_ANSI_Period, "ю": kVK_ANSI_Period
    ]
}

/// Lightweight hashable key for tracking which Carbon hotkey combos are already registered.
private struct HotkeyComboKey: Hashable {
    let keyCode: UInt32
    let modifiers: UInt32
}

private enum GlobalHotkeyError: LocalizedError {
    case invalidHotkey(String)
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidHotkey(let hotkey):
            "Invalid hotkey: \(hotkey). Use a modifier plus a key, for example Option+S."
        case .registrationFailed(let status):
            "Could not register hotkey. macOS returned \(status)."
        }
    }
}

private extension String {
    var fourCharCode: FourCharCode {
        utf8.reduce(0) { ($0 << 8) + FourCharCode($1) }
    }
}
