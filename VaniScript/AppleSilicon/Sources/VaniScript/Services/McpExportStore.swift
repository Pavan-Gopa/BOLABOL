import AppKit
import Foundation

@MainActor
final class McpExportStore {
    struct Record {
        let id: String
        let files: [URL]
        let createdAt: Date
    }

    private var records: [String: Record] = [:]

    func makeDirectory(label: String) throws -> (id: String, url: URL) {
        let exportID = UUID().uuidString.lowercased()
        let cleanLabel = safeFilePart(label)
        let directory = AppStoragePaths.applicationSupportDirectory()
            .appendingPathComponent("MCP Exports", isDirectory: true)
            .appendingPathComponent("\(cleanLabel)-\(exportID.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        records[exportID] = Record(id: exportID, files: [], createdAt: Date())
        return (exportID, directory)
    }

    func register(exportID: String, files: [URL]) -> [String: Any] {
        records[exportID] = Record(id: exportID, files: files, createdAt: Date())
        return [
            "exportId": exportID,
            "files": files.map { ["fileName": $0.lastPathComponent, "sizeBytes": fileSize($0)] },
            "fileCount": files.count,
        ]
    }

    func reveal(exportID: String) throws -> [String: Any] {
        guard let record = records[exportID], let first = record.files.first else {
            throw NSError(domain: "McpExportStore", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unknown exportId or no completed files"])
        }
        NSWorkspace.shared.activateFileViewerSelecting(record.files)
        return ["success": true, "exportId": exportID, "fileName": first.lastPathComponent]
    }

    private func safeFilePart(_ value: String) -> String {
        let clean = value.replacingOccurrences(of: #"[^A-Za-z0-9_-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return clean.isEmpty ? "VaniScript" : String(clean.prefix(80))
    }

    private func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}
