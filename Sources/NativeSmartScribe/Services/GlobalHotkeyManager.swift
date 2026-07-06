import Carbon
import Foundation
import NativeSmartScribeCore

extension Notification.Name {
    static let nativeSmartScribeHotkeyTriggered = Notification.Name("nativeSmartScribeHotkeyTriggered")
    static let nativeSmartScribeTargetHotkeyTriggered = Notification.Name("nativeSmartScribeTargetHotkeyTriggered")
}

@MainActor
final class GlobalHotkeyManager {
    private var primaryHotKeyRef: EventHotKeyRef?
    private var secondaryHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var currentHotkey: HotkeyCombination?

    init() {
        installEventHandler()
    }

    func apply(settings: HotkeySettings) {
        unregister()
        guard settings.enabled else { return }

        do {
            try register(primary: settings.hotkey, secondary: settings.secondaryHotkey)
        } catch {
            NativeSmartScribeLog.models.error(
                "Failed to register global hotkeys: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func register(primary: String, secondary: String) throws {
        let primaryCombo = try HotkeyCombination(primary)
        let secondaryCombo = try HotkeyCombination(secondary)

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

        // Register secondary hotkey (ID 2)
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
        } else {
            NativeSmartScribeLog.models.warning(
                "Failed to register secondary hotkey \(secondary, privacy: .public): \(secondaryStatus)"
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
        primaryHotKeyRef = nil
        secondaryHotKeyRef = nil
        currentHotkey = nil
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

        guard modifiers != 0, let keyCode = Self.keyCodes[key.uppercased()] else {
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
        "SPACE": kVK_Space,
        "RETURN": kVK_Return,
        "ESCAPE": kVK_Escape
    ]
}

private enum GlobalHotkeyError: LocalizedError {
    case invalidHotkey(String)
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidHotkey(let hotkey):
            "Invalid hotkey: \(hotkey). Use a modifier plus a key, for example Alt+S."
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
