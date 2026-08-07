import CoreML
import Foundation
@testable import NativeBolabol
import NativeBolabolCore
import Testing

struct S9RuntimeSmokeTests {
    @Test
    func canary1BDecoderPositionUsesRankOneProductInput() throws {
        let position = 9
        let input = try CanaryCoreMLEngine.pathBDecoderPositionArray(position: position)

        #expect(input.dataType == .int32)
        #expect(input.shape.map(\.intValue) == [1])
        #expect(input[0].intValue == position)
    }

    @Test
    func canaryFlashOfflineDictationProducesTextWhenScratchIsEnabled() async throws {
        guard let paths = scratchPaths(
            model: "canary-flash-spike/models/CanaryFlash",
            audio: "canary-flash-spike/audio/en_short.wav"
        ) else { return }
        let model = try #require(
            TranscriptionModelCatalog.nativeWhisperKit.model(withID: "canary-180m-flash-coreml")
        )
        let engine = CanaryCoreMLEngine(model: model, modelFolderURL: paths.model)
        let result = try await engine.transcribe(
            TranscriptionRequest(audioFileURL: paths.audio, forcedLanguageCode: "en")
        )
        print("SMOKE Canary Flash: \(result.text)")
        #expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test
    func canaryFlashLongOfflineDictationKeepsMoreThanTailWordsWhenScratchIsEnabled() async throws {
        let audioPath = ProcessInfo.processInfo.environment["BOLABOL_FLASH_AUDIO_PATH"]
            ?? "canary-flash-spike/audio/en_long.wav"
        guard let paths = scratchPaths(
            model: "canary-flash-spike/models/CanaryFlash",
            audio: audioPath
        ) else { return }
        let model = try #require(
            TranscriptionModelCatalog.nativeWhisperKit.model(withID: "canary-180m-flash-coreml")
        )
        let engine = CanaryCoreMLEngine(model: model, modelFolderURL: paths.model)
        let result = try await engine.transcribe(
            TranscriptionRequest(audioFileURL: paths.audio, forcedLanguageCode: "en")
        )
        let wordCount = result.text.split(whereSeparator: { $0.isWhitespace }).count
        print("SMOKE Canary Flash long words=\(wordCount): \(result.text)")
        #expect(wordCount > 8)
    }

    @Test
    func canary1BOfflineDictationProducesTextWhenScratchIsEnabled() async throws {
        let audioPath = ProcessInfo.processInfo.environment["BOLABOL_1B_AUDIO_PATH"]
            ?? "canary-flash-spike/audio/en_short.wav"
        guard let paths = scratchPaths(
            model: "canary-1b-fix/package/bolabol-canary-1b-v2-coreml-r1",
            audio: audioPath
        ) else { return }
        let model = try #require(
            TranscriptionModelCatalog.nativeWhisperKit.model(withID: "canary-1b-v2-coreml")
        )
        let engine = CanaryCoreMLEngine(model: model, modelFolderURL: paths.model)
        let result = try await engine.transcribe(
            TranscriptionRequest(audioFileURL: paths.audio, forcedLanguageCode: "en")
        )
        print("SMOKE Canary 1B: \(result.text)")
        #expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test
    func gigaAMOfflineDictationProducesTextWhenScratchIsEnabled() async throws {
        let audioPath = ProcessInfo.processInfo.environment["BOLABOL_GIGAAM_AUDIO_PATH"]
            ?? "gigaam-spike/audio/ru_short.wav"
        guard let paths = scratchPaths(
            model: "gigaam-spike/models",
            audio: audioPath
        ) else { return }
        let model = try #require(
            TranscriptionModelCatalog.nativeWhisperKit.model(withID: "gigaam-v3-rnnt-coreml")
        )
        let engine = GigaAMCoreMLEngine(model: model, modelFolderURL: paths.model)
        let result = try await engine.transcribe(
            TranscriptionRequest(audioFileURL: paths.audio, forcedLanguageCode: "ru")
        )
        print("SMOKE GigaAM: \(result.text)")
        #expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test
    func installedGOModelsProduceTextWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["BOLABOL_INSTALLED_MODEL_SMOKE"] == "1" else {
            return
        }

        let modelRoot = try SharedModelsRoot.modelsDirectory(for: .whisperkit)
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let cases = [
            (
                id: "canary-180m-flash-coreml",
                relativeModelPath: "canary/180m-flash",
                audioPath: "scratch/canary-flash-spike/audio/en_short.wav",
                language: "en"
            ),
            (
                id: "canary-1b-v2-coreml",
                relativeModelPath: "canary/1b-v2",
                audioPath: "scratch/canary-flash-spike/audio/en_short.wav",
                language: "en"
            ),
            (
                id: "gigaam-v3-rnnt-coreml",
                relativeModelPath: "gigaam/v3-rnnt",
                audioPath: "scratch/gigaam-spike/audio/ru_short.wav",
                language: "ru"
            ),
        ]

        for item in cases {
            let modelURL = modelRoot.appendingPathComponent(item.relativeModelPath, isDirectory: true)
            let audioURL = projectRoot.appendingPathComponent(item.audioPath)
            guard FileManager.default.fileExists(atPath: modelURL.path),
                  FileManager.default.fileExists(atPath: audioURL.path)
            else {
                Issue.record("Missing installed smoke input for \(item.id): \(modelURL.path)")
                continue
            }

            let model = try #require(
                TranscriptionModelCatalog.nativeWhisperKit.model(withID: item.id)
            )
            let engine: any TranscriptionEngine
            switch model.backend {
            case .canaryCoreML:
                engine = CanaryCoreMLEngine(model: model, modelFolderURL: modelURL)
            case .gigaAMCoreML:
                engine = GigaAMCoreMLEngine(model: model, modelFolderURL: modelURL)
            case .whisperKitCoreML, .fluidAudioCoreML:
                Issue.record("Unexpected installed GO backend for \(item.id)")
                continue
            }

            let startedAt = Date()
            let result = try await engine.transcribe(
                TranscriptionRequest(audioFileURL: audioURL, forcedLanguageCode: item.language)
            )
            let coldElapsed = Date().timeIntervalSince(startedAt)
            let warmStartedAt = Date()
            let warmResult = try await engine.transcribe(
                TranscriptionRequest(audioFileURL: audioURL, forcedLanguageCode: item.language)
            )
            let warmElapsed = Date().timeIntervalSince(warmStartedAt)
            print("INSTALLED \(item.id) cold=\(String(format: "%.3f", coldElapsed))s warm=\(String(format: "%.3f", warmElapsed))s text=\(result.text)")
            #expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!warmResult.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @MainActor
    @Test
    func installedCanaryOneBProductSessionProducesTextWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["BOLABOL_INSTALLED_MODEL_SMOKE"] == "1" else {
            return
        }

        let modelRoot = try SharedModelsRoot.modelsDirectory(for: .whisperkit)
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let audioURL = projectRoot.appendingPathComponent(
            "scratch/canary-flash-spike/audio/en_short.wav"
        )
        let model = try #require(
            TranscriptionModelCatalog.nativeWhisperKit.model(withID: "canary-1b-v2-coreml")
        )
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            Issue.record("Missing installed 1B smoke audio: \(audioURL.path)")
            return
        }

        let suiteName = "bolabol-installed-1b-session-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let generalSettings = GeneralSettings(
            uiLanguage: .english,
            speechLanguages: UserSpeechLanguages(
                primaryLanguageCode: "en",
                additionalLanguageCode: "fr"
            )
        )
        defaults.set(
            try JSONEncoder().encode(generalSettings),
            forKey: GeneralSettingsStore.settingsDefaultsKey
        )

        let modelStore = TranscriptionModelStore(
            userDefaults: defaults,
            modelsDirectory: modelRoot
        )
        modelStore.activate(model)
        let engineStore = TranscriptionEngineStore.live()
        let resolution = engineStore.makeSession(
            modelStore: modelStore,
            operation: .ordinaryASR
        )

        guard case .available(let session) = resolution else {
            Issue.record("Installed Canary 1B should resolve through the product session path: \(resolution)")
            return
        }

        #expect(session.plan.modelID == model.id)
        #expect(session.plan.backend == .canaryCoreML)
        #expect(session.plan.request.forcedLanguageCode == "en")
        #expect(session.plan.engineIdentity == session.engine.id)

        let result = try await session.engine.transcribe(
            session.plan.request(audioFileURL: audioURL)
        )
        print("PRODUCT SESSION Canary 1B: \(result.text)")
        #expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @MainActor
    @Test
    func installedCanaryFlashProductSessionProducesTextWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["BOLABOL_INSTALLED_MODEL_SMOKE"] == "1" else {
            return
        }

        let modelRoot = try SharedModelsRoot.modelsDirectory(for: .whisperkit)
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let audioPath = ProcessInfo.processInfo.environment["BOLABOL_INSTALLED_FLASH_AUDIO_PATH"]
            ?? "scratch/canary-flash-spike/audio/en_short.wav"
        let audioURL = audioPath.hasPrefix("/")
            ? URL(fileURLWithPath: audioPath)
            : projectRoot.appendingPathComponent(audioPath)
        let model = try #require(
            TranscriptionModelCatalog.nativeWhisperKit.model(withID: "canary-180m-flash-coreml")
        )
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            Issue.record("Missing installed Flash smoke audio: \(audioURL.path)")
            return
        }

        let suiteName = "bolabol-installed-flash-session-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let generalSettings = GeneralSettings(
            uiLanguage: .english,
            speechLanguages: UserSpeechLanguages(
                primaryLanguageCode: "en",
                additionalLanguageCode: "de"
            )
        )
        defaults.set(
            try JSONEncoder().encode(generalSettings),
            forKey: GeneralSettingsStore.settingsDefaultsKey
        )

        let modelStore = TranscriptionModelStore(
            userDefaults: defaults,
            modelsDirectory: modelRoot
        )
        modelStore.activate(model)
        let engineStore = TranscriptionEngineStore.live()
        let resolution = engineStore.makeSession(
            modelStore: modelStore,
            operation: .ordinaryASR
        )

        guard case .available(let session) = resolution else {
            Issue.record("Installed Canary Flash should resolve through the product session path: \(resolution)")
            return
        }

        #expect(session.plan.modelID == model.id)
        #expect(session.plan.backend == .canaryCoreML)
        #expect(session.plan.request.forcedLanguageCode == "en")
        #expect(session.plan.engineIdentity == session.engine.id)

        let result = try await session.engine.transcribe(
            session.plan.request(audioFileURL: audioURL)
        )
        print("PRODUCT SESSION Canary Flash: \(result.text)")
        #expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if ProcessInfo.processInfo.environment["BOLABOL_INSTALLED_FLASH_AUDIO_PATH"] != nil {
            #expect(result.text.split(whereSeparator: { $0.isWhitespace }).count > 8)
        }
    }

    private func scratchPaths(model: String, audio: String) -> (model: URL, audio: URL)? {
        guard ProcessInfo.processInfo.environment["BOLABOL_S9_RUNTIME_SMOKE"] == "1" else {
            print("UNAVAILABLE: set BOLABOL_S9_RUNTIME_SMOKE=1 to run offline S9 smoke")
            return nil
        }

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let modelURL = root.appendingPathComponent("scratch/\(model)", isDirectory: true)
        let audioURL = audio.hasPrefix("/")
            ? URL(fileURLWithPath: audio)
            : root.appendingPathComponent("scratch/\(audio)")
        guard FileManager.default.fileExists(atPath: modelURL.path),
              FileManager.default.fileExists(atPath: audioURL.path) else {
            print("UNAVAILABLE: missing scratch model or audio for \(model)")
            return nil
        }
        return (modelURL, audioURL)
    }
}
