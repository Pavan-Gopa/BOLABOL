import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Native processing readiness")
struct NativeProcessingReadinessTests {
    init() {
        LocalModelVerification.skipVerificationForTesting = true
    }

    @Test("cloud transcription and translation stay ready without local models")
    func cloudBehaviorRemainsReady() {
        var settings = AppSettings.defaults
        settings.geminiKey = "gemini-key"

        let result = NativeProcessingReadiness.evaluate(
            settings: settings,
            sourceLang: "Russian",
            targetLang: "English",
            transcriptionProvider: "gemini-cloud",
            translationProvider: "gemini-cloud"
        )

        #expect(result.canTranscribe)
        #expect(result.canTranslate)
        #expect(result.transcriptionMessage.contains("Gemini Cloud"))
        #expect(result.translationMessage.contains("Gemini Cloud"))
    }

    @Test("canonical language policy maps display values, aliases, and Keep Original")
    func canonicalLanguagePolicy() {
        #expect(NativeLanguagePolicy.canonicalCode(" Russian ") == "ru")
        #expect(NativeLanguagePolicy.canonicalCode("en-US") == "en")
        #expect(NativeLanguagePolicy.canonicalCode("Keep Original") == "same")
        #expect(NativeLanguagePolicy.storageValue(for: "de") == "German")
        #expect(!NativeLanguagePolicy.translationNeeded(sourceLang: "Russian", targetLang: "ru"))
        #expect(!NativeLanguagePolicy.translationNeeded(sourceLang: "English", targetLang: "Keep Original"))
        #expect(NativeLanguagePolicy.translationNeeded(sourceLang: "Russian", targetLang: "English"))
    }

    @Test("equal normalized source and target skip translation readiness")
    func equalSourceAndTargetSkipTranslationReadiness() {
        let result = NativeProcessingReadiness.evaluate(
            settings: .defaults,
            sourceLang: "Russian",
            targetLang: "ru",
            transcriptionProvider: "unknown-transcription-provider",
            translationProvider: "missing-translation-provider"
        )

        #expect(!result.canTranscribe)
        #expect(result.canTranslate)
        #expect(result.translationMessage == "Translation disabled for same-language sessions.")
    }

    @Test("source options follow selected descriptor auto-detect capabilities")
    func sourceOptionsFollowDescriptorCapabilities() throws {
        let flash = try #require(NativeModelCatalog.descriptor(for: "canary-180m-flash-coreml"))
        let parakeet = try #require(NativeModelCatalog.descriptor(for: "parakeet-tdt-06b-v3"))
        let flashCodes = NativeLanguagePolicy.sourceLanguageOptions(for: flash).map(\.code)
        let parakeetCodes = NativeLanguagePolicy.sourceLanguageOptions(for: parakeet).map(\.code)

        #expect(!flashCodes.contains(NativeLanguagePolicy.autoCode))
        #expect(flashCodes == ["en", "de", "fr", "es"])
        #expect(parakeetCodes.first == NativeLanguagePolicy.autoCode)
    }

    @Test("Parakeet accepts auto source language when its package is present")
    func parakeetAutoLanguageIsReady() throws {
        let descriptor = try #require(
            NativeModelCatalog.descriptor(for: "parakeet-tdt-06b-v3")
        )
        let root = try temporaryRoot(named: "Parakeet")
        defer { try? FileManager.default.removeItem(at: root) }
        let modelPath = try installRequiredLayout(for: descriptor, under: root)

        var settings = AppSettings.defaults
        settings.localAsrModels[descriptor.id] = LocalModelState(
            status: .downloaded,
            label: descriptor.displayName,
            path: modelPath.path,
            runtime: descriptor.settingsRuntime
        )

        let result = NativeProcessingReadiness.evaluate(
            settings: settings,
            sourceLang: "auto",
            targetLang: "same",
            transcriptionProvider: descriptor.id,
            translationProvider: "",
            onMacOSMajor: 14
        )

        #expect(result.canTranscribe)
        #expect(result.canTranslate)
        #expect(result.transcriptionMessage.contains(descriptor.displayName))
        #expect(result.transcriptionMessage.contains("ready"))
        #expect(!result.transcriptionMessage.localizedCaseInsensitiveContains("WhisperKit"))
    }

    @Test("Canary Flash rejects auto source language with explicit-source guidance")
    func canaryFlashAutoRequiresExplicitSource() throws {
        let descriptor = try #require(
            NativeModelCatalog.descriptor(for: "canary-180m-flash-coreml")
        )

        let result = NativeProcessingReadiness.evaluate(
            settings: .defaults,
            sourceLang: "auto",
            targetLang: "same",
            transcriptionProvider: descriptor.id,
            translationProvider: "",
            onMacOSMajor: 14
        )

        #expect(!result.canTranscribe)
        #expect(result.transcriptionMessage.contains(descriptor.displayName))
        #expect(result.transcriptionMessage.contains("explicit source language"))
        #expect(result.transcriptionMessage.contains("en, de, fr, es"))
        #expect(!result.transcriptionMessage.localizedCaseInsensitiveContains("WhisperKit"))
    }

    @Test("Canary Flash accepts a supported named source language")
    func canaryFlashNamedSourceIsReady() throws {
        let descriptor = try #require(
            NativeModelCatalog.descriptor(for: "canary-180m-flash-coreml")
        )
        let root = try temporaryRoot(named: "CanaryFlash")
        defer { try? FileManager.default.removeItem(at: root) }
        let modelPath = try installRequiredLayout(for: descriptor, under: root)

        var settings = AppSettings.defaults
        settings.localAsrModels[descriptor.id] = LocalModelState(
            status: .downloaded,
            label: descriptor.displayName,
            path: modelPath.path,
            runtime: descriptor.settingsRuntime
        )

        let result = NativeProcessingReadiness.evaluate(
            settings: settings,
            sourceLang: "English",
            targetLang: "same",
            transcriptionProvider: descriptor.id,
            translationProvider: "",
            onMacOSMajor: 14
        )

        #expect(result.canTranscribe)
        #expect(result.transcriptionMessage.contains(descriptor.displayName))
        #expect(result.transcriptionMessage.contains("ready"))
        #expect(!result.transcriptionMessage.localizedCaseInsensitiveContains("WhisperKit"))
    }

    @Test("Canary Flash rejects an unsupported named source language")
    func canaryFlashRejectsUnsupportedSource() throws {
        let descriptor = try #require(
            NativeModelCatalog.descriptor(for: "canary-180m-flash-coreml")
        )

        let result = NativeProcessingReadiness.evaluate(
            settings: .defaults,
            sourceLang: "Russian",
            targetLang: "same",
            transcriptionProvider: descriptor.id,
            translationProvider: "",
            onMacOSMajor: 14
        )

        #expect(!result.canTranscribe)
        #expect(result.transcriptionMessage.contains(descriptor.displayName))
        #expect(result.transcriptionMessage.contains("Russian"))
        #expect(result.transcriptionMessage.contains("does not support source language"))
        #expect(result.transcriptionMessage.contains("en, de, fr, es"))
        #expect(!result.transcriptionMessage.localizedCaseInsensitiveContains("WhisperKit"))
    }

    @Test("Canary 1B rejects unsupported macOS before package validation")
    func canaryOneBRejectsUnsupportedOSBeforeHashing() throws {
        let descriptor = try #require(
            NativeModelCatalog.descriptor(for: "canary-1b-v2-coreml")
        )
        let root = try temporaryRoot(named: "CanaryOneB")
        defer { try? FileManager.default.removeItem(at: root) }

        var settings = AppSettings.defaults
        settings.localAsrModels[descriptor.id] = LocalModelState(
            status: .downloaded,
            label: descriptor.displayName,
            path: root.path,
            runtime: descriptor.settingsRuntime
        )

        let result = NativeProcessingReadiness.evaluate(
            settings: settings,
            sourceLang: "English",
            targetLang: "same",
            transcriptionProvider: descriptor.id,
            translationProvider: "",
            onMacOSMajor: 14
        )

        #expect(!result.canTranscribe)
        #expect(result.transcriptionMessage.contains(descriptor.displayName))
        #expect(result.transcriptionMessage.contains("requires macOS 15"))
        #expect(!result.transcriptionMessage.contains("integrity"))
        #expect(!result.transcriptionMessage.localizedCaseInsensitiveContains("WhisperKit"))
    }

    @Test("missing, failed, and pathless local models fail with model-specific messages")
    func localModelStateFailuresAreSpecific() throws {
        let descriptor = try #require(
            NativeModelCatalog.descriptor(for: "parakeet-tdt-06b-v3")
        )
        let root = try temporaryRoot(named: "ParakeetFailures")
        defer { try? FileManager.default.removeItem(at: root) }

        let missingSettings = AppSettings.defaults
        let missing = NativeProcessingReadiness.evaluate(
            settings: missingSettings,
            sourceLang: "auto",
            targetLang: "same",
            transcriptionProvider: descriptor.id,
            translationProvider: "",
            onMacOSMajor: 14
        )
        #expect(!missing.canTranscribe)
        #expect(missing.transcriptionMessage.contains(descriptor.displayName))
        #expect(missing.transcriptionMessage.contains("downloaded or located local model"))

        var failedSettings = AppSettings.defaults
        failedSettings.localAsrModels[descriptor.id] = LocalModelState(
            status: .failed,
            label: descriptor.displayName,
            path: root.appendingPathComponent("failed").path,
            runtime: descriptor.settingsRuntime
        )
        let failed = NativeProcessingReadiness.evaluate(
            settings: failedSettings,
            sourceLang: "auto",
            targetLang: "same",
            transcriptionProvider: descriptor.id,
            translationProvider: "",
            onMacOSMajor: 14
        )
        #expect(!failed.canTranscribe)
        #expect(failed.transcriptionMessage.contains(descriptor.displayName))
        #expect(failed.transcriptionMessage.contains("incomplete or failed integrity validation"))

        var pathlessSettings = AppSettings.defaults
        pathlessSettings.localAsrModels[descriptor.id] = LocalModelState(
            status: .downloaded,
            label: descriptor.displayName,
            runtime: descriptor.settingsRuntime
        )
        let pathless = NativeProcessingReadiness.evaluate(
            settings: pathlessSettings,
            sourceLang: "auto",
            targetLang: "same",
            transcriptionProvider: descriptor.id,
            translationProvider: "",
            onMacOSMajor: 14
        )
        #expect(!pathless.canTranscribe)
        #expect(pathless.transcriptionMessage.contains(descriptor.displayName))
        #expect(pathless.transcriptionMessage.contains("downloaded or located local model"))
    }

    @Test("unknown transcription providers fail closed")
    func unknownTranscriptionProviderFails() {
        let result = NativeProcessingReadiness.evaluate(
            settings: .defaults,
            sourceLang: "Russian",
            targetLang: "same",
            transcriptionProvider: "unknown-transcription-provider",
            translationProvider: ""
        )

        #expect(!result.canTranscribe)
        #expect(result.transcriptionMessage.contains("unavailable"))
        #expect(result.transcriptionMessage.contains("unknown-transcription-provider"))
    }

    @Test("translation readiness remains correct when transcription is unavailable")
    func translationReadinessDoesNotDependOnASR() {
        var settings = AppSettings.defaults
        settings.geminiKey = "gemini-key"

        let result = NativeProcessingReadiness.evaluate(
            settings: settings,
            sourceLang: "Russian",
            targetLang: "English",
            transcriptionProvider: "unknown-transcription-provider",
            translationProvider: "gemini-cloud"
        )

        #expect(!result.canTranscribe)
        #expect(result.canTranslate)
        #expect(result.translationMessage == "Gemini Cloud translation ready.")
    }

    @Test("same-language sessions do not require a translation model")
    func sameLanguageDoesNotRequireTranslationModel() {
        let result = NativeProcessingReadiness.evaluate(
            settings: .defaults,
            sourceLang: "Russian",
            targetLang: "same",
            transcriptionProvider: "unknown-transcription-provider",
            translationProvider: ""
        )

        #expect(!result.canTranscribe)
        #expect(result.canTranslate)
        #expect(result.translationMessage == "Translation disabled for same-language sessions.")
    }

    @Test("legacy Core ML alias still resolves a WhisperKit model")
    func coreMLAliasRemainsSupported() throws {
        let root = try temporaryRoot(named: "WhisperAlias")
        defer { try? FileManager.default.removeItem(at: root) }
        let modelPath = root.appendingPathComponent("whisper-large-v3", isDirectory: true)
        try FileManager.default.createDirectory(at: modelPath, withIntermediateDirectories: true)

        var settings = AppSettings.defaults
        settings.localAsrModels["whisper-large-v3"] = LocalModelState(
            status: .downloaded,
            label: "Whisper Large v3",
            path: modelPath.path,
            runtime: .whisper
        )

        let result = NativeProcessingReadiness.evaluate(
            settings: settings,
            sourceLang: "Russian",
            targetLang: "same",
            transcriptionProvider: "coreml-whisperkit",
            translationProvider: "",
            onMacOSMajor: 14
        )

        #expect(result.canTranscribe)
        #expect(result.transcriptionMessage == "Core ML transcription model ready.")
    }

    private func temporaryRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptReadiness-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func installRequiredLayout(
        for descriptor: LocalASRModelDescriptor,
        under root: URL
    ) throws -> URL {
        let modelPath = root.appendingPathComponent(descriptor.id, isDirectory: true)
        for relativePath in descriptor.requiredLayout.requiredFiles {
            let url = modelPath.appendingPathComponent(
                relativePath,
                isDirectory: relativePath.hasSuffix(".mlmodelc")
            )
            if relativePath.hasSuffix(".mlmodelc") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data([1]).write(to: url)
            }
        }
        return modelPath
    }
}
