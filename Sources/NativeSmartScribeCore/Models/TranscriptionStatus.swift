import Foundation

public struct TranscriptionStatus: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case idle
        case pending
        case transcribing
        case completed
        case failed
    }

    public var phase: Phase
    public var message: String?
    public var backendName: String?

    public init(
        phase: Phase,
        message: String? = nil,
        backendName: String? = nil
    ) {
        self.phase = phase
        self.message = message
        self.backendName = backendName
    }

    public static let idle = TranscriptionStatus(phase: .idle)
    public static let pending = TranscriptionStatus(phase: .pending)

    public static func transcribing(backendName: String? = nil) -> TranscriptionStatus {
        TranscriptionStatus(phase: .transcribing, backendName: backendName)
    }

    public static func completed(backendName: String? = nil) -> TranscriptionStatus {
        TranscriptionStatus(phase: .completed, backendName: backendName)
    }

    public static func failed(
        message: String,
        backendName: String? = nil
    ) -> TranscriptionStatus {
        TranscriptionStatus(phase: .failed, message: message, backendName: backendName)
    }
}
