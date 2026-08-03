import Foundation

public enum CloudRequestRetryError: LocalizedError, Sendable {
    case emptySuccessfulResponse

    public var errorDescription: String? {
        switch self {
        case .emptySuccessfulResponse:
            return "The API provider returned an empty response."
        }
    }
}

public struct CloudRequestRetryPolicy: Sendable {
    public static let googleTextGeneration = CloudRequestRetryPolicy(
        timeoutInterval: 20,
        maxAttempts: 2,
        retryDelayNanoseconds: 250_000_000
    )

    public let timeoutInterval: TimeInterval
    public let maxAttempts: Int
    public let retryDelayNanoseconds: UInt64

    public init(
        timeoutInterval: TimeInterval,
        maxAttempts: Int,
        retryDelayNanoseconds: UInt64
    ) {
        self.timeoutInterval = max(1, timeoutInterval)
        self.maxAttempts = max(1, maxAttempts)
        self.retryDelayNanoseconds = retryDelayNanoseconds
    }

    public func shouldRetry(_ error: any Error) -> Bool {
        if error is CloudRequestRetryError {
            return true
        }

        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return false }

        switch URLError.Code(rawValue: error.code) {
        case .timedOut,
             .networkConnectionLost,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}
