import Testing
@testable import VaniScriptCore

@Suite("Universal metadata extraction")
struct MetadataExtractionTests {
    @Test("extracts date lecturer and location from lecture filenames")
    func extractsLectureMetadata() {
        let metadata = MetadataExtractor.extract(fromFileName: "2026-05-22 HH Kadamba Kanana Swami Mayapur Class.mp3")

        #expect(metadata.date == "2026-05-22")
        #expect(metadata.lecturer == "HH Kadamba Kanana Swami")
        #expect(metadata.location == "Mayapur")
        #expect(metadata.participants == "")
    }

    @Test("expands common lecturer abbreviations")
    func expandsLecturerAbbreviations() {
        let metadata = MetadataExtractor.extract(fromFileName: "KKS Vrindavan 20260522.mp4")

        #expect(metadata.date == "20260522")
        #expect(metadata.lecturer == "HH Kadamba Kanana Swami")
        #expect(metadata.location == "Vrindavan")
    }

    @Test("extracts known scripture titles into participants field")
    func extractsKnownScriptureTitles() {
        let metadata = MetadataExtractor.extract(fromFileName: "Srimad Bhagavatam Class HH Kadamba Kanana Swami Mayapur.mp4")

        #expect(metadata.lecturer == "HH Kadamba Kanana Swami")
        #expect(metadata.location == "Mayapur")
        #expect(metadata.participants == "Srimad Bhagavatam")
    }

    @Test("extracts scripture abbreviations and preserves verse dots in title")
    func extractsScriptureAbbreviationsAndPreservesVerseDots() {
        let metadata = MetadataExtractor.extract(fromFileName: "ŚB 3.4.16  HH Kadamba Kanana Swami")

        #expect(metadata.lecturer == "HH Kadamba Kanana Swami")
        #expect(metadata.participants == "Srimad Bhagavatam")
    }

    @Test("extracts metadata from transcript cues and cleans them")
    func extractsMetadataFromCues() {
        var session = SessionState(
            sourceFile: "/path/to/media.mp3",
            sourceFileName: "media.mp3",
            durationSec: 10.0,
            metadata: AudioMetadata(date: "None", location: "None", lecturer: "None", participants: "None"),
            sourceLang: "en",
            targetLang: "ru",
            transcriptionProvider: "local",
            translationProvider: "none",
            outputFormats: [.txt],
            chunks: [
                ChunkData(
                    index: 0,
                    filePath: "/path/to/chunk.wav",
                    durationSec: 10.0,
                    startSec: 0.0,
                    endSec: 10.0,
                    original: "Date: 2020\nLocation: Mayapur\nLecturer: HH Kadamba Kanana Swami\n[00:00] Haribol.",
                    translated: "Дата: 2020\nМесто: Маяпур\nЛектор: Е.С. Кадамба Канана Свами\nХарибол.",
                    originalCues: [
                        TranscriptCue(
                            startSec: 0.0,
                            endSec: 5.0,
                            text: "Date: 2020\nLocation: Mayapur"
                        ),
                        TranscriptCue(
                            startSec: 5.0,
                            endSec: 7.0,
                            text: "Lecturer: HH Kadamba Kanana Swami"
                        ),
                        TranscriptCue(
                            startSec: 7.0,
                            endSec: 10.0,
                            text: "Haribol."
                        )
                    ],
                    translationsByLanguage: [
                        "russian": TranslationVariant(
                            language: "Russian",
                            text: "Дата: 2020\nМесто: Маяпур\nЛектор: Е.С. Кадамба Канана Свами\nХарибол.",
                            cues: [
                                TranscriptCue(
                                    startSec: 0.0,
                                    endSec: 5.0,
                                    text: "Дата: 2020\nМесто: Маяпур"
                                ),
                                TranscriptCue(
                                    startSec: 5.0,
                                    endSec: 7.0,
                                    text: "Лектор: Е.С. Кадамба Канана Свами"
                                ),
                                TranscriptCue(
                                    startSec: 7.0,
                                    endSec: 10.0,
                                    text: "Харибол."
                                )
                            ]
                        )
                    ],
                    status: .done,
                    approved: false
                )
            ],
            currentChunkIndex: 0
        )

        session.normalizeTranslationArchive()

        // Check session metadata is extracted
        #expect(session.metadata.date == "2020")
        #expect(session.metadata.location == "Mayapur")
        #expect(session.metadata.lecturer == "HH Kadamba Kanana Swami")

        // Check first chunk is cleaned
        #expect(session.chunks[0].original == "Haribol.")
        #expect(session.chunks[0].originalCues?.count == 1)
        #expect(session.chunks[0].originalCues?[0].text == "Haribol.")

        // Check translations are cleaned
        let rus = session.chunks[0].translationVariant(for: "Russian")
        #expect(rus?.text == "Харибол.")
        #expect(rus?.cues?.count == 1)
        #expect(rus?.cues?[0].text == "Харибол.")
    }

    @Test("extracts metadata with timestamp prefixes and cleans them")
    func extractsMetadataWithTimestampPrefixes() {
        var session = SessionState(
            sourceFile: "/path/to/media.mp3",
            sourceFileName: "media.mp3",
            durationSec: 10.0,
            metadata: AudioMetadata(date: "None", location: "None", lecturer: "None", participants: "None"),
            sourceLang: "en",
            targetLang: "ru",
            transcriptionProvider: "local",
            translationProvider: "none",
            outputFormats: [.txt],
            chunks: [
                ChunkData(
                    index: 0,
                    filePath: "/path/to/chunk.wav",
                    durationSec: 10.0,
                    startSec: 0.0,
                    endSec: 10.0,
                    original: "[00:00] Date: 2020\n[00:00] Location: Mayapur\n[00:00] Lecturer: HH Kadamba Kanana Swami\n[00:00] Haribol.",
                    translated: "[00:00] Дата: 2020\n[00:00] Место: Маяпур\n[00:00] Лектор: Е.С. Кадамба Канана Свами\n[00:00] Харибол.",
                    originalCues: nil,
                    translationsByLanguage: [
                        "russian": TranslationVariant(
                            language: "Russian",
                            text: "[00:00] Дата: 2020\n[00:00] Место: Маяпур\n[00:00] Лектор: Е.С. Кадамба Канана Свами\n[00:00] Харибол.",
                            cues: nil
                        )
                    ],
                    status: .pending,
                    approved: false
                )
            ],
            currentChunkIndex: 0
        )

        session.normalizeTranslationArchive()

        // Check session metadata is extracted
        #expect(session.metadata.date == "2020")
        #expect(session.metadata.location == "Mayapur")
        #expect(session.metadata.lecturer == "HH Kadamba Kanana Swami")

        // Check first chunk is cleaned
        #expect(session.chunks[0].original == "Haribol.")
        #expect(session.chunks[0].originalCues?.count == 1)
        #expect(session.chunks[0].originalCues?[0].text == "Haribol.")

        // Check translations are cleaned
        let rus = session.chunks[0].translationVariant(for: "Russian")
        #expect(rus?.text == "Харибол.")
        #expect(rus?.cues?.count == 1)
        #expect(rus?.cues?[0].text == "Харибол.")
    }
}
