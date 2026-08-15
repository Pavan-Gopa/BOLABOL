import Foundation

public enum ProjectBundleImporter {
    private struct LegacyAssetMeta: Codable {
        var key: String
        var name: String
        var size: Int64?
    }

    private struct BundleMetadata: Codable {
        var format: String
        var schemaVersion: Int?
        var project: ProjectRecord
        var assetManifest: ProjectAssetManifest?
        var assetMeta: [LegacyAssetMeta]?
    }

    private struct LibraryBundleMetadata: Codable {
        var project: ProjectRecord
        var assetManifest: ProjectAssetManifest?
        var assetMeta: [LegacyAssetMeta]?
    }

    private struct LibraryMetadata: Codable {
        var format: String
        var schemaVersion: Int?
        var bundles: [LibraryBundleMetadata]
    }

    private struct JSONAsset: Codable {
        var key: String
        var name: String
        var dataBase64: String
    }

    private struct JSONProjectBundle: Codable {
        var format: String
        var schemaVersion: Int?
        var project: ProjectRecord
        var assets: [JSONAsset]?
    }

    private struct JSONLibraryBundleItem: Codable {
        var project: ProjectRecord
        var assets: [JSONAsset]?
    }

    private struct JSONLibraryBundle: Codable {
        var format: String
        var schemaVersion: Int?
        var bundles: [JSONLibraryBundleItem]
    }

    public static func importBundle(fileURL: URL, destinationDirectoryURL: URL) throws -> [ProjectRecord] {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        guard let headerData = try fileHandle.read(upToCount: 21),
              let headerStr = String(data: headerData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw NSError(domain: "ProjectBundleImporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot read file header"])
        }

        try fileHandle.seek(toOffset: 0)
        if headerStr == "VANISCRIPT_BUNDLE_V2" {
            return try importBundleV2(fileHandle: fileHandle, destinationDirectoryURL: destinationDirectoryURL)
        }
        if headerStr == "VANISCRIPT_LIBRARY_V2" {
            return try importLibraryV2(fileHandle: fileHandle, destinationDirectoryURL: destinationDirectoryURL)
        }

        guard let rawData = try fileHandle.readToEnd() else {
            throw NSError(domain: "ProjectBundleImporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty file"])
        }
        return try importJSON(data: rawData, destinationDirectoryURL: destinationDirectoryURL)
    }

    private static func readLine(fileHandle: FileHandle, offset: inout UInt64) throws -> String {
        var lineData = Data()
        while true {
            try fileHandle.seek(toOffset: offset)
            guard let byteData = try fileHandle.read(upToCount: 1), !byteData.isEmpty else { break }
            offset += 1
            let byte = byteData[0]
            if byte == 0x0A { break }
            if byte != 0x0D { lineData.append(byte) }
        }
        return String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func readMetadata(
        fileHandle: FileHandle,
        offset: inout UInt64
    ) throws -> Data {
        let lenStr = try readLine(fileHandle: fileHandle, offset: &offset)
        guard let jsonLen = Int(lenStr), jsonLen >= 0 else {
            throw NSError(domain: "ProjectBundleImporter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON metadata length"])
        }
        try fileHandle.seek(toOffset: offset)
        guard let jsonBlock = try fileHandle.read(upToCount: jsonLen), jsonBlock.count == jsonLen else {
            throw NSError(domain: "ProjectBundleImporter", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unexpected EOF reading metadata block"])
        }
        offset += UInt64(jsonLen)
        return jsonBlock
    }

    private static func importBundleV2(fileHandle: FileHandle, destinationDirectoryURL: URL) throws -> [ProjectRecord] {
        var offset: UInt64 = 0
        _ = try readLine(fileHandle: fileHandle, offset: &offset)
        let jsonBlock = try readMetadata(fileHandle: fileHandle, offset: &offset)
        let metadata = try JSONDecoder().decode(BundleMetadata.self, from: jsonBlock)
        let schemaVersion = try ProjectMigrator.resolvedSchemaVersion(metadata.schemaVersion, legacyVersion: 2)

        let newProjectId = UUID().uuidString.lowercased()
        let projectDir = destinationDirectoryURL.appendingPathComponent(newProjectId, isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        var assetMap: [String: String] = [:]
        try readAssets(
            fileHandle: fileHandle,
            offset: &offset,
            destinationDirectory: projectDir,
            projectIndex: nil,
            assetMap: &assetMap
        )
        addManifestAliases(metadata.assetManifest, to: &assetMap)

        var record = try ProjectMigrator.migrate(record: metadata.project, fromSchemaVersion: schemaVersion)
        record.id = newProjectId
        record.createdAt = isoString(Date())
        record.updatedAt = isoString(Date())
        record.session.normalizeTranslationArchive()
        updateAssetPaths(record: &record, assetMap: assetMap)
        return [record]
    }

    private static func importLibraryV2(fileHandle: FileHandle, destinationDirectoryURL: URL) throws -> [ProjectRecord] {
        var offset: UInt64 = 0
        _ = try readLine(fileHandle: fileHandle, offset: &offset)
        let jsonBlock = try readMetadata(fileHandle: fileHandle, offset: &offset)
        let metadata = try JSONDecoder().decode(LibraryMetadata.self, from: jsonBlock)
        let schemaVersion = try ProjectMigrator.resolvedSchemaVersion(metadata.schemaVersion, legacyVersion: 2)

        var importedProjects: [ProjectRecord] = []
        var projectDirs: [URL] = []
        var assetMaps: [[String: String]] = []
        var manifests: [ProjectAssetManifest?] = []

        for bundle in metadata.bundles {
            let newId = UUID().uuidString.lowercased()
            let projectDir = destinationDirectoryURL.appendingPathComponent(newId, isDirectory: true)
            try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
            projectDirs.append(projectDir)
            assetMaps.append([:])
            manifests.append(bundle.assetManifest)

            var record = try ProjectMigrator.migrate(record: bundle.project, fromSchemaVersion: schemaVersion)
            record.id = newId
            record.session.normalizeTranslationArchive()
            importedProjects.append(record)
        }

        while true {
            let marker = try readLine(fileHandle: fileHandle, offset: &offset)
            if marker.isEmpty || marker != "START_ASSET" { break }
            let pIdxString = try readLine(fileHandle: fileHandle, offset: &offset)
            guard let pIdx = Int(pIdxString), pIdx >= 0, pIdx < importedProjects.count else {
                throw NSError(domain: "ProjectBundleImporter", code: 7, userInfo: [NSLocalizedDescriptionKey: "Invalid project index in library asset"])
            }
            try readOneAsset(
                fileHandle: fileHandle,
                offset: &offset,
                destinationDirectory: projectDirs[pIdx],
                projectIndexAlreadyRead: true,
                assetMap: &assetMaps[pIdx]
            )
        }

        for index in importedProjects.indices {
            addManifestAliases(manifests[index], to: &assetMaps[index])
            importedProjects[index].createdAt = isoString(Date())
            importedProjects[index].updatedAt = isoString(Date())
            updateAssetPaths(record: &importedProjects[index], assetMap: assetMaps[index])
        }
        return importedProjects
    }

    private static func readAssets(
        fileHandle: FileHandle,
        offset: inout UInt64,
        destinationDirectory: URL,
        projectIndex: Int?,
        assetMap: inout [String: String]
    ) throws {
        while true {
            let marker = try readLine(fileHandle: fileHandle, offset: &offset)
            if marker.isEmpty || marker != "START_ASSET" { break }
            if projectIndex != nil {
                _ = try readLine(fileHandle: fileHandle, offset: &offset)
            }
            try readOneAsset(
                fileHandle: fileHandle,
                offset: &offset,
                destinationDirectory: destinationDirectory,
                projectIndexAlreadyRead: false,
                assetMap: &assetMap
            )
        }
    }

    private static func readOneAsset(
        fileHandle: FileHandle,
        offset: inout UInt64,
        destinationDirectory: URL,
        projectIndexAlreadyRead: Bool,
        assetMap: inout [String: String]
    ) throws {
        _ = projectIndexAlreadyRead
        let key = try readLine(fileHandle: fileHandle, offset: &offset)
        let name = try readLine(fileHandle: fileHandle, offset: &offset)
        let sizeString = try readLine(fileHandle: fileHandle, offset: &offset)
        guard let size = Int(sizeString), size >= 0 else {
            throw NSError(domain: "ProjectBundleImporter", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid asset size"])
        }

        let subfolder = key.hasPrefix("chunk:") ? "chunks" : "audio"
        let targetDir = destinationDirectory.appendingPathComponent(subfolder, isDirectory: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let safeName = safeFileName(name)
        let destinationURL = targetDir.appendingPathComponent(safeName)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil, attributes: nil)
        let destinationHandle = try FileHandle(forWritingTo: destinationURL)
        defer { try? destinationHandle.close() }

        try fileHandle.seek(toOffset: offset)
        var remaining = size
        let bufferSize = 1024 * 1024
        while remaining > 0 {
            let toRead = min(remaining, bufferSize)
            guard let data = try fileHandle.read(upToCount: toRead), !data.isEmpty else {
                throw NSError(domain: "ProjectBundleImporter", code: 5, userInfo: [NSLocalizedDescriptionKey: "Unexpected EOF reading asset data"])
            }
            try destinationHandle.write(contentsOf: data)
            offset += UInt64(data.count)
            remaining -= data.count
        }

        let endMarker = try readLine(fileHandle: fileHandle, offset: &offset)
        guard endMarker == "END_ASSET" else {
            throw NSError(domain: "ProjectBundleImporter", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected END_ASSET marker"])
        }
        assetMap[key] = destinationURL.path
    }

    private static func addManifestAliases(
        _ manifest: ProjectAssetManifest?,
        to assetMap: inout [String: String]
    ) {
        for entry in manifest?.entries ?? [] {
            guard let canonicalPath = assetMap[entry.key] else { continue }
            for alias in entry.aliases ?? [] {
                assetMap[alias] = canonicalPath
            }
        }
    }

    private static func updateAssetPaths(record: inout ProjectRecord, assetMap: [String: String]) {
        let docAssetKey = record.session.documentState?.originalAsset.key
        let resolvedSource = assetMap["sourceFile"]
            ?? assetMap["originalSource"]
            ?? (docAssetKey.flatMap { assetMap[$0] })
            ?? record.session.sourceFile
        record.session.sourceFile = resolvedSource
        for index in record.session.chunks.indices {
            let key = "chunk:\(index)"
            if let chunkPath = assetMap[key] {
                record.session.chunks[index].filePath = chunkPath
            } else if let sourcePath = resolvedSource {
                record.session.chunks[index].filePath = sourcePath
            }
        }
    }

    private static func importJSON(data: Data, destinationDirectoryURL: URL) throws -> [ProjectRecord] {
        let decoder = JSONDecoder()
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let format = jsonObject["format"] as? String else {
            return try ProjectArchive.decode(data)
        }
        if let rawSchemaVersion = jsonObject["schemaVersion"] as? Int {
            try ProjectMigrator.validateSchemaVersion(rawSchemaVersion)
        }

        if format == "vaniscript-project-v1" || format == "vaniscript-project-v2" {
            let bundle = try decoder.decode(JSONProjectBundle.self, from: data)
            let schemaVersion = try ProjectMigrator.resolvedSchemaVersion(
                bundle.schemaVersion,
                legacyVersion: format == "vaniscript-project-v1" ? 1 : 2
            )
            return [try importJSONProject(bundle, schemaVersion: schemaVersion, destinationDirectoryURL: destinationDirectoryURL)]
        }
        if format == "vaniscript-library-v1" || format == "vaniscript-library-v2" {
            let bundle = try decoder.decode(JSONLibraryBundle.self, from: data)
            let schemaVersion = try ProjectMigrator.resolvedSchemaVersion(
                bundle.schemaVersion,
                legacyVersion: format == "vaniscript-library-v1" ? 1 : 2
            )
            return try bundle.bundles.map {
                try importJSONProject(
                    JSONProjectBundle(format: format, schemaVersion: schemaVersion, project: $0.project, assets: $0.assets),
                    schemaVersion: schemaVersion,
                    destinationDirectoryURL: destinationDirectoryURL
                )
            }
        }
        return try ProjectArchive.decode(data)
    }

    private static func importJSONProject(
        _ bundle: JSONProjectBundle,
        schemaVersion: Int,
        destinationDirectoryURL: URL
    ) throws -> ProjectRecord {
        let newId = UUID().uuidString.lowercased()
        let projectDir = destinationDirectoryURL.appendingPathComponent(newId, isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        var assetMap: [String: String] = [:]

        for asset in bundle.assets ?? [] {
            guard let assetData = Data(base64Encoded: asset.dataBase64) else { continue }
            let subfolder = asset.key.hasPrefix("chunk:") ? "chunks" : "audio"
            let targetDir = projectDir.appendingPathComponent(subfolder, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            let destinationURL = targetDir.appendingPathComponent(safeFileName(asset.name))
            try assetData.write(to: destinationURL)
            assetMap[asset.key] = destinationURL.path
        }

        var record = try ProjectMigrator.migrate(record: bundle.project, fromSchemaVersion: schemaVersion)
        record.id = newId
        record.createdAt = isoString(Date())
        record.updatedAt = isoString(Date())
        record.session.normalizeTranslationArchive()
        updateAssetPaths(record: &record, assetMap: assetMap)
        return record
    }

    private static func safeFileName(_ name: String) -> String {
        let candidate = URL(fileURLWithPath: name).lastPathComponent
        return candidate.isEmpty ? "asset" : candidate
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
