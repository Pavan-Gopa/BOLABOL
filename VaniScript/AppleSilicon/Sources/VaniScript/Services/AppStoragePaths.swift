import Foundation

enum AppStoragePaths {
    static func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("VaniScript", isDirectory: true)
    }

    static func settingsURL(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager).appendingPathComponent("settings.json")
    }

    static func projectsURL(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager).appendingPathComponent("projects.json")
    }

    static func recordingsDirectory(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    static func importsDirectory(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("Imports", isDirectory: true)
    }

    static func mediaToolsDirectory(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("bin", isDirectory: true)
    }
}
