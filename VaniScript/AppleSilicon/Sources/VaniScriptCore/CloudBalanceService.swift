import Foundation

// MARK: - CloudBalanceService
//
// Role: VaniScriptCore service (A7) that fetches the *real* remaining balance / limits
// for a cloud provider — but only for the providers whose API actually exposes one
// (§11). It owns:
//   - the per-provider balance HTTP requests (OpenRouter credits+key; Ollama Cloud),
//   - the pure response parsers → `BalanceInfo` (unit-tested with mocked JSON),
//   - a short-TTL, in-memory, session-only cache (never persisted) so opening a
//     provider card / hitting Refresh does not spam the API.
//
// Honesty invariants (§11 / §14):
//   - For `.none` / `.estimated` providers (Gemini/OpenAI/Anthropic/Qwen/Custom) we
//     NEVER fetch and NEVER show a real balance — the UI keeps its local "Estimated
//     spent" only. No fake "$".
//   - Ollama Cloud bills by GPU-time plan, not USD → we return plan limits / the
//     honest "Plan-based (GPU time)" label, never a fabricated dollar amount.
//   - Any network/parse error is a *quiet* fallback to `.unavailable` (no crash) so
//     the card silently keeps its estimated view.
//   - No keys/tokens in source or logs; network is injected via `CloudHTTPFetcher`
//     (reused from CloudModelCatalog, A4) so tests exercise parsers with mocked JSON.

/// What a provider's balance resolves to at runtime (§11). `Equatable`/`Sendable` so
/// SwiftUI state and unit tests can compare results directly.
public enum BalanceInfo: Equatable, Sendable {
    /// Real USD credits: `remaining` spendable, `total` cap when the provider reports one.
    case usd(remaining: Double, total: Double?)
    /// Non-USD plan limits (Ollama Cloud GPU time). `label` is the short headline,
    /// `detail` an optional secondary line (empty when the API gives nothing concrete).
    case planLimits(label: String, detail: String)
    /// No real balance available — UI falls back to local Estimated spent (§10).
    case unavailable
}

/// A provider that can report a real balance from its API. Concrete conformers own the
/// request shape + parser for one provider; the service picks the right one per `balanceKind`.
public protocol BalanceProvider: Sendable {
    /// Fetch the balance for `apiKey`. Throws on network/HTTP/parse failure so the
    /// caller (CloudBalanceService) can map errors to a quiet `.unavailable`.
    func fetchBalance(apiKey: String) async throws -> BalanceInfo
}

/// Errors surfaced by balance providers. Kept internal to the fetch path — the UI only
/// ever sees the mapped `BalanceInfo.unavailable` (quiet fallback, §11).
public enum CloudBalanceError: LocalizedError, Equatable {
    case requestFailed(provider: String, status: Int)
    case unparsableResponse(provider: String)

    public var errorDescription: String? {
        switch self {
        case let .requestFailed(provider, status):
            return "\(provider) balance request failed with HTTP \(status)."
        case let .unparsableResponse(provider):
            return "\(provider) returned a balance body that could not be read."
        }
    }
}


// MARK: - OpenRouter provider (real USD credits)

/// OpenRouter exposes real USD credits via two endpoints (verified A7 — see ADR):
///   - `GET https://openrouter.ai/api/v1/credits` → `{ data: { total_credits, total_usage } }`
///   - `GET https://openrouter.ai/api/v1/key`     → `{ data: { limit, limit_remaining, usage, ... } }`
/// Both authenticate with `Authorization: Bearer <key>`. We combine them into a single
/// "remaining $X / limit $Y" (like the Cline CLI): account remaining = credits − usage,
/// further capped by the per-key `limit_remaining` when the key defines one.
public struct OpenRouterBalanceProvider: BalanceProvider {
    private let fetcher: CloudHTTPFetcher
    private static let name = "OpenRouter"

    public init(fetcher: @escaping CloudHTTPFetcher = CloudHTTP.live) {
        self.fetcher = fetcher
    }

    public func fetchBalance(apiKey: String) async throws -> BalanceInfo {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let credits = try await load(Self.creditsRequest(apiKey: key))
        let keyBody = try await load(Self.keyRequest(apiKey: key))
        return try Self.balance(creditsData: credits, keyData: keyBody)
    }

    /// Perform one GET and return its body, throwing on non-2xx.
    private func load(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await fetcher(request)
        guard (200...299).contains(response.statusCode) else {
            throw CloudBalanceError.requestFailed(provider: Self.name, status: response.statusCode)
        }
        return data
    }

    // MARK: Request builders (no key ever logged)

    public static func creditsRequest(apiKey: String) -> URLRequest {
        bearerRequest(url: "https://openrouter.ai/api/v1/credits", apiKey: apiKey)
    }

    public static func keyRequest(apiKey: String) -> URLRequest {
        bearerRequest(url: "https://openrouter.ai/api/v1/key", apiKey: apiKey)
    }

    private static func bearerRequest(url: String, apiKey: String) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))",
                         forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: Pure parsers (unit-tested with mocked JSON)

    /// Parse `/api/v1/credits` → (totalCredits, totalUsage).
    public static func parseCredits(_ data: Data) throws -> (total: Double, usage: Double) {
        guard let decoded = try? JSONDecoder().decode(CreditsResponse.self, from: data) else {
            throw CloudBalanceError.unparsableResponse(provider: name)
        }
        return (decoded.data.total_credits, decoded.data.total_usage)
    }

    /// Parse `/api/v1/key` → (limit, limitRemaining). Both are nullable (unlimited key).
    public static func parseKey(_ data: Data) throws -> (limit: Double?, remaining: Double?) {
        guard let decoded = try? JSONDecoder().decode(KeyResponse.self, from: data) else {
            throw CloudBalanceError.unparsableResponse(provider: name)
        }
        return (decoded.data.limit, decoded.data.limit_remaining)
    }

    /// Combine the two response bodies into a single USD `BalanceInfo`.
    public static func balance(creditsData: Data, keyData: Data) throws -> BalanceInfo {
        let (totalCredits, totalUsage) = try parseCredits(creditsData)
        let (keyLimit, keyRemaining) = try parseKey(keyData)

        // Account-level remaining = purchased credits − all-time usage.
        let accountRemaining = totalCredits - totalUsage
        // A per-key credit cap (when set) can be tighter than the account balance;
        // show whichever leaves the user *less* to spend, so we never over-report.
        let remaining: Double
        if let keyRemaining {
            remaining = min(accountRemaining, keyRemaining)
        } else {
            remaining = accountRemaining
        }
        // "Total" is the cap the remaining is measured against: the per-key limit when
        // present, else the purchased credits.
        let total: Double? = keyLimit ?? (totalCredits > 0 ? totalCredits : nil)
        return .usd(remaining: remaining, total: total)
    }

    // MARK: Response DTOs (private)

    private struct CreditsResponse: Decodable {
        struct Payload: Decodable { let total_credits: Double; let total_usage: Double }
        let data: Payload
    }

    private struct KeyResponse: Decodable {
        struct Payload: Decodable { let limit: Double?; let limit_remaining: Double? }
        let data: Payload
    }
}

// MARK: - Ollama Cloud provider (plan limits, never USD)

/// Ollama Cloud bills by plan (GPU time), not USD. There is no verified public balance
/// endpoint (A7 — see ADR), so we honestly surface the plan label rather than a fake "$".
/// If a future API returns concrete plan limits, wire them into `.planLimits(detail:)`.
public struct OllamaCloudBalanceProvider: BalanceProvider {
    public init() {}

    public func fetchBalance(apiKey: String) async throws -> BalanceInfo {
        // No dollar balance exists; report the honest plan label with no fabricated detail.
        .planLimits(label: "Plan-based (GPU time)", detail: "")
    }
}

// MARK: - CloudBalanceService (actor: routing + short-TTL cache + quiet fallback)

public actor CloudBalanceService {
    /// Cached result per provider id, with the time it was fetched (TTL-gated).
    private struct Entry { let info: BalanceInfo; let fetchedAt: Date }
    private var cache: [String: Entry] = [:]

    /// How long a fetched balance stays fresh. Short so Refresh/reopen sees recent data
    /// without hammering the API.
    private let ttl: TimeInterval
    private let fetcher: CloudHTTPFetcher
    private let now: @Sendable () -> Date

    public init(
        ttl: TimeInterval = 60,
        fetcher: @escaping CloudHTTPFetcher = CloudHTTP.live,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.ttl = ttl
        self.fetcher = fetcher
        self.now = now
    }

    /// Fetch the balance for a provider, honoring §11:
    ///   - `.none`/`.estimated` providers → always `.unavailable` (never fetch/show).
    ///   - `.openrouterCredits`/`.ollamaPlan` → real fetch, TTL-cached, errors → `.unavailable`.
    /// `force == true` bypasses the cache (Refresh button).
    public func balance(
        for descriptor: CloudProviderDescriptor,
        apiKey: String,
        force: Bool = false
    ) async -> BalanceInfo {
        // Guard: never touch the network for providers without a real balance API.
        guard let provider = provider(for: descriptor) else { return .unavailable }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        // OpenRouter needs a key to report anything; Ollama's plan label does not.
        if descriptor.balanceKind == .openrouterCredits, trimmedKey.isEmpty {
            return .unavailable
        }

        if !force, let entry = cache[descriptor.id], now().timeIntervalSince(entry.fetchedAt) < ttl {
            return entry.info
        }

        do {
            let info = try await provider.fetchBalance(apiKey: trimmedKey)
            cache[descriptor.id] = Entry(info: info, fetchedAt: now())
            return info
        } catch {
            // Quiet fallback (§11): never surface the error, keep UI on estimated.
            return .unavailable
        }
    }

    /// Drop the cached balance for one provider (e.g. after the key changed).
    public func invalidate(providerID: String) {
        cache[providerID] = nil
    }

    /// Map a provider's `balanceKind` to its concrete `BalanceProvider`, or nil when the
    /// provider has no real balance API (so callers must not fetch).
    private func provider(for descriptor: CloudProviderDescriptor) -> BalanceProvider? {
        switch descriptor.balanceKind {
        case .openrouterCredits:
            return OpenRouterBalanceProvider(fetcher: fetcher)
        case .ollamaPlan:
            return OllamaCloudBalanceProvider()
        case .none, .estimated:
            return nil
        }
    }
}

