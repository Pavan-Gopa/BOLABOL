import Foundation

public enum ProjectBundleExporter {
    public static func exportBundle(record: ProjectRecord, to url: URL) throws {
        struct Asset {
            let key: String
            let name: String
            let filePath: String
            let size: Int64
        }

        var assets: [Asset] = []
        let fileManager = FileManager.default

        func addAsset(key: String, path: String?) {
            guard let path = path, !path.isEmpty, fileManager.fileExists(atPath: path) else { return }
            do {
                let attrs = try fileManager.attributesOfItem(atPath: path)
                if let size = attrs[.size] as? Int64 {
                    let name = URL(fileURLWithPath: path).lastPathComponent
                    assets.append(Asset(key: key, name: name, filePath: path, size: size))
                }
            } catch {}
        }

        addAsset(key: "sourceFile", path: record.session.sourceFile)
        for (index, chunk) in record.session.chunks.enumerated() {
            addAsset(key: "chunk:\(index)", path: chunk.filePath)
        }

        struct AssetMeta: Codable {
            var key: String
            var name: String
            var size: Int64
        }

        struct V2BundleMetadata: Codable {
            var format: String
            var schemaVersion: Int
            var exportedAt: String
            var project: ProjectRecord
            var assetMeta: [AssetMeta]
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let exportedAt = formatter.string(from: Date())

        let metadata = V2BundleMetadata(
            format: "vaniscript-project-v2",
            schemaVersion: 3,
            exportedAt: exportedAt,
            project: record,
            assetMeta: assets.map { AssetMeta(key: $0.key, name: $0.name, size: $0.size) }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonBlock = try encoder.encode(metadata)

        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }

        fileManager.createFile(atPath: url.path, contents: nil, attributes: nil)
        guard let fileHandle = try? FileHandle(forWritingTo: url) else {
            throw NSError(domain: "ProjectBundleExporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot open file for writing"])
        }
        defer { try? fileHandle.close() }

        // 1. Write magic header
        try fileHandle.write(contentsOf: Data("VANISCRIPT_BUNDLE_V2\n".utf8))

        // 2. Write metadata length padded to 12 chars + \n
        let jsonLenStr = String(format: "%012d\n", jsonBlock.count)
        try fileHandle.write(contentsOf: Data(jsonLenStr.utf8))
        try fileHandle.write(contentsOf: jsonBlock)

        // 3. Write each asset
        let bufferSize = 1024 * 1024
        for asset in assets {
            try fileHandle.write(contentsOf: Data("START_ASSET\n".utf8))
            try fileHandle.write(contentsOf: Data("\(asset.key)\n".utf8))
            try fileHandle.write(contentsOf: Data("\(asset.name)\n".utf8))
            try fileHandle.write(contentsOf: Data("\(asset.size)\n".utf8))

            let assetHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: asset.filePath))
            defer { try? assetHandle.close() }

            var remaining = asset.size
            while remaining > 0 {
                let toRead = Int(min(Int64(bufferSize), remaining))
                if let data = try assetHandle.read(upToCount: toRead), !data.isEmpty {
                    try fileHandle.write(contentsOf: data)
                    remaining -= Int64(data.count)
                } else {
                    break
                }
            }

            try fileHandle.write(contentsOf: Data("END_ASSET\n".utf8))
        }
    }

    public static func exportLibrary(records: [ProjectRecord], to url: URL) throws {
        struct Asset {
            let key: String
            let name: String
            let filePath: String
            let size: Int64
        }

        struct Bundle {
            let project: ProjectRecord
            let assets: [Asset]
        }

        var bundles: [Bundle] = []
        let fileManager = FileManager.default

        for record in records {
            var assets: [Asset] = []
            func addAsset(key: String, path: String?) {
                guard let path = path, !path.isEmpty, fileManager.fileExists(atPath: path) else { return }
                do {
                    let attrs = try fileManager.attributesOfItem(atPath: path)
                    if let size = attrs[.size] as? Int64 {
                        let name = URL(fileURLWithPath: path).lastPathComponent
                        assets.append(Asset(key: key, name: name, filePath: path, size: size))
                    }
                } catch {}
            }

            addAsset(key: "sourceFile", path: record.session.sourceFile)
            for (index, chunk) in record.session.chunks.enumerated() {
                addAsset(key: "chunk:\(index)", path: chunk.filePath)
            }

            bundles.append(Bundle(project: record, assets: assets))
        }

        struct AssetMeta: Codable {
            var key: String
            var name: String
            var size: Int64
        }

        struct V2LibraryMetaBundle: Codable {
            var project: ProjectRecord
            var assetMeta: [AssetMeta]
        }

        struct V2LibraryMetadata: Codable {
            var format: String
            var schemaVersion: Int
            var exportedAt: String
            var bundles: [V2LibraryMetaBundle]
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let exportedAt = formatter.string(from: Date())

        let metadata = V2LibraryMetadata(
            format: "vaniscript-library-v2",
            schemaVersion: 3,
            exportedAt: exportedAt,
            bundles: bundles.map { b in
                V2LibraryMetaBundle(
                    project: b.project,
                    assetMeta: b.assets.map { AssetMeta(key: $0.key, name: $0.name, size: $0.size) }
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonBlock = try encoder.encode(metadata)

        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }

        fileManager.createFile(atPath: url.path, contents: nil, attributes: nil)
        guard let fileHandle = try? FileHandle(forWritingTo: url) else {
            throw NSError(domain: "ProjectBundleExporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot open file for writing"])
        }
        defer { try? fileHandle.close() }

        // 1. Write magic header
        try fileHandle.write(contentsOf: Data("VANISCRIPT_LIBRARY_V2\n".utf8))

        // 2. Write metadata length padded to 12 chars + \n
        let jsonLenStr = String(format: "%012d\n", jsonBlock.count)
        try fileHandle.write(contentsOf: Data(jsonLenStr.utf8))
        try fileHandle.write(contentsOf: jsonBlock)

        // 3. Write each asset
        let bufferSize = 1024 * 1024
        for (pIdx, b) in bundles.enumerated() {
            for asset in b.assets {
                try fileHandle.write(contentsOf: Data("START_ASSET\n".utf8))
                try fileHandle.write(contentsOf: Data("\(pIdx)\n".utf8))
                try fileHandle.write(contentsOf: Data("\(asset.key)\n".utf8))
                try fileHandle.write(contentsOf: Data("\(asset.name)\n".utf8))
                try fileHandle.write(contentsOf: Data("\(asset.size)\n".utf8))

                let assetHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: asset.filePath))
                defer { try? assetHandle.close() }

                var remaining = asset.size
                while remaining > 0 {
                    let toRead = Int(min(Int64(bufferSize), remaining))
                    if let data = try assetHandle.read(upToCount: toRead), !data.isEmpty {
                        try fileHandle.write(contentsOf: data)
                        remaining -= Int64(data.count)
                    } else {
                        break
                    }
                }

                try fileHandle.write(contentsOf: Data("END_ASSET\n".utf8))
            }
        }
    }
}
