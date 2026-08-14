import Foundation

public enum LiteraryTranslationMode: String, Codable, CaseIterable, Equatable, Sendable {
    case faithfulLiterary
    case literal
    case free
}

public enum VoicePreservationPolicy: String, Codable, CaseIterable, Equatable, Sendable {
    case preserveVoice
    case strict
    case natural
}

public enum SanskritPolicy: String, Codable, CaseIterable, Equatable, Sendable {
    case preserveExact
    case preserveTransliterationTranslateGloss
    case editorApprovedAdaptation
}

public struct ProtectedTerm: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var source: String
    public var translation: String
    public var notes: String?

    public init(
        id: String = UUID().uuidString,
        source: String,
        translation: String = "",
        notes: String? = nil
    ) {
        self.id = id
        self.source = source
        self.translation = translation
        self.notes = notes
    }

    public init(
        id: String = UUID().uuidString,
        source: String,
        target: String,
        notes: String? = nil
    ) {
        self.init(id: id, source: source, translation: target, notes: notes)
    }
}

public struct DocumentTranslationProfile: Codable, Equatable, Sendable {
    public var sourceLanguage: String
    public var targetLanguage: String
    public var mode: LiteraryTranslationMode
    public var voice: VoicePreservationPolicy
    public var sanskritPolicy: SanskritPolicy
    public var protectedTerms: [ProtectedTerm]
    public var projectGlossary: [GlossaryEntry]
    public var translatorNotes: String

    public init(
        sourceLanguage: String = "auto",
        targetLanguage: String = "Russian",
        mode: LiteraryTranslationMode = .faithfulLiterary,
        voice: VoicePreservationPolicy = .preserveVoice,
        sanskritPolicy: SanskritPolicy = .preserveTransliterationTranslateGloss,
        protectedTerms: [ProtectedTerm] = [],
        projectGlossary: [GlossaryEntry] = [],
        translatorNotes: String = ""
    ) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.mode = mode
        self.voice = voice
        self.sanskritPolicy = sanskritPolicy
        self.protectedTerms = protectedTerms
        self.projectGlossary = projectGlossary
        self.translatorNotes = translatorNotes
    }
    
    public static let `default` = DocumentTranslationProfile(
        projectGlossary: StarterGlossary.entries
    )

    public static let faithfulLiteraryDefault = DocumentTranslationProfile(
        mode: .faithfulLiterary,
        voice: .preserveVoice,
        sanskritPolicy: .preserveTransliterationTranslateGloss,
        projectGlossary: StarterGlossary.entries
    )
}
