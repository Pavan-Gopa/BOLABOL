import AppKit
import Combine
import Foundation
import NativeSmartScribeCore
import SwiftUI

@MainActor
final class GeneralSettingsStore: ObservableObject {
    private static let settingsDefaultsKey = "general.settings"

    private let userDefaults: UserDefaults

    @Published var logExportMessage: String?

    @Published var settings: GeneralSettings {
        didSet {
            saveSettings()
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.settings = Self.loadSettings(from: userDefaults)
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
                        NativeSmartScribeLog.app.error(
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
                NativeSmartScribeLog.app.error(
                    "HUD sound preview delay interrupted: \(error.localizedDescription, privacy: .public)"
                )
            }
            AudioCuePlayer.shared.play(.finish, settings: settings)
        }
        logExportMessage = "HUD audio debug log: ~/Library/Application Support/NativeSmartScribe/Logs/hud-audio.log"
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
        settings.normalize()
        return settings
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
        .appendingPathComponent("NativeSmartScribe", isDirectory: true)
        .appendingPathComponent("Logs", isDirectory: true)

        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)

        let outputURL = logsDirectory.appendingPathComponent("NativeSmartScribe-system.log")
        let predicate = "subsystem == \"\(NativeSmartScribeLog.subsystem)\""

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
            throw NSError(domain: "NativeSmartScribeLogs", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }

        let header = """
        NativeSmartScribe system logs
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
