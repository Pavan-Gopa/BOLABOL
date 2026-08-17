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
enum PrimaryHotkeySource: Equatable, Sendable {
    case none
    case carbonCombination
    case rightOption
    case rightCommand
}

enum PrimaryHotkeyDelivery: Equatable, Sendable {
    case toggle
    case hold
}

enum PrimaryHotkeyPhase: Equatable, Sendable {
    case idle
    case suppressedModifierDown
    case acceptedToggle
    case acceptedHold
}

struct PrimaryHotkeyConfiguration: Equatable, Sendable {
    var generation: UInt64
    var enabled: Bool
    var source: PrimaryHotkeySource
    var delivery: PrimaryHotkeyDelivery

    init(
        generation: UInt64 = 0,
        enabled: Bool = false,
        source: PrimaryHotkeySource = .none,
        delivery: PrimaryHotkeyDelivery = .toggle
    ) {
        self.generation = generation
        self.enabled = enabled
        self.source = source
        self.delivery = delivery
    }

    func isReconfigurationRelevant(comparedTo other: PrimaryHotkeyConfiguration) -> Bool {
        enabled != other.enabled || source != other.source || delivery != other.delivery
    }
}

enum PrimaryHotkeyInput: Equatable, Sendable {
    case configure(PrimaryHotkeyConfiguration)
    case flagsChanged(keyCode: UInt16, rawFlags: UInt, generation: UInt64)
    case carbonPressed(generation: UInt64)
    case carbonReleased(generation: UInt64)
}

enum PrimaryHotkeyOutput: Equatable, Sendable {
    case triggered
    case keyDown
    case keyUp
}

struct PrimaryHotkeyStateMachine: Sendable {
    private(set) var configuration: PrimaryHotkeyConfiguration
    private(set) var phase: PrimaryHotkeyPhase

    init(
        configuration: PrimaryHotkeyConfiguration = PrimaryHotkeyConfiguration(),
        phase: PrimaryHotkeyPhase = .idle
    ) {
        self.configuration = configuration
        self.phase = phase
    }

    mutating func handle(_ input: PrimaryHotkeyInput) -> PrimaryHotkeyOutput? {
        switch input {
        case .configure(let newConfig):
            if configuration.isReconfigurationRelevant(comparedTo: newConfig) {
                let previousPhase = phase
                configuration = newConfig
                phase = .idle
                if previousPhase == .acceptedHold {
                    return .keyUp
                }
                return nil
            } else {
                configuration = newConfig
                return nil
            }

        case .carbonPressed(let generation):
            guard configuration.enabled, configuration.source == .carbonCombination else { return nil }
            guard generation == configuration.generation else { return nil }

            switch configuration.delivery {
            case .toggle:
                if phase == .idle {
                    phase = .acceptedToggle
                    return .triggered
                }
                return nil
            case .hold:
                if phase == .idle {
                    phase = .acceptedHold
                    return .keyDown
                }
                return nil
            }

        case .carbonReleased(let generation):
            guard configuration.enabled, configuration.source == .carbonCombination else { return nil }
            guard generation == configuration.generation else { return nil }

            switch phase {
            case .acceptedHold:
                phase = .idle
                return .keyUp
            case .acceptedToggle:
                phase = .idle
                return nil
            case .idle, .suppressedModifierDown:
                return nil
            }

        case .flagsChanged(let keyCode, let rawFlags, let generation):
            guard configuration.enabled else { return nil }
            guard generation == configuration.generation else { return nil }

            let targetKeyCode: UInt16
            let targetMask: UInt
            let targetIndependentMask: UInt

            switch configuration.source {
            case .rightOption:
                targetKeyCode = UInt16(kVK_RightOption)
                targetMask = UInt(0x0040)
                targetIndependentMask = UInt(0x00080000)
            case .rightCommand:
                targetKeyCode = UInt16(kVK_RightCommand)
                targetMask = UInt(0x0010)
                targetIndependentMask = UInt(0x00100000)
            case .carbonCombination, .none:
                return nil
            }

            // Physical modifier bitmask (excluding CapsLock):
            // Left Ctrl: 0x0001, Right Ctrl: 0x2000
            // Left Shift: 0x0002, Right Shift: 0x0004
            // Left Cmd: 0x0008, Right Cmd: 0x0010
            // Left Alt: 0x0020, Right Alt: 0x0040
            let allPhysicalModifiersMask: UInt = 0x207F
            let heldPhysical = rawFlags & allPhysicalModifiersMask

            // Device-independent modifier bitmask (excluding CapsLock 0x00010000 and NumericPad/Help):
            // Shift: 0x00020000, Control: 0x00040000, Option: 0x00080000, Command: 0x00100000, Function: 0x00800000
            let allIndependentMask: UInt = 0x009E0000
            let heldIndependent = rawFlags & allIndependentMask

            let isTargetPhysicalDown = (rawFlags & targetMask) != 0
            let isTargetIndependentDown = (rawFlags & targetIndependentMask) != 0
            let isTargetDown = isTargetPhysicalDown && isTargetIndependentDown

            let isTargetSolePhysicalHeld = (heldPhysical == targetMask)
            let isTargetSoleIndependentHeld = (heldIndependent == targetIndependentMask)
            let isTargetSoleModifierHeld = isTargetSolePhysicalHeld && isTargetSoleIndependentHeld

            let areAllModifiersReleased = (heldPhysical == 0 && heldIndependent == 0)

            switch phase {
            case .idle:
                if keyCode == targetKeyCode && isTargetDown && isTargetSoleModifierHeld {
                    switch configuration.delivery {
                    case .toggle:
                        phase = .acceptedToggle
                        return .triggered
                    case .hold:
                        phase = .acceptedHold
                        return .keyDown
                    }
                } else if heldPhysical != 0 || heldIndependent != 0 {
                    phase = .suppressedModifierDown
                    return nil
                } else {
                    return nil
                }

            case .suppressedModifierDown:
                if areAllModifiersReleased {
                    phase = .idle
                }
                return nil

            case .acceptedToggle:
                if !isTargetPhysicalDown {
                    if areAllModifiersReleased {
                        phase = .idle
                    } else {
                        phase = .suppressedModifierDown
                    }
                    return nil
                } else if !isTargetSoleModifierHeld {
                    phase = .suppressedModifierDown
                    return nil
                } else {
                    return nil
                }

            case .acceptedHold:
                if !isTargetPhysicalDown {
                    if areAllModifiersReleased {
                        phase = .idle
                    } else {
                        phase = .suppressedModifierDown
                    }
                    return .keyUp
                } else {
                    return nil
                }
            }
        }
    }
}

@MainActor
final class GlobalHotkeyManager: HotkeyManaging {
    private enum CarbonAction: Equatable, Sendable {
        case primary
        case secondary
        case tertiary
        case settings
    }

    private var activeHotKeyRefs: [EventHotKeyRef] = []
    private var currentCarbonActionMap: [UInt32: CarbonAction] = [:]
    private var nextCarbonID: UInt32 = 100
    private var isSuspended: Bool = false
    private var isTornDown: Bool = false
    private var latestSettings: HotkeySettings?

    private var eventHandlerRef: EventHandlerRef?
    private var localEventMonitor: Any?
    private var primaryFlagsMonitorLocal: Any?
    private var primaryFlagsMonitorGlobal: Any?
    private var primaryStateMachine = PrimaryHotkeyStateMachine()
    private var currentGeneration: UInt64 = 0
    private var currentSettingsHotkey: String = HotkeySettings.defaultSettingsHotkey
    init() {
        installEventHandler()
        installLocalMonitor()
    }

    func apply(settings: HotkeySettings) {
        latestSettings = settings
        guard !isSuspended else { return }
        applyInternal(settings: settings)
    }

    func suspendForShortcutCapture() {
        guard !isSuspended else { return }
        isSuspended = true

        currentGeneration &+= 1
        currentCarbonActionMap.removeAll()
        unregister()
        removeFlagsMonitors()

        let disabledConfig = PrimaryHotkeyConfiguration(
            generation: currentGeneration,
            enabled: false,
            source: .none,
            delivery: .toggle
        )
        if let output = primaryStateMachine.handle(.configure(disabledConfig)) {
            dispatchOutput(output)
        }
    }

    func resumeAfterShortcutCapture() {
        guard isSuspended else { return }

        if let settings = latestSettings {
            applyInternal(settings: settings)
        }
        isSuspended = false
    }

    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        isSuspended = true

        currentGeneration &+= 1
        currentCarbonActionMap.removeAll()
        unregister()
        removeFlagsMonitors()
        removeLocalMonitor()
        removeEventHandler()

        let disabledConfig = PrimaryHotkeyConfiguration(
            generation: currentGeneration,
            enabled: false,
            source: .none,
            delivery: .toggle
        )
        if let output = primaryStateMachine.handle(.configure(disabledConfig)) {
            dispatchOutput(output)
        }
    }
    deinit {
        MainActor.assumeIsolated {
            teardown()
        }
    }

    private func applyInternal(settings: HotkeySettings) {
        currentSettingsHotkey = settings.settingsHotkey

        let primaryKind = HotkeySettings.classifyPrimaryHotkey(settings.hotkey)
        let primarySource: PrimaryHotkeySource
        if !settings.enabled {
            primarySource = .none
        } else {
            switch primaryKind {
            case .rightOption:
                primarySource = .rightOption
            case .rightCommand:
                primarySource = .rightCommand
            case .combination:
                primarySource = .carbonCombination
            }
        }

        let primaryDelivery: PrimaryHotkeyDelivery = settings.holdToRecord ? .hold : .toggle
        let newConfigCandidate = PrimaryHotkeyConfiguration(
            generation: currentGeneration,
            enabled: settings.enabled,
            source: primarySource,
            delivery: primaryDelivery
        )

        let isRelevant = primaryStateMachine.configuration.isReconfigurationRelevant(comparedTo: newConfigCandidate)
        if isRelevant {
            currentGeneration &+= 1
            var updatedConfig = newConfigCandidate
            updatedConfig.generation = currentGeneration
            if let output = primaryStateMachine.handle(.configure(updatedConfig)) {
                dispatchOutput(output)
            }
        } else {
            _ = primaryStateMachine.handle(.configure(newConfigCandidate))
        }

        currentCarbonActionMap.removeAll()
        unregister()
        guard settings.enabled else {
            removeFlagsMonitors()
            return
        }

        register(
            primary: settings.hotkey,
            secondary: settings.secondaryHotkey,
            tertiary: settings.tertiaryHotkey,
            settings: settings.settingsHotkey
        )

        updateFlagsMonitors(for: primarySource)
    }

    private func updateFlagsMonitors(for source: PrimaryHotkeySource) {
        switch source {
        case .rightOption, .rightCommand:
            removeFlagsMonitors()
            let capturedGeneration = self.currentGeneration

            primaryFlagsMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self else { return event }
                let keyCode = event.keyCode
                let rawFlags = event.modifierFlags.rawValue
                self.handleFlagsChanged(keyCode: keyCode, rawFlags: rawFlags, generation: capturedGeneration)
                return event
            }

            primaryFlagsMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self else { return }
                let keyCode = event.keyCode
                let rawFlags = event.modifierFlags.rawValue
                Task { @MainActor [weak self] in
                    self?.handleFlagsChanged(keyCode: keyCode, rawFlags: rawFlags, generation: capturedGeneration)
                }
            }

        case .carbonCombination, .none:
            removeFlagsMonitors()
        }
    }

    private func removeFlagsMonitors() {
        if let primaryFlagsMonitorLocal {
            NSEvent.removeMonitor(primaryFlagsMonitorLocal)
            self.primaryFlagsMonitorLocal = nil
        }
        if let primaryFlagsMonitorGlobal {
            NSEvent.removeMonitor(primaryFlagsMonitorGlobal)
            self.primaryFlagsMonitorGlobal = nil
        }
    }

    private func handleFlagsChanged(keyCode: UInt16, rawFlags: UInt, generation: UInt64) {
        guard !isSuspended else { return }
        guard generation == currentGeneration else { return }
        guard let output = primaryStateMachine.handle(.flagsChanged(keyCode: keyCode, rawFlags: rawFlags, generation: generation)) else {
            return
        }
        dispatchOutput(output)
    }

    private func handleCarbonPrimary(isPress: Bool, generation: UInt64) {
        guard !isSuspended else { return }
        guard generation == currentGeneration else { return }
        let input: PrimaryHotkeyInput = isPress
            ? .carbonPressed(generation: generation)
            : .carbonReleased(generation: generation)
        guard let output = primaryStateMachine.handle(input) else { return }
        dispatchOutput(output)
    }

    private func dispatchOutput(_ output: PrimaryHotkeyOutput) {
        switch output {
        case .triggered:
            NotificationCenter.default.post(name: .nativeBolabolHotkeyTriggered, object: nil)
        case .keyDown:
            NotificationCenter.default.post(name: .nativeBolabolHotkeyKeyDown, object: nil)
        case .keyUp:
            NotificationCenter.default.post(name: .nativeBolabolHotkeyKeyUp, object: nil)
        }
    }

    private func register(primary: String, secondary: String, tertiary: String, settings: String) {
        var registeredCombos: Set<HotkeyComboKey> = []

        if !HotkeySettings.isRightModifierOnlyPrimaryHotkey(primary) {
            if let primaryCombo = try? HotkeyCombination(primary) {
                registerCombination(primaryCombo, action: .primary, name: "primary (\(primary))", registeredCombos: &registeredCombos)
            } else {
                NativeBolabolLog.models.warning("Failed to parse primary hotkey: \(primary, privacy: .public)")
            }
        }

        if let secondaryCombo = try? HotkeyCombination(secondary) {
            registerCombination(secondaryCombo, action: .secondary, name: "translation (\(secondary))", registeredCombos: &registeredCombos)
        } else {
            NativeBolabolLog.models.warning("Failed to parse secondary hotkey: \(secondary, privacy: .public)")
        }

        if let tertiaryCombo = try? HotkeyCombination(tertiary) {
            registerCombination(tertiaryCombo, action: .tertiary, name: "quick translation (\(tertiary))", registeredCombos: &registeredCombos)
        } else {
            NativeBolabolLog.models.warning("Failed to parse tertiary hotkey: \(tertiary, privacy: .public)")
        }

        if let settingsCombo = try? HotkeyCombination(settings) {
            registerCombination(settingsCombo, action: .settings, name: "settings (\(settings))", registeredCombos: &registeredCombos)

            // If key is Tilde (kVK_ANSI_Grave), also register alternate modifier variant (without/with Shift)
            // so Option+` and Option+~ both trigger the Settings toggle when pressed.
            if settingsCombo.keyCode == UInt32(kVK_ANSI_Grave) {
                let altModifiers = (settingsCombo.carbonModifiers & UInt32(shiftKey) != 0)
                    ? (settingsCombo.carbonModifiers & ~UInt32(shiftKey))
                    : (settingsCombo.carbonModifiers | UInt32(shiftKey))
                let altCombo = HotkeyCombination(keyCode: settingsCombo.keyCode, carbonModifiers: altModifiers)
                registerCombination(altCombo, action: .settings, name: "settings alt", registeredCombos: &registeredCombos)
            }
        } else {
            NativeBolabolLog.models.warning("Failed to parse settings hotkey: \(settings, privacy: .public)")
        }
    }

    private func registerCombination(
        _ combo: HotkeyCombination,
        action: CarbonAction,
        name: String,
        registeredCombos: inout Set<HotkeyComboKey>
    ) {
        let comboKey = HotkeyComboKey(keyCode: combo.keyCode, modifiers: combo.carbonModifiers)
        guard !registeredCombos.contains(comboKey) else {
            NativeBolabolLog.models.warning("Skipped hotkey \(name, privacy: .public): duplicates an already-registered hotkey")
            return
        }

        let hotKeyIDNumber = nextCarbonID
        nextCarbonID &+= 1
        currentCarbonActionMap[hotKeyIDNumber] = action

        let hotKeyID = EventHotKeyID(signature: OSType("NSSK".fourCharCode), id: hotKeyIDNumber)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr, let hotKeyRef {
            activeHotKeyRefs.append(hotKeyRef)
            registeredCombos.insert(comboKey)
            NativeBolabolLog.models.info("Registered \(name, privacy: .public) keyCode=\(combo.keyCode) modifiers=\(combo.carbonModifiers) ID=\(hotKeyIDNumber)")
        } else {
            currentCarbonActionMap.removeValue(forKey: hotKeyIDNumber)
            NativeBolabolLog.models.warning("Failed to register \(name, privacy: .public): \(status)")
        }
    }

    private func unregister() {
        for ref in activeHotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        activeHotKeyRefs.removeAll()
    }

    private func installLocalMonitor() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !self.isSuspended else { return event }
            if self.isSettingsHotkeyEvent(event) {
                let capturedGeneration = self.currentGeneration
                Task { @MainActor [weak self] in
                    guard let self, !self.isSuspended, self.currentGeneration == capturedGeneration else { return }
                    NotificationCenter.default.post(name: .nativeBolabolSettingsHotkeyTriggered, object: nil)
                }
                return nil
            }
            return event
        }
    }

    private func removeLocalMonitor() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func removeEventHandler() {
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func isSettingsHotkeyEvent(_ event: NSEvent) -> Bool {
        guard !isSuspended else { return false }

        // Parse current settings hotkey configuration
        guard let combo = try? HotkeyCombination(currentSettingsHotkey) else {
            return false
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

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
            { _, eventRef, userData -> OSStatus in
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

                if hotKeyID.signature == OSType("NSSK".fourCharCode), let userData {
                    let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                    let isPress = (eventKind == UInt32(kEventHotKeyPressed))
                    let capturedGeneration = manager.currentGeneration
                    Task { @MainActor [weak manager] in
                        guard let manager, !manager.isSuspended, manager.currentGeneration == capturedGeneration else { return }
                        guard let action = manager.currentCarbonActionMap[hotKeyID.id] else { return }
                        switch action {
                        case .primary:
                            manager.handleCarbonPrimary(isPress: isPress, generation: capturedGeneration)
                        case .secondary:
                            if isPress {
                                NativeBolabolLog.hotkey.info("Translation hotkey triggered")
                                NotificationCenter.default.post(name: .nativeBolabolTargetHotkeyTriggered, object: nil)
                            }
                        case .tertiary:
                            if isPress {
                                NativeBolabolLog.hotkey.info("Quick translation hotkey triggered")
                                NotificationCenter.default.post(name: .nativeBolabolQuickTranslationHotkeyTriggered, object: nil)
                            }
                        case .settings:
                            if isPress {
                                NativeBolabolLog.models.info("Settings hotkey triggered")
                                NotificationCenter.default.post(name: .nativeBolabolSettingsHotkeyTriggered, object: nil)
                            }
                        }
                    }
                }
                return noErr
            },
            2,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
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

        guard let keyCode = HotkeyKeyCatalog.keyCode(forToken: keyPart) else {
            throw GlobalHotkeyError.invalidHotkey(string)
        }

        self.keyCode = UInt32(keyCode)
        self.carbonModifiers = modifiers
    }

    // Supported key codes and aliases are provided centrally by HotkeyKeyCatalog.
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
