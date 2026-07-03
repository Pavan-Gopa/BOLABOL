import Testing
@testable import VaniScriptCore

@Suite("Universal media source")
struct MediaSourceTests {
    @Test("classifies audio and video paths")
    func classifiesMediaPaths() {
        #expect(MediaSource.kind(forPath: "lecture.mp3") == .audio)
        #expect(MediaSource.kind(forPath: "lecture.MOV") == .video)
        #expect(MediaSource.kind(forPath: "lecture.txt") == .unknown)
    }

    @Test("accepts app-store safe direct media urls")
    func acceptsDirectMediaURLs() {
        #expect(MediaSource.directMediaURL(from: "https://example.com/lecture.mp3")?.absoluteString == "https://example.com/lecture.mp3")
        #expect(MediaSource.directMediaURL(from: "javascript:alert(1)") == nil)
        #expect(MediaSource.directMediaURL(from: "https://example.com/page") == nil)
    }

    @Test("recognizes supported web media page urls separately from direct files")
    func recognizesWebMediaPageURLs() {
        #expect(MediaSource.isWebVideoOrAudioLink("https://www.youtube.com/watch?v=hROZyZHw9NI"))
        #expect(MediaSource.isWebVideoOrAudioLink("https://youtu.be/hROZyZHw9NI"))
        #expect(MediaSource.isWebVideoOrAudioLink("https://soundcloud.com/example/track"))
        #expect(!MediaSource.isWebVideoOrAudioLink("https://example.com/watch?v=hROZyZHw9NI"))
    }

    @Test("formats technical media details without repeating file path as title")
    func formatsTechnicalMediaDetails() {
        let info = SourceMediaInfo(
            originalURL: "https://youtube.com/watch?v=abc",
            filePath: "/Users/pavan/Library/Application Support/VaniScript/Imports/lecture_abc.mp4",
            fileName: "lecture_abc.mp4",
            title: "Lecture",
            kind: .video,
            durationSec: 2662,
            fileSizeBytes: 1_048_576_000,
            width: 3840,
            height: 2160,
            frameRate: 25,
            videoCodec: "avc1",
            audioCodec: "mp4a",
            container: "mp4",
            writingApplication: "Lavf62.12.101",
            overallBitrateBps: 3_151_996,
            videoBitrateBps: 3_000_000,
            audioBitrateBps: 151_996,
            audioSampleRateHz: 48_000,
            audioChannelCount: 2
        )

        let details = info.mediaInfoLines().joined(separator: "\n")

        #expect(details.contains("Title: Lecture"))
        #expect(details.contains("General"))
        #expect(details.contains("MPEG-4 (Base Media):"))
        #expect(details.contains("Overall bitrate: 3.2 Mbps"))
        #expect(details.contains("Writing application: Lavf62.12.101"))
        #expect(details.contains("1 Video stream: AVC"))
        #expect(details.contains("1 Audio stream: AAC LC"))
        #expect(details.contains("Video"))
        #expect(details.contains("3 Mbps, 3840x2160 (16:9), at 25.000 FPS, AVC"))
        #expect(details.contains("Quality: 4K"))
        #expect(details.contains("Resolution: 3840x2160"))
        #expect(details.contains("Frame rate: 25.000 fps"))
        #expect(details.contains("Video bitrate: 3 Mbps"))
        #expect(details.contains("Audio"))
        #expect(details.contains("152 kbps, 48 kHz, stereo (2), AAC LC"))
        #expect(details.contains("Audio bitrate: 152 kbps"))
        #expect(details.contains("Sample rate: 48 kHz"))
        #expect(details.contains("Channels: Stereo (2)"))
        #expect(!details.contains("Path:"))
        #expect(!details.contains("/Users/pavan/Library/Application Support"))
    }
}
