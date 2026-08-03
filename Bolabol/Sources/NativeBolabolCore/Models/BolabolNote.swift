import Foundation

public struct BolabolNote: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var rawText: String
    public var polishedVariantOne: String
    public var polishedVariantTwo: String
    public var audioRecording: AudioRecording?
    public var transcriptionStatus: TranscriptionStatus
    public var polishingStatuses: [ProcessingVariant: PolishingStatus]

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        rawText: String,
        polishedVariantOne: String = "",
        polishedVariantTwo: String = "",
        audioRecording: AudioRecording? = nil,
        transcriptionStatus: TranscriptionStatus = .idle,
        polishingStatuses: [ProcessingVariant: PolishingStatus] = [:]
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.rawText = rawText
        self.polishedVariantOne = polishedVariantOne
        self.polishedVariantTwo = polishedVariantTwo
        self.audioRecording = audioRecording
        self.transcriptionStatus = transcriptionStatus
        self.polishingStatuses = polishingStatuses
    }

    public func polishingStatus(for variant: ProcessingVariant) -> PolishingStatus {
        polishingStatuses[variant] ?? .idle
    }

    public func bestDisplayText() -> String {
        let candidates = [rawText, polishedVariantOne, polishedVariantTwo]
        return candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    public func previewText(maxLength: Int = 72) -> String {
        let text = bestDisplayText()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        guard !text.isEmpty else {
            return title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? AppText.localized(.blankNoteFallback, language: .english)
                : title
        }

        guard text.count > maxLength else {
            return text
        }

        let endIndex = text.index(text.startIndex, offsetBy: max(0, maxLength - 3))
        return String(text[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

public extension Array where Element == BolabolNote {
    func copyAllText() -> String {
        sorted { $0.createdAt < $1.createdAt }
            .map { $0.bestDisplayText() }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    static let preview: [BolabolNote] = [
        BolabolNote(
            title: "Local polishing architecture",
            createdAt: Date(timeIntervalSince1970: 1_775_000_000),
            rawText: "We need to replace the Ollama HTTP polishing path with an in-app native engine.",
            polishedVariantOne: "Replace the Ollama HTTP polishing path with an in-app native engine.",
            polishedVariantTwo: "The native rewrite should move text polishing into a first-class in-app engine so performance, model selection, and compute diagnostics are controlled by Bolabol."
        ),
        BolabolNote(
            title: "Audio import baseline",
            createdAt: Date(timeIntervalSince1970: 1_775_003_600),
            rawText: "Keep file import and microphone recording as separate services.",
            polishedVariantOne: "Keep file import and microphone recording as separate services.",
            polishedVariantTwo: "Model file import and microphone capture as independent services so each path can be tested, logged, and optimized without affecting the other."
        )
    ]
}
