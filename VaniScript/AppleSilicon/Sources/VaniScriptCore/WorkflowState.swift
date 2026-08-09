import Foundation

public struct WorkflowState: Codable, Equatable, Sendable {
    public var settings: AppSettings
    public var screen: UniversalWorkflowScreen
    public var sourceFile: String
    public var sourceFileName: String
    public var sourceMediaInfo: SourceMediaInfo?
    public var durationSec: Double
    public var metadata: AudioMetadata
    public var sourceLang: String
    public var targetLang: String
    public var transcriptionProvider: String
    public var translationProvider: String
    public var outputFormats: [OutputFormat]
    public var processingMessage: String
    public var processingProgress: Double
    public var session: SessionState?

    public static func initial(settings: AppSettings) -> WorkflowState {
        WorkflowState(
            settings: settings,
            screen: .upload,
            sourceFile: "",
            sourceFileName: "",
            sourceMediaInfo: nil,
            durationSec: 0,
            metadata: .empty,
            sourceLang: settings.defaultSourceLang,
            targetLang: settings.defaultTargetLang,
            transcriptionProvider: settings.transcriptionProvider,
            translationProvider: settings.translationProvider,
            outputFormats: [.txt],
            processingMessage: "",
            processingProgress: 0,
            session: nil
        )
    }

    public var canStartSession: Bool {
        !sourceFile.isEmpty && !transcriptionProvider.isEmpty
    }

    public mutating func selectSource(path: String, durationSec: Double, sourceMediaInfo: SourceMediaInfo? = nil) {
        self.sourceFile = path
        self.sourceFileName = URL(fileURLWithPath: path).lastPathComponent
        self.sourceMediaInfo = sourceMediaInfo
        self.durationSec = max(0, durationSec)
        self.metadata = MetadataExtractor.extract(fromFileName: sourceFileName)
        self.screen = .config
    }

    public mutating func updateMetadata(_ metadata: AudioMetadata) {
        self.metadata = metadata
    }

    public mutating func updateTargetLanguage(_ targetLang: String) {
        self.targetLang = targetLang
        self.translationProvider = settings.translationProvider
    }

    public mutating func synchronizeProviderSelections(
        previousSettings: AppSettings,
        forceTranscriptionProvider: Bool = false,
        forceTranslationProvider: Bool = false
    ) {
        let availableTranscriptionIDs = ProviderRegistry.availableTranscriptionProviders(settings: settings).map(\.id)
        if !availableTranscriptionIDs.contains(settings.transcriptionProvider) {
            settings.transcriptionProvider = availableTranscriptionIDs.first ?? "coreml-whisperkit"
        }
        if forceTranscriptionProvider
            || transcriptionProvider.isEmpty
            || transcriptionProvider == previousSettings.transcriptionProvider
            || !availableTranscriptionIDs.contains(transcriptionProvider) {
            transcriptionProvider = settings.transcriptionProvider
        }

        let availableTranslationIDs = ProviderRegistry.availableTranslationProviders(settings: settings, targetLang: targetLang).providers.map(\.id)
        if !availableTranslationIDs.contains(settings.translationProvider) {
            settings.translationProvider = availableTranslationIDs.first ?? "mlx-native"
        }
        if forceTranslationProvider
            || translationProvider.isEmpty
            || translationProvider == previousSettings.translationProvider
            || !availableTranslationIDs.contains(translationProvider) {
            translationProvider = settings.translationProvider
        }
    }

    public mutating func synchronizeActiveSessionProviders(
        forceTranscriptionProvider: Bool,
        forceTranslationProvider: Bool
    ) {
        guard var activeSession = session else { return }
        if forceTranscriptionProvider {
            activeSession.transcriptionProvider = transcriptionProvider
        }
        if forceTranslationProvider {
            activeSession.translationProvider = translationProvider
        }
        session = activeSession
    }

    public mutating func startSession() {
        guard canStartSession else { return }

        let chunks = ChunkPlanner.plan(
            sourcePath: sourceFile,
            durationSec: durationSec,
            chunkDurationMin: settings.chunkDurationMin
        )
        session = SessionState(
            sourceFile: sourceFile,
            sourceFileName: sourceFileName,
            durationSec: durationSec,
            metadata: metadata,
            sourceLang: sourceLang,
            targetLang: targetLang,
            transcriptionProvider: transcriptionProvider,
            translationProvider: translationProvider,
            outputFormats: outputFormats,
            chunks: chunks,
            currentChunkIndex: 0,
            sourceMediaInfo: sourceMediaInfo
        )
        if TranslationArchive.isRealLanguage(targetLang) {
            session?.activeTranslationLanguage = targetLang
            session?.availableTranslationLanguages = [targetLang]
        }
        processingMessage = "Prepared \(chunks.count) segment\(chunks.count == 1 ? "" : "s")"
        processingProgress = 1
        screen = .review
    }

    public mutating func openExport() {
        guard session != nil else { return }
        screen = .export
    }

    public mutating func openReview() {
        guard session != nil else { return }
        screen = .review
    }

    public mutating func reset() {
        self = .initial(settings: settings)
    }
}
