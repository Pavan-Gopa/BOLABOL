import Foundation

public enum BatchCueViolation: Codable, Equatable, Sendable {
    case invalidDuration
    case nonFiniteTime(cueIndex: Int)
    case invalidRange(cueIndex: Int)
    case outsideDuration(cueIndex: Int)
    case nonMonotonic(cueIndex: Int)
    case emptyText(cueIndex: Int)
}

public struct BatchCueValidationResult: Codable, Equatable, Sendable {
    public let violations: [BatchCueViolation]

    public init(violations: [BatchCueViolation]) {
        self.violations = violations
    }

    public var isValid: Bool { violations.isEmpty }
}

public enum BatchTimedTextRendererError: Error, Equatable, Sendable, LocalizedError {
    case invalidTranscript([BatchCueViolation])

    public var errorDescription: String? {
        switch self {
        case .invalidTranscript(let violations):
            if violations.isEmpty {
                return "The transcription produced invalid timed text."
            }
            return "The transcription produced invalid timed text: \(violations.map { String(describing: $0) }.joined(separator: ", "))"
        }
    }
}
public struct SourceFileFingerprint: Codable, Equatable, Sendable {
    public let byteCount: Int64
    public let modificationTimeNanoseconds: Int64
    public let sha256: String

    public init(byteCount: Int64, modificationTimeNanoseconds: Int64, sha256: String) {
        self.byteCount = byteCount
        self.modificationTimeNanoseconds = modificationTimeNanoseconds
        self.sha256 = sha256
    }
}

public struct GeneratedOutputFingerprint: Codable, Equatable, Sendable {
    public let sha256: String

    public init(sha256: String) {
        self.sha256 = sha256
    }
}

public enum CompanionOverwritePolicy: String, Codable, Equatable, Sendable {
    case replaceGeneratedOnly
}

public struct CompanionWriteRequest: Equatable, Sendable {
    public let sourceURL: URL
    public let outputURL: URL
    public let expectedSourceFingerprint: SourceFileFingerprint
    public let knownGeneratedOutput: GeneratedOutputFingerprint?
    public let overwritePolicy: CompanionOverwritePolicy

    public init(
        sourceURL: URL,
        outputURL: URL,
        expectedSourceFingerprint: SourceFileFingerprint,
        knownGeneratedOutput: GeneratedOutputFingerprint? = nil,
        overwritePolicy: CompanionOverwritePolicy = .replaceGeneratedOnly
    ) {
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.expectedSourceFingerprint = expectedSourceFingerprint
        self.knownGeneratedOutput = knownGeneratedOutput
        self.overwritePolicy = overwritePolicy
    }
}

public enum CompanionWriteDisposition: String, Codable, Equatable, Sendable {
    case created
    case replacedGenerated
}

public struct CompanionWriteResult: Codable, Equatable, Sendable {
    public let outputURL: URL
    public let outputFingerprint: GeneratedOutputFingerprint
    public let disposition: CompanionWriteDisposition

    public init(
        outputURL: URL,
        outputFingerprint: GeneratedOutputFingerprint,
        disposition: CompanionWriteDisposition
    ) {
        self.outputURL = outputURL
        self.outputFingerprint = outputFingerprint
        self.disposition = disposition
    }
}

public enum AtomicCompanionWriterError: Error, Equatable, Sendable, LocalizedError {
    case sourceUnavailable
    case sourceChanged
    case caseInsensitiveCollision(existingName: String)
    case existingOutputNotKnownGenerated
    case existingOutputModified
    case directoryReadFailed
    case permissionDenied
    case temporaryCreateFailed(code: Int32)
    case writeFailed(code: Int32)
    case syncFailed(code: Int32)
    case closeFailed(code: Int32)
    case renameFailed(code: Int32)

    public var isOutputCollision: Bool {
        switch self {
        case .existingOutputNotKnownGenerated, .existingOutputModified, .caseInsensitiveCollision:
            return true
        default:
            return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .existingOutputNotKnownGenerated:
            return "A companion file already exists and was not created by VaniScript. Remove or rename it to retry."
        case .existingOutputModified:
            return "The companion file was modified outside VaniScript. Remove or rename it to retry."
        case .caseInsensitiveCollision(let existingName):
            return "A companion file named '\(existingName)' already exists with different casing. Remove or rename '\(existingName)' to retry."
        case .sourceUnavailable:
            return "The source audio file is no longer accessible."
        case .sourceChanged:
            return "The source audio file was modified during transcription."
        case .directoryReadFailed:
            return "The output directory could not be read."
        case .permissionDenied:
            return "Permission denied. Check folder write access."
        case .temporaryCreateFailed(let code):
            return "The companion file could not be created (POSIX \(code))."
        case .writeFailed(let code):
            return "The companion file could not be written (POSIX \(code))."
        case .syncFailed(let code):
            return "The companion file could not be synced to disk (POSIX \(code))."
        case .closeFailed(let code):
            return "The companion file could not be closed (POSIX \(code))."
        case .renameFailed(let code):
            return "The companion file could not be renamed to destination (POSIX \(code))."
        }
    }

    public func actionableMessage(forOutputFilename filename: String) -> String {
        switch self {
        case .existingOutputNotKnownGenerated:
            return "A companion file named '\(filename)' already exists and was not created by VaniScript. Remove or rename it to retry."
        case .existingOutputModified:
            return "The companion file '\(filename)' was modified outside VaniScript. Remove or rename it to retry."
        case .caseInsensitiveCollision(let existingName):
            return "A companion file named '\(existingName)' already exists with different casing. Remove or rename '\(existingName)' to retry."
        default:
            return errorDescription ?? "Output error."
        }
    }
}
