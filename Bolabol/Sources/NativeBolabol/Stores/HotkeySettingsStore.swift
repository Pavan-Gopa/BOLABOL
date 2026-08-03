import Combine
import Foundation
import NativeBolabolCore

@MainActor
final class HotkeySettingsStore: ObservableObject {
    private static let settingsDefaultsKey = "hotkey.settings"

    private let userDefaults: UserDefaults
    private let hotkeyManager: GlobalHotkeyManager

    @Published var settings: HotkeySettings {
        didSet {
            saveSettings()
            hotkeyManager.apply(settings: settings)
        }
    }

    init(
        userDefaults: UserDefaults = .standard,
        hotkeyManager: GlobalHotkeyManager = GlobalHotkeyManager()
    ) {
        self.userDefaults = userDefaults
        self.hotkeyManager = hotkeyManager
        self.settings = Self.loadSettings(from: userDefaults)
        hotkeyManager.apply(settings: settings)
    }

    static func live() -> HotkeySettingsStore {
        HotkeySettingsStore()
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
