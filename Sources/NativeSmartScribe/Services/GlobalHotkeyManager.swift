import AppKit
import Carbon
import Foundation
import NativeSmartScribeCore

extension Notification.Name {
    static let nativeSmartScribeHotkeyTriggered = Notification.Name("nativeSmartScribeHotkeyTriggered")
    static let nativeSmartScribeTargetHotkeyTriggered = Notification.Name("nativeSmartScribeTargetHotkeyTriggered")
    static let nativeSmartScribeQuickTranslationHotkeyTriggered = Notification.Name("nativeSmartScribeQuickTranslationHotkeyTriggered")
    static let nativeSmartScribeSettingsHotkeyTriggered = Notification.Name("nativeSmartScribeSettingsHotkeyTriggered")
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

        do {
            try register(
                primary: settings.hotkey,
                secondary: settings.secondaryHotkey,
                tertiary: settings.tertiaryHotkey,
                settings: settings.settingsHotkey
            )
        } catch {
            NativeSmartScribeLog.models.error(
                "Failed to register global hotkeys: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func register(primary: String, secondary: String, tertiary: String, settings: String) throws {
        let primaryCombo = try HotkeyCombination(primary)
        let secondaryCombo = try HotkeyCombination(secondary)

        // Track registered combinations to prevent duplicate registrations
        // (Carbon silently fails when the same key+modifier combo is registered twice).
        var registeredCombos: Set<HotkeyComboKey> = []

        // Register primary hotkey (ID 1)
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
        guard primaryStatus == noErr, let primaryRef else {
            throw GlobalHotkeyError.registrationFailed(primaryStatus)
        }
        self.primaryHotKeyRef = primaryRef
        registeredCombos.insert(HotkeyComboKey(keyCode: primaryCombo.keyCode, modifiers: primaryCombo.carbonModifiers))

        // Register secondary hotkey (ID 2) — full translation modal
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
            registeredCombos.insert(HotkeyComboKey(keyCode: secondaryCombo.keyCode, modifiers: secondaryCombo.carbonModifiers))
        } else {
            NativeSmartScribeLog.models.warning(
                "Failed to register secondary hotkey \(secondary, privacy: .public): \(secondaryStatus)"
            )
        }

        // Register tertiary hotkey (ID 3) — quick translation
        if let tertiaryCombo = try? HotkeyCombination(tertiary) {
            let tertiaryKey = HotkeyComboKey(keyCode: tertiaryCombo.keyCode, modifiers: tertiaryCombo.carbonModifiers)
            if registeredCombos.contains(tertiaryKey) {
                NativeSmartScribeLog.models.warning(
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
                } else {
                    NativeSmartScribeLog.models.warning(
                        "Failed to register tertiary hotkey \(tertiary, privacy: .public): \(tertiaryStatus)"
                    )
                }
            }
        }

        // Register settings hotkey (ID 4)
        if let settingsCombo = try? HotkeyCombination(settings) {
            let settingsKey = HotkeyComboKey(keyCode: settingsCombo.keyCode, modifiers: settingsCombo.carbonModifiers)
            if registeredCombos.contains(settingsKey) {
                NativeSmartScribeLog.models.warning(
                    "Skipped settings hotkey \(settings, privacy: .public): duplicates an already-registered hotkey"
                )
            } else {
                NativeSmartScribeLog.models.info(
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
                    NativeSmartScribeLog.models.info("Settings hotkey registered successfully")
                } else {
                    NativeSmartScribeLog.models.warning(
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
            NativeSmartScribeLog.models.warning(
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
                    NotificationCenter.default.post(name: .nativeSmartScribeSettingsHotkeyTriggered, object: nil)
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
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
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

                if hotKeyID.signature == OSType("NSSK".fourCharCode) {
                    if hotKeyID.id == 1 {
                        Task { @MainActor in
                            NotificationCenter.default.post(name: .nativeSmartScribeHotkeyTriggered, object: nil)
                        }
                    } else if hotKeyID.id == 2 {
                        Task { @MainActor in
                            NotificationCenter.default.post(name: .nativeSmartScribeTargetHotkeyTriggered, object: nil)
                        }
                    } else if hotKeyID.id == 3 {
                        Task { @MainActor in
                            NotificationCenter.default.post(name: .nativeSmartScribeQuickTranslationHotkeyTriggered, object: nil)
                        }
                    } else if hotKeyID.id == 4 {
                        NativeSmartScribeLog.models.info("Settings hotkey triggered (ID 4)")
                        Task { @MainActor in
                            NotificationCenter.default.post(name: .nativeSmartScribeSettingsHotkeyTriggered, object: nil)
                        }
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        if status != noErr {
            NativeSmartScribeLog.models.error("Failed to install global hotkey event handler: \(status)")
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
            .filter { !$0.isEmpty }
        guard let key = parts.last else {
            throw GlobalHotkeyError.invalidHotkey(string)
        }

        let modifiers = parts.dropLast().reduce(UInt32(0)) { partial, modifier in
            switch modifier.lowercased() {
            case "command", "cmd", "⌘":
                return partial | UInt32(cmdKey)
            case "control", "ctrl", "⌃":
                return partial | UInt32(controlKey)
            case "alt", "option", "opt", "⌥":
                return partial | UInt32(optionKey)
            case "shift", "⇧":
                return partial | UInt32(shiftKey)
            default:
                return partial
            }
        }

        // Characters that require Shift on standard keyboard layouts.
        // When the user types "~" they physically press Shift+backtick,
        // so the Carbon hotkey must include shiftKey to match.
        var effectiveModifiers = modifiers
        if key == "~" || key == "TILDE" {
            effectiveModifiers |= UInt32(shiftKey)
        }

        guard effectiveModifiers != 0, let keyCode = Self.keyCodes[key.uppercased()] else {
            throw GlobalHotkeyError.invalidHotkey(string)
        }

        self.keyCode = UInt32(keyCode)
        self.carbonModifiers = effectiveModifiers
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
        "SPACE": kVK_Space,
        "RETURN": kVK_Return,
        "ESCAPE": kVK_Escape,
        "~": kVK_ANSI_Grave,
        "`": kVK_ANSI_Grave,
        "TILDE": kVK_ANSI_Grave,
        "GRAVE": kVK_ANSI_Grave,
        "BACKTICK": kVK_ANSI_Grave
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
