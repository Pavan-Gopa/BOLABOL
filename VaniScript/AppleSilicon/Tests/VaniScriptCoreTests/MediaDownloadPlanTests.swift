import Testing
@testable import VaniScriptCore

@Suite("Native media download plan")
struct MediaDownloadPlanTests {
    @Test("builds maximum quality H264 MP4 YouTube strategy before HLS fallback")
    func buildsYouTubeStrategies() {
        let strategies = MediaDownloadPlan.strategies(
            for: "https://www.youtube.com/watch?v=hROZyZHw9NI",
            ffmpegPath: "/App/Contents/Resources/bin/ffmpeg",
            outputTemplate: "/Imports/%(title).180B_%(id)s.%(ext)s"
        )

        #expect(strategies.map(\.key) == ["youtube-h264", "youtube-hls"])
        #expect(strategies[0].args.contains("--ffmpeg-location"))
        #expect(strategies[0].args.contains("/App/Contents/Resources/bin/ffmpeg"))
        #expect(strategies[0].args.contains("bv*[vcodec^=avc1]+ba[acodec^=mp4a]/bv*+ba/b"))
        #expect(strategies[0].args.contains("--merge-output-format"))
        #expect(strategies[0].args.contains("mp4"))
        #expect(strategies[0].args.contains("--no-simulate"))
        #expect(strategies[0].args.contains("--print"))
        #expect(strategies[0].args.contains("VANISCRIPT_TITLE:%(title)s"))
        #expect(strategies[0].args.contains("after_move:VANISCRIPT_FILEPATH:%(filepath)s"))
        #expect(strategies[0].args.contains("--progress-template"))
        #expect(strategies[0].args.contains(MediaDownloadPlan.progressTemplate))
        #expect(strategies[0].args.contains("/Imports/%(title).180B_%(id)s.%(ext)s"))
    }

    @Test("builds best audio extraction strategy for SoundCloud")
    func buildsSoundCloudStrategy() {
        let strategies = MediaDownloadPlan.strategies(
            for: "https://soundcloud.com/example/track",
            ffmpegPath: "/App/Contents/Resources/bin/ffmpeg",
            outputTemplate: "/Imports/%(title).180B_%(id)s.%(ext)s"
        )

        #expect(strategies.map(\.key) == ["audio"])
        #expect(strategies[0].args.contains("ba/b"))
        #expect(strategies[0].args.contains("-x"))
        #expect(strategies[0].args.contains("--audio-format"))
        #expect(strategies[0].args.contains("mp3"))
        #expect(strategies[0].args.contains("--audio-quality"))
        #expect(strategies[0].args.contains("0"))
    }

    @Test("adds optional JavaScript runtime args to YouTube strategies")
    func addsJavaScriptRuntimeArgsToYouTubeStrategies() {
        let strategies = MediaDownloadPlan.strategies(
            for: "https://youtu.be/hROZyZHw9NI",
            ffmpegPath: "/App/Contents/Resources/bin/ffmpeg",
            outputTemplate: "/Imports/%(title).180B_%(id)s.%(ext)s",
            javaScriptRuntimeArgs: ["--js-runtimes", "deno:/opt/homebrew/bin/deno"]
        )

        #expect(strategies[0].args.contains("--js-runtimes"))
        #expect(strategies[0].args.contains("deno:/opt/homebrew/bin/deno"))
        #expect(strategies[1].args.contains("--js-runtimes"))
        #expect(strategies[1].args.contains("deno:/opt/homebrew/bin/deno"))
    }

    @Test("parses yt-dlp progress template lines")
    func parsesProgressTemplateLines() {
        let progress = MediaDownloadProgress.parse(" 42.7%|3.1MiB/s|00:12")

        #expect(progress?.fraction == 0.427)
        #expect(progress?.speed == "3.1MiB/s")
        #expect(progress?.eta == "00:12")
    }

    @Test("ignores non progress stdout lines")
    func ignoresNonProgressLines() {
        #expect(MediaDownloadProgress.parse("[download] Destination: lecture.mp4") == nil)
        #expect(MediaDownloadProgress.parse("/Users/pavan/Imports/lecture.mp4") == nil)
    }
}
