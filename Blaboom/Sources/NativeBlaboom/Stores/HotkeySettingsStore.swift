import Combine
import Foundation
import NativeBlaboomCore

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
