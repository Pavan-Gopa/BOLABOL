import Foundation

public struct ProjectRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var createdAt: String
    public var updatedAt: String
    public var session: SessionState

    public init(id: String, createdAt: String, updatedAt: String, session: SessionState) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.session = session
    }

    public var summary: ProjectSummary {
        ProjectSummary(
            id: id,
            name: projectName(from: session.sourceFileName),
            sourceFileName: session.sourceFileName,
            sourceMediaInfo: session.sourceMediaInfo ?? fallbackSourceMediaInfo(from: session),
            updatedAt: updatedAt,
            createdAt: createdAt,
            currentIndex: session.currentChunkIndex,
            totalChunks: session.chunks.count,
            approvedChunks: session.chunks.filter(\.approved).count,
            completedChunks: session.chunks.filter { $0.approved || $0.status == .done }.count,
            targetLang: session.targetLang
        )
    }

    private func projectName(from fileName: String) -> String {
        let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        return stem.isEmpty ? "VaniScript Project" : stem
    }

    private func fallbackSourceMediaInfo(from session: SessionState) -> SourceMediaInfo? {
        guard let sourceFile = session.sourceFile, !sourceFile.isEmpty else { return nil }
        let url = URL(fileURLWithPath: sourceFile)
        return SourceMediaInfo(
            filePath: sourceFile,
            fileName: url.lastPathComponent,
            title: session.sourceFileName,
            kind: MediaSource.kind(forPath: sourceFile),
            durationSec: session.durationSec > 0 ? session.durationSec : nil,
            container: url.pathExtension.isEmpty ? nil : url.pathExtension.lowercased()
        )
    }
}

public enum ProjectArchive {
    public static func encode(_ records: [ProjectRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(records)
    }

    public static func decode(_ data: Data) throws -> [ProjectRecord] {
        let decoder = JSONDecoder()
        func normalized(_ records: [ProjectRecord]) -> [ProjectRecord] {
            records.map { record in
                var copy = ProjectMigrator.migrate(record, fromSchemaVersion: 1)
                copy.session.normalizeTranslationArchive()
                return copy
            }
        }

        if let records = try? decoder.decode([ProjectRecord].self, from: data) {
            return normalized(records)
        }
        return normalized([try decoder.decode(ProjectRecord.self, from: data)])
    }

    public static func sortedRecent(_ records: [ProjectRecord]) -> [ProjectRecord] {
        records.sorted {
            if $0.updatedAt == $1.updatedAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.updatedAt > $1.updatedAt
        }
    }
}
