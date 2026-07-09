import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Universal project archive")
struct ProjectArchiveTests {
    @Test("builds project summaries from saved sessions")
    func buildsProjectSummary() {
        let record = ProjectRecord(
            id: "project-1",
            createdAt: "2026-05-25T10:00:00Z",
            updatedAt: "2026-05-25T10:05:00Z",
            session: makeSession(approved: true)
        )

        let summary = record.summary

        #expect(summary.id == "project-1")
        #expect(summary.name == "lecture")
        #expect(summary.sourceFileName == "lecture.mp3")
        #expect(summary.currentIndex == 0)
        #expect(summary.totalChunks == 2)
        #expect(summary.approvedChunks == 1)
        #expect(summary.completedChunks == 1)
        #expect(summary.targetLang == "Russian")
    }

    @Test("opens every chunk in a fully approved saved project")
    func opensEveryChunkInFullyApprovedProject() {
        var session = makeSession(approved: false)
        session.currentChunkIndex = 1
        for index in session.chunks.indices {
            session.chunks[index].status = .done
            session.chunks[index].approved = true
        }
        let record = ProjectRecord(
            id: "project-approved",
            createdAt: "2026-06-27T10:00:00Z",
            updatedAt: "2026-06-27T10:05:00Z",
            session: session
        )

        let summary = record.summary

        #expect(summary.totalChunks == 2)
        #expect(summary.approvedChunks == 2)
        #expect(summary.completedChunks == 2)
        #expect(summary.canOpenChunk(at: 0))
        #expect(summary.canOpenChunk(at: 1))
        #expect(!summary.canOpenChunk(at: 2))
        #expect(summary.lastWorkInProgressChunkIndex == nil)
        #expect(!summary.shouldShowLastBadge(at: 0))
        #expect(!summary.shouldShowLastBadge(at: 1))
    }

    @Test("keeps future pending chunks locked during sequential processing")
    func keepsFuturePendingChunksLocked() {
        var session = makeSession(approved: false)
        session.currentChunkIndex = 0
        session.chunks[0].status = .done
        session.chunks[1].status = .pending
        let record = ProjectRecord(
            id: "project-pending",
            createdAt: "2026-06-27T10:00:00Z",
            updatedAt: "2026-06-27T10:05:00Z",
            session: session
        )

        let summary = record.summary

        #expect(summary.completedChunks == 1)
        #expect(summary.canOpenChunk(at: 0))
        #expect(!summary.canOpenChunk(at: 1))
        #expect(summary.lastWorkInProgressChunkIndex == 0)
        #expect(summary.shouldShowLastBadge(at: 0))
        #expect(!summary.shouldShowLastBadge(at: 1))
    }

    @Test("marks the last generated chunk while review is still in progress")
    func marksLastGeneratedChunkWhileReviewIsStillInProgress() {
        var session = makeSession(approved: false)
        session.currentChunkIndex = 0
        for index in session.chunks.indices {
            session.chunks[index].status = .done
            session.chunks[index].approved = false
        }
        let record = ProjectRecord(
            id: "project-generated",
            createdAt: "2026-06-27T10:00:00Z",
            updatedAt: "2026-06-27T10:05:00Z",
            session: session
        )

        let summary = record.summary

        #expect(summary.completedChunks == 2)
        #expect(summary.approvedChunks == 0)
        #expect(summary.lastWorkInProgressChunkIndex == 1)
        #expect(!summary.shouldShowLastBadge(at: 0))
        #expect(summary.shouldShowLastBadge(at: 1))
    }

    @Test("round trips project records through JSON")
    func roundTripsJSON() throws {
        let records = [
            ProjectRecord(
                id: "project-1",
                createdAt: "2026-05-25T10:00:00Z",
                updatedAt: "2026-05-25T10:05:00Z",
                session: makeSession(approved: false)
            )
        ]

        let data = try ProjectArchive.encode(records)
        let decoded = try ProjectArchive.decode(data)
        let expected = records.map { record in
            var copy = record
            copy.session.normalizeTranslationArchive()
            return copy
        }

        #expect(decoded == expected)
    }

    @Test("preserves source media information in session archive and summary")
    func preservesSourceMediaInformation() throws {
        var session = makeSession(approved: false)
        session.sourceMediaInfo = SourceMediaInfo(
            originalURL: "https://www.youtube.com/watch?v=abc123",
            filePath: "/Users/pavan/Imports/lecture_abc123.mp4",
            fileName: "lecture_abc123.mp4",
            title: "Lecture Title",
            kind: .video,
            durationSec: 508.0,
            fileSizeBytes: 734_003_200,
            width: 3840,
            height: 2160,
            frameRate: 25,
            videoCodec: "avc1",
            audioCodec: "mp4a",
            container: "mp4",
            importedAt: "2026-06-27T10:00:00Z"
        )
        let record = ProjectRecord(id: "media-info-project", createdAt: "", updatedAt: "", session: session)

        let decoded = try ProjectArchive.decode(try ProjectArchive.encode([record]))
        let mediaInfo = try #require(decoded.first?.session.sourceMediaInfo)

        #expect(mediaInfo.originalURL == "https://www.youtube.com/watch?v=abc123")
        #expect(mediaInfo.filePath == "/Users/pavan/Imports/lecture_abc123.mp4")
        #expect(mediaInfo.fileName == "lecture_abc123.mp4")
        #expect(mediaInfo.title == "Lecture Title")
        #expect(mediaInfo.kind == .video)
        #expect(mediaInfo.width == 3840)
        #expect(mediaInfo.height == 2160)
        #expect(decoded.first?.summary.sourceMediaInfo == mediaInfo)
    }

    @Test("migrates legacy single translation into the language archive")
    func migratesLegacySingleTranslation() throws {
        let legacyJSON = """
        [
          {
            "id": "project-legacy",
            "createdAt": "2026-05-25T10:00:00Z",
            "updatedAt": "2026-05-25T10:05:00Z",
            "session": {
              "sourceFile": "/tmp/lecture.mp3",
              "sourceFileName": "lecture.mp3",
              "durationSec": 60,
              "metadata": {
                "date": "2026-05-25",
                "location": "Mayapur",
                "lecturer": "HH Kadamba Kanana Swami",
                "participants": ""
              },
              "sourceLang": "auto",
              "targetLang": "Russian",
              "transcriptionProvider": "coreml-whisperkit",
              "translationProvider": "mlx-native",
              "outputFormats": ["TXT"],
              "chunks": [
                {
                  "index": 0,
                  "filePath": "/tmp/lecture.mp3",
                  "durationSec": 60,
                  "startSec": 0,
                  "endSec": 60,
                  "original": "One",
                  "translated": "Один",
                  "originalFormats": null,
                  "translatedFormats": null,
                  "unrecognizedFragments": [],
                  "status": "done",
                  "approved": true
                }
              ],
              "currentChunkIndex": 0
            }
          }
        ]
        """

        let decoded = try ProjectArchive.decode(Data(legacyJSON.utf8))
        let session = try #require(decoded.first?.session)

        #expect(session.activeTranslationLanguage == "Russian")
        #expect(session.availableTranslationLanguages == ["Russian"])
        #expect(session.chunks[0].translationText(for: "Russian") == "Один")
    }

    @Test("sorts recent projects first")
    func sortsRecentProjectsFirst() {
        let older = ProjectRecord(id: "older", createdAt: "2026-05-24T10:00:00Z", updatedAt: "2026-05-24T10:00:00Z", session: makeSession(approved: false))
        let newer = ProjectRecord(id: "newer", createdAt: "2026-05-25T10:00:00Z", updatedAt: "2026-05-25T10:00:00Z", session: makeSession(approved: false))

        #expect(ProjectArchive.sortedRecent([older, newer]).map(\.id) == ["newer", "older"])
    }

    @Test("round trips word timings in transcript cues")
    func roundTripsWordTimingsInTranscriptCues() throws {
        var session = makeSession(approved: false)
        session.chunks[0].originalCues = [
            TranscriptCue(
                startSec: 0,
                endSec: 2,
                text: "Hare Krishna",
                words: [
                    TranscriptWord(startSec: 0, endSec: 0.7, text: "Hare"),
                    TranscriptWord(startSec: 0.7, endSec: 1.5, text: "Krishna"),
                ]
            )
        ]
        let record = ProjectRecord(id: "word-project", createdAt: "", updatedAt: "", session: session)

        let decoded = try ProjectArchive.decode(try ProjectArchive.encode([record]))

        #expect(decoded[0].session.chunks[0].originalCues?.first?.words?.map(\.text) == ["Hare", "Krishna"])
    }

    @Test("automatically reconstructs missing cues and word timings from raw text when normalized")
    func reconstructsCuesAndWords() throws {
        var session = makeSession(approved: false)
        session.chunks[0].originalCues = nil
        session.chunks[0].original = "Hello world. This is a test."

        session.normalizeTranslationArchive()

        let cues = try #require(session.chunks[0].originalCues)
        #expect(cues.count == 2)
        #expect(cues[0].text == "Hello world.")
        #expect(cues[1].text == "This is a test.")

        let words = try #require(cues[0].words)
        #expect(words.count == 2)
        #expect(words[0].text == "Hello")
        #expect(words[1].text == "world.")
        #expect(words[0].startSec >= 0)
        #expect(words[0].endSec > words[0].startSec)
        #expect(words[1].startSec >= words[0].endSec)
    }

    @Test("normalizes language codes to full capitalized display names on normalization")
    func normalizesLanguageCodes() throws {
        var session = makeSession(approved: false)
        session.targetLang = "ru"
        session.chunks[0].translated = "Привет мир."

        session.normalizeTranslationArchive()

        #expect(session.targetLang == "Russian")
        #expect(session.availableTranslationLanguages == ["Russian"])
        #expect(session.chunks[0].translationVariant(for: "Russian")?.text == "Привет мир.")

        let cues = session.chunks[0].translationCues(for: "Russian")
        #expect(cues.count == 1)
        #expect(cues[0].text == "Привет мир.")
    }

    @Test("parses inline timestamp markers into cues and strips them from text")
    func parsesTimestampMarkersIntoCues() throws {
        var session = makeSession(approved: false)
        session.chunks[0].originalCues = nil
        session.chunks[0].original = "[00:03] First line.\n\n[00:06] Second line."

        session.normalizeTranslationArchive()

        let cues = try #require(session.chunks[0].originalCues)
        #expect(cues.count == 2)
        #expect(cues[0].startSec == 3)
        #expect(cues[0].endSec == 6)
        #expect(cues[0].text == "First line.")
        #expect(cues[1].startSec == 6)
        #expect(cues[1].text == "Second line.")
        // Markers stripped so they don't render as literal text.
        #expect(!session.chunks[0].original.contains("["))
        #expect(session.chunks[0].original.contains("First line."))
        #expect(session.chunks[0].original.contains("Second line."))
    }

    @Test("offsets chunk-relative timestamps to absolute session time")
    func offsetsRelativeTimestamps() {
        // Markers relative to the chunk start (Electron-style), in a chunk that
        // starts at 600s. Mirrors src/lib/karaoke.ts shouldOffsetRelativeTimestamps.
        let cues = SessionState.reconstructCuesFromTimestampedText(
            "[00:02] Hello.\n\n[00:05] World.",
            startSec: 600,
            endSec: 660
        )
        #expect(cues.count == 2)
        #expect(cues[0].startSec == 602)
        #expect(cues[1].startSec == 605)
    }

    @Test("strips inline timestamp markers without dropping surrounding text")
    func stripsTimestampMarkers() {
        let cleaned = SessionState.strippingInlineTimestampMarkers("[00:03] First.\n\n[00:06] Second.")
        #expect(!cleaned.contains("["))
        #expect(cleaned.contains("First."))
        #expect(cleaned.contains("Second."))
    }

    private func makeSession(approved: Bool) -> SessionState {
        SessionState(
            sourceFile: "/tmp/lecture.mp3",
            sourceFileName: "lecture.mp3",
            durationSec: 120,
            metadata: AudioMetadata(date: "2026-05-25", location: "Mayapur", lecturer: "HH Kadamba Kanana Swami", participants: ""),
            sourceLang: "auto",
            targetLang: "Russian",
            transcriptionProvider: "coreml-whisperkit",
            translationProvider: "mlx-native",
            outputFormats: [.txt],
            chunks: [
                ChunkData(index: 0, filePath: "/tmp/lecture.mp3", durationSec: 60, startSec: 0, endSec: 60, original: "One", translated: "Один", originalFormats: nil, translatedFormats: nil, unrecognizedFragments: [], status: .done, approved: approved),
                ChunkData(index: 1, filePath: "/tmp/lecture.mp3", durationSec: 60, startSec: 60, endSec: 120, original: "Two", translated: "Два", originalFormats: nil, translatedFormats: nil, unrecognizedFragments: [], status: .pending, approved: false),
            ],
            currentChunkIndex: 0
        )
    }
}
