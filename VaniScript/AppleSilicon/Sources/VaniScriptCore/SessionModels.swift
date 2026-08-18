import Foundation

public enum OutputFormat: String, Codable, CaseIterable, Equatable, Sendable {
    case txt = "TXT"
    case srt = "SRT"
    case vtt = "VTT"
    case markdown = "Markdown"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawVal = try container.decode(String.self)
        let cleaned = rawVal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch cleaned {
        case "txt":
            self = .txt
        case "srt":
            self = .srt
        case "vtt":
            self = .vtt
        case "markdown":
            self = .markdown
        default:
            if let matched = OutputFormat(rawValue: rawVal) {
                self = matched
            } else {
                self = .txt
            }
        }
    }
}

public struct AudioMetadata: Codable, Equatable, Sendable {
    public var date: String
    public var location: String
    public var lecturer: String
    public var participants: String

    public static let empty = AudioMetadata(date: "", location: "", lecturer: "", participants: "")

    enum CodingKeys: String, CodingKey {
        case date, location, lecturer, participants
    }

    public init(date: String, location: String, lecturer: String, participants: String) {
        self.date = date
        self.location = location
        self.lecturer = lecturer
        self.participants = participants
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        self.location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        self.lecturer = try container.decodeIfPresent(String.self, forKey: .lecturer) ?? ""
        self.participants = try container.decodeIfPresent(String.self, forKey: .participants) ?? ""
    }
}

public struct LanguageResult: Codable, Equatable, Sendable {
    public var txt: String?
    public var srt: String?
    public var vtt: String?
    public var markdown: String?

    enum CodingKeys: String, CodingKey {
        case txt, srt, vtt, markdown
        case TXT, SRT, VTT, Markdown
    }

    public init(txt: String? = nil, srt: String? = nil, vtt: String? = nil, markdown: String? = nil) {
        self.txt = txt
        self.srt = srt
        self.vtt = vtt
        self.markdown = markdown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.txt = try container.decodeIfPresent(String.self, forKey: .txt) ?? container.decodeIfPresent(String.self, forKey: .TXT)
        self.srt = try container.decodeIfPresent(String.self, forKey: .srt) ?? container.decodeIfPresent(String.self, forKey: .SRT)
        self.vtt = try container.decodeIfPresent(String.self, forKey: .vtt) ?? container.decodeIfPresent(String.self, forKey: .VTT)
        self.markdown = try container.decodeIfPresent(String.self, forKey: .markdown) ?? container.decodeIfPresent(String.self, forKey: .Markdown)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(txt, forKey: .txt)
        try container.encodeIfPresent(srt, forKey: .srt)
        try container.encodeIfPresent(vtt, forKey: .vtt)
        try container.encodeIfPresent(markdown, forKey: .markdown)
    }
}

public struct TranscriptWord: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(startSec)-\(endSec)-\(text)" }

    public var startSec: Double
    public var endSec: Double
    public var text: String

    public init(startSec: Double, endSec: Double, text: String) {
        self.startSec = startSec
        self.endSec = endSec
        self.text = text
    }
}

public struct TranscriptCue: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(startSec)-\(endSec)" }

    public var startSec: Double
    public var endSec: Double
    public var text: String
    public var words: [TranscriptWord]?

    public init(startSec: Double, endSec: Double, text: String, words: [TranscriptWord]? = nil) {
        self.startSec = startSec
        self.endSec = endSec
        self.text = text
        self.words = words
    }
}

public enum TranslationArchive {
    public static func displayLanguage(_ language: String) -> String {
        let clean = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.hasPrefix("ru") { return "Russian" }
        if clean.hasPrefix("cs") || clean.hasPrefix("cz") { return "Czech" }
        if clean.hasPrefix("fr") { return "French" }
        if clean.hasPrefix("de") { return "German" }
        if clean.hasPrefix("pl") { return "Polish" }
        if clean.hasPrefix("en") { return "English" }
        if clean.hasPrefix("hi") { return "Hindi" }
        if clean.hasPrefix("es") { return "Spanish" }
        if clean.hasPrefix("sv") { return "Swedish" }
        if clean.hasPrefix("it") { return "Italian" }
        if clean.hasPrefix("pt") { return "Portuguese" }
        if clean.hasPrefix("nl") { return "Dutch" }

        guard !language.isEmpty else { return language }
        return language.prefix(1).uppercased() + language.dropFirst()
    }

    public static func languageKey(_ language: String) -> String {
        displayLanguage(language).lowercased()
    }

    public static func isRealLanguage(_ language: String) -> Bool {
        let clean = languageKey(language)
        return !clean.isEmpty && clean != "same"
    }

    public static func isUsableTranslationText(_ text: String) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }

        let lower = clean.lowercased()
        let failureMarkers = [
            "mlx translation failed",
            "mlx returned no usable translation text",
            "translation failed:",
            "generation timed out",
        ]
        return !failureMarkers.contains { lower.contains($0) }
    }
}

public struct TranslationVariant: Codable, Equatable, Sendable {
    public var language: String
    public var text: String
    public var cues: [TranscriptCue]?
    public var formats: LanguageResult?
    public var provider: String?
    public var updatedAt: String?

    public init(
        language: String,
        text: String,
        cues: [TranscriptCue]? = nil,
        formats: LanguageResult? = nil,
        provider: String? = nil,
        updatedAt: String? = nil
    ) {
        self.language = language
        self.text = text
        self.cues = cues
        self.formats = formats
        self.provider = provider
        self.updatedAt = updatedAt
    }
}

public enum ChunkStatus: String, Codable, Equatable, Sendable {
    case pending
    case processing
    case done
    case error
}
public enum ApprovalMode: String, Codable, CaseIterable, Equatable, Sendable {
    case manual
    case automatic
}

public enum ReviewDisposition: String, Codable, CaseIterable, Equatable, Sendable {
    case pending
    case autoApproved
    case manuallyApproved
    case needsReview
    case failed

    public var isApproved: Bool {
        switch self {
        case .autoApproved, .manuallyApproved:
            return true
        case .pending, .needsReview, .failed:
            return false
        }
    }
}

public enum QualityIssueSeverity: String, Codable, CaseIterable, Equatable, Sendable {
    case error
    case warning
}

public struct QualityIssue: Codable, Equatable, Sendable {
    public var code: String
    public var message: String
    public var severity: QualityIssueSeverity
    public var blockID: String?

    public init(
        code: String,
        message: String,
        severity: QualityIssueSeverity = .error,
        blockID: String? = nil
    ) {
        self.code = code
        self.message = message
        self.severity = severity
        self.blockID = blockID
    }
}

public struct ChunkQualityReport: Codable, Equatable, Sendable {
    public var validatorVersion: Int
    public var errors: [QualityIssue]
    public var warnings: [QualityIssue]
    public var attempts: Int
    public var sourceHash: String
    public var outputHash: String?

    public init(
        validatorVersion: Int = 1,
        errors: [QualityIssue] = [],
        warnings: [QualityIssue] = [],
        attempts: Int = 0,
        sourceHash: String = "",
        outputHash: String? = nil
    ) {
        self.validatorVersion = validatorVersion
        self.errors = errors
        self.warnings = warnings
        self.attempts = attempts
        self.sourceHash = sourceHash
        self.outputHash = outputHash
    }
}


public struct ChunkData: Codable, Equatable, Identifiable, Sendable {
    public var id: Int { index }

    public var index: Int
    public var filePath: String
    public var durationSec: Double
    public var startSec: Double
    public var endSec: Double
    public var original: String
    public var translated: String
    public var originalCues: [TranscriptCue]?
    public var originalFormats: LanguageResult?
    public var translatedFormats: LanguageResult?
    public var translationsByLanguage: [String: TranslationVariant]?
    public var unrecognizedFragments: [String]?
    public var status: ChunkStatus
    public var reviewDisposition: ReviewDisposition {
        didSet {
            let dispositionApproved = reviewDisposition.isApproved
            if approved != dispositionApproved {
                approved = dispositionApproved
            }
        }
    }
    public var qualityReport: ChunkQualityReport?
    public var sourceAnchor: SourceAnchor?
    public var approved: Bool {
        didSet {
            if approved, !reviewDisposition.isApproved {
                reviewDisposition = .manuallyApproved
            } else if !approved, reviewDisposition.isApproved {
                reviewDisposition = .pending
            }
        }
    }

    public init(
        index: Int,
        filePath: String,
        durationSec: Double,
        startSec: Double,
        endSec: Double,
        original: String,
        translated: String,
        originalCues: [TranscriptCue]? = nil,
        originalFormats: LanguageResult? = nil,
        translatedFormats: LanguageResult? = nil,
        translationsByLanguage: [String: TranslationVariant]? = nil,
        unrecognizedFragments: [String]? = nil,
        status: ChunkStatus,
        approved: Bool,
        sourceAnchor: SourceAnchor? = nil,
        reviewDisposition: ReviewDisposition? = nil,
        qualityReport: ChunkQualityReport? = nil
    ) {
        self.index = index
        self.filePath = filePath
        self.durationSec = durationSec
        self.startSec = startSec
        self.endSec = endSec
        self.original = original
        self.translated = translated
        self.originalCues = originalCues
        self.originalFormats = originalFormats
        self.translatedFormats = translatedFormats
        self.translationsByLanguage = translationsByLanguage
        self.unrecognizedFragments = unrecognizedFragments
        self.status = status
        self.reviewDisposition = reviewDisposition ?? (approved ? .manuallyApproved : .pending)
        self.qualityReport = qualityReport
        self.sourceAnchor = sourceAnchor ?? .media(startSec: startSec, endSec: endSec)
        self.approved = self.reviewDisposition.isApproved
    }

    enum CodingKeys: String, CodingKey {
        case index, filePath, durationSec, startSec, endSec, original, translated
        case originalCues, originalFormats, translatedFormats, translationsByLanguage
        case unrecognizedFragments, status, approved, reviewDisposition, qualityReport, sourceAnchor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.index = try container.decode(Int.self, forKey: .index)
        self.filePath = try container.decodeIfPresent(String.self, forKey: .filePath) ?? ""
        self.durationSec = try container.decodeIfPresent(Double.self, forKey: .durationSec) ?? 0.0
        self.startSec = try container.decodeIfPresent(Double.self, forKey: .startSec) ?? 0.0
        self.endSec = try container.decodeIfPresent(Double.self, forKey: .endSec) ?? 0.0
        self.original = try container.decodeIfPresent(String.self, forKey: .original) ?? ""
        self.translated = try container.decodeIfPresent(String.self, forKey: .translated) ?? ""
        self.originalCues = try container.decodeIfPresent([TranscriptCue].self, forKey: .originalCues)
        self.originalFormats = try container.decodeIfPresent(LanguageResult.self, forKey: .originalFormats)
        self.translatedFormats = try container.decodeIfPresent(LanguageResult.self, forKey: .translatedFormats)
        self.translationsByLanguage = try container.decodeIfPresent([String: TranslationVariant].self, forKey: .translationsByLanguage)
        self.unrecognizedFragments = try container.decodeIfPresent([String].self, forKey: .unrecognizedFragments)

        if let statusStr = try container.decodeIfPresent(String.self, forKey: .status) {
            self.status = ChunkStatus(rawValue: statusStr.lowercased()) ?? .pending
        } else {
            self.status = .pending
        }

        let decodedApproved = try container.decodeIfPresent(Bool.self, forKey: .approved) ?? false
        self.reviewDisposition = try container.decodeIfPresent(ReviewDisposition.self, forKey: .reviewDisposition)
            ?? (decodedApproved ? .manuallyApproved : .pending)
        self.qualityReport = try container.decodeIfPresent(ChunkQualityReport.self, forKey: .qualityReport)
        self.sourceAnchor = try container.decodeIfPresent(SourceAnchor.self, forKey: .sourceAnchor)
            ?? .media(startSec: self.startSec, endSec: self.endSec)
        self.approved = self.reviewDisposition.isApproved
    }
}

public enum ShortsPlanLanguageMode: String, Codable, CaseIterable, Equatable, Sendable {
    case source
    case target
    case bilingual
}

public struct ShortsClipTranslation: Codable, Equatable, Sendable {
    public var language: String
    public var title: String
    public var summary: String
    public var hook: String
    public var category: String?
    public var captionText: String?
    public var provider: String?
    public var updatedAt: String?

    public init(
        language: String,
        title: String,
        summary: String,
        hook: String,
        category: String? = nil,
        captionText: String? = nil,
        provider: String? = nil,
        updatedAt: String? = nil
    ) {
        self.language = language
        self.title = title
        self.summary = summary
        self.hook = hook
        self.category = category
        self.captionText = captionText
        self.provider = provider
        self.updatedAt = updatedAt
    }
}

public struct ShortsClipPlan: Codable, Equatable, Identifiable, Sendable {
    public var id: String { stableID ?? "legacy-\(start)-\(end)-\(title)" }

    public var stableID: String? = nil
    public var start: String
    public var end: String
    public var title: String
    public var summary: String
    public var hook: String
    public var category: String?
    public var sourceTitle: String?
    public var sourceSummary: String?
    public var sourceHook: String?
    public var sourceCategory: String?
    public var targetTitle: String?
    public var targetSummary: String?
    public var targetHook: String?
    public var targetCategory: String?
    public var captionText: String?
    public var sourceCaptionText: String?
    public var targetCaptionText: String?
    public var translationsByLanguage: [String: ShortsClipTranslation]?
    public var languageMode: ShortsPlanLanguageMode?
    public var sourceAlignment: [AlignedSubtitleSegment]? = nil
    public var targetAlignment: [AlignedSubtitleSegment]? = nil
    public var sourceFrameKeyframes: [FrameKeyframe]? = nil
    public var targetFrameKeyframes: [FrameKeyframe]? = nil
    public var linkedClipGroupId: String? = nil
    public var syncEnabled: Bool? = nil
    public var timelineCuts: [TimelineCut]? = nil
    public var timelineTrim: TimelineTrim? = nil
    public var backgroundSettings: ShortsBackgroundSettings? = nil
    public var subtitleStyle: ShortsSubtitleStyle? = nil
    public var logo: LogoOverlaySettings? = nil
    public var textTracks: [TextOverlayTrack]? = nil
    public var audioTracks: [ExtraAudioTrack]? = nil
    public var intro: IntroOutroOverlaySettings? = nil
    public var outro: IntroOutroOverlaySettings? = nil
    public var sourceLogo: LogoOverlaySettings? = nil
    public var targetLogo: LogoOverlaySettings? = nil
    public var sourceTextTracks: [TextOverlayTrack]? = nil
    public var targetTextTracks: [TextOverlayTrack]? = nil
    public var sourceAudioTracks: [ExtraAudioTrack]? = nil
    public var targetAudioTracks: [ExtraAudioTrack]? = nil
    public var sourceIntro: IntroOutroOverlaySettings? = nil
    public var targetIntro: IntroOutroOverlaySettings? = nil
    public var sourceOutro: IntroOutroOverlaySettings? = nil
    public var targetOutro: IntroOutroOverlaySettings? = nil

    public init(
        stableID: String? = UUID().uuidString.lowercased(),
        start: String,
        end: String,
        title: String,
        summary: String,
        hook: String,
        category: String? = nil,
        sourceTitle: String? = nil,
        sourceSummary: String? = nil,
        sourceHook: String? = nil,
        sourceCategory: String? = nil,
        targetTitle: String? = nil,
        targetSummary: String? = nil,
        targetHook: String? = nil,
        targetCategory: String? = nil,
        captionText: String? = nil,
        sourceCaptionText: String? = nil,
        targetCaptionText: String? = nil,
        translationsByLanguage: [String: ShortsClipTranslation]? = nil,
        languageMode: ShortsPlanLanguageMode? = nil,
        sourceAlignment: [AlignedSubtitleSegment]? = nil,
        targetAlignment: [AlignedSubtitleSegment]? = nil,
        sourceFrameKeyframes: [FrameKeyframe]? = nil,
        targetFrameKeyframes: [FrameKeyframe]? = nil,
        linkedClipGroupId: String? = nil,
        syncEnabled: Bool? = nil,
        timelineCuts: [TimelineCut]? = nil,
        timelineTrim: TimelineTrim? = nil,
        backgroundSettings: ShortsBackgroundSettings? = nil,
        subtitleStyle: ShortsSubtitleStyle? = nil,
        logo: LogoOverlaySettings? = nil,
        textTracks: [TextOverlayTrack]? = nil,
        audioTracks: [ExtraAudioTrack]? = nil,
        intro: IntroOutroOverlaySettings? = nil,
        outro: IntroOutroOverlaySettings? = nil,
        sourceLogo: LogoOverlaySettings? = nil,
        targetLogo: LogoOverlaySettings? = nil,
        sourceTextTracks: [TextOverlayTrack]? = nil,
        targetTextTracks: [TextOverlayTrack]? = nil,
        sourceAudioTracks: [ExtraAudioTrack]? = nil,
        targetAudioTracks: [ExtraAudioTrack]? = nil,
        sourceIntro: IntroOutroOverlaySettings? = nil,
        targetIntro: IntroOutroOverlaySettings? = nil,
        sourceOutro: IntroOutroOverlaySettings? = nil,
        targetOutro: IntroOutroOverlaySettings? = nil
    ) {
        self.stableID = stableID
        self.start = start
        self.end = end
        self.title = title
        self.summary = summary
        self.hook = hook
        self.category = category
        self.sourceTitle = sourceTitle
        self.sourceSummary = sourceSummary
        self.sourceHook = sourceHook
        self.sourceCategory = sourceCategory
        self.targetTitle = targetTitle
        self.targetSummary = targetSummary
        self.targetHook = targetHook
        self.targetCategory = targetCategory
        self.captionText = captionText
        self.sourceCaptionText = sourceCaptionText
        self.targetCaptionText = targetCaptionText
        self.translationsByLanguage = translationsByLanguage
        self.languageMode = languageMode
        self.sourceAlignment = sourceAlignment
        self.targetAlignment = targetAlignment
        self.sourceFrameKeyframes = sourceFrameKeyframes
        self.targetFrameKeyframes = targetFrameKeyframes
        self.linkedClipGroupId = linkedClipGroupId
        self.syncEnabled = syncEnabled
        self.timelineCuts = timelineCuts
        self.timelineTrim = timelineTrim
        self.backgroundSettings = backgroundSettings
        self.subtitleStyle = subtitleStyle
        self.logo = logo
        self.textTracks = textTracks
        self.audioTracks = audioTracks
        self.intro = intro
        self.outro = outro
        self.sourceLogo = sourceLogo
        self.targetLogo = targetLogo
        self.sourceTextTracks = sourceTextTracks
        self.targetTextTracks = targetTextTracks
        self.sourceAudioTracks = sourceAudioTracks
        self.targetAudioTracks = targetAudioTracks
        self.sourceIntro = sourceIntro
        self.targetIntro = targetIntro
        self.sourceOutro = sourceOutro
        self.targetOutro = targetOutro
    }
}

public struct SessionConfig: Codable, Equatable, Sendable {
    public var date: String
    public var location: String
    public var lecturer: String
    public var participants: String
    public var targetLang: String
    public var formats: [OutputFormat]
    public var transcriptionProvider: String
    public var translationProvider: String
}

public struct SessionState: Codable, Equatable, Sendable {
    public var sourceFile: String?
    public var sourceFileName: String
    public var sourceMediaInfo: SourceMediaInfo?
    public var sourceKind: WorkflowSourceKind
    public var documentState: DocumentState?
    public var durationSec: Double
    public var metadata: AudioMetadata
    public var sourceLang: String
    public var targetLang: String
    public var transcriptionProvider: String
    public var translationProvider: String
    public var outputFormats: [OutputFormat]
    public var chunks: [ChunkData]
    public var currentChunkIndex: Int
    public var approvalMode: ApprovalMode
    public var availableTranslationLanguages: [String]? = nil
    public var activeTranslationLanguage: String? = nil
    public var shortsPlans: [ShortsClipPlan]? = nil
    public var shortsRejectedPlans: [ShortsClipPlan]? = nil

    public init(
        sourceFile: String?,
        sourceFileName: String,
        durationSec: Double,
        metadata: AudioMetadata,
        sourceLang: String,
        targetLang: String,
        transcriptionProvider: String,
        translationProvider: String,
        outputFormats: [OutputFormat],
        chunks: [ChunkData],
        currentChunkIndex: Int,
        availableTranslationLanguages: [String]? = nil,
        activeTranslationLanguage: String? = nil,
        shortsPlans: [ShortsClipPlan]? = nil,
        shortsRejectedPlans: [ShortsClipPlan]? = nil,
        sourceMediaInfo: SourceMediaInfo? = nil,
        sourceKind: WorkflowSourceKind = .media,
        documentState: DocumentState? = nil,
        approvalMode: ApprovalMode = .manual
    ) {
        self.sourceFile = sourceFile
        self.sourceFileName = sourceFileName
        self.sourceMediaInfo = sourceMediaInfo
        self.sourceKind = sourceKind
        self.documentState = documentState
        self.durationSec = durationSec
        self.metadata = metadata
        self.sourceLang = sourceLang
        self.targetLang = targetLang
        self.transcriptionProvider = transcriptionProvider
        self.translationProvider = translationProvider
        self.outputFormats = outputFormats
        self.chunks = chunks
        self.currentChunkIndex = currentChunkIndex
        self.availableTranslationLanguages = availableTranslationLanguages
        self.activeTranslationLanguage = activeTranslationLanguage
        self.shortsPlans = shortsPlans
        self.shortsRejectedPlans = shortsRejectedPlans
        self.approvalMode = approvalMode
    }

    enum CodingKeys: String, CodingKey {
        case sourceFile, sourceFileName, sourceMediaInfo, sourceKind, documentState
        case durationSec, metadata, sourceLang, targetLang
        case transcriptionProvider, translationProvider, outputFormats, chunks, currentChunkIndex
        case availableTranslationLanguages, activeTranslationLanguage, shortsPlans, shortsRejectedPlans
        case approvalMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sourceFile = try container.decodeIfPresent(String.self, forKey: .sourceFile)
        self.sourceFileName = try container.decodeIfPresent(String.self, forKey: .sourceFileName) ?? "Imported Session"
        self.sourceMediaInfo = try container.decodeIfPresent(SourceMediaInfo.self, forKey: .sourceMediaInfo)
        self.sourceKind = try container.decodeIfPresent(WorkflowSourceKind.self, forKey: .sourceKind) ?? .media
        self.documentState = try container.decodeIfPresent(DocumentState.self, forKey: .documentState)
        self.durationSec = try container.decodeIfPresent(Double.self, forKey: .durationSec) ?? 0.0
        self.metadata = try container.decodeIfPresent(AudioMetadata.self, forKey: .metadata) ?? AudioMetadata.empty
        self.sourceLang = try container.decodeIfPresent(String.self, forKey: .sourceLang) ?? "auto"
        self.targetLang = try container.decodeIfPresent(String.self, forKey: .targetLang) ?? "ru"

        self.transcriptionProvider = try container.decodeIfPresent(String.self, forKey: .transcriptionProvider) ?? "coreml-whisperkit"
        self.translationProvider = try container.decodeIfPresent(String.self, forKey: .translationProvider) ?? "none"

        self.outputFormats = try container.decodeIfPresent([OutputFormat].self, forKey: .outputFormats) ?? []
        self.chunks = try container.decodeIfPresent([ChunkData].self, forKey: .chunks) ?? []
        self.currentChunkIndex = try container.decodeIfPresent(Int.self, forKey: .currentChunkIndex) ?? 0
        self.approvalMode = try container.decodeIfPresent(ApprovalMode.self, forKey: .approvalMode) ?? .manual
        self.availableTranslationLanguages = try container.decodeIfPresent([String].self, forKey: .availableTranslationLanguages)
        self.activeTranslationLanguage = try container.decodeIfPresent(String.self, forKey: .activeTranslationLanguage)
        self.shortsPlans = try container.decodeIfPresent([ShortsClipPlan].self, forKey: .shortsPlans)
        self.shortsRejectedPlans = try container.decodeIfPresent([ShortsClipPlan].self, forKey: .shortsRejectedPlans)
    }
}

/// The data-only presentation contract used by the document Review surface.
/// Media Review continues to use timed cues and playback controls; document
/// Review uses this value when a chunk has no cues at all.
public struct DocumentReviewPresentation: Equatable, Sendable {
    public let sourceText: String
    public let translatedText: String
    public let chapterLabel: String
    public let blockRangeLabel: String
    public let displayLabel: String
    public let blockRoles: [String]
    public let showsAudioBar: Bool
    public let showsWaveform: Bool
    public let showsTimecode: Bool
    public let usesSourceTextFallback: Bool

    public init(
        sourceText: String,
        translatedText: String,
        chapterLabel: String,
        blockRangeLabel: String,
        displayLabel: String,
        blockRoles: [String],
        showsAudioBar: Bool = false,
        showsWaveform: Bool = false,
        showsTimecode: Bool = false,
        usesSourceTextFallback: Bool = true
    ) {
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.chapterLabel = chapterLabel
        self.blockRangeLabel = blockRangeLabel
        self.displayLabel = displayLabel
        self.blockRoles = blockRoles
        self.showsAudioBar = showsAudioBar
        self.showsWaveform = showsWaveform
        self.showsTimecode = showsTimecode
        self.usesSourceTextFallback = usesSourceTextFallback
    }
}

public enum DocumentReviewPresentationPolicy {
    public static func make(
        session: SessionState,
        chunk: ChunkData
    ) -> DocumentReviewPresentation? {
        guard session.sourceKind == .document else { return nil }
        let documentState = session.documentState
        let plan = documentState?.chunks.first { plan in
            guard case let .document(range) = chunk.sourceAnchor else { return false }
            return plan.blockIDs.first == range.startBlockID
                && plan.blockIDs.last == range.endBlockID
        }
        let blockIDs: [String]
        if let plan {
            blockIDs = plan.blockIDs
        } else if case let .document(range) = chunk.sourceAnchor {
            blockIDs = [range.startBlockID, range.endBlockID].uniquedPreservingOrder()
        } else {
            blockIDs = []
        }
        let blocks = blockIDs.compactMap { id in
            documentState?.blocks.first(where: { $0.id == id })
        }
        let derivedText = aggregateSourceText(blocks: blocks, plan: plan)
        let sourceText = chunk.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? derivedText
            : chunk.original
        let roles = blocks.map(role(for:))
        let firstBlock = blocks.first
        let lastBlock = blocks.last ?? firstBlock
        let startOrdinal = firstBlock?.location.paragraphOrdinal ?? 0
        let endOrdinal = lastBlock?.location.paragraphOrdinal ?? startOrdinal
        let blockRangeLabel = startOrdinal == endOrdinal
            ? "paragraph \(startOrdinal + 1)"
            : "paragraphs \(startOrdinal + 1)–\(endOrdinal + 1)"
        let chapter = chapterLabel(for: firstBlock, in: documentState?.blocks ?? [])
        return DocumentReviewPresentation(
            sourceText: sourceText,
            translatedText: session.documentTranslationText(for: chunk) ?? chunk.translated,
            chapterLabel: chapter,
            blockRangeLabel: blockRangeLabel,
            displayLabel: "\(chapter) · \(blockRangeLabel)",
            blockRoles: roles,
            usesSourceTextFallback: (chunk.originalCues ?? []).isEmpty
        )
    }

    public static func visibleSourceText(session: SessionState, chunk: ChunkData) -> String {
        make(session: session, chunk: chunk)?.sourceText ?? chunk.original
    }

    private static func aggregateSourceText(
        blocks: [DocumentBlock],
        plan: DocumentChunkPlan?
    ) -> String {
        guard let plan, let slices = plan.blockSlices, !slices.isEmpty else {
            return blocks.map { $0.spans.map(\.text).joined() }.joined(separator: "\n\n")
        }
        let byID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
        return slices.compactMap { slice in
            guard let block = byID[slice.blockID] else { return nil }
            let text = block.spans.map(\.text).joined()
            let start = text.index(text.startIndex, offsetBy: min(slice.startOffset, text.count))
            let end = text.index(text.startIndex, offsetBy: min(max(slice.endOffset, slice.startOffset), text.count))
            return String(text[start..<end])
        }.joined(separator: "\n\n")
    }

    private static func chapterLabel(for block: DocumentBlock?, in blocks: [DocumentBlock]) -> String {
        guard let block else { return "Document" }
        let prior = blocks.filter {
            $0.location.part == block.location.part
                && $0.location.paragraphOrdinal <= block.location.paragraphOrdinal
                && isChapterTitle($0)
        }.last
        return prior
            .map { $0.spans.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "Document"
    }

    private static func role(for block: DocumentBlock) -> String {
        if block.kind == .heading { return "heading" }
        if block.kind == .quote { return "quote" }
        if block.kind == .verse { return "verse" }
        let style = (block.styleID ?? "").lowercased()
        if style.contains("verse") || style.contains("shlok") || style.contains("stanza") || style.contains("poem") {
            return "verse"
        }
        if style.contains("quote") { return "quote" }
        if block.kind == .empty { return "empty" }
        return "body"
    }

    private static func isChapterTitle(_ block: DocumentBlock) -> Bool {
        guard block.kind == .heading || (block.styleID?.lowercased().contains("chapter") == true) else { return false }
        let style = (block.styleID ?? "").lowercased()
        if style.contains("book title") || style.contains("book-title") { return false }
        if style.contains("chapter") { return true }
        let rawText = block.spans.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let text = rawText.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
        return ["chapter ", "глава ", "part ", "часть ", "prologue", "epilogue", "preface", "afterword"]
            .contains(where: text.hasPrefix)
    }
}

private extension Array where Element: Equatable {
    func uniquedPreservingOrder() -> [Element] {
        reduce(into: []) { result, element in
            if !result.contains(element) { result.append(element) }
        }
    }
}

public struct ProjectSummary: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var sourceFileName: String
    public var sourceMediaInfo: SourceMediaInfo?
    public var updatedAt: String
    public var createdAt: String
    public var currentIndex: Int
    public var totalChunks: Int
    public var approvedChunks: Int
    public var completedChunks: Int
    public var targetLang: String
    /// Derived, not persisted: document chunk indices whose translation no
    /// longer matches the source (PRD §9). Empty for media projects.
    public var staleChunkIndices: Set<Int>

    enum CodingKeys: String, CodingKey {
        case id, name, sourceFileName, sourceMediaInfo, updatedAt, createdAt
        case currentIndex, totalChunks, approvedChunks, completedChunks, targetLang
    }

    public init(
        id: String,
        name: String,
        sourceFileName: String,
        sourceMediaInfo: SourceMediaInfo? = nil,
        updatedAt: String,
        createdAt: String,
        currentIndex: Int,
        totalChunks: Int,
        approvedChunks: Int,
        completedChunks: Int,
        targetLang: String,
        staleChunkIndices: Set<Int> = []
    ) {
        self.id = id
        self.name = name
        self.sourceFileName = sourceFileName
        self.sourceMediaInfo = sourceMediaInfo
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.currentIndex = currentIndex
        self.totalChunks = totalChunks
        self.approvedChunks = approvedChunks
        self.completedChunks = completedChunks
        self.targetLang = targetLang
        self.staleChunkIndices = staleChunkIndices
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.sourceFileName = try container.decode(String.self, forKey: .sourceFileName)
        self.sourceMediaInfo = try container.decodeIfPresent(SourceMediaInfo.self, forKey: .sourceMediaInfo)
        self.updatedAt = try container.decode(String.self, forKey: .updatedAt)
        self.createdAt = try container.decode(String.self, forKey: .createdAt)
        self.currentIndex = try container.decode(Int.self, forKey: .currentIndex)
        self.totalChunks = try container.decode(Int.self, forKey: .totalChunks)
        self.approvedChunks = try container.decode(Int.self, forKey: .approvedChunks)
        self.completedChunks = try container.decodeIfPresent(Int.self, forKey: .completedChunks) ?? self.approvedChunks
        self.targetLang = try container.decode(String.self, forKey: .targetLang)
        self.staleChunkIndices = []
    }

    public func canOpenChunk(at index: Int) -> Bool {
        guard index >= 0, index < totalChunks else { return false }
        guard totalChunks > 0 else { return false }

        if approvedChunks >= totalChunks || completedChunks >= totalChunks {
            return true
        }

        let lastVisitedIndex = min(max(0, currentIndex), totalChunks - 1)
        if index <= lastVisitedIndex {
            return true
        }

        return index < min(max(0, completedChunks), totalChunks)
    }

    public var lastWorkInProgressChunkIndex: Int? {
        guard totalChunks > 0 else { return nil }
        guard approvedChunks < totalChunks else { return nil }

        if completedChunks >= totalChunks {
            return totalChunks - 1
        }

        let lastCompletedIndex = completedChunks > 0 ? completedChunks - 1 : 0
        return min(max(currentIndex, lastCompletedIndex, 0), totalChunks - 1)
    }

    public func shouldShowLastBadge(at index: Int) -> Bool {
        lastWorkInProgressChunkIndex == index
    }

    public func isStaleChunk(at index: Int) -> Bool {
        staleChunkIndices.contains(index)
    }
}

public extension ChunkData {
    mutating func setTranslation(
        _ text: String,
        language: String,
        provider: String? = nil,
        updatedAt: String? = nil,
        formats: LanguageResult? = nil,
        cues: [TranscriptCue]? = nil
    ) {
        let display = TranslationArchive.displayLanguage(language)
        guard TranslationArchive.isRealLanguage(display) else { return }
        guard TranslationArchive.isUsableTranslationText(text) else { return }

        var archive = translationsByLanguage ?? [:]
        archive[TranslationArchive.languageKey(display)] = TranslationVariant(
            language: display,
            text: text,
            cues: cues,
            formats: formats,
            provider: provider,
            updatedAt: updatedAt
        )
        translationsByLanguage = archive
    }

    func translationVariant(for language: String?) -> TranslationVariant? {
        guard let language, TranslationArchive.isRealLanguage(language) else { return nil }
        return translationsByLanguage?[TranslationArchive.languageKey(language)]
    }

    func translationText(for language: String?) -> String? {
        if let text = translationVariant(for: language)?.text {
            return TranslationArchive.isUsableTranslationText(text) ? text : nil
        }

        guard language == nil else { return nil }
        let legacyText = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        return TranslationArchive.isUsableTranslationText(legacyText) ? translated : nil
    }

    func translationCues(for language: String?) -> [TranscriptCue] {
        translationVariant(for: language)?.cues ?? []
    }
}

public extension ShortsClipPlan {
    mutating func setTranslation(_ translation: ShortsClipTranslation) {
        let display = TranslationArchive.displayLanguage(translation.language)
        guard TranslationArchive.isRealLanguage(display) else { return }

        var copy = translation
        copy.language = display
        var archive = translationsByLanguage ?? [:]
        archive[TranslationArchive.languageKey(display)] = copy
        translationsByLanguage = archive
    }

    func translation(for language: String?) -> ShortsClipTranslation? {
        guard let language, TranslationArchive.isRealLanguage(language) else { return nil }
        return translationsByLanguage?[TranslationArchive.languageKey(language)]
    }
}

public extension SessionState {
    var selectedTranslationLanguage: String? {
        if let activeTranslationLanguage, TranslationArchive.isRealLanguage(activeTranslationLanguage) {
            return activeTranslationLanguage
        }
        if TranslationArchive.isRealLanguage(targetLang) {
            return targetLang
        }
        return nil
    }

    mutating func registerTranslationLanguage(_ language: String) {
        let display = TranslationArchive.displayLanguage(language)
        guard TranslationArchive.isRealLanguage(display) else { return }

        var languagesByKey: [String: String] = [:]
        for existing in availableTranslationLanguages ?? [] where TranslationArchive.isRealLanguage(existing) {
            languagesByKey[TranslationArchive.languageKey(existing)] = TranslationArchive.displayLanguage(existing)
        }
        languagesByKey[TranslationArchive.languageKey(display)] = display
        availableTranslationLanguages = sortedLanguages(languagesByKey)
    }

    mutating func setActiveTranslationLanguage(_ language: String) {
        let display = TranslationArchive.displayLanguage(language)
        guard TranslationArchive.isRealLanguage(display) else { return }
        activeTranslationLanguage = display
        targetLang = display
        registerTranslationLanguage(display)

        for index in chunks.indices {
            if let text = chunks[index].translationText(for: display) {
                chunks[index].translated = text
            } else {
                chunks[index].translated = ""
            }
        }
    }

    func documentTranslationText(for chunk: ChunkData, language: String? = nil) -> String? {
        guard sourceKind == .document, let documentState else { return nil }
        let selected = language ?? selectedTranslationLanguage ?? targetLang
        let key = TranslationArchive.languageKey(selected)
        let translations = documentState.translationsByLanguage[key] ?? [:]
        guard let plan = documentPlan(for: chunk, in: documentState) else { return nil }
        let text = plan.blockIDs.compactMap { translations[$0]?.text }.joined(separator: "\n\n")
        return TranslationArchive.isUsableTranslationText(text) ? text : nil
    }

    mutating func extractMetadataFromCuesIfNeeded() {
        guard !chunks.isEmpty else { return }

        let timestampPattern = "^\\[(?:(?:\\d+:)?\\d{1,5}:\\d{2}(?:[.,]\\d{1,3})?)\\]\\s*"
        let timestampRegex = try? NSRegularExpression(pattern: timestampPattern)

        func stripTimestampPrefix(_ line: String) -> String {
            guard let regex = timestampRegex else { return line }
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            if regex.firstMatch(in: line, range: range) != nil {
                return regex.stringByReplacingMatches(in: line, range: range, withTemplate: "")
            }
            return line
        }

        var firstChunk = chunks[0]
        var metadataUpdated = false

        var extractedDate: String?
        var extractedLocation: String?
        var extractedLecturer: String?
        var extractedParticipants: String?

        func parseMetadataLine(_ line: String) -> Bool {
            let stripped = stripTimestampPrefix(line)
            let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()

            if lower.hasPrefix("date:") {
                let val = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                if val.lowercased() != "none" && !val.isEmpty {
                    extractedDate = val
                }
                return true
            } else if lower.hasPrefix("location:") {
                let val = trimmed.dropFirst(9).trimmingCharacters(in: .whitespacesAndNewlines)
                if val.lowercased() != "none" && !val.isEmpty {
                    extractedLocation = val
                }
                return true
            } else if lower.hasPrefix("lecturer:") || lower.hasPrefix("author:") || lower.hasPrefix("speaker:") {
                let limit = lower.hasPrefix("lecturer:") ? 9 : (lower.hasPrefix("speaker:") ? 8 : 7)
                let val = trimmed.dropFirst(limit).trimmingCharacters(in: .whitespacesAndNewlines)
                if val.lowercased() != "none" && !val.isEmpty {
                    extractedLecturer = val
                }
                return true
            } else if lower.hasPrefix("interviewer:") || lower.hasPrefix("participants:") || lower.hasPrefix("interviewer / participants:") {
                let limit = lower.hasPrefix("interviewer / participants:") ? 27 : (lower.hasPrefix("participants:") ? 13 : 12)
                let val = trimmed.dropFirst(limit).trimmingCharacters(in: .whitespacesAndNewlines)
                if val.lowercased() != "none" && !val.isEmpty {
                    extractedParticipants = val
                }
                return true
            }
            return false
        }

        // Clean originalCues
        if let cues = firstChunk.originalCues {
            var newCues: [TranscriptCue] = []
            for cue in cues {
                let lines = cue.text.components(separatedBy: .newlines)
                var remainingLines: [String] = []
                var cueHadMetadata = false

                for line in lines {
                    if parseMetadataLine(line) {
                        cueHadMetadata = true
                    } else {
                        remainingLines.append(line)
                    }
                }

                if cueHadMetadata {
                    metadataUpdated = true
                    let remainingText = remainingLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !remainingText.isEmpty {
                        var updatedCue = cue
                        updatedCue.text = remainingText
                        newCues.append(updatedCue)
                    }
                } else {
                    newCues.append(cue)
                }
            }
            firstChunk.originalCues = newCues
        }

        // Clean original raw text
        let lines = firstChunk.original.components(separatedBy: .newlines)
        var remainingLines: [String] = []
        var rawTextUpdated = false
        for line in lines {
            if parseMetadataLine(line) {
                rawTextUpdated = true
            } else {
                remainingLines.append(line)
            }
        }
        if rawTextUpdated {
            metadataUpdated = true
            firstChunk.original = remainingLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if let updatedCues = firstChunk.originalCues {
                firstChunk.original = updatedCues.map(\.text).joined(separator: " ")
            }
        }

        // Clean translationsByLanguage as well
        if var translations = firstChunk.translationsByLanguage {
            for langKey in translations.keys {
                guard var variant = translations[langKey] else { continue }
                var variantUpdated = false

                func isTranslationMetadataLine(_ line: String) -> Bool {
                    let stripped = stripTimestampPrefix(line)
                    let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let prefixes = [
                        "date:", "дата:",
                        "location:", "локация:", "место:",
                        "lecturer:", "лектор:", "автор:", "speaker:", "докладчик:",
                        "interviewer:", "интервьюер:", "participants:", "участники:"
                    ]
                    return prefixes.contains { prefix in
                        trimmed.hasPrefix(prefix)
                    }
                }

                if let variantCues = variant.cues {
                    var newVarCues: [TranscriptCue] = []
                    for cue in variantCues {
                        let lines = cue.text.components(separatedBy: .newlines)
                        var remainingLines: [String] = []
                        var cueHadMetadata = false
                        for line in lines {
                            if isTranslationMetadataLine(line) {
                                cueHadMetadata = true
                            } else {
                                remainingLines.append(line)
                            }
                        }
                        if cueHadMetadata {
                            variantUpdated = true
                            let remainingText = remainingLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                            if !remainingText.isEmpty {
                                var updatedCue = cue
                                updatedCue.text = remainingText
                                newVarCues.append(updatedCue)
                            }
                        } else {
                            newVarCues.append(cue)
                        }
                    }
                    variant.cues = newVarCues
                }

                let varLines = variant.text.components(separatedBy: .newlines)
                var varRemainingLines: [String] = []
                var textVarUpdated = false
                for line in varLines {
                    if isTranslationMetadataLine(line) {
                        textVarUpdated = true
                    } else {
                        varRemainingLines.append(line)
                    }
                }
                if textVarUpdated {
                    variantUpdated = true
                    variant.text = varRemainingLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                }

                if variantUpdated {
                    if let varCues = variant.cues {
                        variant.text = varCues.map(\.text).joined(separator: " ")
                    }
                    translations[langKey] = variant
                }
            }
            firstChunk.translationsByLanguage = translations
        }

        if metadataUpdated {
            func isPlaceholder(_ val: String) -> Bool {
                let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return trimmed.isEmpty || trimmed == "none" || trimmed == "unknown" || trimmed == "null"
            }

            if let date = extractedDate, isPlaceholder(metadata.date) {
                metadata.date = date
            }
            if let location = extractedLocation, isPlaceholder(metadata.location) {
                metadata.location = location
            }
            if let lecturer = extractedLecturer, isPlaceholder(metadata.lecturer) {
                metadata.lecturer = lecturer
            }
            if let participants = extractedParticipants, isPlaceholder(metadata.participants) {
                metadata.participants = participants
            }

            chunks[0] = firstChunk
        }
    }

    mutating func normalizeTranslationArchive() {
        if sourceKind == .media {
            extractMetadataFromCuesIfNeeded()
        }

        if shortsPlans != nil {
            for index in shortsPlans!.indices {
                if shortsPlans![index].stableID == nil {
                    shortsPlans![index].stableID = UUID().uuidString.lowercased()
                }
                if shortsPlans![index].timelineCuts != nil {
                    for cutIndex in shortsPlans![index].timelineCuts!.indices where shortsPlans![index].timelineCuts![cutIndex].stableID == nil {
                        shortsPlans![index].timelineCuts![cutIndex].stableID = UUID().uuidString.lowercased()
                    }
                }
            }
        }
        if shortsRejectedPlans != nil {
            for index in shortsRejectedPlans!.indices {
                if shortsRejectedPlans![index].stableID == nil {
                    shortsRejectedPlans![index].stableID = UUID().uuidString.lowercased()
                }
                if shortsRejectedPlans![index].timelineCuts != nil {
                    for cutIndex in shortsRejectedPlans![index].timelineCuts!.indices where shortsRejectedPlans![index].timelineCuts![cutIndex].stableID == nil {
                        shortsRejectedPlans![index].timelineCuts![cutIndex].stableID = UUID().uuidString.lowercased()
                    }
                }
            }
        }
        let legacyLanguage = TranslationArchive.displayLanguage(targetLang)
        if TranslationArchive.isRealLanguage(legacyLanguage) {
            targetLang = legacyLanguage
            for index in chunks.indices {
                let legacyText = chunks[index].translated.trimmingCharacters(in: .whitespacesAndNewlines)
                if TranslationArchive.isUsableTranslationText(legacyText), chunks[index].translationVariant(for: legacyLanguage) == nil {
                    chunks[index].setTranslation(legacyText, language: legacyLanguage)
                }
            }
            registerTranslationLanguage(legacyLanguage)
        }

        migrateLegacyDocumentSourceHashes()

        if sourceKind == .document, let documentState {
            let documentLanguage = TranslationArchive.languageKey(targetLang)
            let translations = documentState.translationsByLanguage[documentLanguage] ?? [:]
            for index in chunks.indices {
                guard let plan = documentPlan(for: chunks[index], in: documentState) else { continue }
                let text = plan.blockIDs.compactMap { translations[$0]?.text }
                    .joined(separator: "\n\n")
                if TranslationArchive.isUsableTranslationText(text) {
                    chunks[index].translated = text
                }
            }
            registerTranslationLanguage(targetLang)
        }

        if sourceKind == .media {
            for index in chunks.indices {
                // Reconstruct original cues if missing.
                let originalText = chunks[index].original.trimmingCharacters(in: .whitespacesAndNewlines)
                if !originalText.isEmpty && (chunks[index].originalCues == nil || chunks[index].originalCues?.isEmpty == true) {
                    // Prefer real timing parsed from inline [mm:ss] markers
                    // (VaniScript/Electron transcripts) over the even-distribution
                    // fallback, and strip the markers so they don't render as text.
                    let timestampedCues = SessionState.reconstructCuesFromTimestampedText(
                        chunks[index].original,
                        startSec: chunks[index].startSec,
                        endSec: chunks[index].endSec
                    )
                    if !timestampedCues.isEmpty {
                        chunks[index].originalCues = timestampedCues
                        chunks[index].original = SessionState.strippingInlineTimestampMarkers(chunks[index].original)
                    } else {
                        chunks[index].originalCues = SessionState.reconstructCuesFromRawText(
                            originalText,
                            startSec: chunks[index].startSec,
                            endSec: chunks[index].endSec
                        )
                    }
                }

                // Reconstruct translation cues if missing. Electron transcripts carry
                // their own [mm:ss] markers in the translation, so parse those for real
                // timing (and strip them); otherwise distribute evenly over the source cues.
                if var translations = chunks[index].translationsByLanguage {
                    for key in translations.keys {
                        if translations[key]?.cues == nil || translations[key]?.cues?.isEmpty == true {
                            let variantText = translations[key]?.text ?? ""
                            let trimmedVariant = variantText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmedVariant.isEmpty else { continue }
                            let timestamped = SessionState.reconstructCuesFromTimestampedText(
                                variantText,
                                startSec: chunks[index].startSec,
                                endSec: chunks[index].endSec
                            )
                            if !timestamped.isEmpty {
                                translations[key]?.cues = timestamped
                                translations[key]?.text = SessionState.strippingInlineTimestampMarkers(variantText)
                            } else if let originalCues = chunks[index].originalCues, !originalCues.isEmpty {
                                translations[key]?.cues = SessionState.reconstructTranslationCues(
                                    from: trimmedVariant,
                                    matching: originalCues
                                )
                            }
                        }
                    }
                    chunks[index].translationsByLanguage = translations
                }
            }
        }

        var languagesByKey: [String: String] = [:]
        for existing in availableTranslationLanguages ?? [] where TranslationArchive.isRealLanguage(existing) {
            languagesByKey[TranslationArchive.languageKey(existing)] = TranslationArchive.displayLanguage(existing)
        }
        for chunk in chunks {
            if let translations = chunk.translationsByLanguage {
                for variant in translations.values where TranslationArchive.isRealLanguage(variant.language) {
                    languagesByKey[TranslationArchive.languageKey(variant.language)] = TranslationArchive.displayLanguage(variant.language)
                }
            }
        }
        for plan in shortsPlans ?? [] {
            if let translations = plan.translationsByLanguage {
                for variant in translations.values where TranslationArchive.isRealLanguage(variant.language) {
                    languagesByKey[TranslationArchive.languageKey(variant.language)] = TranslationArchive.displayLanguage(variant.language)
                }
            }
        }

        availableTranslationLanguages = sortedLanguages(languagesByKey)
        if activeTranslationLanguage == nil {
            activeTranslationLanguage = TranslationArchive.isRealLanguage(legacyLanguage)
                ? legacyLanguage
                : availableTranslationLanguages?.first
        }
        if let activeTranslationLanguage {
            setActiveTranslationLanguage(activeTranslationLanguage)
        }
    }

    /// ADR-005: rewrite pre-ADR-004 translations whose stored sourceHash equals
    /// the composite plan hash (the legacy convention) to the current block text
    /// hash. The marker is exact — a SHA-256 block hash can never equal a
    /// composite plan hash — so this only touches legacy-convention entries.
    private mutating func migrateLegacyDocumentSourceHashes() {
        guard sourceKind == .document, var documentState else { return }
        // Map base blockID -> plan.sourceHash for every plan.
        var planHashByBlockID: [String: String] = [:]
        for plan in documentState.chunks {
            for blockID in plan.blockIDs { planHashByBlockID[blockID] = plan.sourceHash }
        }
        guard !planHashByBlockID.isEmpty else { return }
        let blocksByID = Dictionary(uniqueKeysWithValues: documentState.blocks.map { ($0.id, $0) })
        var anyChanged = false
        for (languageKey, translations) in documentState.translationsByLanguage {
            var updated = translations
            var languageChanged = false
            for (key, translated) in translations {
                // Resolve slice/fragment keys ("id#slice_N", "id:slice:a:b") to the base block id.
                let afterHash = key.split(separator: "#").first.map(String.init) ?? key
                let baseID = afterHash.split(separator: ":").first.map(String.init) ?? afterHash
                guard let legacyPlanHash = planHashByBlockID[baseID],
                      translated.sourceHash == legacyPlanHash,
                      let block = blocksByID[baseID],
                      !block.sourceHash.isEmpty
                else { continue }
                updated[key]?.sourceHash = block.sourceHash
                languageChanged = true
            }
            if languageChanged {
                documentState.translationsByLanguage[languageKey] = updated
                anyChanged = true
            }
        }
        if anyChanged { self.documentState = documentState }
    }

    /// Indices of document chunks whose translation no longer matches the
    /// source in the given language (PRD §9). A chunk is stale when any of
    /// its plan blocks is provably stale (both hashes present and different);
    /// empty-hash blocks cannot prove staleness. Empty for media or missing
    /// document state.
    func staleDocumentChunkIndices(languageKey: String) -> Set<Int> {
        guard sourceKind == .document, let documentState else { return [] }
        var staleIndices: Set<Int> = []
        for index in chunks.indices {
            let plan: DocumentChunkPlan?
            if case let .document(range) = chunks[index].sourceAnchor {
                plan = documentState.chunks.first {
                    $0.blockIDs.first == range.startBlockID && $0.blockIDs.last == range.endBlockID
                }
            } else {
                plan = documentState.chunks.indices.contains(index) ? documentState.chunks[index] : nil
            }
            guard let plan else { continue }
            let isStale = plan.blockIDs.contains { blockID in
                TranslationFreshness.isProvablyStale(
                    documentState: documentState,
                    blockID: blockID,
                    languageKey: languageKey
                )
            }
            if isStale { staleIndices.insert(index) }
        }
        return staleIndices
    }

    private func documentPlan(for chunk: ChunkData, in state: DocumentState) -> DocumentChunkPlan? {
        if case let .document(range) = chunk.sourceAnchor {
            if let matched = state.chunks.first(where: {
                $0.blockIDs.first == range.startBlockID && $0.blockIDs.last == range.endBlockID
            }) {
                return matched
            }
        }
        return state.chunks.indices.contains(chunk.index) ? state.chunks[chunk.index] : nil
    }

    static func reconstructCuesFromRawText(_ text: String, startSec: Double, endSec: Double) -> [TranscriptCue] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var sentences: [String] = []
        var currentSentence = ""

        let chars = Array(trimmed)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            currentSentence.append(c)

            let isBoundChar = (c == "." || c == "?" || c == "!" || c == "\n")
            var isBoundary = false
            if isBoundChar {
                if c == "\n" || i + 1 == chars.count {
                    isBoundary = true
                } else {
                    let next = chars[i + 1]
                    if next.isWhitespace {
                        isBoundary = true
                    }
                }
            }

            if isBoundary && !currentSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sentences.append(currentSentence.trimmingCharacters(in: .whitespacesAndNewlines))
                currentSentence = ""
            }
            i += 1
        }

        if !currentSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sentences.append(currentSentence.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if sentences.isEmpty {
            sentences = [trimmed]
        }

        let totalLen = Double(sentences.map { $0.count }.reduce(0, +))
        let totalDuration = max(0.5, endSec - startSec)

        var cues: [TranscriptCue] = []
        var currentStart = startSec

        for sentence in sentences {
            let sentenceLen = Double(sentence.count)
            let ratio = totalLen > 0 ? (sentenceLen / totalLen) : (1.0 / Double(sentences.count))
            let duration = max(0.2, totalDuration * ratio)
            let currentEnd = min(endSec, currentStart + duration)

            let wordStrings = sentence.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            var words: [TranscriptWord] = []
            if !wordStrings.isEmpty {
                let totalWordLen = Double(wordStrings.map { $0.count }.reduce(0, +))
                var wordStart = currentStart
                for wordStr in wordStrings {
                    let wordLen = Double(wordStr.count)
                    let wordRatio = totalWordLen > 0 ? (wordLen / totalWordLen) : (1.0 / Double(wordStrings.count))
                    let wordDuration = duration * wordRatio
                    let wordEnd = min(currentEnd, wordStart + wordDuration)

                    words.append(TranscriptWord(startSec: wordStart, endSec: wordEnd, text: wordStr))
                    wordStart = wordEnd
                }
            }

            cues.append(TranscriptCue(
                startSec: currentStart,
                endSec: currentEnd,
                text: sentence,
                words: words.isEmpty ? nil : words
            ))
            currentStart = currentEnd
        }

        return cues
    }

    /// Parses inline `[mm:ss]` / `[h:mm:ss]` timestamp markers embedded in text
    /// (the format the VaniScript/Electron edition writes into `original`) into
    /// structured cues with real start/end seconds. Mirrors
    /// `src/lib/karaoke.ts` (parseKaraokeLines / splitKaraokeBlocks /
    /// parseTimestampToSeconds / shouldOffsetRelativeTimestamps). Returns an
    /// empty array when the text carries no markers so callers can fall back to
    /// `reconstructCuesFromRawText`.
    static func reconstructCuesFromTimestampedText(_ text: String, startSec: Double, endSec: Double) -> [TranscriptCue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let markerPattern = "\\[((?:\\d+:)?\\d{1,5}:\\d{2}(?:[.,]\\d{1,3})?)\\]"
        guard let markerRegex = try? NSRegularExpression(pattern: markerPattern) else { return [] }
        let nsNormalized = normalized as NSString
        let matches = markerRegex.matches(in: normalized, range: NSRange(location: 0, length: nsNormalized.length))

        struct TimestampMarker {
            let range: NSRange
            var startSec: Double
        }

        var markers: [TimestampMarker] = []
        for match in matches where match.numberOfRanges >= 2 {
            let raw = nsNormalized.substring(with: match.range(at: 1))
            if let seconds = parseTimestampToSeconds(raw) {
                markers.append(TimestampMarker(range: match.range, startSec: seconds))
            }
        }
        guard !markers.isEmpty else { return [] }

        if shouldOffsetRelativeTimestamps(markers.map(\.startSec), fallbackStartSec: startSec, fallbackEndSec: endSec) {
            for index in markers.indices { markers[index].startSec += startSec }
        }

        var cues: [TranscriptCue] = []
        for (index, marker) in markers.enumerated() {
            let bodyStart = marker.range.location + marker.range.length
            let bodyEnd = index + 1 < markers.count ? markers[index + 1].range.location : nsNormalized.length
            guard bodyStart < bodyEnd, bodyEnd > 0 else { continue }
            let body = nsNormalized
                .substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }

            let cueEnd = index + 1 < markers.count ? markers[index + 1].startSec : endSec
            let resolvedEnd = cueEnd > marker.startSec ? cueEnd : max(marker.startSec + 1, endSec)
            cues.append(TranscriptCue(startSec: marker.startSec, endSec: resolvedEnd, text: body, words: nil))
        }
        return cues
    }

    /// Removes inline `[mm:ss]` timestamp markers from text so they don't leak
    /// into the displayed transcript once structured cues (not markers) drive
    /// the karaoke highlighter.
    static func strippingInlineTimestampMarkers(_ text: String) -> String {
        let pattern = "\\[(?:(?:\\d+:)?\\d{1,5}:\\d{2}(?:[.,]\\d{1,3})?)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(location: 0, length: (text as NSString).length)
        let cleaned = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        var lines: [String] = []
        for rawLine in cleaned.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { lines.append(line) }
        }
        return lines.joined(separator: "\n")
    }

    private static func parseTimestampToSeconds(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "^(?:(\\d+):)?(\\d{1,5}):(\\d{2})(?:[.,](\\d{1,3}))?$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = trimmed as NSString
        guard let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)) else { return nil }

        func substring(_ index: Int) -> String? {
            guard index < match.numberOfRanges, match.range(at: index).location != NSNotFound else { return nil }
            return ns.substring(with: match.range(at: index))
        }

        let hours = Double(substring(1) ?? "0") ?? 0
        let minutes = Double(substring(2) ?? "0") ?? 0
        let seconds = Double(substring(3) ?? "0") ?? 0
        var millis: Double = 0
        if let fraction = substring(4) {
            var padded = fraction
            while padded.count < 3 { padded += "0" }
            millis = (Double(padded) ?? 0) / 1000
        }
        return (hours * 3600) + (minutes * 60) + seconds + millis
    }

    private static func shouldOffsetRelativeTimestamps(_ startSeconds: [Double], fallbackStartSec: Double, fallbackEndSec: Double) -> Bool {
        if fallbackStartSec <= 0 || startSeconds.isEmpty { return false }
        let chunkDurationSec = max(0, fallbackEndSec - fallbackStartSec)
        let maxStartSec = startSeconds.max() ?? 0
        let allTimestampsBeforeChunk = startSeconds.allSatisfy { $0 < fallbackStartSec - 0.5 }
        let timestampsFitInsideChunk = chunkDurationSec <= 0 || maxStartSec <= chunkDurationSec + 10
        return allTimestampsBeforeChunk && timestampsFitInsideChunk
    }

    static func reconstructTranslationCues(from text: String, matching sourceCues: [TranscriptCue]) -> [TranscriptCue] {
        guard !sourceCues.isEmpty else { return [] }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }

        var sentences: [String] = []
        var currentSentence = ""
        let chars = Array(clean)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            currentSentence.append(c)
            let isBoundChar = (c == "." || c == "?" || c == "!" || c == "\n")
            var isBoundary = false
            if isBoundChar {
                if c == "\n" || i + 1 == chars.count {
                    isBoundary = true
                } else {
                    let next = chars[i + 1]
                    if next.isWhitespace {
                        isBoundary = true
                    }
                }
            }
            if isBoundary && !currentSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sentences.append(currentSentence.trimmingCharacters(in: .whitespacesAndNewlines))
                currentSentence = ""
            }
            i += 1
        }
        if !currentSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sentences.append(currentSentence.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let alignedTexts: [String]
        if sentences.count == sourceCues.count {
            alignedTexts = sentences
        } else {
            var forced = sentences
            while forced.count < sourceCues.count {
                forced.append("")
            }
            alignedTexts = Array(forced.prefix(sourceCues.count))
        }

        return zip(sourceCues, alignedTexts).map { source, translated in
            let cueText = translated.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalOutput = cueText.isEmpty ? "..." : cueText

            let wordStrings = finalOutput.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            var words: [TranscriptWord] = []
            let duration = source.endSec - source.startSec
            if !wordStrings.isEmpty {
                let totalWordLen = Double(wordStrings.map { $0.count }.reduce(0, +))
                var wordStart = source.startSec
                for wordStr in wordStrings {
                    let wordLen = Double(wordStr.count)
                    let wordRatio = totalWordLen > 0 ? (wordLen / totalWordLen) : (1.0 / Double(wordStrings.count))
                    let wordDuration = duration * wordRatio
                    let wordEnd = min(source.endSec, wordStart + wordDuration)

                    words.append(TranscriptWord(startSec: wordStart, endSec: wordEnd, text: wordStr))
                    wordStart = wordEnd
                }
            }

            return TranscriptCue(
                startSec: source.startSec,
                endSec: source.endSec,
                text: finalOutput,
                words: words.isEmpty ? nil : words
            )
        }
    }

    private func sortedLanguages(_ languagesByKey: [String: String]) -> [String] {
        var languages = Array(languagesByKey.values)
            .filter { TranslationArchive.isRealLanguage($0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if let activeTranslationLanguage, TranslationArchive.isRealLanguage(activeTranslationLanguage) {
            let activeKey = TranslationArchive.languageKey(activeTranslationLanguage)
            languages.removeAll { TranslationArchive.languageKey($0) == activeKey }
            languages.insert(TranslationArchive.displayLanguage(activeTranslationLanguage), at: 0)
        }
        return languages
    }
}
