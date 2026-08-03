import Foundation

public struct PolishingStatus: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case idle
        case pending
        case polishing
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

    public static let idle = PolishingStatus(phase: .idle)
    public static let pending = PolishingStatus(phase: .pending)

    public static func polishing(backendName: String? = nil) -> PolishingStatus {
        PolishingStatus(phase: .polishing, backendName: backendName)
    }

    public static func completed(backendName: String? = nil) -> PolishingStatus {
        PolishingStatus(phase: .completed, backendName: backendName)
    }

    public static func failed(
        message: String,
        backendName: String? = nil
    ) -> PolishingStatus {
        PolishingStatus(phase: .failed, message: message, backendName: backendName)
    }
}
