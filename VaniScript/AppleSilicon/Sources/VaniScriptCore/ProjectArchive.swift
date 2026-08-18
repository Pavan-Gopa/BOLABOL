import CryptoKit
import Foundation

public enum ProjectDeletionPolicy: Equatable, Sendable {
    case cleanImported(archivePath: String)
    case dirtyImported(archivePath: String)
    case localCreated
}

public struct ProjectWorkSnapshot: Codable, Equatable, Sendable {
    public var name: String?
    public var session: SessionState

    public init(name: String?, session: SessionState) {
        self.name = name
        self.session = session
    }
}

public struct ProjectRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String?
    public var createdAt: String
    public var updatedAt: String
    public var session: SessionState
    public var originatingArchivePath: String?
    public var originatingArchiveIndex: Int?
    public var importBaselineFingerprint: String?

    public var displayName: String? {
        get { name }
        set { name = newValue }
    }

    public var originatingArchiveURL: URL? {
        guard let originatingArchivePath, !originatingArchivePath.isEmpty else { return nil }
        return URL(fileURLWithPath: originatingArchivePath)
    }

    public var isImported: Bool {
        guard let path = originatingArchivePath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return false
        }
        return true
    }

    public var isDirty: Bool {
        guard isImported, let baseline = importBaselineFingerprint, !baseline.isEmpty else {
            return false
        }
        return computeWorkFingerprint() != baseline
    }

    public var deletionPolicy: ProjectDeletionPolicy {
        guard isImported, let path = originatingArchivePath else {
            return .localCreated
        }
        if isDirty {
            return .dirtyImported(archivePath: path)
        } else {
            return .cleanImported(archivePath: path)
        }
    }

    public func computeWorkFingerprint() -> String {
        var normalizedSession = self.session
        normalizedSession.currentChunkIndex = 0
        normalizedSession.transcriptionProvider = ""
        normalizedSession.translationProvider = ""
        normalizedSession.normalizeTranslationArchive()

        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = (trimmedName?.isEmpty == false) ? trimmedName : nil

        let snapshot = ProjectWorkSnapshot(
            name: normalizedName,
            session: normalizedSession
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot) else {
            return ""
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case displayName
        case createdAt
        case updatedAt
        case session
        case originatingArchivePath
        case originatingArchiveIndex
        case importBaselineFingerprint
    }

    public init(
        id: String,
        name: String? = nil,
        createdAt: String,
        updatedAt: String,
        session: SessionState,
        originatingArchivePath: String? = nil,
        originatingArchiveIndex: Int? = nil,
        importBaselineFingerprint: String? = nil
    ) {
        self.id = id
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = (trimmed?.isEmpty == false) ? trimmed : nil
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.session = session
        self.originatingArchivePath = originatingArchivePath
        self.originatingArchiveIndex = originatingArchiveIndex
        self.importBaselineFingerprint = importBaselineFingerprint
    }

    public init(id: String, createdAt: String, updatedAt: String, session: SessionState) {
        self.init(id: id, name: nil, createdAt: createdAt, updatedAt: updatedAt, session: session)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let rawName = try container.decodeIfPresent(String.self, forKey: .name)
        let rawDisplayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        let resolved = rawName ?? rawDisplayName
        let trimmed = resolved?.trimmingCharacters(in: .whitespacesAndNewlines)
        name = (trimmed?.isEmpty == false) ? trimmed : nil
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        session = try container.decode(SessionState.self, forKey: .session)
        originatingArchivePath = try container.decodeIfPresent(String.self, forKey: .originatingArchivePath)
        originatingArchiveIndex = try container.decodeIfPresent(Int.self, forKey: .originatingArchiveIndex)
        importBaselineFingerprint = try container.decodeIfPresent(String.self, forKey: .importBaselineFingerprint)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(session, forKey: .session)
        try container.encodeIfPresent(originatingArchivePath, forKey: .originatingArchivePath)
        try container.encodeIfPresent(originatingArchiveIndex, forKey: .originatingArchiveIndex)
        try container.encodeIfPresent(importBaselineFingerprint, forKey: .importBaselineFingerprint)
    }
    public var summary: ProjectSummary {
        let resolvedName: String
        if let nonBlankName = name?.trimmingCharacters(in: .whitespacesAndNewlines), !nonBlankName.isEmpty {
            resolvedName = nonBlankName
        } else {
            resolvedName = projectName(from: session.sourceFileName)
        }
        return ProjectSummary(
            id: id,
            name: resolvedName,
            sourceFileName: session.sourceFileName,
            sourceMediaInfo: session.sourceMediaInfo ?? fallbackSourceMediaInfo(from: session),
            updatedAt: updatedAt,
            createdAt: createdAt,
            currentIndex: session.currentChunkIndex,
            totalChunks: session.chunks.count,
            approvedChunks: session.chunks.filter(\.approved).count,
            completedChunks: session.chunks.filter { $0.approved || $0.status == .done }.count,
            targetLang: session.targetLang,
            staleChunkIndices: session.sourceKind == .document
                ? session.staleDocumentChunkIndices(
                    languageKey: TranslationArchive.languageKey(session.selectedTranslationLanguage ?? session.targetLang)
                )
                : []
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

    public static func overwriteArchive(
        record: ProjectRecord,
        at url: URL,
        targetIndex: Int? = nil
    ) throws {
        let parentDir = url.deletingLastPathComponent()
        let tempURL = parentDir.appendingPathComponent(".\(UUID().uuidString).tmp")
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: url.path) else {
            if url.pathExtension.lowercased() == "json" {
                let encodedData = try ProjectArchive.encode([record])
                try encodedData.write(to: tempURL)
            } else if url.pathExtension.lowercased() == "vaniscript-library" {
                try ProjectBundleExporter.exportLibrary(records: [record], to: tempURL)
            } else {
                try ProjectBundleExporter.exportBundle(record: record, to: tempURL)
            }
            try fileManager.moveItem(at: tempURL, to: url)
            return
        }

        let fileHandle = try FileHandle(forReadingFrom: url)
        let headerData = try fileHandle.read(upToCount: 24)
        try? fileHandle.close()

        let headerStr = headerData.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let tempImportDir = fileManager.temporaryDirectory.appendingPathComponent("VaniScriptOverwrite-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempImportDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempImportDir) }

        var existingRecords = try ProjectBundleImporter.importBundle(
            fileURL: url,
            destinationDirectoryURL: tempImportDir
        )

        if let idx = targetIndex, idx >= 0, idx < existingRecords.count {
            existingRecords[idx] = record
        } else if let matchIdx = existingRecords.firstIndex(where: { $0.id == record.id }) {
            existingRecords[matchIdx] = record
        } else if let matchIdx = existingRecords.firstIndex(where: { $0.name == record.name }) {
            existingRecords[matchIdx] = record
        } else if !existingRecords.isEmpty {
            existingRecords[0] = record
        } else {
            existingRecords.append(record)
        }

        if headerStr.hasPrefix("VANISCRIPT_LIBRARY_V2") || url.pathExtension.lowercased() == "vaniscript-library" {
            try ProjectBundleExporter.exportLibrary(records: existingRecords, to: tempURL)
        } else if headerStr.hasPrefix("VANISCRIPT_BUNDLE_V2") || url.pathExtension.lowercased() == "vaniscript" {
            if existingRecords.count > 1 {
                try ProjectBundleExporter.exportLibrary(records: existingRecords, to: tempURL)
            } else {
                try ProjectBundleExporter.exportBundle(record: record, to: tempURL)
            }
        } else if let data = try? Data(contentsOf: url) {
            let isTopLevelArray = (try? JSONSerialization.jsonObject(with: data) as? [Any]) != nil
            let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let format = jsonObject?["format"] as? String

            if let format, format.contains("library") {
                try ProjectBundleExporter.exportLibrary(records: existingRecords, to: tempURL)
            } else if let format, format.contains("project"), existingRecords.count <= 1 {
                try ProjectBundleExporter.exportBundle(record: record, to: tempURL)
            } else if isTopLevelArray || existingRecords.count > 1 {
                let encodedData = try ProjectArchive.encode(existingRecords)
                try encodedData.write(to: tempURL)
            } else if url.pathExtension.lowercased() == "json" {
                let encodedData = try ProjectArchive.encode(existingRecords)
                try encodedData.write(to: tempURL)
            } else {
                try ProjectBundleExporter.exportBundle(record: record, to: tempURL)
            }
        } else {
            if existingRecords.count > 1 {
                try ProjectBundleExporter.exportLibrary(records: existingRecords, to: tempURL)
            } else {
                try ProjectBundleExporter.exportBundle(record: record, to: tempURL)
            }
        }

        let backupURL = parentDir.appendingPathComponent(".\(UUID().uuidString).bak")
        try fileManager.moveItem(at: url, to: backupURL)
        do {
            try fileManager.moveItem(at: tempURL, to: url)
            try? fileManager.removeItem(at: backupURL)
        } catch {
            try? fileManager.moveItem(at: backupURL, to: url)
            try? fileManager.removeItem(at: tempURL)
            throw error
        }
    }
}
