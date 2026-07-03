import Testing
@testable import VaniScriptCore

@Suite("Universal transcript export")
struct TranscriptExportBuilderTests {
    @Test("builds text export with metadata and ranges")
    func buildsTextExport() {
        let session = makeSession()

        let text = TranscriptExportBuilder.build(side: .original, format: .txt, session: session)

        #expect(text.contains("Source: lecture.mp3"))
        #expect(text.contains("[00:00:00-00:01:00]"))
        #expect(text.contains("Original text"))
    }

    @Test("builds subtitle timestamps")
    func buildsSubtitleExport() {
        let session = makeSession()

        let srt = TranscriptExportBuilder.build(side: .translated, format: .srt, session: session)
        let vtt = TranscriptExportBuilder.build(side: .translated, format: .vtt, session: session)

        #expect(srt.contains("00:00:00,000 --> 00:01:00,000"))
        #expect(srt.contains("Перевод"))
        #expect(vtt.hasPrefix("WEBVTT"))
        #expect(vtt.contains("00:00:00.000 --> 00:01:00.000"))
    }

    @Test("exports a selected archived translation language")
    func exportsSelectedArchivedTranslationLanguage() {
        var session = makeSession()
        session.chunks[0].setTranslation("Deutsche Übersetzung", language: "German")
        session.setActiveTranslationLanguage("German")

        let srt = TranscriptExportBuilder.build(side: .translated, format: .srt, session: session, language: "German")
        let name = TranscriptExportBuilder.defaultFileName(side: .translated, format: .srt, session: session, language: "German")

        #expect(srt.contains("Deutsche Übersetzung"))
        #expect(!srt.contains("Перевод"))
        #expect(name.hasSuffix("_german.srt"))
    }

    @Test("does not export MLX failure text as translation")
    func doesNotExportMLXFailureTextAsTranslation() {
        var session = makeSession()
        session.chunks[0].translated = "MLX translation failed: MLX returned no usable translation text."

        let text = TranscriptExportBuilder.build(side: .translated, format: .txt, session: session)

        #expect(!text.contains("MLX translation failed"))
    }

    @Test("exports timed cue subtitles when available")
    func exportsTimedCueSubtitlesWhenAvailable() {
        var session = makeSession()
        session.chunks[0].originalCues = [
            TranscriptCue(startSec: 0, endSec: 2.5, text: "First cue"),
            TranscriptCue(startSec: 2.5, endSec: 5, text: "Second cue"),
        ]
        session.chunks[0].setTranslation(
            "Первая строка\nВторая строка",
            language: "Russian",
            cues: [
                TranscriptCue(startSec: 0, endSec: 2.5, text: "Первая строка"),
                TranscriptCue(startSec: 2.5, endSec: 5, text: "Вторая строка"),
            ]
        )
        session.setActiveTranslationLanguage("Russian")

        let original = TranscriptExportBuilder.build(side: .original, format: .srt, session: session)
        let translated = TranscriptExportBuilder.build(side: .translated, format: .srt, session: session)

        #expect(original.contains("00:00:00,000 --> 00:00:02,500\nFirst cue"))
        #expect(original.contains("00:00:02,500 --> 00:00:05,000\nSecond cue"))
        #expect(translated.contains("00:00:00,000 --> 00:00:02,500\nПервая строка"))
        #expect(translated.contains("00:00:02,500 --> 00:00:05,000\nВторая строка"))
    }

    private func makeSession() -> SessionState {
        SessionState(
            sourceFile: "/tmp/lecture.mp3",
            sourceFileName: "lecture.mp3",
            durationSec: 60,
            metadata: AudioMetadata(date: "2026-05-22", location: "Mayapur", lecturer: "HH Kadamba Kanana Swami", participants: ""),
            sourceLang: "auto",
            targetLang: "Russian",
            transcriptionProvider: "coreml-whisperkit",
            translationProvider: "mlx-native",
            outputFormats: [.txt, .srt, .vtt, .markdown],
            chunks: [
                ChunkData(
                    index: 0,
                    filePath: "/tmp/lecture.mp3",
                    durationSec: 60,
                    startSec: 0,
                    endSec: 60,
                    original: "Original text",
                    translated: "Перевод",
                    originalFormats: nil,
                    translatedFormats: nil,
                    unrecognizedFragments: [],
                    status: .done,
                    approved: true
                )
            ],
            currentChunkIndex: 0
        )
    }
}
