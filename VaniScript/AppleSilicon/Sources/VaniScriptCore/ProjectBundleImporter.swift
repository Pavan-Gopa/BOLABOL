import Foundation

public enum ProjectBundleImporter {
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
        } else if headerStr == "VANISCRIPT_LIBRARY_V2" {
            return try importLibraryV2(fileHandle: fileHandle, destinationDirectoryURL: destinationDirectoryURL)
        } else {
            guard let rawData = try fileHandle.readToEnd() else {
                throw NSError(domain: "ProjectBundleImporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty file"])
            }
            return try importJSON(data: rawData, destinationDirectoryURL: destinationDirectoryURL)
        }
    }

    private static func readLine(fileHandle: FileHandle, offset: inout UInt64) throws -> String {
        var lineData = Data()
        while true {
            try fileHandle.seek(toOffset: offset)
            guard let byteData = try fileHandle.read(upToCount: 1), !byteData.isEmpty else {
                break
            }
            offset += 1
            let byte = byteData[0]
            if byte == 0x0A { // \n
                break
            }
            if byte != 0x0D {
                lineData.append(byte)
            }
        }
        return String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func importBundleV2(fileHandle: FileHandle, destinationDirectoryURL: URL) throws -> [ProjectRecord] {
        var offset: UInt64 = 0
        let _ = try readLine(fileHandle: fileHandle, offset: &offset) // VANISCRIPT_BUNDLE_V2

        let lenStr = try readLine(fileHandle: fileHandle, offset: &offset)
        guard let jsonLen = Int(lenStr) else {
            throw NSError(domain: "ProjectBundleImporter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON metadata length"])
        }

        try fileHandle.seek(toOffset: offset)
        guard let jsonBlock = try fileHandle.read(upToCount: jsonLen) else {
            throw NSError(domain: "ProjectBundleImporter", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unexpected EOF reading metadata block"])
        }
        offset += UInt64(jsonLen)

        struct V2BundleMetadata: Codable {
            var format: String
            var schemaVersion: Int?
            var project: ProjectRecord
        }

        let decoder = JSONDecoder()
        let metadata = try decoder.decode(V2BundleMetadata.self, from: jsonBlock)

        let newProjectId = UUID().uuidString.lowercased()
        let projectDir = destinationDirectoryURL.appendingPathComponent(newProjectId, isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        var assetMap: [String: String] = [:]

        while true {
            let marker = try readLine(fileHandle: fileHandle, offset: &offset)
            if marker.isEmpty { break }
            if marker != "START_ASSET" { break }

            let key = try readLine(fileHandle: fileHandle, offset: &offset)
            let name = try readLine(fileHandle: fileHandle, offset: &offset)
            let sizeStr = try readLine(fileHandle: fileHandle, offset: &offset)
            guard let size = Int(sizeStr) else {
                throw NSError(domain: "ProjectBundleImporter", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid asset size"])
            }

            let subfolder = key.hasPrefix("chunk:") ? "chunks" : "audio"
            let targetDir = projectDir.appendingPathComponent(subfolder, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

            let safeName = name.isEmpty ? "asset" : name
            let destinationURL = targetDir.appendingPathComponent(safeName)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            FileManager.default.createFile(atPath: destinationURL.path, contents: nil, attributes: nil)
            let destHandle = try FileHandle(forWritingTo: destinationURL)

            try fileHandle.seek(toOffset: offset)
            var remaining = size
            let bufferSize = 1024 * 1024
            while remaining > 0 {
                let toRead = min(remaining, bufferSize)
                guard let data = try fileHandle.read(upToCount: toRead), !data.isEmpty else {
                    try? destHandle.close()
                    throw NSError(domain: "ProjectBundleImporter", code: 5, userInfo: [NSLocalizedDescriptionKey: "Unexpected EOF reading asset data"])
                }
                try destHandle.write(contentsOf: data)
                offset += UInt64(data.count)
                remaining -= data.count
            }
            try? destHandle.close()

            assetMap[key] = destinationURL.path

            let endMarker = try readLine(fileHandle: fileHandle, offset: &offset)
            if endMarker != "END_ASSET" {
                throw NSError(domain: "ProjectBundleImporter", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected END_ASSET marker"])
            }
        }

        var record = metadata.project
        record.id = newProjectId
        record.createdAt = isoString(Date())
        record.updatedAt = isoString(Date())
        record.session.normalizeTranslationArchive()

        record.session.sourceFile = assetMap["sourceFile"] ?? record.session.sourceFile
        for index in 0..<record.session.chunks.count {
            if let chunkPath = assetMap["chunk:\(index)"] {
                record.session.chunks[index].filePath = chunkPath
            } else if let sourcePath = assetMap["sourceFile"] {
                record.session.chunks[index].filePath = sourcePath
            }
        }

        return [record]
    }

    private static func importLibraryV2(fileHandle: FileHandle, destinationDirectoryURL: URL) throws -> [ProjectRecord] {
        var offset: UInt64 = 0
        let _ = try readLine(fileHandle: fileHandle, offset: &offset) // VANISCRIPT_LIBRARY_V2

        let lenStr = try readLine(fileHandle: fileHandle, offset: &offset)
        guard let jsonLen = Int(lenStr) else {
            throw NSError(domain: "ProjectBundleImporter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON metadata length"])
        }

        try fileHandle.seek(toOffset: offset)
        guard let jsonBlock = try fileHandle.read(upToCount: jsonLen) else {
            throw NSError(domain: "ProjectBundleImporter", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unexpected EOF reading metadata block"])
        }
        offset += UInt64(jsonLen)

        struct V2LibraryMetaBundle: Codable {
            var project: ProjectRecord
        }
        struct V2LibraryMetadata: Codable {
            var format: String
            var schemaVersion: Int?
            var bundles: [V2LibraryMetaBundle]
        }

        let decoder = JSONDecoder()
        let metadata = try decoder.decode(V2LibraryMetadata.self, from: jsonBlock)

        var importedProjects: [ProjectRecord] = []
        var projectIds: [String] = []
        var projectDirs: [URL] = []
        var assetMaps: [[String: String]] = []

        for bundle in metadata.bundles {
            let newId = UUID().uuidString.lowercased()
            projectIds.append(newId)
            let projectDir = destinationDirectoryURL.appendingPathComponent(newId, isDirectory: true)
            try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
            projectDirs.append(projectDir)
            assetMaps.append([:])

            var record = bundle.project
            record.id = newId
            record.session.normalizeTranslationArchive()
            importedProjects.append(record)
        }

        while true {
            let marker = try readLine(fileHandle: fileHandle, offset: &offset)
            if marker.isEmpty { break }
            if marker != "START_ASSET" { break }

            let pIdxStr = try readLine(fileHandle: fileHandle, offset: &offset)
            guard let pIdx = Int(pIdxStr), pIdx >= 0, pIdx < importedProjects.count else {
                throw NSError(domain: "ProjectBundleImporter", code: 7, userInfo: [NSLocalizedDescriptionKey: "Invalid project index in library asset"])
            }

            let key = try readLine(fileHandle: fileHandle, offset: &offset)
            let name = try readLine(fileHandle: fileHandle, offset: &offset)
            let sizeStr = try readLine(fileHandle: fileHandle, offset: &offset)
            guard let size = Int(sizeStr) else {
                throw NSError(domain: "ProjectBundleImporter", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid asset size"])
            }

            let projectDir = projectDirs[pIdx]
            let subfolder = key.hasPrefix("chunk:") ? "chunks" : "audio"
            let targetDir = projectDir.appendingPathComponent(subfolder, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

            let safeName = name.isEmpty ? "asset" : name
            let destinationURL = targetDir.appendingPathComponent(safeName)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            FileManager.default.createFile(atPath: destinationURL.path, contents: nil, attributes: nil)
            let destHandle = try FileHandle(forWritingTo: destinationURL)

            try fileHandle.seek(toOffset: offset)
            var remaining = size
            let bufferSize = 1024 * 1024
            while remaining > 0 {
                let toRead = min(remaining, bufferSize)
                guard let data = try fileHandle.read(upToCount: toRead), !data.isEmpty else {
                    try? destHandle.close()
                    throw NSError(domain: "ProjectBundleImporter", code: 5, userInfo: [NSLocalizedDescriptionKey: "Unexpected EOF reading asset data"])
                }
                try destHandle.write(contentsOf: data)
                offset += UInt64(data.count)
                remaining -= data.count
            }
            try? destHandle.close()

            assetMaps[pIdx][key] = destinationURL.path

            let endMarker = try readLine(fileHandle: fileHandle, offset: &offset)
            if endMarker != "END_ASSET" {
                throw NSError(domain: "ProjectBundleImporter", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected END_ASSET marker"])
            }
        }

        for i in 0..<importedProjects.count {
            let assetMap = assetMaps[i]
            importedProjects[i].createdAt = isoString(Date())
            importedProjects[i].updatedAt = isoString(Date())

            importedProjects[i].session.sourceFile = assetMap["sourceFile"] ?? importedProjects[i].session.sourceFile
            for index in 0..<importedProjects[i].session.chunks.count {
                if let chunkPath = assetMap["chunk:\(index)"] {
                    importedProjects[i].session.chunks[index].filePath = chunkPath
                } else if let sourcePath = assetMap["sourceFile"] {
                    importedProjects[i].session.chunks[index].filePath = sourcePath
                }
            }
        }

        return importedProjects
    }

    private static func importJSON(data: Data, destinationDirectoryURL: URL) throws -> [ProjectRecord] {
        let decoder = JSONDecoder()

        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let format = jsonObject["format"] as? String {
            if format == "vaniscript-project-v1" {
                struct V1ProjectBundle: Codable {
                    struct V1Asset: Codable {
                        var key: String
                        var name: String
                        var dataBase64: String
                    }
                    var project: ProjectRecord
                    var assets: [V1Asset]?
                }
                let bundle = try decoder.decode(V1ProjectBundle.self, from: data)
                let newId = UUID().uuidString.lowercased()
                let projectDir = destinationDirectoryURL.appendingPathComponent(newId, isDirectory: true)
                try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

                var assetMap: [String: String] = [:]
                for asset in bundle.assets ?? [] {
                    guard let assetData = Data(base64Encoded: asset.dataBase64) else { continue }
                    let subfolder = asset.key.hasPrefix("chunk:") ? "chunks" : "audio"
                    let targetDir = projectDir.appendingPathComponent(subfolder, isDirectory: true)
                    try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

                    let destinationURL = targetDir.appendingPathComponent(asset.name.isEmpty ? "asset" : asset.name)
                    try assetData.write(to: destinationURL)
                    assetMap[asset.key] = destinationURL.path
                }

                var record = bundle.project
                record.id = newId
                record.createdAt = isoString(Date())
                record.updatedAt = isoString(Date())
                record.session.normalizeTranslationArchive()

                record.session.sourceFile = assetMap["sourceFile"] ?? record.session.sourceFile
                for index in 0..<record.session.chunks.count {
                    if let chunkPath = assetMap["chunk:\(index)"] {
                        record.session.chunks[index].filePath = chunkPath
                    } else if let sourcePath = assetMap["sourceFile"] {
                        record.session.chunks[index].filePath = sourcePath
                    }
                }
                return [record]

            } else if format == "vaniscript-library-v1" {
                struct V1LibraryBundleItem: Codable {
                    struct V1Asset: Codable {
                        var key: String
                        var name: String
                        var dataBase64: String
                    }
                    var project: ProjectRecord
                    var assets: [V1Asset]?
                }
                struct V1LibraryBundle: Codable {
                    var format: String
                    var bundles: [V1LibraryBundleItem]
                }
                let bundle = try decoder.decode(V1LibraryBundle.self, from: data)
                var records: [ProjectRecord] = []

                for item in bundle.bundles {
                    let newId = UUID().uuidString.lowercased()
                    let projectDir = destinationDirectoryURL.appendingPathComponent(newId, isDirectory: true)
                    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

                    var assetMap: [String: String] = [:]
                    for asset in item.assets ?? [] {
                        guard let assetData = Data(base64Encoded: asset.dataBase64) else { continue }
                        let subfolder = asset.key.hasPrefix("chunk:") ? "chunks" : "audio"
                        let targetDir = projectDir.appendingPathComponent(subfolder, isDirectory: true)
                        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

                        let destinationURL = targetDir.appendingPathComponent(asset.name.isEmpty ? "asset" : asset.name)
                        try assetData.write(to: destinationURL)
                        assetMap[asset.key] = destinationURL.path
                    }

                    var record = item.project
                    record.id = newId
                    record.createdAt = isoString(Date())
                    record.updatedAt = isoString(Date())
                    record.session.normalizeTranslationArchive()

                    record.session.sourceFile = assetMap["sourceFile"] ?? record.session.sourceFile
                    for index in 0..<record.session.chunks.count {
                        if let chunkPath = assetMap["chunk:\(index)"] {
                            record.session.chunks[index].filePath = chunkPath
                        } else if let sourcePath = assetMap["sourceFile"] {
                            record.session.chunks[index].filePath = sourcePath
                        }
                    }
                    records.append(record)
                }
                return records
            }
        }

        return try ProjectArchive.decode(data)
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
