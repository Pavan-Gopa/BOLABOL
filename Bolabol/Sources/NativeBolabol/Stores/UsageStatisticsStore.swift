import Combine
import Foundation
import NativeBolabolCore

@MainActor
final class UsageStatisticsStore: ObservableObject {
    private static let settingsDefaultsKey = "usage.statistics"

    private let userDefaults: UserDefaults

    @Published private(set) var settings: UsageStatisticsSettings {
        didSet {
            saveSettings()
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.settings = Self.loadSettings(from: userDefaults)
    }

    static func live() -> UsageStatisticsStore {
        UsageStatisticsStore()
    }

    var selectedModelID: String? {
        settings.modelNames.keys.sorted().first
    }

    func modelIDs() -> [String] {
        settings.modelNames.keys.sorted {
            settings.modelNames[$0, default: $0] < settings.modelNames[$1, default: $1]
        }
    }

    func modelName(for modelID: String) -> String {
        settings.modelNames[modelID] ?? modelID
    }

    func total(for modelID: String?) -> UsageTokenCount {
        guard let modelID else { return UsageTokenCount() }
        return settings.totals[modelID] ?? UsageTokenCount()
    }

    func record(modelID: String, modelName: String, diagnostics: EngineDiagnostics) {
        guard let promptTokens = diagnostics.promptTokens,
              let completionTokens = diagnostics.completionTokens
        else {
            return
        }

        settings.record(
            modelID: modelID,
            modelName: modelName,
            promptTokens: promptTokens,
            completionTokens: completionTokens
        )
    }

    func reset(modelID: String?) {
        guard let modelID else { return }
        settings.reset(modelID: modelID)
    }

    func reset(modelIDs: [String]) {
        guard !modelIDs.isEmpty else { return }
        settings.reset(modelIDs: modelIDs)
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: Self.settingsDefaultsKey)
    }

    private static func loadSettings(from userDefaults: UserDefaults) -> UsageStatisticsSettings {
        guard let data = userDefaults.data(forKey: settingsDefaultsKey),
              let settings = try? JSONDecoder().decode(UsageStatisticsSettings.self, from: data)
        else {
            return UsageStatisticsSettings()
        }
        return settings
    }
}
