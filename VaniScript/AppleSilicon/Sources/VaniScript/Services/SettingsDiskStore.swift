import Foundation
import VaniScriptCore

enum SettingsDiskStore {
    static func load(fileManager: FileManager = .default) -> AppSettings {
        let url = AppStoragePaths.settingsURL(fileManager: fileManager)
        guard let data = try? Data(contentsOf: url) else { return .defaults }
        let loadedSettings = (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? .defaults
        var settings = loadedSettings

        // Keep only supported keys and merge missing defaults for local translation models
        let supportedTranslationKeys = Set(AppSettings.defaults.localTranslationModels.keys)
        settings.localTranslationModels = settings.localTranslationModels.filter { supportedTranslationKeys.contains($0.key) }
        for (key, defaultModel) in AppSettings.defaults.localTranslationModels {
            if settings.localTranslationModels[key] == nil {
                settings.localTranslationModels[key] = defaultModel
            }
        }

        // Keep only supported keys and merge missing defaults for local ASR models
        let supportedAsrKeys = Set(AppSettings.defaults.localAsrModels.keys)
        settings.localAsrModels = settings.localAsrModels.filter { supportedAsrKeys.contains($0.key) }
        for (key, defaultModel) in AppSettings.defaults.localAsrModels {
            if settings.localAsrModels[key] == nil {
                settings.localAsrModels[key] = defaultModel
            }
        }

        // Merge missing default keys for prompt presets
        for (key, defaultPreset) in DefaultPrompts.defaultPresets {
            if settings.promptPresets[key] == nil {
                settings.promptPresets[key] = defaultPreset
            }
        }

        // Merge latest Vaishnava starter glossary terms
        settings.glossary = StarterGlossary.mergeStarterGlossary(settings.glossary)
        settings.synchronizeLocalModelsWithDisk()
        settings.normalizeMcpSettings()
        if settings != loadedSettings {
            try? save(settings, fileManager: fileManager)
        }

        return settings
    }

    static func save(_ settings: AppSettings, fileManager: FileManager = .default) throws {
        let directory = AppStoragePaths.applicationSupportDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: AppStoragePaths.settingsURL(fileManager: fileManager), options: .atomic)
    }
}
