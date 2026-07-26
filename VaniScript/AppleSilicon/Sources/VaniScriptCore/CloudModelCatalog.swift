import Foundation

// MARK: - CloudModelCatalog
//
// Role: VaniScriptCore service (A4) that fetches the *live model list* for a cloud
// provider once its API key is valid, so the UI can offer a real dropdown instead
// of a hardcoded model name. It owns:
//   - the per-provider "list models" HTTP requests (built from CloudProviderCatalog
//     descriptors + §9.2 endpoints),
//   - the response parsers for the four response shapes (OpenAI-compatible, Gemini,
//     Anthropic, Ollama tags),
//   - an in-memory, session-only cache (never persisted) to avoid re-hitting the API.
//
// It must NOT: persist anything, log or embed API keys, or perform transcription/
// translation (those live in the Cloud*Engine layer). Network is injected via a
// `CloudHTTPFetcher` closure so unit tests exercise the parsers with mocked JSON.
//
// Invariants (§14): no keys/tokens in source or logs; migration-safe; buildable.

/// One model offered by a provider. `id` is the value written into settings and sent
/// to the provider API (e.g. `gpt-4o-mini`, `gemini-2.5-flash`, `gpt-oss:120b`).
public struct CloudModel: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: String
    public init(id: String) { self.id = id }
}

/// Injectable network boundary. Default is URLSession-backed; tests pass a stub that
/// returns canned `(Data, HTTPURLResponse)` so no real request is made.
public typealias CloudHTTPFetcher = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

/// Errors surfaced while listing models. UI turns these into the "editable combo +
/// Retry" fallback (§9.2), never a hard failure of the provider card.
public enum CloudModelCatalogError: LocalizedError, Equatable {
    /// Provider has no automatic model listing (custom / none endpoints).
    case listingUnsupported(provider: String)
    /// The provider replied but with a non-2xx status.
    case requestFailed(provider: String, status: Int)
    /// The response body could not be parsed into a model list.
    case unparsableResponse(provider: String)

    public var errorDescription: String? {
        switch self {
        case let .listingUnsupported(provider):
            return "\(provider) does not support automatic model listing."
        case let .requestFailed(provider, status):
            return "\(provider) model listing failed with HTTP \(status)."
        case let .unparsableResponse(provider):
            return "\(provider) returned a model list that could not be read."
        }
    }
}

/// Live HTTP fetcher used in the app. Kept separate from parsing so tests never touch
/// the network. No blocking work here — URLSession is fully async.
public enum CloudHTTP {
    public static let live: CloudHTTPFetcher = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

public actor CloudModelCatalog {
    // Session-only cache. Key = provider id + a non-reversible hash of the API key, so
    // a changed key busts the cache without ever storing the key itself (invariant §14).
    private var cache: [String: [CloudModel]] = [:]
    private let fetcher: CloudHTTPFetcher

    public init(fetcher: @escaping CloudHTTPFetcher = CloudHTTP.live) {
        self.fetcher = fetcher
    }

    /// Fetch (and cache) the model list for a provider. Throws `CloudModelCatalogError`
    /// on unsupported providers, non-2xx responses, or unparsable bodies so the UI can
    /// fall back to the editable combo (§9.2).
    public func listModels(
        descriptor: CloudProviderDescriptor,
        apiKey: String,
        baseURL: String? = nil,
        useCache: Bool = true
    ) async throws -> [CloudModel] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = "\(descriptor.id):\(Self.keyFingerprint(trimmedKey)):\(baseURL ?? "")"
        if useCache, let cached = cache[cacheKey] {
            return cached
        }

        guard let request = Self.listRequest(descriptor: descriptor, apiKey: trimmedKey, baseURL: baseURL) else {
            throw CloudModelCatalogError.listingUnsupported(provider: descriptor.label)
        }

        let (data, response) = try await fetcher(request)
        guard (200...299).contains(response.statusCode) else {
            throw CloudModelCatalogError.requestFailed(provider: descriptor.label, status: response.statusCode)
        }

        let models = try Self.parse(data: data, endpoint: descriptor.modelsEndpoint, provider: descriptor.label)
        cache[cacheKey] = models
        return models
    }

    /// Drop cached models for one provider (e.g. after the key changed). Session only.
    public func invalidate(providerID: String) {
        cache = cache.filter { !$0.key.hasPrefix("\(providerID):") }
    }

    /// Non-reversible fingerprint of the API key for cache keying. Never stores or logs
    /// the key itself (invariant §14.3).
    private static func keyFingerprint(_ key: String) -> String {
        String(key.hashValue, radix: 16)
    }

    // MARK: - Request building (shared with CloudKeyValidator)

    /// Build the "list models" request for a provider, or nil when listing is not
    /// supported (custom / none). Auth is applied per §9.1 / §9.2.
    public static func listRequest(
        descriptor: CloudProviderDescriptor,
        apiKey: String,
        baseURL: String? = nil
    ) -> URLRequest? {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        switch descriptor.modelsEndpoint {
        case .gemini:
            // Gemini authenticates via ?key= query param (§9.1).
            guard var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models") else { return nil }
            components.queryItems = [URLQueryItem(name: "key", value: key)]
            guard let url = components.url else { return nil }
            return URLRequest(url: url)
        case .openAICompatible:
            let urlString = openAICompatibleBase(for: descriptor.id) + "/v1/models"
            guard let url = URL(string: urlString) else { return nil }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            return request
        case .anthropic:
            guard let url = URL(string: "https://api.anthropic.com/v1/models") else { return nil }
            var request = URLRequest(url: url)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            return request
        case .ollamaTags:
            let base = (baseURL?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "https://ollama.com"
            guard let url = URL(string: base + "/api/tags") else { return nil }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            return request
        case .custom, .none:
            return nil
        }
    }

    /// Base host for OpenAI-compatible providers (OpenAI / Qwen / OpenRouter).
    private static func openAICompatibleBase(for providerID: String) -> String {
        switch providerID {
        case CloudProviderCatalog.qwenID:
            return "https://dashscope-intl.aliyuncs.com/compatible-mode"
        case CloudProviderCatalog.openrouterID:
            return "https://openrouter.ai/api"
        default: // OpenAI and anything else OpenAI-shaped
            return "https://api.openai.com"
        }
    }

    // MARK: - Parsers (pure, unit-tested with mocked JSON)

    /// Parse a raw response body into `[CloudModel]` based on the provider's endpoint
    /// shape. Duplicate ids are removed while preserving first-seen order.
    public static func parse(data: Data, endpoint: ModelsEndpoint, provider: String) throws -> [CloudModel] {
        let ids: [String]
        switch endpoint {
        case .openAICompatible, .anthropic:
            // OpenAI-compatible + Anthropic: `{ "data": [ { "id": "..." } ] }`.
            guard let decoded = try? JSONDecoder().decode(OpenAICompatibleModelList.self, from: data) else {
                throw CloudModelCatalogError.unparsableResponse(provider: provider)
            }
            ids = decoded.data.map(\.id)
        case .gemini:
            // Gemini: `{ "models": [ { "name": "models/gemini-2.5-flash" } ] }` → strip prefix.
            guard let decoded = try? JSONDecoder().decode(GeminiModelList.self, from: data) else {
                throw CloudModelCatalogError.unparsableResponse(provider: provider)
            }
            ids = decoded.models.map { Self.stripGeminiPrefix($0.name) }
        case .ollamaTags:
            // Ollama Cloud: `{ "models": [ { "name": "gpt-oss:120b" } ] }`.
            guard let decoded = try? JSONDecoder().decode(OllamaTagList.self, from: data) else {
                throw CloudModelCatalogError.unparsableResponse(provider: provider)
            }
            ids = decoded.models.map(\.name)
        case .custom, .none:
            throw CloudModelCatalogError.listingUnsupported(provider: provider)
        }

        // De-dupe (preserve order) and drop empties.
        var seen = Set<String>()
        let models = ids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .map { CloudModel(id: $0) }
        return models
    }

    /// Gemini returns fully-qualified names like `models/gemini-2.5-flash`; the UI and
    /// engines use the bare id, so drop the `models/` prefix.
    static func stripGeminiPrefix(_ name: String) -> String {
        let prefix = "models/"
        return name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
    }
}

// MARK: - Response DTOs (private to the catalog)

private struct OpenAICompatibleModelList: Decodable {
    struct Entry: Decodable { let id: String }
    let data: [Entry]
}

private struct GeminiModelList: Decodable {
    struct Entry: Decodable { let name: String }
    let models: [Entry]
}

private struct OllamaTagList: Decodable {
    struct Entry: Decodable { let name: String }
    let models: [Entry]
}
