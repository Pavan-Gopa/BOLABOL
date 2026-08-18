import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

@Suite("WorkflowStore project import and drop handling", .serialized)
struct WorkflowStoreProjectImportTests {
    private static let isolatedSettingsPersistence: @Sendable (AppSettings) throws -> Void = { _ in }
    private static let isolatedProjectsPersistence: @Sendable ([ProjectRecord]) throws -> Void = { _ in }

    @MainActor
    private func makeStore(projects: [ProjectRecord] = []) -> WorkflowStore {
        WorkflowStore(
            settings: AppSettings.defaults,
            projects: projects,
            settingsPersistence: Self.isolatedSettingsPersistence,
            projectsPersistence: Self.isolatedProjectsPersistence,
            startInitialModelScan: false
        )
    }

    @Test("identifies supported project file extensions")
    func identifiesSupportedProjectURLs() {
        #expect(WorkflowStore.isSupportedProjectURL(URL(fileURLWithPath: "/tmp/project.vaniscript")))
        #expect(WorkflowStore.isSupportedProjectURL(URL(fileURLWithPath: "/tmp/library.vaniscript-library")))
        #expect(WorkflowStore.isSupportedProjectURL(URL(fileURLWithPath: "/tmp/legacy.json")))
        #expect(WorkflowStore.isSupportedProjectURL(URL(fileURLWithPath: "/tmp/PROJECT.VANISCRIPT")))

        #expect(!WorkflowStore.isSupportedProjectURL(URL(fileURLWithPath: "/tmp/audio.mp3")))
        #expect(!WorkflowStore.isSupportedProjectURL(URL(fileURLWithPath: "/tmp/video.mp4")))
        #expect(!WorkflowStore.isSupportedProjectURL(URL(fileURLWithPath: "/tmp/document.docx")))
        #expect(!WorkflowStore.isSupportedProjectURL(URL(fileURLWithPath: "/tmp/image.png")))
    }

    @Test("extracts archive display name stem from URL")
    func extractsArchiveDisplayName() {
        #expect(WorkflowStore.archiveDisplayName(from: URL(fileURLWithPath: "/path/to/Renamed-Project-2026.vaniscript")) == "Renamed-Project-2026")
        #expect(WorkflowStore.archiveDisplayName(from: URL(fileURLWithPath: "/path/to/Lecture Series 1.vaniscript-library")) == "Lecture Series 1")
        #expect(WorkflowStore.archiveDisplayName(from: URL(fileURLWithPath: "/path/to/export.json")) == "export")
        #expect(WorkflowStore.archiveDisplayName(from: URL(fileURLWithPath: "/path/to/.vaniscript")) == nil)
    }

    @Test("rejects drop when all URLs are unsupported")
    @MainActor
    func rejectsUnsupportedDrop() {
        let store = makeStore()
        let unsupportedURLs = [
            URL(fileURLWithPath: "/tmp/movie.mp4"),
            URL(fileURLWithPath: "/tmp/screenshot.png")
        ]

        let result = store.handleProjectDrop(urls: unsupportedURLs)
        #expect(result == false)
        #expect(store.statusMessage.contains("Unsupported file type"))
        #expect(store.projects.isEmpty)
    }

    @Test("imports multiple valid project files and merges into store")
    @MainActor
    func importsMultipleValidProjects() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptDropTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mediaFile1 = tempDir.appendingPathComponent("media1.mp3")
        let mediaFile2 = tempDir.appendingPathComponent("media2.mp3")
        try Data("m1".utf8).write(to: mediaFile1)
        try Data("m2".utf8).write(to: mediaFile2)

        let proj1 = ProjectRecord(
            id: "proj-drop-1",
            name: "Original 1",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: SessionState(sourceFile: mediaFile1.path, sourceFileName: "media1.mp3", durationSec: 10, metadata: AudioMetadata(date: "", location: "", lecturer: "", participants: ""), sourceLang: "auto", targetLang: "ru", transcriptionProvider: "mlx", translationProvider: "mlx", outputFormats: [.txt], chunks: [], currentChunkIndex: 0)
        )
        let proj2 = ProjectRecord(
            id: "proj-drop-2",
            name: "Original 2",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: SessionState(sourceFile: mediaFile2.path, sourceFileName: "media2.mp3", durationSec: 10, metadata: AudioMetadata(date: "", location: "", lecturer: "", participants: ""), sourceLang: "auto", targetLang: "ru", transcriptionProvider: "mlx", translationProvider: "mlx", outputFormats: [.txt], chunks: [], currentChunkIndex: 0)
        )

        let bundle1URL = tempDir.appendingPathComponent("Session-One-Renamed.vaniscript")
        let bundle2URL = tempDir.appendingPathComponent("Session-Two-Renamed.vaniscript")
        try ProjectBundleExporter.exportBundle(record: proj1, to: bundle1URL)
        try ProjectBundleExporter.exportBundle(record: proj2, to: bundle2URL)

        let store = makeStore()
        let result = store.handleProjectDrop(urls: [bundle1URL, bundle2URL])

        #expect(result == true)
        #expect(store.statusMessage == "Imported 2 projects.")
        #expect(store.projects.count == 2)

        let first = try #require(store.projects.first(where: { $0.summary.name == "Session-One-Renamed" }))
        #expect(first.summary.sourceFileName == "media1.mp3")
        #expect(first.session.sourceFileName == "media1.mp3")

        let second = try #require(store.projects.first(where: { $0.summary.name == "Session-Two-Renamed" }))
        #expect(second.summary.sourceFileName == "media2.mp3")
        #expect(second.session.sourceFileName == "media2.mp3")
    }

    @Test("handles partial failures during multi-file import")
    @MainActor
    func handlesPartialImportFailures() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptPartialTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mediaFile = tempDir.appendingPathComponent("good_media.mp3")
        try Data("good".utf8).write(to: mediaFile)

        let validProj = ProjectRecord(
            id: "proj-good",
            name: "Good Project",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: SessionState(sourceFile: mediaFile.path, sourceFileName: "good_media.mp3", durationSec: 10, metadata: AudioMetadata(date: "", location: "", lecturer: "", participants: ""), sourceLang: "auto", targetLang: "ru", transcriptionProvider: "mlx", translationProvider: "mlx", outputFormats: [.txt], chunks: [], currentChunkIndex: 0)
        )
        let validBundleURL = tempDir.appendingPathComponent("ValidProject.vaniscript")
        try ProjectBundleExporter.exportBundle(record: validProj, to: validBundleURL)

        let corruptedBundleURL = tempDir.appendingPathComponent("Corrupted.vaniscript")
        try Data("corrupted-header-garbage".utf8).write(to: corruptedBundleURL)

        let store = makeStore()
        let result = store.handleProjectDrop(urls: [validBundleURL, corruptedBundleURL])

        #expect(result == true)
        #expect(store.statusMessage.contains("Imported 1 project with 1 failure"))
        #expect(store.statusMessage.contains("Corrupted.vaniscript"))
        #expect(store.projects.count == 1)
        #expect(store.projects.first?.summary.name == "ValidProject")
    }

    @Test("reports full failure when all dropped project files fail")
    @MainActor
    func reportsFullFailure() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptFullFailTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let corrupted1 = tempDir.appendingPathComponent("Bad1.vaniscript")
        let corrupted2 = tempDir.appendingPathComponent("Bad2.json")
        try Data("bad1".utf8).write(to: corrupted1)
        try Data("{ invalid json ".utf8).write(to: corrupted2)

        let store = makeStore()
        let result = store.handleProjectDrop(urls: [corrupted1, corrupted2])

        #expect(result == false)
        #expect(store.statusMessage.hasPrefix("Project import failed:"))
        #expect(store.statusMessage.contains("Bad1.vaniscript"))
        #expect(store.statusMessage.contains("Bad2.json"))
        #expect(store.projects.isEmpty)
    }

    @Test("clean imported deletion immediately removes project and leaves external archive untouched")
    @MainActor
    func cleanImportedDeletionLeavesArchiveUntouched() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptCleanDelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mediaFile = tempDir.appendingPathComponent("clean_media.mp3")
        try Data("clean-media".utf8).write(to: mediaFile)

        let proj = ProjectRecord(
            id: "proj-clean",
            name: "Clean Project",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: SessionState(
                sourceFile: mediaFile.path,
                sourceFileName: "clean_media.mp3",
                durationSec: 10,
                metadata: AudioMetadata(date: "", location: "", lecturer: "", participants: ""),
                sourceLang: "auto",
                targetLang: "ru",
                transcriptionProvider: "mlx",
                translationProvider: "mlx",
                outputFormats: [.txt],
                chunks: [
                    ChunkData(index: 0, filePath: mediaFile.path, durationSec: 10, startSec: 0, endSec: 10, original: "Hello", translated: "Привет", originalFormats: nil, translatedFormats: nil, unrecognizedFragments: [], status: .done, approved: true)
                ],
                currentChunkIndex: 0
            )
        )

        let archiveURL = tempDir.appendingPathComponent("CleanArchive.vaniscript")
        try ProjectBundleExporter.exportBundle(record: proj, to: archiveURL)
        let originalArchiveData = try Data(contentsOf: archiveURL)

        let store = makeStore()
        let importOk = store.handleProjectDrop(urls: [archiveURL])
        #expect(importOk == true)
        #expect(store.projects.count == 1)

        let importedProject = try #require(store.projects.first)
        let policy = store.deletionPolicy(for: importedProject.id)
        #expect(policy == .cleanImported(archivePath: archiveURL.standardizedFileURL.path))

        // Discard & remove
        store.discardAndRemoveProject(id: importedProject.id)
        #expect(store.projects.isEmpty)

        // Verify original archive on disk is 100% untouched
        #expect(FileManager.default.fileExists(atPath: archiveURL.path))
        let archiveAfterData = try Data(contentsOf: archiveURL)
        #expect(archiveAfterData == originalArchiveData)
    }

    @Test("dirty imported save safely updates originating archive and removes project")
    @MainActor
    func dirtyImportedSaveUpdatesArchiveAndRemovesProject() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptDirtySaveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mediaFile = tempDir.appendingPathComponent("dirty_save_media.mp3")
        try Data("dirty-save-media".utf8).write(to: mediaFile)

        let proj = ProjectRecord(
            id: "proj-dirty-save",
            name: "Initial Save Proj",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: SessionState(
                sourceFile: mediaFile.path,
                sourceFileName: "dirty_save_media.mp3",
                durationSec: 10,
                metadata: AudioMetadata(date: "", location: "", lecturer: "", participants: ""),
                sourceLang: "auto",
                targetLang: "ru",
                transcriptionProvider: "mlx",
                translationProvider: "mlx",
                outputFormats: [.txt],
                chunks: [
                    ChunkData(index: 0, filePath: mediaFile.path, durationSec: 10, startSec: 0, endSec: 10, original: "Hello", translated: "Привет", originalFormats: nil, translatedFormats: nil, unrecognizedFragments: [], status: .done, approved: true)
                ],
                currentChunkIndex: 0
            )
        )

        let archiveURL = tempDir.appendingPathComponent("DirtySaveArchive.vaniscript")
        try ProjectBundleExporter.exportBundle(record: proj, to: archiveURL)

        let store = makeStore()
        _ = store.handleProjectDrop(urls: [archiveURL])
        let importedProject = try #require(store.projects.first)

        // Modify project to make it dirty
        store.openProject(id: importedProject.id)
        store.workflow.session?.chunks[0].setTranslation("Здравствуйте (Updated)", language: "Russian")
        store.workflow.session?.chunks[0].translated = "Здравствуйте (Updated)"
        if let index = store.projects.firstIndex(where: { $0.id == importedProject.id }) {
            store.projects[index].session.chunks[0].setTranslation("Здравствуйте (Updated)", language: "Russian")
            store.projects[index].session.chunks[0].translated = "Здравствуйте (Updated)"
        }

        let policy = store.deletionPolicy(for: importedProject.id)
        #expect(policy == .dirtyImported(archivePath: archiveURL.standardizedFileURL.path))
        // Save and remove
        let saveOk = store.saveAndRemoveProject(id: importedProject.id)
        #expect(saveOk == true)
        #expect(store.projects.isEmpty)

        // Verify originating archive was updated
        let verifyDir = tempDir.appendingPathComponent("VerifyDir", isDirectory: true)
        let reloaded = try ProjectBundleImporter.importBundle(fileURL: archiveURL, destinationDirectoryURL: verifyDir)
        let reloadedProj = try #require(reloaded.first)
        #expect(reloadedProj.session.chunks[0].translated == "Здравствуйте (Updated)")
    }

    @Test("dirty imported discard leaves originating archive untouched and removes project")
    @MainActor
    func dirtyImportedDiscardLeavesArchiveUntouched() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptDirtyDiscardTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mediaFile = tempDir.appendingPathComponent("dirty_discard_media.mp3")
        try Data("dirty-discard-media".utf8).write(to: mediaFile)

        let proj = ProjectRecord(
            id: "proj-dirty-disc",
            name: "Original Text",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: SessionState(
                sourceFile: mediaFile.path,
                sourceFileName: "dirty_discard_media.mp3",
                durationSec: 10,
                metadata: AudioMetadata(date: "", location: "", lecturer: "", participants: ""),
                sourceLang: "auto",
                targetLang: "ru",
                transcriptionProvider: "mlx",
                translationProvider: "mlx",
                outputFormats: [.txt],
                chunks: [
                    ChunkData(index: 0, filePath: mediaFile.path, durationSec: 10, startSec: 0, endSec: 10, original: "Hello", translated: "Оригинал", originalFormats: nil, translatedFormats: nil, unrecognizedFragments: [], status: .done, approved: true)
                ],
                currentChunkIndex: 0
            )
        )

        let archiveURL = tempDir.appendingPathComponent("DirtyDiscardArchive.vaniscript")
        try ProjectBundleExporter.exportBundle(record: proj, to: archiveURL)

        let store = makeStore()
        _ = store.handleProjectDrop(urls: [archiveURL])
        let importedProject = try #require(store.projects.first)

        // Modify project
        store.openProject(id: importedProject.id)
        store.workflow.session?.chunks[0].setTranslation("Discarded Modification", language: "Russian")
        store.workflow.session?.chunks[0].translated = "Discarded Modification"
        if let index = store.projects.firstIndex(where: { $0.id == importedProject.id }) {
            store.projects[index].session.chunks[0].setTranslation("Discarded Modification", language: "Russian")
            store.projects[index].session.chunks[0].translated = "Discarded Modification"
        }
        #expect(store.deletionPolicy(for: importedProject.id) == .dirtyImported(archivePath: archiveURL.standardizedFileURL.path))

        // Discard & remove
        store.discardAndRemoveProject(id: importedProject.id)
        #expect(store.projects.isEmpty)

        // Verify originating archive is untouched
        let verifyDir = tempDir.appendingPathComponent("VerifyDiscard", isDirectory: true)
        let reloaded = try ProjectBundleImporter.importBundle(fileURL: archiveURL, destinationDirectoryURL: verifyDir)
        let reloadedProj = try #require(reloaded.first)
        #expect(reloadedProj.session.chunks[0].translated == "Оригинал")
    }

    @Test("dirty imported export as new writes to new location, keeps original untouched, and removes project")
    @MainActor
    func dirtyImportedExportAsNew() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptExportNewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mediaFile = tempDir.appendingPathComponent("export_new_media.mp3")
        try Data("export-new-media".utf8).write(to: mediaFile)

        let proj = ProjectRecord(
            id: "proj-export-new",
            name: "Original Version",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: SessionState(
                sourceFile: mediaFile.path,
                sourceFileName: "export_new_media.mp3",
                durationSec: 10,
                metadata: AudioMetadata(date: "", location: "", lecturer: "", participants: ""),
                sourceLang: "auto",
                targetLang: "ru",
                transcriptionProvider: "mlx",
                translationProvider: "mlx",
                outputFormats: [.txt],
                chunks: [
                    ChunkData(index: 0, filePath: mediaFile.path, durationSec: 10, startSec: 0, endSec: 10, original: "Hello", translated: "Оригинальный", originalFormats: nil, translatedFormats: nil, unrecognizedFragments: [], status: .done, approved: true)
                ],
                currentChunkIndex: 0
            )
        )

        let originalArchiveURL = tempDir.appendingPathComponent("OriginalArchive.vaniscript")
        try ProjectBundleExporter.exportBundle(record: proj, to: originalArchiveURL)

        let store = makeStore()
        _ = store.handleProjectDrop(urls: [originalArchiveURL])
        let importedProject = try #require(store.projects.first)

        // Modify project
        if let index = store.projects.firstIndex(where: { $0.id == importedProject.id }) {
            store.projects[index].session.chunks[0].setTranslation("Новая версия перевода", language: "Russian")
            store.projects[index].session.chunks[0].translated = "Новая версия перевода"
        }

        let newExportURL = tempDir.appendingPathComponent("NewVersionExport.vaniscript")
        let exportOk = store.exportAsNewAndRemoveProject(id: importedProject.id, to: newExportURL)
        #expect(exportOk == true)
        #expect(store.projects.isEmpty)

        // Original archive untouched
        let verifyOrigDir = tempDir.appendingPathComponent("VerifyOrig", isDirectory: true)
        let origReloaded = try ProjectBundleImporter.importBundle(fileURL: originalArchiveURL, destinationDirectoryURL: verifyOrigDir)
        #expect(origReloaded.first?.session.chunks[0].translated == "Оригинальный")

        // New export has updated translation
        let verifyNewDir = tempDir.appendingPathComponent("VerifyNew", isDirectory: true)
        let newReloaded = try ProjectBundleImporter.importBundle(fileURL: newExportURL, destinationDirectoryURL: verifyNewDir)
        #expect(newReloaded.first?.session.chunks[0].translated == "Новая версия перевода")
    }

    @Test("dirty save failure retains project in store without removing it")
    @MainActor
    func dirtySaveFailureRetainsProject() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptSaveFailTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let invalidPath = "/nonexistent/read-only/path/archive.vaniscript"
        let record = ProjectRecord(
            id: "proj-save-fail",
            name: "Fail Proj",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: SessionState(
                sourceFile: nil,
                sourceFileName: "fail.mp3",
                durationSec: 10,
                metadata: AudioMetadata(date: "", location: "", lecturer: "", participants: ""),
                sourceLang: "auto",
                targetLang: "ru",
                transcriptionProvider: "mlx",
                translationProvider: "mlx",
                outputFormats: [.txt],
                chunks: [],
                currentChunkIndex: 0
            ),
            originatingArchivePath: invalidPath,
            originatingArchiveIndex: 0,
            importBaselineFingerprint: "old-baseline"
        )

        let store = makeStore(projects: [record])
        #expect(store.projects.count == 1)
        #expect(store.deletionPolicy(for: record.id) == .dirtyImported(archivePath: invalidPath))

        let result = store.saveAndRemoveProject(id: record.id)
        #expect(result == false)
        #expect(store.statusMessage.contains("Failed to save changes to archive"))
        #expect(store.projects.count == 1)
    }

    @Test("local created project uses localCreated deletion policy and removes project on delete")
    @MainActor
    func localCreatedDeletion() {
        let localRecord = ProjectRecord(
            id: "proj-local-created",
            name: "My Local Session",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: SessionState(
                sourceFile: nil,
                sourceFileName: "local.mp3",
                durationSec: 10,
                metadata: AudioMetadata(date: "", location: "", lecturer: "", participants: ""),
                sourceLang: "auto",
                targetLang: "ru",
                transcriptionProvider: "mlx",
                translationProvider: "mlx",
                outputFormats: [.txt],
                chunks: [],
                currentChunkIndex: 0
            )
        )

        let store = makeStore(projects: [localRecord])
        #expect(store.deletionPolicy(for: localRecord.id) == .localCreated)

        store.deleteProject(id: localRecord.id)
        #expect(store.projects.isEmpty)
        #expect(store.statusMessage == "Project deleted.")
    }

    @Test("path-escaping project ID cannot delete outside projects directory")
    @MainActor
    func pathEscapingProjectIDCannotDeleteOutsideProjects() throws {
        let fileManager = FileManager.default
        let recordingsDir = AppStoragePaths.recordingsDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        let canaryFile = recordingsDir.appendingPathComponent("canary_\(UUID().uuidString).txt")
        try Data("safe-canary-data".utf8).write(to: canaryFile)
        defer { try? fileManager.removeItem(at: canaryFile) }

        let validProjID = "valid-test-proj-\(UUID().uuidString.lowercased())"
        let validProjDir = AppStoragePaths.projectDirectory(id: validProjID, fileManager: fileManager)
        try fileManager.createDirectory(at: validProjDir, withIntermediateDirectories: true)
        let validProjFile = validProjDir.appendingPathComponent("data.txt")
        try Data("proj-data".utf8).write(to: validProjFile)
        defer { try? fileManager.removeItem(at: validProjDir) }

        let store = makeStore()

        // Attempt path-escaping deletions
        store.deleteProject(id: "../Recordings")
        store.deleteProject(id: "../../")
        store.deleteProject(id: "..")
        store.deleteProject(id: "../Recordings/\(canaryFile.lastPathComponent)")
        store.deleteProject(id: "/tmp")

        // Verify canary file is still safe and intact
        #expect(fileManager.fileExists(atPath: canaryFile.path))

        // Valid project deletion should clean up its directory
        #expect(fileManager.fileExists(atPath: validProjDir.path))
        store.deleteProject(id: validProjID)
        #expect(!fileManager.fileExists(atPath: validProjDir.path))
    }

    @Test("dirty imported raw JSON archive save preserves sibling records")
    @MainActor
    func dirtyImportedRawJSONArchiveSavePreservesSiblings() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptRawJSONSaveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mediaFile = tempDir.appendingPathComponent("raw_media.mp3")
        try Data("raw-media-content".utf8).write(to: mediaFile)

        let p1 = ProjectRecord(
            id: "raw-store-p1",
            name: "Raw Store P1",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: SessionState(
                sourceFile: mediaFile.path,
                sourceFileName: "raw_media.mp3",
                durationSec: 10,
                metadata: AudioMetadata(date: "", location: "", lecturer: "", participants: ""),
                sourceLang: "auto",
                targetLang: "ru",
                transcriptionProvider: "mlx",
                translationProvider: "mlx",
                outputFormats: [.txt],
                chunks: [
                    ChunkData(index: 0, filePath: mediaFile.path, durationSec: 10, startSec: 0, endSec: 10, original: "Hello 1", translated: "Оригинал 1", originalFormats: nil, translatedFormats: nil, unrecognizedFragments: [], status: .done, approved: true)
                ],
                currentChunkIndex: 0
            )
        )
        let p2 = ProjectRecord(
            id: "raw-store-p2",
            name: "Raw Store P2",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: SessionState(
                sourceFile: mediaFile.path,
                sourceFileName: "raw_media.mp3",
                durationSec: 10,
                metadata: AudioMetadata(date: "", location: "", lecturer: "", participants: ""),
                sourceLang: "auto",
                targetLang: "ru",
                transcriptionProvider: "mlx",
                translationProvider: "mlx",
                outputFormats: [.txt],
                chunks: [
                    ChunkData(index: 0, filePath: mediaFile.path, durationSec: 10, startSec: 0, endSec: 10, original: "Hello 2", translated: "Оригинал 2", originalFormats: nil, translatedFormats: nil, unrecognizedFragments: [], status: .done, approved: true)
                ],
                currentChunkIndex: 0
            )
        )

        let rawArchiveURL = tempDir.appendingPathComponent("MultiProjectArchive.json")
        let rawData = try ProjectArchive.encode([p1, p2])
        try rawData.write(to: rawArchiveURL)

        let store = makeStore()
        _ = store.handleProjectDrop(urls: [rawArchiveURL])
        #expect(store.projects.count == 2)

        // Modify P2 in store
        let p2Index = try #require(store.projects.firstIndex(where: { $0.id == "raw-store-p2" }))
        store.projects[p2Index].session.chunks[0].setTranslation("Сохраненный Перевод 2", language: "Russian")
        store.projects[p2Index].session.chunks[0].translated = "Сохраненный Перевод 2"

        #expect(store.deletionPolicy(for: "raw-store-p2") == .dirtyImported(archivePath: rawArchiveURL.standardizedFileURL.path))

        // Save P2 to archive & remove from store
        let saved = store.saveAndRemoveProject(id: "raw-store-p2")
        #expect(saved == true)
        #expect(store.projects.count == 1)
        #expect(store.projects.first?.id == "raw-store-p1")

        // Verify archive on disk has BOTH projects, with P1 intact and P2 updated
        let diskData = try Data(contentsOf: rawArchiveURL)
        let diskRecords = try ProjectArchive.decode(diskData)
        #expect(diskRecords.count == 2)

        let diskP1 = try #require(diskRecords.first(where: { $0.id == "raw-store-p1" }))
        #expect(diskP1.session.chunks[0].translated == "Оригинал 1")

        let diskP2 = try #require(diskRecords.first(where: { $0.id == "raw-store-p2" }))
        #expect(diskP2.session.chunks[0].translated == "Сохраненный Перевод 2")
    }

    @Test("deletion policy and save consume live active session for open imported project")
    @MainActor
    func deletionPolicyAndSaveUseLiveActiveSession() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptLiveSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mediaFile = tempDir.appendingPathComponent("live_session_media.mp3")
        try Data("live-session-media".utf8).write(to: mediaFile)

        let proj = ProjectRecord(
            id: "proj-live-session",
            name: "Live Session Proj",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: SessionState(
                sourceFile: mediaFile.path,
                sourceFileName: "live_session_media.mp3",
                durationSec: 10,
                metadata: AudioMetadata(date: "", location: "", lecturer: "", participants: ""),
                sourceLang: "auto",
                targetLang: "ru",
                transcriptionProvider: "mlx",
                translationProvider: "mlx",
                outputFormats: [.txt],
                chunks: [
                    ChunkData(index: 0, filePath: mediaFile.path, durationSec: 10, startSec: 0, endSec: 10, original: "Hello", translated: "Привет", originalFormats: nil, translatedFormats: nil, unrecognizedFragments: [], status: .done, approved: true)
                ],
                currentChunkIndex: 0
            )
        )

        let archiveURL = tempDir.appendingPathComponent("LiveSessionArchive.vaniscript")
        try ProjectBundleExporter.exportBundle(record: proj, to: archiveURL)

        let store = makeStore()
        _ = store.handleProjectDrop(urls: [archiveURL])
        let importedProject = try #require(store.projects.first)

        store.openProject(id: importedProject.id)
        // Opening alone must not flip a clean imported project to dirty.
        #expect(store.deletionPolicy(for: importedProject.id) == .cleanImported(archivePath: archiveURL.standardizedFileURL.path))

        // Edit ONLY the live active session, mirroring the real review-edit path
        // before any commit back into the stored record.
        store.workflow.session?.chunks[0].setTranslation("Live Session Edit", language: "Russian")
        store.workflow.session?.chunks[0].translated = "Live Session Edit"

        let storedRecord = try #require(store.projects.first(where: { $0.id == importedProject.id }))
        #expect(storedRecord.session.chunks[0].translated == "Привет")
        // Policy must merge the live session; otherwise the UI would offer a
        // destructive clean-imported deletion and silently lose the edit.
        #expect(store.deletionPolicy(for: importedProject.id) == .dirtyImported(archivePath: archiveURL.standardizedFileURL.path))

        let saved = store.saveAndRemoveProject(id: importedProject.id)
        #expect(saved == true)
        #expect(store.projects.isEmpty)

        let verifyDir = tempDir.appendingPathComponent("VerifyLive", isDirectory: true)
        let reloaded = try ProjectBundleImporter.importBundle(fileURL: archiveURL, destinationDirectoryURL: verifyDir)
        #expect(reloaded.first?.session.chunks[0].translated == "Live Session Edit")

        // The single-project bundle format must survive the overwrite.
        let rawHeader = try String(contentsOf: archiveURL, encoding: .utf8)
        #expect(rawHeader.hasPrefix("VANISCRIPT_BUNDLE_V2"))
    }

    @Test("deleting the currently open clean imported project resets the session and preserves archive bytes")
    @MainActor
    func deletingOpenCleanProjectResetsSessionAndPreservesArchive() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptOpenCleanDelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mediaFile = tempDir.appendingPathComponent("open_clean_media.mp3")
        try Data("open-clean-media".utf8).write(to: mediaFile)

        let proj = ProjectRecord(
            id: "proj-open-clean",
            name: "Open Clean Proj",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: SessionState(
                sourceFile: mediaFile.path,
                sourceFileName: "open_clean_media.mp3",
                durationSec: 10,
                metadata: AudioMetadata(date: "", location: "", lecturer: "", participants: ""),
                sourceLang: "auto",
                targetLang: "ru",
                transcriptionProvider: "mlx",
                translationProvider: "mlx",
                outputFormats: [.txt],
                chunks: [
                    ChunkData(index: 0, filePath: mediaFile.path, durationSec: 10, startSec: 0, endSec: 10, original: "Hello", translated: "Привет", originalFormats: nil, translatedFormats: nil, unrecognizedFragments: [], status: .done, approved: true)
                ],
                currentChunkIndex: 0
            )
        )

        let archiveURL = tempDir.appendingPathComponent("OpenCleanArchive.vaniscript")
        try ProjectBundleExporter.exportBundle(record: proj, to: archiveURL)
        let originalArchiveData = try Data(contentsOf: archiveURL)

        let store = makeStore()
        _ = store.handleProjectDrop(urls: [archiveURL])
        let importedProject = try #require(store.projects.first)

        store.openProject(id: importedProject.id)
        #expect(store.workflow.session != nil)
        #expect(store.deletionPolicy(for: importedProject.id) == .cleanImported(archivePath: archiveURL.standardizedFileURL.path))

        store.discardAndRemoveProject(id: importedProject.id)
        #expect(store.projects.isEmpty)
        // Deleting the currently open project must reset the active workflow
        // so no ghost session can be re-persisted.
        #expect(store.workflow.session == nil)
        #expect(store.deletionPolicy(for: importedProject.id) == nil)

        #expect(FileManager.default.fileExists(atPath: archiveURL.path))
        #expect(try Data(contentsOf: archiveURL) == originalArchiveData)
    }

    @Test("dirty export-as-new failure retains project and writes nothing")
    @MainActor
    func exportAsNewFailureRetainsProject() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptExportFailTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mediaFile = tempDir.appendingPathComponent("export_fail_media.mp3")
        try Data("export-fail-media".utf8).write(to: mediaFile)

        let proj = ProjectRecord(
            id: "proj-export-fail",
            name: "Export Fail Proj",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: SessionState(
                sourceFile: mediaFile.path,
                sourceFileName: "export_fail_media.mp3",
                durationSec: 10,
                metadata: AudioMetadata(date: "", location: "", lecturer: "", participants: ""),
                sourceLang: "auto",
                targetLang: "ru",
                transcriptionProvider: "mlx",
                translationProvider: "mlx",
                outputFormats: [.txt],
                chunks: [
                    ChunkData(index: 0, filePath: mediaFile.path, durationSec: 10, startSec: 0, endSec: 10, original: "Hello", translated: "Привет", originalFormats: nil, translatedFormats: nil, unrecognizedFragments: [], status: .done, approved: true)
                ],
                currentChunkIndex: 0
            )
        )

        let archiveURL = tempDir.appendingPathComponent("ExportFailArchive.vaniscript")
        try ProjectBundleExporter.exportBundle(record: proj, to: archiveURL)
        let originalArchiveData = try Data(contentsOf: archiveURL)

        let store = makeStore()
        _ = store.handleProjectDrop(urls: [archiveURL])
        let importedProject = try #require(store.projects.first)

        if let index = store.projects.firstIndex(where: { $0.id == importedProject.id }) {
            store.projects[index].session.chunks[0].setTranslation("Измененный перевод", language: "Russian")
            store.projects[index].session.chunks[0].translated = "Измененный перевод"
        }
        #expect(store.deletionPolicy(for: importedProject.id) == .dirtyImported(archivePath: archiveURL.standardizedFileURL.path))

        let badDestination = tempDir.appendingPathComponent("Missing/Nested/Export.vaniscript")
        let exported = store.exportAsNewAndRemoveProject(id: importedProject.id, to: badDestination)
        #expect(exported == false)
        #expect(store.statusMessage.contains("Export failed"))
        // Failure must retain the project; a lost export must not delete data.
        #expect(store.projects.count == 1)
        #expect(!FileManager.default.fileExists(atPath: badDestination.path))
        #expect(try Data(contentsOf: archiveURL) == originalArchiveData)
    }

    @Test("save and remove rejects local created project and retains it")
    @MainActor
    func saveAndRemoveRejectsLocalCreatedProject() {
        let localRecord = ProjectRecord(
            id: "proj-local-save-guard",
            name: "Local Save Guard",
            createdAt: "2026-08-17T10:00:00Z",
            updatedAt: "2026-08-17T10:05:00Z",
            session: SessionState(
                sourceFile: nil,
                sourceFileName: "local_guard.mp3",
                durationSec: 10,
                metadata: AudioMetadata(date: "", location: "", lecturer: "", participants: ""),
                sourceLang: "auto",
                targetLang: "ru",
                transcriptionProvider: "mlx",
                translationProvider: "mlx",
                outputFormats: [.txt],
                chunks: [],
                currentChunkIndex: 0
            )
        )

        let store = makeStore(projects: [localRecord])
        #expect(store.deletionPolicy(for: localRecord.id) == .localCreated)

        let saved = store.saveAndRemoveProject(id: localRecord.id)
        #expect(saved == false)
        #expect(store.statusMessage == "Originating archive path not found.")
        #expect(store.projects.count == 1)
    }
}
