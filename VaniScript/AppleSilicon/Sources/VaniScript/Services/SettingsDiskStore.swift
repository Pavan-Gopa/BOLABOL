import Foundation
import VaniScriptCore

enum SettingsDiskStore {
    static func load(fileManager: FileManager = .default) -> AppSettings {
        let url = AppStoragePaths.settingsURL(fileManager: fileManager)
        guard let data = try? Data(contentsOf: url) else { return .defaults }
        let loadedSettings = (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? .defaults
        var settings = loadedSettings

        // Canonicalize known model labels and runtimes while retaining all
        // user-owned install state, then discard unsupported legacy IDs.
        settings.normalizeLocalModelMetadata()
        let supportedTranslationKeys = Set(AppSettings.defaults.localTranslationModels.keys)
        settings.localTranslationModels = settings.localTranslationModels.filter {
            supportedTranslationKeys.contains($0.key)
        }

        let supportedAsrKeys = Set(AppSettings.defaults.localAsrModels.keys)
        settings.localAsrModels = settings.localAsrModels.filter {
            supportedAsrKeys.contains($0.key)
        }

        // Merge missing default keys for prompt presets
        for (key, defaultPreset) in DefaultPrompts.defaultPresets {
            if settings.promptPresets[key] == nil {
                settings.promptPresets[key] = defaultPreset
            }
        }

        // Merge latest Vaishnava starter glossary terms
        settings.glossary = StarterGlossary.mergeStarterGlossary(settings.glossary)
        // Model file presence and integrity are reconciled asynchronously by WorkflowStore
        // so a large package cannot hash on the MainActor during startup.
        settings.normalizeMcpSettings()
        if settings != loadedSettings {
            try? save(settings, fileManager: fileManager)
        }

        return settings
    }

    static func save(_ settings: AppSettings, fileManager: FileManager = .default) throws {
        let directory = AppStoragePaths.applicationSupportDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: directory.path
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        let settingsURL = AppStoragePaths.settingsURL(fileManager: fileManager)
        try data.write(to: settingsURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: settingsURL.path
        )
    }
}
