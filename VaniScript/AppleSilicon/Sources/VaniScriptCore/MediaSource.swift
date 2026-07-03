import Foundation

public enum SourceMediaKind: String, Codable, Equatable, Sendable {
    case audio
    case video
    case unknown
}

public enum MediaSource {
    private static let audioExtensions: Set<String> = ["mp3", "wav", "m4a", "flac", "ogg", "aac", "wma"]
    private static let videoExtensions: Set<String> = ["mp4", "mov", "mkv", "webm"]

    public static func kind(forPath path: String) -> SourceMediaKind {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        if audioExtensions.contains(ext) { return .audio }
        if videoExtensions.contains(ext) { return .video }
        return .unknown
    }

    public static func directMediaURL(from rawValue: String) -> URL? {
        guard let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["https", "http", "file"].contains(scheme),
              kind(forPath: url.path) != .unknown
        else {
            return nil
        }
        return url
    }

    public static func isWebVideoOrAudioLink(_ rawValue: String) -> Bool {
        guard let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased() else {
            return false
        }
        return host.contains("youtube.com") || host.contains("youtu.be") || host.contains("soundcloud.com")
    }
}

public struct SourceMediaInfo: Codable, Equatable, Sendable {
    public var originalURL: String?
    public var filePath: String
    public var fileName: String
    public var title: String?
    public var kind: SourceMediaKind
    public var durationSec: Double?
    public var fileSizeBytes: Int64?
    public var width: Int?
    public var height: Int?
    public var frameRate: Double?
    public var videoCodec: String?
    public var audioCodec: String?
    public var container: String?
    public var writingApplication: String?
    public var overallBitrateBps: Double?
    public var videoBitrateBps: Double?
    public var audioBitrateBps: Double?
    public var audioSampleRateHz: Double?
    public var audioChannelCount: Int?
    public var importedAt: String?

    public init(
        originalURL: String? = nil,
        filePath: String,
        fileName: String,
        title: String? = nil,
        kind: SourceMediaKind,
        durationSec: Double? = nil,
        fileSizeBytes: Int64? = nil,
        width: Int? = nil,
        height: Int? = nil,
        frameRate: Double? = nil,
        videoCodec: String? = nil,
        audioCodec: String? = nil,
        container: String? = nil,
        writingApplication: String? = nil,
        overallBitrateBps: Double? = nil,
        videoBitrateBps: Double? = nil,
        audioBitrateBps: Double? = nil,
        audioSampleRateHz: Double? = nil,
        audioChannelCount: Int? = nil,
        importedAt: String? = nil
    ) {
        self.originalURL = originalURL
        self.filePath = filePath
        self.fileName = fileName
        self.title = title
        self.kind = kind
        self.durationSec = durationSec
        self.fileSizeBytes = fileSizeBytes
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.container = container
        self.writingApplication = writingApplication
        self.overallBitrateBps = overallBitrateBps
        self.videoBitrateBps = videoBitrateBps
        self.audioBitrateBps = audioBitrateBps
        self.audioSampleRateHz = audioSampleRateHz
        self.audioChannelCount = audioChannelCount
        self.importedAt = importedAt
    }
}

public extension SourceMediaInfo {
    var qualityLabel: String {
        guard kind == .video, let width, let height else {
            return kind == .audio ? "Audio" : "Media"
        }
        let shortEdge = min(width, height)
        let longEdge = max(width, height)
        if shortEdge >= 2160 || longEdge >= 3840 { return "4K" }
        if shortEdge >= 1440 || longEdge >= 2560 { return "2K" }
        if shortEdge >= 1080 || longEdge >= 1920 { return "Full HD" }
        if shortEdge >= 720 || longEdge >= 1280 { return "HD" }
        return "\(width)x\(height)"
    }

    var resolutionLabel: String {
        guard let width, let height else { return "" }
        return "\(width)x\(height)"
    }

    var displayTitle: String {
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleanTitle.isEmpty ? fileName : cleanTitle
    }

    func mediaInfoLines(includeOriginalURL: Bool = true) -> [String] {
        let hasVideo = kind == .video || width != nil || height != nil || videoCodec != nil || videoBitrateBps != nil
        let hasAudio = audioCodec != nil || audioBitrateBps != nil || audioSampleRateHz != nil || audioChannelCount != nil

        var lines: [String] = ["Title: \(displayTitle)", "", "General"]
        var generalSummaryParts: [String] = []
        if let container, !container.isEmpty {
            generalSummaryParts.append(Self.containerLabel(container))
        }
        if let fileSizeBytes {
            generalSummaryParts.append(ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file))
        }
        if let durationSec, durationSec > 0 {
            generalSummaryParts.append(Self.durationWordsLabel(durationSec))
        }
        if !generalSummaryParts.isEmpty {
            let head = generalSummaryParts.first ?? ""
            let tail = generalSummaryParts.dropFirst().joined(separator: ", ")
            lines.append(tail.isEmpty ? head : "\(head): \(tail)")
        }
        if let overallBitrateBps, overallBitrateBps > 0 {
            lines.append("Overall bitrate: \(Self.bitrateLabel(overallBitrateBps))")
        }
        if let writingApplication, !writingApplication.isEmpty {
            lines.append("Writing application: \(writingApplication)")
        }
        if hasVideo {
            lines.append("1 Video stream: \(Self.codecDisplayName(videoCodec, media: .video))")
        }
        if hasAudio {
            lines.append("1 Audio stream: \(Self.codecDisplayName(audioCodec, media: .audio))")
        }

        if hasVideo {
            lines.append("")
            lines.append("Video")
            var summaryParts: [String] = []
            if let videoBitrateBps, videoBitrateBps > 0 {
                summaryParts.append(Self.bitrateLabel(videoBitrateBps))
            }
            if !resolutionLabel.isEmpty {
                summaryParts.append("\(resolutionLabel) \(Self.aspectRatioLabel(width: width, height: height))")
            }
            if let frameRate, frameRate > 0 {
                summaryParts.append("at \(Self.frameRateLabel(frameRate)) FPS")
            }
            summaryParts.append(Self.codecDisplayName(videoCodec, media: .video))
            lines.append(summaryParts.joined(separator: ", "))
            lines.append("Quality: \(qualityLabel)")
            if !resolutionLabel.isEmpty {
                lines.append("Resolution: \(resolutionLabel)")
            }
            if let frameRate, frameRate > 0 {
                lines.append("Frame rate: \(Self.frameRateLabel(frameRate)) fps")
            }
            lines.append("Codec: \(Self.codecDisplayName(videoCodec, media: .video))")
            if let videoBitrateBps, videoBitrateBps > 0 {
                lines.append("Video bitrate: \(Self.bitrateLabel(videoBitrateBps))")
            }
        }

        if hasAudio {
            lines.append("")
            lines.append("Audio")
            var summaryParts: [String] = []
            if let audioBitrateBps, audioBitrateBps > 0 {
                summaryParts.append(Self.bitrateLabel(audioBitrateBps))
            }
            if let audioSampleRateHz, audioSampleRateHz > 0 {
                summaryParts.append(Self.sampleRateLabel(audioSampleRateHz))
            }
            if let audioChannelCount, audioChannelCount > 0 {
                summaryParts.append(Self.channelLabel(audioChannelCount).lowercased())
            }
            summaryParts.append(Self.codecDisplayName(audioCodec, media: .audio))
            lines.append(summaryParts.joined(separator: ", "))
            lines.append("Codec: \(Self.codecDisplayName(audioCodec, media: .audio))")
            if let audioBitrateBps, audioBitrateBps > 0 {
                lines.append("Audio bitrate: \(Self.bitrateLabel(audioBitrateBps))")
            }
            if let audioSampleRateHz, audioSampleRateHz > 0 {
                lines.append("Sample rate: \(Self.sampleRateLabel(audioSampleRateHz))")
            }
            if let audioChannelCount, audioChannelCount > 0 {
                lines.append("Channels: \(Self.channelLabel(audioChannelCount))")
            }
        }

        if includeOriginalURL, let originalURL, !originalURL.isEmpty {
            lines.append("")
            lines.append("Source URL: \(originalURL)")
        }

        return lines
    }

    private enum CodecMedia {
        case video
        case audio
    }

    private static func bitrateLabel(_ bitsPerSecond: Double) -> String {
        if bitsPerSecond >= 1_000_000 {
            return "\(numberLabel(bitsPerSecond / 1_000_000)) Mbps"
        }
        return "\(numberLabel(bitsPerSecond / 1_000)) kbps"
    }

    private static func sampleRateLabel(_ hertz: Double) -> String {
        if hertz >= 1_000 {
            return "\(numberLabel(hertz / 1_000)) kHz"
        }
        return "\(numberLabel(hertz)) Hz"
    }

    private static func channelLabel(_ channels: Int) -> String {
        switch channels {
        case 1:
            return "Mono (1)"
        case 2:
            return "Stereo (2)"
        default:
            return "\(channels)"
        }
    }

    private static func frameRateLabel(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        return String(format: "%.3f", value)
    }

    private static func durationWordsLabel(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return "\(hours) h \(minutes) min \(secs) sec"
        }
        if minutes > 0 {
            return "\(minutes) min \(secs) sec"
        }
        return "\(secs) sec"
    }

    private static func containerLabel(_ container: String) -> String {
        switch container.lowercased() {
        case "mp4", "m4v", "m4a":
            return "MPEG-4 (Base Media)"
        case "mov":
            return "QuickTime"
        case "mp3":
            return "MPEG Audio"
        default:
            return container.uppercased()
        }
    }

    private static func codecDisplayName(_ codec: String?, media: CodecMedia) -> String {
        let normalized = codec?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch normalized {
        case "avc1", "avc3", "h264":
            return "AVC"
        case "hvc1", "hev1", "hevc":
            return "HEVC"
        case "vp09", "vp9":
            return "VP9"
        case "av01", "av1":
            return "AV1"
        case "mp4a", "aac":
            return "AAC LC"
        case "alac":
            return "ALAC"
        case "opus":
            return "Opus"
        default:
            if let codec, !codec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return codec
            }
            return media == .video ? "Video" : "Audio"
        }
    }

    private static func aspectRatioLabel(width: Int?, height: Int?) -> String {
        guard let width, let height, width > 0, height > 0 else { return "" }
        let divisor = gcd(width, height)
        return "(\(width / divisor):\(height / divisor))"
    }

    private static func gcd(_ lhs: Int, _ rhs: Int) -> Int {
        var a = abs(lhs)
        var b = abs(rhs)
        while b != 0 {
            let next = a % b
            a = b
            b = next
        }
        return max(a, 1)
    }

    private static func numberLabel(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let rounded = (value * 10).rounded() / 10
        if abs(rounded.rounded() - rounded) < 0.0001 {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.1f", rounded)
    }
}
