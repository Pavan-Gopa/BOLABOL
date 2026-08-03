import Foundation

public struct AudioRecording: Identifiable, Codable, Equatable, Sendable {
    public enum Source: String, Codable, Equatable, Sendable {
        case microphone
        case importedFile
    }

    public var id: UUID
    public var fileURL: URL
    public var createdAt: Date
    public var duration: TimeInterval
    public var sampleRate: Double
    public var channelCount: Int
    public var fileSizeBytes: Int64?
    public var suggestedTitle: String
    public var source: Source

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        createdAt: Date = .now,
        duration: TimeInterval,
        sampleRate: Double,
        channelCount: Int,
        fileSizeBytes: Int64? = nil,
        suggestedTitle: String = AppText.localized(.voiceNote, language: .english),
        source: Source = .microphone
    ) {
        self.id = id
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.duration = duration
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.fileSizeBytes = fileSizeBytes
        self.suggestedTitle = suggestedTitle
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case fileURL
        case createdAt
        case duration
        case sampleRate
        case channelCount
        case fileSizeBytes
        case suggestedTitle
        case source
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileURL = try container.decode(URL.self, forKey: .fileURL)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        sampleRate = try container.decode(Double.self, forKey: .sampleRate)
        channelCount = try container.decode(Int.self, forKey: .channelCount)
        fileSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .fileSizeBytes)
        suggestedTitle = try container.decode(String.self, forKey: .suggestedTitle)
        source = try container.decodeIfPresent(Source.self, forKey: .source) ?? .microphone
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fileURL, forKey: .fileURL)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(duration, forKey: .duration)
        try container.encode(sampleRate, forKey: .sampleRate)
        try container.encode(channelCount, forKey: .channelCount)
        try container.encodeIfPresent(fileSizeBytes, forKey: .fileSizeBytes)
        try container.encode(suggestedTitle, forKey: .suggestedTitle)
        try container.encode(source, forKey: .source)
    }
}
