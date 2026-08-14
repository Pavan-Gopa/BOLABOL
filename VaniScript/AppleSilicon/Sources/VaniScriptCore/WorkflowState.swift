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
    public var sourceKind: WorkflowSourceKind
    public var documentState: DocumentState?
    public var documentApprovalMode: ApprovalMode
    private enum CodingKeys: String, CodingKey {
        case settings, screen, sourceFile, sourceFileName, sourceMediaInfo
        case sourceKind, documentState, durationSec, metadata, sourceLang, targetLang
        case transcriptionProvider, translationProvider, outputFormats
        case processingMessage, processingProgress, session, documentApprovalMode
    }

    public init(
        settings: AppSettings,
        screen: UniversalWorkflowScreen,
        sourceFile: String,
        sourceFileName: String,
        sourceMediaInfo: SourceMediaInfo?,
        durationSec: Double,
        metadata: AudioMetadata,
        sourceLang: String,
        targetLang: String,
        transcriptionProvider: String,
        translationProvider: String,
        outputFormats: [OutputFormat],
        processingMessage: String,
        processingProgress: Double,
        session: SessionState?,
        sourceKind: WorkflowSourceKind = .media,
        documentState: DocumentState? = nil,
        documentApprovalMode: ApprovalMode? = nil
    ) {
        self.settings = settings
        self.screen = screen
        self.sourceFile = sourceFile
        self.sourceFileName = sourceFileName
        self.sourceMediaInfo = sourceMediaInfo
        self.durationSec = durationSec
        self.metadata = metadata
        self.sourceLang = sourceLang
        self.targetLang = targetLang
        self.transcriptionProvider = transcriptionProvider
        self.translationProvider = translationProvider
        self.outputFormats = outputFormats
        self.processingMessage = processingMessage
        self.processingProgress = processingProgress
        self.session = session
        self.sourceKind = sourceKind
        self.documentState = documentState
        self.documentApprovalMode = documentApprovalMode ?? settings.documentApprovalModeDefault
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? .defaults
        self.screen = try container.decodeIfPresent(UniversalWorkflowScreen.self, forKey: .screen) ?? .upload
        self.sourceFile = try container.decodeIfPresent(String.self, forKey: .sourceFile) ?? ""
        self.sourceFileName = try container.decodeIfPresent(String.self, forKey: .sourceFileName) ?? ""
        self.sourceMediaInfo = try container.decodeIfPresent(SourceMediaInfo.self, forKey: .sourceMediaInfo)
        self.sourceKind = try container.decodeIfPresent(WorkflowSourceKind.self, forKey: .sourceKind) ?? .media
        self.documentState = try container.decodeIfPresent(DocumentState.self, forKey: .documentState)
        self.durationSec = try container.decodeIfPresent(Double.self, forKey: .durationSec) ?? 0
        self.metadata = try container.decodeIfPresent(AudioMetadata.self, forKey: .metadata) ?? .empty
        self.sourceLang = try container.decodeIfPresent(String.self, forKey: .sourceLang) ?? self.settings.defaultSourceLang
        self.targetLang = try container.decodeIfPresent(String.self, forKey: .targetLang) ?? self.settings.defaultTargetLang
        self.transcriptionProvider = try container.decodeIfPresent(String.self, forKey: .transcriptionProvider) ?? self.settings.transcriptionProvider
        self.translationProvider = try container.decodeIfPresent(String.self, forKey: .translationProvider) ?? self.settings.translationProvider
        self.documentApprovalMode = try container.decodeIfPresent(ApprovalMode.self, forKey: .documentApprovalMode)
            ?? self.settings.documentApprovalModeDefault
        self.outputFormats = try container.decodeIfPresent([OutputFormat].self, forKey: .outputFormats) ?? [.txt]
        self.processingMessage = try container.decodeIfPresent(String.self, forKey: .processingMessage) ?? ""
        self.processingProgress = try container.decodeIfPresent(Double.self, forKey: .processingProgress) ?? 0
        self.session = try container.decodeIfPresent(SessionState.self, forKey: .session)
    }

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
            session: nil,
            sourceKind: .media,
            documentState: nil,
        )
    }

    public var canStartSession: Bool {
        guard !sourceFile.isEmpty else { return false }
        if sourceKind == .document {
            return documentState != nil
        }
        return !transcriptionProvider.isEmpty
    }

    public mutating func selectSource(path: String, durationSec: Double, sourceMediaInfo: SourceMediaInfo? = nil) {
        self.sourceFile = path
        self.sourceFileName = URL(fileURLWithPath: path).lastPathComponent
        self.sourceMediaInfo = sourceMediaInfo
        self.sourceKind = .media
        self.documentState = nil
        self.durationSec = max(0, durationSec)
        self.metadata = MetadataExtractor.extract(fromFileName: sourceFileName)
        self.screen = .config
    }

    public mutating func selectDocument(path: String, documentState: DocumentState) {
        var normalizedDocumentState = documentState
        normalizedDocumentState.profile.sourceLanguage = NativeLanguagePolicy.autoCode
        normalizedDocumentState.profile.targetLanguage = targetLang

        self.sourceFile = path
        self.sourceFileName = normalizedDocumentState.originalAsset.originalFileName.isEmpty
            ? URL(fileURLWithPath: path).lastPathComponent
            : normalizedDocumentState.originalAsset.originalFileName
        self.sourceMediaInfo = nil
        self.sourceKind = .document
        self.documentState = normalizedDocumentState
        self.sourceLang = NativeLanguagePolicy.autoCode
        self.durationSec = 0
        self.metadata = AudioMetadata.empty
        self.screen = .config
    }

    public mutating func updateMetadata(_ metadata: AudioMetadata) {
        self.metadata = metadata
    }

    public mutating func updateTargetLanguage(_ targetLang: String) {
        self.targetLang = targetLang
        self.translationProvider = settings.translationProvider
        guard sourceKind == .document, var documentState else { return }
        documentState.profile.sourceLanguage = NativeLanguagePolicy.autoCode
        documentState.profile.targetLanguage = targetLang
        self.sourceLang = NativeLanguagePolicy.autoCode
        self.documentState = documentState
    }

    public mutating func synchronizeProviderSelections(
        previousSettings: AppSettings,
        forceTranscriptionProvider: Bool = false,
        forceTranslationProvider: Bool = false
    ) {
        let availableTranscriptionIDs = Set(
            ProviderRegistry.availableTranscriptionProviders(settings: settings).map(\.id)
        )
        if forceTranscriptionProvider
            || transcriptionProvider.isEmpty
            || transcriptionProvider == previousSettings.transcriptionProvider
        {
            // An archived provider remains the honest route when the current
            // settings selection is unavailable. The caller can surface the
            // readiness error instead of silently switching to another model.
            if availableTranscriptionIDs.contains(settings.transcriptionProvider) {
                transcriptionProvider = settings.transcriptionProvider
            }
        }

        let availableTranslationIDs = ProviderRegistry.availableTranslationProviders(settings: settings, targetLang: targetLang).providers.map(\.id)
        if !availableTranslationIDs.contains(settings.translationProvider) {
            settings.translationProvider = availableTranslationIDs.first ?? "mlx-native"
        }
        if forceTranslationProvider
            || translationProvider.isEmpty
            || translationProvider == previousSettings.translationProvider
            || !availableTranslationIDs.contains(translationProvider)
        {
            translationProvider = settings.translationProvider
        }
    }

    /// Applies the user's current transcription selection to the active
    /// workflow and session only when that exact provider is available.
    ///
    /// An unavailable setting must not silently replace an archived provider:
    /// native readiness will report the honest failure for that archived route.
    @discardableResult
    public mutating func applySelectedTranscriptionProviderIfAvailable() -> Bool {
        let selectedProvider = settings.transcriptionProvider
        guard ProviderRegistry.availableTranscriptionProviders(settings: settings)
            .contains(where: { $0.id == selectedProvider })
        else {
            return false
        }

        transcriptionProvider = selectedProvider
        if var activeSession = session {
            activeSession.transcriptionProvider = selectedProvider
            session = activeSession
        }
        return true
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

        let chunks: [ChunkData]
        var activeDocumentState: DocumentState?
        switch sourceKind {
        case .media:
            chunks = ChunkPlanner.plan(
                sourcePath: sourceFile,
                durationSec: durationSec,
                chunkDurationMin: settings.chunkDurationMin
            )
        case .document:
            guard var documentState else { return }
            sourceLang = NativeLanguagePolicy.autoCode
            documentState.profile.sourceLanguage = NativeLanguagePolicy.autoCode
            documentState.profile.targetLanguage = targetLang
            let plans = SemanticChunkPlanner.plan(
                blocks: documentState.blocks,
                profile: documentState.profile
            )
            documentState.chunks = plans
            self.documentState = documentState
            activeDocumentState = documentState
            chunks = Self.documentChunks(from: documentState, sourceFile: sourceFile)
        }

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
            sourceMediaInfo: sourceMediaInfo,
            sourceKind: sourceKind,
            documentState: activeDocumentState,
            approvalMode: sourceKind == .document ? documentApprovalMode : .manual
        )
        if TranslationArchive.isRealLanguage(targetLang) {
            session?.activeTranslationLanguage = targetLang
            session?.availableTranslationLanguages = [targetLang]
        }
        processingMessage = "Prepared \(chunks.count) segment\(chunks.count == 1 ? "" : "s")"
        processingProgress = 1
        screen = .review
    }

    private static func documentChunks(
        from documentState: DocumentState,
        sourceFile: String
    ) -> [ChunkData] {
        let blocksByID = Dictionary(uniqueKeysWithValues: documentState.blocks.map { ($0.id, $0) })
        return documentState.chunks.enumerated().map { index, plan in
            let original = documentSourceText(plan: plan, blocksByID: blocksByID)
            let firstBlockID = plan.blockIDs.first ?? ""
            let lastBlockID = plan.blockIDs.last ?? firstBlockID
            let firstSlice = plan.blockSlices?.first
            let lastSlice = plan.blockSlices?.last
            return ChunkData(
                index: index,
                filePath: sourceFile,
                durationSec: 0,
                startSec: 0,
                endSec: 0,
                original: original,
                translated: "",
                status: .pending,
                approved: false,
                sourceAnchor: .document(
                    DocumentRange(
                        startBlockID: firstBlockID,
                        endBlockID: lastBlockID,
                        startOffset: firstSlice?.startOffset,
                        endOffset: lastSlice.map(\.endOffset)
                    )
                )
            )
        }
    }

    private static func documentSourceText(
        plan: DocumentChunkPlan,
        blocksByID: [String: DocumentBlock]
    ) -> String {
        if let slices = plan.blockSlices, !slices.isEmpty {
            return slices.compactMap { slice in
                guard let block = blocksByID[slice.blockID] else { return nil }
                return sliceText(block: block, startOffset: slice.startOffset, endOffset: slice.endOffset)
            }.joined(separator: "\n\n")
        }
        return plan.blockIDs.compactMap { blocksByID[$0] }
            .map { $0.spans.map(\.text).joined() }
            .joined(separator: "\n\n")
    }

    private static func sliceText(block: DocumentBlock, startOffset: Int, endOffset: Int) -> String {
        let text = block.spans.map(\.text).joined()
        let start = text.index(text.startIndex, offsetBy: min(max(0, startOffset), text.count))
        let end = text.index(text.startIndex, offsetBy: min(max(startOffset, endOffset), text.count))
        return String(text[start..<end])
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

/// Pure policy for the document Review "Approve & Next" transition. The store
/// supplies the resolved next-chunk text because document translations may live
/// in the block archive rather than on `ChunkData.translated`.
public enum DocumentApprovalAdvancePolicy {
    public static func shouldTranslateNext(
        approvalMode: ApprovalMode,
        hasNextChunk: Bool,
        nextTranslationIsUsable: Bool
    ) -> Bool {
        approvalMode == .manual && hasNextChunk && !nextTranslationIsUsable
    }

    public static func isSourceEmptyChunk(
        original: String?,
        blockTexts: [String]
    ) -> Bool {
        let originalIsEmpty = original?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        let blocksAreEmpty = blockTexts.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return originalIsEmpty && blocksAreEmpty
    }
}
