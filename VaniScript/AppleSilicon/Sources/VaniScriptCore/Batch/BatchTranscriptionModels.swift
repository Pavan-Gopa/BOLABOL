import Foundation

public struct BatchFolderProfile: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var bookmarkData: Data?
    public var displayPath: String
    public var enabled: Bool
    public var recursive: Bool

    public init(
        id: String,
        name: String,
        bookmarkData: Data? = nil,
        displayPath: String = "",
        enabled: Bool = true,
        recursive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.bookmarkData = bookmarkData
        self.displayPath = displayPath
        self.enabled = enabled
        self.recursive = recursive
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, bookmarkData, displayPath, enabled, recursive
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        bookmarkData = try values.decodeIfPresent(Data.self, forKey: .bookmarkData)
        displayPath = try values.decodeIfPresent(String.self, forKey: .displayPath) ?? ""
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        recursive = try values.decodeIfPresent(Bool.self, forKey: .recursive) ?? false
    }
}

public struct BatchTranscriptionConfiguration: Codable, Equatable, Hashable, Sendable {
    public let identifier: String
    public let sourceLanguage: String

    public init(identifier: String, sourceLanguage: String) {
        self.identifier = identifier
        self.sourceLanguage = sourceLanguage
    }
}

public enum BatchProgressPhase: String, Codable, Equatable, Sendable {
    case planning
    case loadingModel
    case convertingAudio
    case transcribing
    case finalizing
}

public struct BatchProgressDetail: Codable, Equatable, Sendable {
    public var phase: BatchProgressPhase
    public var currentChunkAudioPositionSec: Double?
    public var currentChunkDurationSec: Double?

    public init(
        phase: BatchProgressPhase,
        currentChunkAudioPositionSec: Double? = nil,
        currentChunkDurationSec: Double? = nil
    ) {
        self.phase = phase
        self.currentChunkAudioPositionSec = currentChunkAudioPositionSec
        self.currentChunkDurationSec = currentChunkDurationSec
    }
}

public enum BatchJobState: String, Codable, CaseIterable, Equatable, Sendable {
    case pending
    case processing
    case completed
    case failed
    case cancelled
    case blockedOutputCollision
}

public struct BatchChunkCheckpoint: Codable, Equatable, Sendable {
    public let index: Int
    public let text: String
    public let cues: [TranscriptCue]

    public init(index: Int, text: String, cues: [TranscriptCue]) {
        self.index = index
        self.text = text
        self.cues = cues
    }
}
public struct BatchJob: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let profileID: String
    public let relativeSourcePath: String
    public let relativeOutputPath: String
    public let sourceFingerprint: SourceFileFingerprint
    public let configuration: BatchTranscriptionConfiguration
    public var generation: Int
    public var state: BatchJobState
    public var attempt: Int
    public var progress: Double
    public var checkpoints: [BatchChunkCheckpoint]
    public var outputFingerprint: GeneratedOutputFingerprint?
    public var lastError: String?
    public let createdAt: Date
    public var updatedAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    public var totalChunks: Int?
    public var progressDetail: BatchProgressDetail?

    public init(
        id: UUID = UUID(),
        profileID: String,
        relativeSourcePath: String,
        relativeOutputPath: String,
        sourceFingerprint: SourceFileFingerprint,
        configuration: BatchTranscriptionConfiguration,
        generation: Int = 1,
        state: BatchJobState = .pending,
        attempt: Int = 0,
        progress: Double = 0,
        checkpoints: [BatchChunkCheckpoint] = [],
        outputFingerprint: GeneratedOutputFingerprint? = nil,
        lastError: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        totalChunks: Int? = nil,
        progressDetail: BatchProgressDetail? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.relativeSourcePath = relativeSourcePath
        self.relativeOutputPath = relativeOutputPath
        self.sourceFingerprint = sourceFingerprint
        self.configuration = configuration
        self.generation = generation
        self.state = state
        self.attempt = attempt
        self.progress = progress
        self.checkpoints = checkpoints
        self.outputFingerprint = outputFingerprint
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.totalChunks = totalChunks
        self.progressDetail = progressDetail
    }
}
public extension BatchJob {
    var chunkProgressLabel: String {
        let completed = checkpoints.count
        let total: Int
        if state == .completed {
            total = max(completed, 1)
        } else if let totalChunks, totalChunks > 0 {
            total = max(totalChunks, completed)
        } else if progress >= 1 {
            total = max(completed, 1)
        } else if progress > 0 {
            total = max(completed, Int((Double(completed) / progress).rounded()))
        } else {
            total = max(completed + 1, 1)
        }
        let safeTotal = max(total, 1)
        let current = (state == .completed || progress >= 1) ? safeTotal : min(completed + 1, safeTotal)
        return "chunk \(current) of \(safeTotal)"
    }
    var elapsedDuration: TimeInterval? {
        if let startedAt, let finishedAt {
            return max(0, finishedAt.timeIntervalSince(startedAt))
        }
        if let startedAt, state == .processing {
            return max(0, Date().timeIntervalSince(startedAt))
        }
        if let finishedAt {
            return max(0, finishedAt.timeIntervalSince(createdAt))
        }
        if state == .completed || state == .failed || state == .cancelled || state == .blockedOutputCollision {
            return max(0, updatedAt.timeIntervalSince(createdAt))
        }
        if state == .processing {
            return max(0, Date().timeIntervalSince(createdAt))
        }
        return nil
    }

    var formattedDuration: String? {
        guard let elapsed = elapsedDuration else { return nil }
        return Self.formatDuration(elapsed)
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    static func formatClockTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }

    var isDeterminateProgress: Bool {
        guard state == .processing else { return false }
        guard let detail = progressDetail else { return false }
        return detail.phase == .transcribing
    }

    var progressStageText: String {
        switch state {
        case .pending:
            return "Pending"
        case .processing:
            guard let detail = progressDetail else {
                return "Starting…"
            }
            switch detail.phase {
            case .planning:
                return "Analyzing audio and planning chunks…"
            case .loadingModel:
                return "Loading model…"
            case .convertingAudio:
                return "Preparing audio…"
            case .transcribing:
                let percent = Int((min(max(progress, 0), 1) * 100).rounded())
                if let pos = detail.currentChunkAudioPositionSec,
                   let dur = detail.currentChunkDurationSec,
                   dur > 0 {
                    return "Transcribing · \(Self.formatClockTime(pos)) / \(Self.formatClockTime(dur)) · \(chunkProgressLabel) · \(percent)%"
                } else {
                    return "Transcribing · \(chunkProgressLabel) · \(percent)%"
                }
            case .finalizing:
                return "Saving transcript…"
            }
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        case .blockedOutputCollision:
            return "Output conflict"
        }
    }

    var voiceOverProgressValue: String {
        switch state {
        case .processing:
            guard let detail = progressDetail else {
                return "\(chunkProgressLabel), \(Int((progress * 100).rounded())) percent"
            }
            switch detail.phase {
            case .planning:
                return "Analyzing audio and planning chunks, indeterminate"
            case .loadingModel:
                return "Loading model, indeterminate"
            case .convertingAudio:
                return "Preparing audio, indeterminate"
            case .transcribing:
                let percent = Int((min(max(progress, 0), 1) * 100).rounded())
                if let pos = detail.currentChunkAudioPositionSec,
                   let dur = detail.currentChunkDurationSec,
                   dur > 0 {
                    return "Transcribing, \(Self.formatClockTime(pos)) of \(Self.formatClockTime(dur)), \(chunkProgressLabel), \(percent) percent"
                } else {
                    return "Transcribing, \(chunkProgressLabel), \(percent) percent"
                }
            case .finalizing:
                return "Saving transcript, indeterminate"
            }
        default:
            return "\(chunkProgressLabel), \(Int((progress * 100).rounded())) percent"
        }
    }
}


public enum BatchReconciliationIssue: Equatable, Sendable {
    case invalidName(relativePath: String, violations: [MediaNameViolation])
    case outputCollision(relativePath: String, existingName: String)
}

public extension BatchReconciliationIssue {
    var relativePath: String {
        switch self {
        case let .invalidName(relativePath, _), let .outputCollision(relativePath, _): relativePath
        }
    }

    var reason: String {
        switch self {
        case let .invalidName(_, violations):
            violations.map(\.shortDescription).joined(separator: ", ")
        case let .outputCollision(_, existingName):
            "output already exists at \(existingName)"
        }
    }
}

private extension MediaNameViolation {
    var shortDescription: String {
        switch self {
        case .filenameTooLong: "filename is too long"
        case .missingExtension: "missing file extension"
        case .uppercaseExtension: "file extension must be lowercase"
        case .invalidExtension: "invalid file extension"
        case .spaceNotAllowed: "spaces are not allowed"
        case .dotInStem: "filename stem contains a dot"
        case .invalidStructure: "required naming fields are missing"
        case .invalidDate: "invalid date"
        case .invalidWho: "invalid speaker"
        case .invalidWhat: "invalid topic"
        case .invalidWhere: "invalid location"
        case .invalidCountry: "invalid country code"
        case .ambiguousLegacyName: "ambiguous speaker and topic"
        }
    }
}

public struct BatchReconciliationResult: Equatable, Sendable {
    public let enqueued: [BatchJob]
    public let duplicateCount: Int
    public let issues: [BatchReconciliationIssue]

    public init(enqueued: [BatchJob], duplicateCount: Int, issues: [BatchReconciliationIssue]) {
        self.enqueued = enqueued
        self.duplicateCount = duplicateCount
        self.issues = issues
    }
}
