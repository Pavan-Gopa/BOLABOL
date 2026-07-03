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
    public var approved: Bool

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
        approved: Bool
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
        self.approved = approved
    }

    enum CodingKeys: String, CodingKey {
        case index, filePath, durationSec, startSec, endSec, original, translated
        case originalCues, originalFormats, translatedFormats, translationsByLanguage
        case unrecognizedFragments, status, approved
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

        self.approved = try container.decodeIfPresent(Bool.self, forKey: .approved) ?? false
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
    public var id: String { "\(start)-\(end)-\(title)" }

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
    public var durationSec: Double
    public var metadata: AudioMetadata
    public var sourceLang: String
    public var targetLang: String
    public var transcriptionProvider: String
    public var translationProvider: String
    public var outputFormats: [OutputFormat]
    public var chunks: [ChunkData]
    public var currentChunkIndex: Int
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
        sourceMediaInfo: SourceMediaInfo? = nil
    ) {
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
        self.chunks = chunks
        self.currentChunkIndex = currentChunkIndex
        self.availableTranslationLanguages = availableTranslationLanguages
        self.activeTranslationLanguage = activeTranslationLanguage
        self.shortsPlans = shortsPlans
        self.shortsRejectedPlans = shortsRejectedPlans
    }

    enum CodingKeys: String, CodingKey {
        case sourceFile, sourceFileName, sourceMediaInfo, durationSec, metadata, sourceLang, targetLang
        case transcriptionProvider, translationProvider, outputFormats, chunks, currentChunkIndex
        case availableTranslationLanguages, activeTranslationLanguage, shortsPlans, shortsRejectedPlans
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sourceFile = try container.decodeIfPresent(String.self, forKey: .sourceFile)
        self.sourceFileName = try container.decodeIfPresent(String.self, forKey: .sourceFileName) ?? "Imported Session"
        self.sourceMediaInfo = try container.decodeIfPresent(SourceMediaInfo.self, forKey: .sourceMediaInfo)
        self.durationSec = try container.decodeIfPresent(Double.self, forKey: .durationSec) ?? 0.0
        self.metadata = try container.decodeIfPresent(AudioMetadata.self, forKey: .metadata) ?? AudioMetadata.empty
        self.sourceLang = try container.decodeIfPresent(String.self, forKey: .sourceLang) ?? "auto"
        self.targetLang = try container.decodeIfPresent(String.self, forKey: .targetLang) ?? "ru"

        self.transcriptionProvider = try container.decodeIfPresent(String.self, forKey: .transcriptionProvider) ?? "coreml-whisperkit"
        self.translationProvider = try container.decodeIfPresent(String.self, forKey: .translationProvider) ?? "none"

        self.outputFormats = try container.decodeIfPresent([OutputFormat].self, forKey: .outputFormats) ?? []
        self.chunks = try container.decodeIfPresent([ChunkData].self, forKey: .chunks) ?? []
        self.currentChunkIndex = try container.decodeIfPresent(Int.self, forKey: .currentChunkIndex) ?? 0
        self.availableTranslationLanguages = try container.decodeIfPresent([String].self, forKey: .availableTranslationLanguages)
        self.activeTranslationLanguage = try container.decodeIfPresent(String.self, forKey: .activeTranslationLanguage)
        self.shortsPlans = try container.decodeIfPresent([ShortsClipPlan].self, forKey: .shortsPlans)
        self.shortsRejectedPlans = try container.decodeIfPresent([ShortsClipPlan].self, forKey: .shortsRejectedPlans)
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
        targetLang: String
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
        extractMetadataFromCuesIfNeeded()
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

    public static func reconstructCuesFromRawText(_ text: String, startSec: Double, endSec: Double) -> [TranscriptCue] {
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
    public static func reconstructCuesFromTimestampedText(_ text: String, startSec: Double, endSec: Double) -> [TranscriptCue] {
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
    public static func strippingInlineTimestampMarkers(_ text: String) -> String {
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

    public static func reconstructTranslationCues(from text: String, matching sourceCues: [TranscriptCue]) -> [TranscriptCue] {
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
