import Foundation

/// Pure per-key failover policy for every cloud provider key list (ADR-029).
///
/// timeout / transport / 5xx / 429-quota / 401-403 / empty-2xx → next key
/// immediately, no same-key retry. Other 4xx and decode errors stop the chain.
/// Disabled keys are skipped.
public enum CloudKeyFailover {
    public enum Failure: Equatable, Sendable {
        case timeoutOrTransport
        case serverError(status: Int)
        case rateLimited
        case unauthorized(status: Int)
        case emptyResponse
        case clientError(status: Int)
        case decodeError
    }

    public enum Action: Equatable, Sendable {
        case nextKey
        case stop
    }

    public static func action(for failure: Failure) -> Action {
        switch failure {
        case .timeoutOrTransport, .serverError, .rateLimited, .unauthorized, .emptyResponse:
            return .nextKey
        case .clientError, .decodeError:
            return .stop
        }
    }

    public static func classifyHTTPStatus(_ status: Int, message: String = "") -> Failure {
        if status == 429 || status == 401 || status == 403 {
            if status == 429 { return .rateLimited }
            return .unauthorized(status: status)
        }
        if (500...599).contains(status) { return .serverError(status: status) }
        if (400...499).contains(status) {
            let lower = message.lowercased()
            if lower.contains("quota") || lower.contains("rate limit")
                || lower.contains("resource_exhausted") {
                return .rateLimited
            }
            return .clientError(status: status)
        }
        return .decodeError
    }

    public static func classify(error: any Error) -> Failure {
        if error is CloudRequestRetryError { return .emptyResponse }
        if error is DecodingError { return .decodeError }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: ns.code) {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet,
                 .dataNotAllowed, .internationalRoamingOff:
                return .timeoutOrTransport
            default:
                return .decodeError
            }
        }
        let message = ns.localizedDescription.lowercased()
        if message.contains("timed out") || message.contains("connection") {
            return .timeoutOrTransport
        }
        return .decodeError
    }

    public struct Plan: Equatable, Sendable {
        /// Enabled key indices in attempt order.
        public var keyIndices: [Int]
        public init(keyIndices: [Int]) { self.keyIndices = keyIndices }
    }

    /// Enabled (non-disabled) key indices for one provider configuration.
    public static func plan(apiKeys: [String]) -> Plan {
        let indices = apiKeys.indices.filter { index in
            let trimmed = apiKeys[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty
                && !trimmed.hasPrefix(APIProviderConfiguration.disabledPrefix)
                && !trimmed.hasPrefix("disabled:")
        }
        return Plan(keyIndices: Array(indices))
    }

    /// Time budget (Q5a): per-request 15 s; key chain until 40 s; translation
    /// provider up to 20 s; hard cap 60 s → source fallback.
    public struct TimeBudget: Equatable, Sendable {
        public var perRequestSeconds: TimeInterval = 15
        public var keyChainSeconds: TimeInterval = 40
        public var translationSeconds: TimeInterval = 20
        public var hardCapSeconds: TimeInterval = 60

        public init(
            perRequestSeconds: TimeInterval = 15,
            keyChainSeconds: TimeInterval = 40,
            translationSeconds: TimeInterval = 20,
            hardCapSeconds: TimeInterval = 60
        ) {
            self.perRequestSeconds = perRequestSeconds
            self.keyChainSeconds = keyChainSeconds
            self.translationSeconds = translationSeconds
            self.hardCapSeconds = hardCapSeconds
        }

        public static let `default` = TimeBudget()

        public func expired(elapsed: TimeInterval) -> Bool {
            elapsed >= hardCapSeconds
        }
    }
    /// Q5a timeout: thrown by `withTimeout` instead of starting — or to
    /// cancel — budgeted work (strict retry, translation provider, polish)
    /// once its slice of the output-language chain is spent.
    public struct TimeoutError: LocalizedError, Equatable, Sendable {
        public init() {}
        public var errorDescription: String? {
            "Timed out waiting for the provider."
        }
    }

    /// Races budgeted async work against its remaining slice. Work never
    /// starts when `seconds <= 0` (the chain cap is already spent); in-flight
    /// work is cancelled when the slice expires.
    public static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        guard seconds > 0, seconds.isFinite else { throw TimeoutError() }
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw TimeoutError()
            }
            return first
        }
    }
}
