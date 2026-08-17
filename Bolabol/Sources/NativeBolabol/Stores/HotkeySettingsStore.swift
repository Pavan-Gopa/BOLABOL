import Combine
import Foundation
import NativeBolabolCore

/// Manager protocol seam for hotkey registration lifecycle and suspension.
@MainActor
protocol HotkeyManaging: AnyObject {
    func apply(settings: HotkeySettings)
    func suspendForShortcutCapture()
    func resumeAfterShortcutCapture()
    func teardown()
}

@MainActor
final class HotkeySettingsStore: ObservableObject {
    private static let settingsDefaultsKey = "hotkey.settings"

    private let userDefaults: UserDefaults
    private let hotkeyManager: any HotkeyManaging
    private var currentCaptureOwner: UUID?

    @Published var settings: HotkeySettings {
        didSet {
            saveSettings()
            hotkeyManager.apply(settings: settings)
        }
    }

    init(
        userDefaults: UserDefaults = .standard,
        hotkeyManager: any HotkeyManaging = GlobalHotkeyManager()
    ) {
        self.userDefaults = userDefaults
        self.hotkeyManager = hotkeyManager
        self.settings = Self.loadSettings(from: userDefaults)
        hotkeyManager.apply(settings: settings)
    }

    static func live() -> HotkeySettingsStore {
        HotkeySettingsStore()
    }

    /// Synchronously suspends app hotkey ingress before first-responder activation for the given owner.
    /// Returns true only when capture is successfully acquired or already owned by the same owner.
    /// Rejects any different/foreign capture owner while active.
    func beginShortcutCapture(owner: UUID) -> Bool {
        if let current = currentCaptureOwner {
            return current == owner
        }
        currentCaptureOwner = owner
        hotkeyManager.suspendForShortcutCapture()
        return true
    }

    /// Resumes app hotkey registrations once after capture finishes or cancels for the current owner.
    /// Foreign or stale owners cannot resume or overwrite.
    func endShortcutCapture(owner: UUID) {
        guard currentCaptureOwner == owner else { return }
        currentCaptureOwner = nil
        hotkeyManager.resumeAfterShortcutCapture()
    }

    /// Canonical speech-language pair (plan §3.3), read from the shared
    /// GeneralSettings blob. Hotkey sessions / HUD (B6+) read this to render
    /// the primary ↔ additional speech-language cycle.
    var speechLanguages: UserSpeechLanguages {
        guard let data = userDefaults.data(forKey: GeneralSettingsStore.settingsDefaultsKey),
              let generalSettings = try? JSONDecoder().decode(GeneralSettings.self, from: data)
        else {
            return UserSpeechLanguages()
        }
        return generalSettings.speechLanguages
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: Self.settingsDefaultsKey)
    }

    private static func loadSettings(from userDefaults: UserDefaults) -> HotkeySettings {
        guard let data = userDefaults.data(forKey: settingsDefaultsKey),
              let settings = try? JSONDecoder().decode(HotkeySettings.self, from: data)
        else {
            return HotkeySettings()
        }

        return settings
    }
}
