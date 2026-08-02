import AppKit
import Combine
import Foundation
import NativeBlaboomCore
import SwiftUI

extension Notification.Name {
    public static let didChangeAudioRetentionSettings = Notification.Name("didChangeAudioRetentionSettings")
}

@MainActor
final class GeneralSettingsStore: ObservableObject {
    /// Canonical settings blob key. Internal so sibling stores
    /// (TranscriptionModelStore, HotkeySettingsStore) can read the speech-language
    /// pair from the same blob (plan §3.3 — single source of truth).
    static let settingsDefaultsKey = "general.settings"

    private let userDefaults: UserDefaults

    @Published var logExportMessage: String?

    @Published var settings: GeneralSettings {
        didSet {
            saveSettings()
            NotificationCenter.default.post(name: .didChangeAudioRetentionSettings, object: settings)
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.settings = Self.loadSettings(from: userDefaults)
        NotificationCenter.default.post(name: .didChangeAudioRetentionSettings, object: self.settings)
    }

    static func live() -> GeneralSettingsStore {
        GeneralSettingsStore()
    }

    var preferredColorScheme: ColorScheme? {
        switch settings.theme {
        case .dark:
            .dark
        case .light:
            .light
        case .system:
            nil
        }
    }

    var uiScalePercentage: Int {
        Int((settings.uiScale * 100).rounded())
    }

    var overlayScalePercentage: Int {
        Int((settings.overlay.scale * 100).rounded())
    }

    var overlayTransparencyPercentage: Int {
        Int(((1 - settings.overlay.capsuleOpacity) * 100).rounded())
    }

    var overlayVolumePercentage: Int {
        Int((settings.overlay.volume * 100).rounded())
    }

    /// Canonical speech-language pair (plan §3.3). This is the single source of
    /// truth for primary + additional; onboarding (B2) and settings (B3) will
    /// read/write through this accessor.
    var speechLanguages: UserSpeechLanguages {
        get { settings.speechLanguages }
        set {
            update { $0.speechLanguages = newValue }
        }
    }

    func reset() {
        settings = GeneralSettings()
    }

    func text(_ key: AppTextKey) -> String {
        AppText.localized(key, language: settings.uiLanguage)
    }

    func formattedText(_ key: AppTextKey, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    func update(_ mutation: (inout GeneralSettings) -> Void) {
        var nextSettings = settings
        mutation(&nextSettings)
        nextSettings.normalize()
        settings = nextSettings
    }

    func exportSystemLogs() {
        Task {
            do {
                let url = try await Task.detached {
                    do {
                        return try SystemLogExporter.exportRecentLogs()
                    } catch {
                        NativeBlaboomLog.app.error(
                            "System log export failed: \(error.localizedDescription, privacy: .public)"
                        )
                        throw error
                    }
                }.value
                logExportMessage = text(.logsExported)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                logExportMessage = "\(text(.logsExportFailed)) \(error.localizedDescription)"
            }
        }
    }

    func testOverlayHUDSounds() {
        let settings = settings.overlay
        AudioCuePlayer.shared.play(.start, settings: settings)
        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                NativeBlaboomLog.app.error(
                    "HUD sound preview delay interrupted: \(error.localizedDescription, privacy: .public)"
                )
            }
            AudioCuePlayer.shared.play(.finish, settings: settings)
        }
        logExportMessage = "HUD audio debug log: ~/Library/Application Support/NativeBlaboom/Logs/hud-audio.log"
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: Self.settingsDefaultsKey)
    }

    private static func loadSettings(from userDefaults: UserDefaults) -> GeneralSettings {
        guard let data = userDefaults.data(forKey: settingsDefaultsKey),
              var settings = try? JSONDecoder().decode(GeneralSettings.self, from: data)
        else {
            return GeneralSettings()
        }

        // Best-effort migration (plan §3.4): a legacy blob has no
        // `speechLanguages` key yet, so seed the canonical pair from the old
        // transcription / force-target prefs and persist it immediately so the
        // canonical store becomes the source of truth after the first launch.
        if !Self.payloadContainsSpeechLanguages(data) {
            settings.speechLanguages = Self.migratedSpeechLanguages(from: userDefaults)
            if let migrated = try? JSONEncoder().encode(settings) {
                userDefaults.set(migrated, forKey: settingsDefaultsKey)
            }
        }

        settings.normalize()
        return settings
    }

    private static func payloadContainsSpeechLanguages(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object["speechLanguages"] != nil
    }

    /// Gathers legacy inputs and runs the pure migration in `UserSpeechLanguages`.
    ///
    /// - Old transcription language: `TranscriptionModelSettings.languagePreference`
    ///   (explicit `.language`/`.custom` code seeds primary; `.auto` keeps
    ///   system-locale default — auto-detect behavior itself is untouched, §4.1).
    /// - Old force-target language: the `translation.targetLanguage` AppStorage
    ///   value (a name or code) seeds additional when it differs from primary.
    private static func migratedSpeechLanguages(from userDefaults: UserDefaults) -> UserSpeechLanguages {
        var legacyTranscriptionCode: String?
        if let data = userDefaults.data(forKey: TranscriptionModelStore.settingsDefaultsKey),
           let modelSettings = try? JSONDecoder().decode(TranscriptionModelSettings.self, from: data) {
            legacyTranscriptionCode = modelSettings.languagePreference.resolvedSpeechLanguageCode
        }
        return UserSpeechLanguages.migrating(
            legacyTranscriptionCode: legacyTranscriptionCode,
            legacyTargetLanguageName: userDefaults.string(forKey: "translation.targetLanguage")
        )
    }
}

private enum SystemLogExporter {
    static func exportRecentLogs() throws -> URL {
        let logsDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("NativeBlaboom", isDirectory: true)
        .appendingPathComponent("Logs", isDirectory: true)

        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)

        let outputURL = logsDirectory.appendingPathComponent("NativeBlaboom-system.log")
        let predicate = "subsystem == \"\(NativeBlaboomLog.subsystem)\""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show",
            "--style", "compact",
            "--last", "24h",
            "--predicate", predicate
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorOutput, encoding: .utf8) ?? "log show failed"
            throw NSError(domain: "NativeBlaboomLogs", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }

        let header = """
        NativeBlaboom system logs
        Generated: \(Date().formatted(date: .complete, time: .complete))
        Predicate: \(predicate)
        Range: last 24h

        """
        var data = Data(header.utf8)
        data.append(output)
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }
}
