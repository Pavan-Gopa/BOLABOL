import Foundation

public struct MediaDownloadStrategy: Equatable, Sendable {
    public let key: String
    public let label: String
    public let args: [String]
    public let resolveMessage: String

    public init(key: String, label: String, args: [String], resolveMessage: String) {
        self.key = key
        self.label = label
        self.args = args
        self.resolveMessage = resolveMessage
    }
}

public struct MediaDownloadProgress: Equatable, Sendable {
    public let fraction: Double
    public let speed: String?
    public let eta: String?

    public static func parse(_ line: String) -> MediaDownloadProgress? {
        let fields = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        guard fields.count == 3,
              let percentText = fields.first?.replacingOccurrences(of: "%", with: ""),
              let percent = Double(percentText) else {
            return nil
        }

        let normalized = max(0.0, min(1.0, percent / 100.0))
        let rounded = (normalized * 1000).rounded() / 1000
        return MediaDownloadProgress(
            fraction: rounded,
            speed: fields[1].isEmpty ? nil : fields[1],
            eta: fields[2].isEmpty ? nil : fields[2]
        )
    }
}

public enum MediaDownloadPlan {
    public static let progressTemplate = "%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s"

    public static func outputTemplate(importsDirectoryPath: String) -> String {
        "\(importsDirectoryPath)/%(title).180B_%(id)s.%(ext)s"
    }

    public static func strategies(
        for rawURL: String,
        ffmpegPath: String,
        outputTemplate: String,
        javaScriptRuntimeArgs: [String] = [],
        audioOnly: Bool = false
    ) -> [MediaDownloadStrategy] {
        let baseArgs = [
            "--no-playlist",
            "--newline",
            "--progress",
            "--no-warnings",
            "--force-ipv4",
            "--concurrent-fragments",
            "12",
            "--throttled-rate",
            "250K",
            "--retries",
            "3",
            "--fragment-retries",
            "3",
            "--extractor-retries",
            "3",
            "--socket-timeout",
            "30",
            "--progress-template",
            progressTemplate,
            "--ffmpeg-location",
            ffmpegPath,
            "--no-simulate",
            "--print",
            "VANISCRIPT_TITLE:%(title)s",
            "--print",
            "after_move:VANISCRIPT_FILEPATH:%(filepath)s",
            "-o",
            outputTemplate,
        ]

        if audioOnly || isSoundCloudURL(rawURL) {
            return [
                MediaDownloadStrategy(
                    key: "audio",
                    label: "best audio stream",
                    args: baseArgs + ["-f", "ba/b", "-x", "--audio-format", "mp3", "--audio-quality", "0"],
                    resolveMessage: "Resolving best audio stream..."
                )
            ]
        }

        return [
            MediaDownloadStrategy(
                key: "youtube-h264",
                label: "maximum-quality H.264 MP4 video stream",
                args: baseArgs + javaScriptRuntimeArgs + [
                    "-f",
                    "bv*[vcodec^=avc1]+ba[acodec^=mp4a]/bv*+ba/b",
                    "--merge-output-format",
                    "mp4",
                ],
                resolveMessage: "Resolving maximum-quality H.264 MP4 video stream..."
            ),
            MediaDownloadStrategy(
                key: "youtube-hls",
                label: "maximum-quality HLS video stream",
                args: baseArgs + javaScriptRuntimeArgs + [
                    "-f",
                    "bestvideo[protocol^=m3u8]+bestaudio[protocol^=m3u8]/best[protocol^=m3u8]/bv*+ba/b",
                    "--merge-output-format",
                    "mp4",
                ],
                resolveMessage: "Resolving maximum-quality HLS video stream..."
            ),
        ]
    }

    private static func isSoundCloudURL(_ rawURL: String) -> Bool {
        guard let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased() else {
            return false
        }
        return host == "soundcloud.com" || host.hasSuffix(".soundcloud.com")
    }
}
