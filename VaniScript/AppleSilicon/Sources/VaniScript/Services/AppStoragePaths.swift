import Foundation

public enum AppStoragePaths {
    public static func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("VaniScript", isDirectory: true)
    }

    public static func settingsURL(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager).appendingPathComponent("settings.json")
    }

    public static func projectsURL(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager).appendingPathComponent("projects.json")
    }

    public static func batchDirectory(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("Batch", isDirectory: true)
    }

    public static func batchDatabaseURL(fileManager: FileManager = .default) -> URL {
        batchDirectory(fileManager: fileManager).appendingPathComponent("jobs.sqlite")
    }

    public static func batchWorkspacesDirectory(fileManager: FileManager = .default) -> URL {
        batchDirectory(fileManager: fileManager)
            .appendingPathComponent("Workspaces", isDirectory: true)
    }
    public static func batchFolderProfilesURL(fileManager: FileManager = .default) -> URL {
        batchDirectory(fileManager: fileManager).appendingPathComponent("folder-profiles.json")
    }

    public static func prepareBatchStorage(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: batchDirectory(fileManager: fileManager), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: batchWorkspacesDirectory(fileManager: fileManager), withIntermediateDirectories: true)
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
    static func projectsDirectory(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("Projects", isDirectory: true)
    }

    static func projectDirectory(
        id: String,
        fileManager: FileManager = .default
    ) -> URL {
        projectsDirectory(fileManager: fileManager)
            .appendingPathComponent(id, isDirectory: true)
    }

    static func projectSourceDirectory(
        id: String,
        fileManager: FileManager = .default
    ) -> URL {
        projectDirectory(id: id, fileManager: fileManager)
            .appendingPathComponent("source", isDirectory: true)
    }
    public static func updateReceiptURL(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager).appendingPathComponent("update_receipt.json")
    }

    public static func updateBackupDirectory(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("UpdateBackups", isDirectory: true)
    }
}
