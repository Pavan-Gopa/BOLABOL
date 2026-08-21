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

    @Test("timestamp markers with equal out-of-order and oversized values produce bounded monotonic renderable cues")
    func reconstructsBoundedMonotonicCuesFromNoisyMarkers() throws {
        // Equal markers:
        let equalCues = SessionState.reconstructCuesFromTimestampedText(
            "[01:40] First sentence.\n\n[01:40] Second sentence.\n\n[02:00] Third sentence.",
            startSec: 0,
            endSec: 180
        )
        #expect(equalCues.map(\.text) == ["First sentence.", "Second sentence.", "Third sentence."])
        #expect(equalCues[0].startSec == 100)
        #expect(equalCues[0].endSec == 100)
        #expect(equalCues[1].startSec == 100)
        #expect(equalCues[1].endSec == 120)
        #expect(equalCues[2].startSec == 120)
        #expect(equalCues[2].endSec == 180)
        let equalValidation = BatchTimedTextRenderer.validate(duration: 180, cues: equalCues)
        #expect(equalValidation.isValid)
        let equalRendered = try BatchTimedTextRenderer.render(duration: 180, cues: equalCues)
        #expect(equalRendered.contains("First sentence."))
        #expect(equalRendered.contains("Second sentence."))
        #expect(equalRendered.contains("Third sentence."))

        // Out-of-order markers:
        let outOfOrderCues = SessionState.reconstructCuesFromTimestampedText(
            "[01:00] First segment.\n\n[00:30] Second segment.\n\n[01:30] Third segment.",
            startSec: 0,
            endSec: 120
        )
        #expect(outOfOrderCues.map(\.text) == ["First segment.", "Second segment.", "Third segment."])
        #expect(outOfOrderCues[0].startSec == 60)
        #expect(outOfOrderCues[0].endSec == 60)
        #expect(outOfOrderCues[1].startSec == 60)
        #expect(outOfOrderCues[1].endSec == 90)
        #expect(outOfOrderCues[2].startSec == 90)
        #expect(outOfOrderCues[2].endSec == 120)
        let outOfOrderValidation = BatchTimedTextRenderer.validate(duration: 120, cues: outOfOrderCues)
        #expect(outOfOrderValidation.isValid)
        let outOfOrderRendered = try BatchTimedTextRenderer.render(duration: 120, cues: outOfOrderCues)
        #expect(outOfOrderRendered.contains("First segment."))
        #expect(outOfOrderRendered.contains("Second segment."))
        #expect(outOfOrderRendered.contains("Third segment."))

        // Relative and oversized markers in later chunk (Candidate 9 failure shape 2):
        let laterChunkCues = SessionState.reconstructCuesFromTimestampedText(
            "[04:55] Alpha chunk.\n\n[04:55] Beta chunk.\n\n[05:45] Gamma chunk.",
            startSec: 1800,
            endSec: 2100
        )
        #expect(laterChunkCues.map(\.text) == ["Alpha chunk.", "Beta chunk.", "Gamma chunk."])
        #expect(laterChunkCues[0].startSec == 2095)
        #expect(laterChunkCues[0].endSec == 2095)
        #expect(laterChunkCues[1].startSec == 2095)
        #expect(laterChunkCues[1].endSec == 2100)
        #expect(laterChunkCues[2].startSec == 2100)
        #expect(laterChunkCues[2].endSec == 2100)
        let laterValidation = BatchTimedTextRenderer.validate(duration: 2100, cues: laterChunkCues)
        #expect(laterValidation.isValid)
        let laterRendered = try BatchTimedTextRenderer.render(duration: 2100, cues: laterChunkCues)
        #expect(laterRendered.contains("Alpha chunk."))
        #expect(laterRendered.contains("Beta chunk."))
        #expect(laterRendered.contains("Gamma chunk."))
    }

    @Test("strips inline timestamp markers without dropping surrounding text")
    func stripsTimestampMarkers() {
        let cleaned = SessionState.strippingInlineTimestampMarkers("[00:03] First.\n\n[00:06] Second.")
        #expect(!cleaned.contains("["))
        #expect(cleaned.contains("First."))
        #expect(cleaned.contains("Second."))
    }

    @Test("persists project display name and prefers it in summary")
    func persistsProjectDisplayName() throws {
        let session = makeSession(approved: true)
        let record = ProjectRecord(
            id: "proj-custom-name",
            name: "My Custom Renamed Project",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: session
        )

        #expect(record.name == "My Custom Renamed Project")
        #expect(record.displayName == "My Custom Renamed Project")
        #expect(record.summary.name == "My Custom Renamed Project")
        #expect(record.summary.sourceFileName == "lecture.mp3")
        #expect(record.session.sourceFileName == "lecture.mp3")

        let encoded = try ProjectArchive.encode([record])
        let decoded = try ProjectArchive.decode(encoded)
        let first = try #require(decoded.first)
        #expect(first.name == "My Custom Renamed Project")
        #expect(first.displayName == "My Custom Renamed Project")
        #expect(first.summary.name == "My Custom Renamed Project")
        #expect(first.summary.sourceFileName == "lecture.mp3")
    }

    @Test("falls back to sourceFileName stem when display name is nil, empty, or whitespace")
    func fallsBackToSourceFileNameStem() throws {
        let session = makeSession(approved: true)
        let nilNameRecord = ProjectRecord(
            id: "proj-nil-name",
            name: nil,
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: session
        )
        #expect(nilNameRecord.name == nil)
        #expect(nilNameRecord.summary.name == "lecture")
        #expect(nilNameRecord.summary.sourceFileName == "lecture.mp3")

        let whitespaceRecord = ProjectRecord(
            id: "proj-ws-name",
            name: "   \n  \t ",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: session
        )
        #expect(whitespaceRecord.name == nil)
        #expect(whitespaceRecord.summary.name == "lecture")

        var namedSourceSession = session
        namedSourceSession.sourceFileName = "MyInterview.wav"
        let namedFallbackRecord = ProjectRecord(
            id: "proj-named-source",
            name: nil,
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: namedSourceSession
        )
        #expect(namedFallbackRecord.summary.name == "MyInterview")
    }

    @Test("decodes backward-compatible displayName field and unifies with name")
    func decodesBackwardCompatibleDisplayName() throws {
        let legacyJSON = """
        {
            "id": "legacy-proj-1",
            "displayName": "Legacy Project Name",
            "createdAt": "2026-08-17T10:00:00Z",
            "updatedAt": "2026-08-17T10:05:00Z",
            "session": {
                "sourceFile": "/tmp/test.mp3",
                "sourceFileName": "test.mp3",
                "durationSec": 10,
                "sourceLang": "en",
                "targetLang": "es",
                "chunks": [],
                "currentChunkIndex": 0
            }
        }
        """
        let data = Data(legacyJSON.utf8)
        let decoded = try ProjectArchive.decode(data)
        let record = try #require(decoded.first)
        #expect(record.name == "Legacy Project Name")
        #expect(record.displayName == "Legacy Project Name")
        #expect(record.summary.name == "Legacy Project Name")
        #expect(record.summary.sourceFileName == "test.mp3")
    }

    @Test("computes deterministic dirty state and deletion policy correctly")
    func computesDirtyStateAndPolicy() {
        let session = makeSession(approved: true)
        var record = ProjectRecord(
            id: "proj-imported-1",
            name: "Original Lecture",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: session,
            originatingArchivePath: "/path/to/archive.vaniscript",
            originatingArchiveIndex: 0
        )
        let baseline = record.computeWorkFingerprint()
        record.importBaselineFingerprint = baseline

        #expect(record.isImported == true)
        #expect(record.isDirty == false)
        #expect(record.deletionPolicy == .cleanImported(archivePath: "/path/to/archive.vaniscript"))

        // Navigation change: currentChunkIndex must NOT cause dirty state
        var navigatingRecord = record
        navigatingRecord.session.currentChunkIndex = 1
        #expect(navigatingRecord.isDirty == false)
        #expect(navigatingRecord.deletionPolicy == .cleanImported(archivePath: "/path/to/archive.vaniscript"))

        // Provider reconciliation: transcriptionProvider / translationProvider must NOT cause dirty state
        var providerRecord = record
        providerRecord.session.transcriptionProvider = "reconciled-provider"
        providerRecord.session.translationProvider = "reconciled-translation"
        #expect(providerRecord.isDirty == false)
        #expect(providerRecord.deletionPolicy == .cleanImported(archivePath: "/path/to/archive.vaniscript"))

        // Meaningful chunk modification causes dirty state
        var dirtyRecord = record
        dirtyRecord.session.chunks[0].translated = "Измененный перевод"
        #expect(dirtyRecord.isDirty == true)
        #expect(dirtyRecord.deletionPolicy == .dirtyImported(archivePath: "/path/to/archive.vaniscript"))

        // Local created project
        let localRecord = ProjectRecord(
            id: "proj-local",
            name: "Local Project",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: session
        )
        #expect(localRecord.isImported == false)
        #expect(localRecord.isDirty == false)
        #expect(localRecord.deletionPolicy == .localCreated)
    }

    @Test("decodes legacy JSON without provenance as local created project")
    func decodesLegacyJSONAsLocalCreated() throws {
        let legacyJSON = """
        {
            "id": "legacy-proj-no-provenance",
            "name": "Legacy Local",
            "createdAt": "2026-08-17T10:00:00Z",
            "updatedAt": "2026-08-17T10:05:00Z",
            "session": {
                "sourceFile": "/tmp/test.mp3",
                "sourceFileName": "test.mp3",
                "durationSec": 10,
                "sourceLang": "en",
                "targetLang": "es",
                "chunks": [],
                "currentChunkIndex": 0
            }
        }
        """
        let data = Data(legacyJSON.utf8)
        let records = try ProjectArchive.decode(data)
        let record = try #require(records.first)
        #expect(record.originatingArchivePath == nil)
        #expect(record.originatingArchiveIndex == nil)
        #expect(record.importBaselineFingerprint == nil)
        #expect(record.isImported == false)
        #expect(record.deletionPolicy == .localCreated)
    }

    @Test("overwrites single project archive safely")
    func overwritesSingleProjectArchive() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptOverwriteSingleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mediaFile = tempDir.appendingPathComponent("test_audio.mp3")
        try Data("audio-bytes".utf8).write(to: mediaFile)

        var initialSession = makeSession(approved: true)
        initialSession.sourceFile = mediaFile.path
        initialSession.chunks[0].filePath = mediaFile.path
        initialSession.chunks[1].filePath = mediaFile.path

        let initialRecord = ProjectRecord(
            id: "orig-proj",
            name: "Initial Version",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: initialSession
        )

        let archiveURL = tempDir.appendingPathComponent("ProjectArchive.vaniscript")
        try ProjectBundleExporter.exportBundle(record: initialRecord, to: archiveURL)

        var modifiedRecord = initialRecord
        modifiedRecord.name = "Updated Version"
        modifiedRecord.session.chunks[0].translated = "Обновленный перевод"

        try ProjectArchive.overwriteArchive(record: modifiedRecord, at: archiveURL)

        let importDir = tempDir.appendingPathComponent("Imported", isDirectory: true)
        let importedRecords = try ProjectBundleImporter.importBundle(fileURL: archiveURL, destinationDirectoryURL: importDir)
        let reloaded = try #require(importedRecords.first)
        #expect(reloaded.name == "Updated Version")
        #expect(reloaded.session.chunks[0].translated == "Обновленный перевод")
    }

    @Test("overwrites multi-project library archive preserving other projects")
    func overwritesMultiProjectLibraryArchive() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptOverwriteMultiTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mediaFile = tempDir.appendingPathComponent("library_audio.mp3")
        try Data("library-audio-bytes".utf8).write(to: mediaFile)

        var session1 = makeSession(approved: true)
        session1.sourceFile = mediaFile.path
        session1.chunks[0].filePath = mediaFile.path
        session1.chunks[1].filePath = mediaFile.path
        var session2 = makeSession(approved: false)
        session2.sourceFile = mediaFile.path
        session2.chunks[0].filePath = mediaFile.path
        session2.chunks[1].filePath = mediaFile.path

        let p1 = ProjectRecord(
            id: "proj-1",
            name: "Project One",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: session1
        )
        let p2 = ProjectRecord(
            id: "proj-2",
            name: "Project Two",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: session2
        )

        let libraryURL = tempDir.appendingPathComponent("MyLibrary.vaniscript-library")
        try ProjectBundleExporter.exportLibrary(records: [p1, p2], to: libraryURL)

        // Modify only Project Two
        var p2Modified = p2
        p2Modified.name = "Project Two Modified"
        p2Modified.session.chunks[0].translated = "Перевод Проекта 2"

        try ProjectArchive.overwriteArchive(record: p2Modified, at: libraryURL, targetIndex: 1)

        let importDir = tempDir.appendingPathComponent("ImportedLibrary", isDirectory: true)
        let imported = try ProjectBundleImporter.importBundle(fileURL: libraryURL, destinationDirectoryURL: importDir)
        #expect(imported.count == 2)

        let reloadedP1 = try #require(imported.first(where: { $0.summary.name == "Project One" }))
        #expect(reloadedP1.session.chunks[0].translated == "Один")

        let reloadedP2 = try #require(imported.first(where: { $0.summary.name == "Project Two Modified" }))
        #expect(reloadedP2.session.chunks[0].translated == "Перевод Проекта 2")
    }
    @Test("overwrites multi-project raw JSON archive preserving sibling records")
    func overwritesMultiProjectRawJSONArchive() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptOverwriteRawJSONTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mediaFile = tempDir.appendingPathComponent("raw_json_audio.mp3")
        try Data("raw-json-audio-bytes".utf8).write(to: mediaFile)

        var session1 = makeSession(approved: true)
        session1.sourceFile = mediaFile.path
        session1.chunks[0].filePath = mediaFile.path
        session1.chunks[1].filePath = mediaFile.path
        var session2 = makeSession(approved: false)
        session2.sourceFile = mediaFile.path
        session2.chunks[0].filePath = mediaFile.path
        session2.chunks[1].filePath = mediaFile.path
        var session3 = makeSession(approved: true)
        session3.sourceFile = mediaFile.path
        session3.chunks[0].filePath = mediaFile.path
        session3.chunks[1].filePath = mediaFile.path

        let p1 = ProjectRecord(
            id: "raw-proj-1",
            name: "Raw Project One",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: session1
        )
        let p2 = ProjectRecord(
            id: "raw-proj-2",
            name: "Raw Project Two",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: session2
        )
        let p3 = ProjectRecord(
            id: "raw-proj-3",
            name: "Raw Project Three",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: session3
        )

        let rawJSONURL = tempDir.appendingPathComponent("RawLibrary.json")
        let rawData = try ProjectArchive.encode([p1, p2, p3])
        try rawData.write(to: rawJSONURL)

        // Modify only Project Two
        var p2Modified = p2
        p2Modified.name = "Raw Project Two Modified"
        p2Modified.session.chunks[0].translated = "Перевод Проекта 2 Обновлен"

        try ProjectArchive.overwriteArchive(record: p2Modified, at: rawJSONURL, targetIndex: 1)

        // Verify file is still raw JSON array and contains all 3 projects
        let fileData = try Data(contentsOf: rawJSONURL)
        let decoded = try ProjectArchive.decode(fileData)
        #expect(decoded.count == 3)

        let reloadedP1 = try #require(decoded.first(where: { $0.id == "raw-proj-1" }))
        #expect(reloadedP1.name == "Raw Project One")
        #expect(reloadedP1.session.chunks[0].translated == "Один")

        let reloadedP2 = try #require(decoded.first(where: { $0.id == "raw-proj-2" }))
        #expect(reloadedP2.name == "Raw Project Two Modified")
        #expect(reloadedP2.session.chunks[0].translated == "Перевод Проекта 2 Обновлен")

        let reloadedP3 = try #require(decoded.first(where: { $0.id == "raw-proj-3" }))
        #expect(reloadedP3.name == "Raw Project Three")
        #expect(reloadedP3.session.chunks[0].translated == "Один")

        // Verify importBundle also parses it correctly
        let importDir = tempDir.appendingPathComponent("ImportedRawJSON", isDirectory: true)
        let imported = try ProjectBundleImporter.importBundle(fileURL: rawJSONURL, destinationDirectoryURL: importDir)
        #expect(imported.count == 3)
        #expect(imported[1].name == "Raw Project Two Modified")
        #expect(imported[1].session.chunks[0].translated == "Перевод Проекта 2 Обновлен")
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
