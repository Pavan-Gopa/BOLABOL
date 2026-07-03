import Foundation
import VaniScriptCore

enum ProjectDiskStore {
    static func load(fileManager: FileManager = .default) -> [ProjectRecord] {
        let url = AppStoragePaths.projectsURL(fileManager: fileManager)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? ProjectArchive.decode(data)) ?? []
    }

    static func save(_ records: [ProjectRecord], fileManager: FileManager = .default) throws {
        let directory = AppStoragePaths.applicationSupportDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try ProjectArchive.encode(ProjectArchive.sortedRecent(records))
        try data.write(to: AppStoragePaths.projectsURL(fileManager: fileManager), options: .atomic)
    }
}
