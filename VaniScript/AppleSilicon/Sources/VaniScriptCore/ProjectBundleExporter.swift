import CryptoKit
import Foundation

public enum ProjectBundleExporter {
    private struct BundleAsset {
        var key: String
        var aliases: [String]
        var name: String
        var filePath: String
        var size: Int64
        var role: ProjectAssetRole
        var language: String?
        var format: String
        var sha256: String
    }

    private struct BundleMetadata: Codable {
        var format: String
        var schemaVersion: Int
        var exportedAt: String
        var project: ProjectRecord
        var assetManifest: ProjectAssetManifest
    }

    private struct LibraryBundleMetadata: Codable {
        var project: ProjectRecord
        var assetManifest: ProjectAssetManifest
    }

    private struct LibraryMetadata: Codable {
        var format: String
        var schemaVersion: Int
        var exportedAt: String
        var bundles: [LibraryBundleMetadata]
    }

    private static let schemaVersion = ProjectMigrator.currentSchemaVersion

    public static func exportBundle(record: ProjectRecord, to url: URL) throws {
        let assets = try collectAssets(for: record)
        let metadata = BundleMetadata(
            format: "vaniscript-project-v2",
            schemaVersion: schemaVersion,
            exportedAt: isoString(Date()),
            project: record,
            assetManifest: ProjectAssetManifest(entries: assets.map(manifestEntry))
        )
        let jsonBlock = try encoded(metadata)
        try writeBundle(
            header: "VANISCRIPT_BUNDLE_V2",
            jsonBlock: jsonBlock,
            assets: assets,
            to: url
        )
    }

    public static func exportLibrary(records: [ProjectRecord], to url: URL) throws {
        let bundles = try records.map { record in
            (record: record, assets: try collectAssets(for: record))
        }
        let metadata = LibraryMetadata(
            format: "vaniscript-library-v2",
            schemaVersion: schemaVersion,
            exportedAt: isoString(Date()),
            bundles: bundles.map { bundle in
                LibraryBundleMetadata(
                    project: bundle.record,
                    assetManifest: ProjectAssetManifest(entries: bundle.assets.map(manifestEntry))
                )
            }
        )
        let jsonBlock = try encoded(metadata)

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        fileManager.createFile(atPath: url.path, contents: nil, attributes: nil)
        guard let fileHandle = try? FileHandle(forWritingTo: url) else {
            throw NSError(
                domain: "ProjectBundleExporter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot open file for writing"]
            )
        }
        defer { try? fileHandle.close() }

        try fileHandle.write(contentsOf: Data("VANISCRIPT_LIBRARY_V2\n".utf8))
        try fileHandle.write(contentsOf: Data(String(format: "%012d\n", jsonBlock.count).utf8))
        try fileHandle.write(contentsOf: jsonBlock)

        for (projectIndex, bundle) in bundles.enumerated() {
            try writeAssets(bundle.assets, projectIndex: projectIndex, to: fileHandle)
        }
    }

    private static func collectAssets(for record: ProjectRecord) throws -> [BundleAsset] {
        let fileManager = FileManager.default
        var assets: [BundleAsset] = []
        var signatureToIndex: [String: Int] = [:]

        func addAsset(key: String, path: String?, role: ProjectAssetRole, language: String? = nil) throws {
            guard let path, !path.isEmpty, fileManager.fileExists(atPath: path) else { return }
            let attributes = try fileManager.attributesOfItem(atPath: path)
            guard let size = attributes[.size] as? Int64 else { return }
            let name = URL(fileURLWithPath: path).lastPathComponent
            let format = URL(fileURLWithPath: path).pathExtension.lowercased()
            let hash = try sha256(of: URL(fileURLWithPath: path))
            let signature = "\(role.rawValue):\(hash)"

            if let existingIndex = signatureToIndex[signature] {
                if !assets[existingIndex].aliases.contains(key), assets[existingIndex].key != key {
                    assets[existingIndex].aliases.append(key)
                }
                return
            }

            signatureToIndex[signature] = assets.count
            assets.append(
                BundleAsset(
                    key: key,
                    aliases: [],
                    name: name,
                    filePath: path,
                    size: size,
                    role: role,
                    language: language,
                    format: format,
                    sha256: hash
                )
            )
        }
        try addAsset(key: "sourceFile", path: record.session.sourceFile, role: .originalSource)
        for (index, chunk) in record.session.chunks.enumerated() {
            try addAsset(key: "chunk:\(index)", path: chunk.filePath, role: .mediaChunk)
        }
        return assets
    }

    private static func manifestEntry(_ asset: BundleAsset) -> ProjectAssetManifestEntry {
        ProjectAssetManifestEntry(
            key: asset.key,
            role: asset.role,
            language: asset.language,
            format: asset.format,
            originalFileName: asset.name,
            sha256: asset.sha256,
            size: asset.size,
            aliases: asset.aliases.isEmpty ? nil : asset.aliases
        )
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private static func writeBundle(
        header: String,
        jsonBlock: Data,
        assets: [BundleAsset],
        to url: URL
    ) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        fileManager.createFile(atPath: url.path, contents: nil, attributes: nil)
        guard let fileHandle = try? FileHandle(forWritingTo: url) else {
            throw NSError(
                domain: "ProjectBundleExporter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot open file for writing"]
            )
        }
        defer { try? fileHandle.close() }

        try fileHandle.write(contentsOf: Data("\(header)\n".utf8))
        try fileHandle.write(contentsOf: Data(String(format: "%012d\n", jsonBlock.count).utf8))
        try fileHandle.write(contentsOf: jsonBlock)
        try writeAssets(assets, to: fileHandle)
    }

    private static func writeAssets(
        _ assets: [BundleAsset],
        projectIndex: Int? = nil,
        to fileHandle: FileHandle
    ) throws {
        let bufferSize = 1024 * 1024
        for asset in assets {
            try fileHandle.write(contentsOf: Data("START_ASSET\n".utf8))
            if let projectIndex {
                try fileHandle.write(contentsOf: Data("\(projectIndex)\n".utf8))
            }
            try fileHandle.write(contentsOf: Data("\(asset.key)\n".utf8))
            try fileHandle.write(contentsOf: Data("\(asset.name)\n".utf8))
            try fileHandle.write(contentsOf: Data("\(asset.size)\n".utf8))

            let assetHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: asset.filePath))
            defer { try? assetHandle.close() }
            var remaining = asset.size
            while remaining > 0 {
                let toRead = Int(min(Int64(bufferSize), remaining))
                guard let data = try assetHandle.read(upToCount: toRead), !data.isEmpty else {
                    throw NSError(
                        domain: "ProjectBundleExporter",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Unexpected EOF reading asset"]
                    )
                }
                try fileHandle.write(contentsOf: data)
                remaining -= Int64(data.count)
            }
            try fileHandle.write(contentsOf: Data("END_ASSET\n".utf8))
        }
    }

    private static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
