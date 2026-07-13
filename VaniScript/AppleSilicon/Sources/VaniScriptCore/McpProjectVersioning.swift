import Foundation

public enum McpEntityIdentifier {
    public static func chunkID(_ chunk: ChunkData) -> String {
        "chunk-\(chunk.index)"
    }

    public static func chunkIndex(from id: String) -> Int? {
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.hasPrefix("chunk-") else { return nil }
        return Int(normalized.dropFirst("chunk-".count))
    }

    public static func cueID(chunk: ChunkData, side: String, index: Int) -> String {
        "\(chunkID(chunk))-\(side.lowercased())-cue-\(index)"
    }
}

public enum McpProjectRevision {
    public static func make(workflow: WorkflowState) -> String {
        var data = Data(workflow.screen.rawValue.utf8)
        data.append(0)
        data.append(contentsOf: workflow.sourceFileName.utf8)
        data.append(0)
        data.append(contentsOf: workflow.sourceLang.utf8)
        data.append(0)
        data.append(contentsOf: workflow.targetLang.utf8)
        data.append(0)
        data.append(contentsOf: workflow.transcriptionProvider.utf8)
        data.append(0)
        data.append(contentsOf: workflow.translationProvider.utf8)
        data.append(0)
        data.append(contentsOf: workflow.outputFormats.map(\.rawValue).joined(separator: ",").utf8)
        data.append(0)
        data.append(contentsOf: "\(workflow.settings.chunkDurationMin)|\(workflow.settings.sliceMode.rawValue)|\(workflow.settings.silenceThreshDb)|\(workflow.settings.minSilenceMs)".utf8)
        data.append(0)
        if let session = workflow.session,
           let encoded = try? sortedEncoder.encode(session) {
            data.append(encoded)
        }
        data.append(0)
        if let glossary = try? sortedEncoder.encode(workflow.settings.glossary) {
            data.append(glossary)
        }
        return String(format: "rev-%016llx", fnv1a64(data))
    }
}

private extension McpProjectRevision {
    static var sortedEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func fnv1a64(_ data: Data) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}
