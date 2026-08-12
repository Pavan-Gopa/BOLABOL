import Foundation
import NativeBolabolCore

/// Fetches remote model catalogs (and OpenRouter pricing) for cloud polishing providers.
enum CloudProviderModelCatalog {
    struct FetchResult: Sendable {
        var models: [CloudRemoteModel]
        var errorMessage: String?
    }

    static func fetchModels(
        kind: APIProviderKind,
        configuration: APIProviderConfiguration
    ) async -> FetchResult {
        let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            return FetchResult(models: [], errorMessage: nil)
        }
        if apiKey.unicodeScalars.contains(where: { !$0.isASCII }) {
            return FetchResult(
                models: [],
                errorMessage: "API key has non-Latin characters. Re-paste the key in ASCII."
            )
        }

        do {
            let models: [CloudRemoteModel]
            switch kind {
            case .openAI:
                models = try await fetchOpenAICompatibleModels(
                    baseURL: APIProviderKind.openAI.defaultBaseURL,
                    apiKey: apiKey,
                    includePricing: false
                )
            case .qwen:
                models = qwenSubscriptionModels
            case .openRouter:
                models = try await fetchOpenAICompatibleModels(
                    baseURL: APIProviderKind.openRouter.defaultBaseURL,
                    apiKey: apiKey,
                    includePricing: true
                )
            case .custom:
                let base = configuration.baseURL
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard !base.isEmpty else {
                    return FetchResult(models: [], errorMessage: "Enter a Base URL first.")
                }
                models = try await fetchOpenAICompatibleModels(
                    baseURL: base,
                    apiKey: apiKey,
                    includePricing: base.contains("openrouter")
                )
            case .anthropic:
                models = try await fetchAnthropicModels(apiKey: apiKey)
            case .google:
                models = try await fetchGoogleModels(apiKey: apiKey)
            }
            return FetchResult(models: models, errorMessage: nil)
        } catch {
            return FetchResult(models: [], errorMessage: error.localizedDescription)
        }
    }

    // MARK: - Qwen Subscription Models

    public static let qwenSubscriptionModels: [CloudRemoteModel] = [
        CloudRemoteModel(id: "qwen3.8-max-preview", contextLength: 262_144, promptPricePer1M: 0.35, completionPricePer1M: 1.05),
        CloudRemoteModel(id: "qwen3.7-plus", contextLength: 131_072, promptPricePer1M: 0.11, completionPricePer1M: 0.33),
        CloudRemoteModel(id: "qwen3.7-max", contextLength: 131_072, promptPricePer1M: 0.35, completionPricePer1M: 1.05),
        CloudRemoteModel(id: "qwen3.6-flash", contextLength: 131_072, promptPricePer1M: 0.05, completionPricePer1M: 0.15),
        CloudRemoteModel(id: "deepseek-v4-pro", contextLength: 131_072, promptPricePer1M: 0.14, completionPricePer1M: 0.28),
        CloudRemoteModel(id: "glm-5.2", contextLength: 131_072, promptPricePer1M: 0.10, completionPricePer1M: 0.20),
    ]

    // MARK: - Pricing & Context Fallbacks

    public static func defaultContextLabel(for model: String) -> String {
        let lower = model.lowercased()
        if lower.contains("qwen3.8") || lower.contains("qwen3.7") || lower.contains("qwen3.6") || lower.contains("qwen") {
            return "131K"
        }
        if lower.contains("gemini-2.5") || lower.contains("gemini-2.0") || lower.contains("gemini-1.5") || lower.contains("gemini") {
            return "1.0M"
        }
        if lower.contains("claude-3") || lower.contains("sonnet") || lower.contains("haiku") || lower.contains("opus") {
            return "200K"
        }
        return "128K"
    }

    public static func inputPricePer1M(for model: String) -> Double {
        let lower = model.lowercased()
        if lower.contains("qwen3.8") || lower.contains("qwen3.7-max") || lower.contains("qwen-max") { return 0.35 }
        if lower.contains("qwen3.7-plus") || lower.contains("qwen-plus") { return 0.11 }
        if lower.contains("qwen3.6") || lower.contains("qwen-turbo") || lower.contains("flash") { return 0.05 }
        if lower.contains("deepseek") { return 0.14 }
        if lower.contains("glm") { return 0.10 }
        if lower.contains("gemini-2.5-pro") || lower.contains("gemini-1.5-pro") { return 1.25 }
        if lower.contains("gemini-2.5-flash") || lower.contains("gemini-2.0-flash") || lower.contains("gemini-1.5-flash") || lower.contains("gemini") { return 0.075 }
        if lower.contains("gpt-4o-mini") || lower.contains("gpt-4.1-mini") { return 0.15 }
        if lower.contains("gpt-4o") { return 2.50 }
        if lower.contains("claude-3-5-sonnet") || lower.contains("sonnet") { return 3.00 }
        return 0.15
    }

    public static func outputPricePer1M(for model: String) -> Double {
        let lower = model.lowercased()
        if lower.contains("qwen3.8") || lower.contains("qwen3.7-max") || lower.contains("qwen-max") { return 1.05 }
        if lower.contains("qwen3.7-plus") || lower.contains("qwen-plus") { return 0.33 }
        if lower.contains("qwen3.6") || lower.contains("qwen-turbo") || lower.contains("flash") { return 0.15 }
        if lower.contains("deepseek") { return 0.28 }
        if lower.contains("glm") { return 0.20 }
        if lower.contains("gemini-2.5-pro") || lower.contains("gemini-1.5-pro") { return 5.00 }
        if lower.contains("gemini-2.5-flash") || lower.contains("gemini-2.0-flash") || lower.contains("gemini-1.5-flash") || lower.contains("gemini") { return 0.30 }
        if lower.contains("gpt-4o-mini") || lower.contains("gpt-4.1-mini") { return 0.60 }
        if lower.contains("gpt-4o") { return 10.00 }
        if lower.contains("claude-3-5-sonnet") || lower.contains("sonnet") { return 15.00 }
        return 0.60
    }

    public static func estimateCostUSD(modelID: String, promptTokens: Int, completionTokens: Int) -> Double {
        let inputRate = inputPricePer1M(for: modelID)
        let outputRate = outputPricePer1M(for: modelID)
        let inputCost = (Double(max(0, promptTokens)) * inputRate) / 1_000_000.0
        let outputCost = (Double(max(0, completionTokens)) * outputRate) / 1_000_000.0
        return inputCost + outputCost
    }

    public static func formattedCostUSD(modelID: String, promptTokens: Int, completionTokens: Int) -> String {
        let cost = estimateCostUSD(modelID: modelID, promptTokens: promptTokens, completionTokens: completionTokens)
        if cost <= 0 { return "$0.00" }
        if cost < 0.0001 { return "< $0.0001" }
        if cost < 0.01 { return String(format: "$%.4f", cost) }
        return String(format: "$%.2f", cost)
    }

    public static func defaultInputCost(for model: String) -> String {
        String(format: "$%.3f / 1M", inputPricePer1M(for: model))
    }

    public static func defaultOutputCost(for model: String) -> String {
        String(format: "$%.3f / 1M", outputPricePer1M(for: model))
    }

    // MARK: - OpenAI-compatible

    private static func fetchOpenAICompatibleModels(
        baseURL: String,
        apiKey: String,
        includePricing: Bool
    ) async throws -> [CloudRemoteModel] {
        guard let url = URL(string: "\(baseURL)/models") else {
            throw CatalogError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if includePricing {
            request.setValue("https://bolabol.app", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("Bolabol", forHTTPHeaderField: "X-Title")
        }
        request.timeoutInterval = 25

        let (data, response) = try await URLSession.shared.data(for: request)
        try throwIfHTTPError(response, data: data)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(OpenAIModelsResponse.self, from: data)
        let models = decoded.data.compactMap { item -> CloudRemoteModel? in
            let id = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return nil }
            let prompt = includePricing ? parsePrice(item.pricing?.prompt) : nil
            let completion = includePricing ? parsePrice(item.pricing?.completion) : nil
            // OpenRouter prices are per-token USD strings → convert to per-1M.
            let prompt1M = prompt.map { $0 * 1_000_000 }
            let completion1M = completion.map { $0 * 1_000_000 }
            let context = item.contextLength ?? item.topProvider?.contextLength
            return CloudRemoteModel(
                id: id,
                contextLength: context,
                promptPricePer1M: prompt1M,
                completionPricePer1M: completion1M
            )
        }
        return models.sorted {
            $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
        }
    }

    /// OpenRouter returns price as a string like "0.00000015" (USD per token).
    private static func parsePrice(_ raw: String?) -> Double? {
        guard let raw, let value = Double(raw), value >= 0, value.isFinite else { return nil }
        return value
    }

    // MARK: - Anthropic

    private static func fetchAnthropicModels(apiKey: String) async throws -> [CloudRemoteModel] {
        guard let url = URL(string: "https://api.anthropic.com/v1/models") else {
            throw CatalogError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        try throwIfHTTPError(response, data: data)
        let decoded = try JSONDecoder().decode(AnthropicModelsResponse.self, from: data)
        return decoded.data.map { CloudRemoteModel(id: $0.id) }.sorted {
            $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
        }
    }

    // MARK: - Google

    // MARK: - Google

    private static func fetchGoogleModels(apiKey: String) async throws -> [CloudRemoteModel] {
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components?.url else { throw CatalogError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        try throwIfHTTPError(response, data: data)
        let decoded = try JSONDecoder().decode(GoogleModelsResponse.self, from: data)
        let models = (decoded.models ?? []).compactMap { model -> CloudRemoteModel? in
            let methods = model.supportedGenerationMethods ?? []
            if !methods.isEmpty, !methods.contains("generateContent") { return nil }
            var name = model.name ?? ""
            if name.hasPrefix("models/") { name = String(name.dropFirst("models/".count)) }
            guard !name.isEmpty else { return nil }

            let lower = name.lowercased()
            // Exclude obsolete 1.0/1.5/8b/bison/embedding/experimental legacy models
            if lower.contains("1.0") || lower.contains("1.5") || lower.contains("8b")
                || lower.contains("bison") || lower.contains("embedding") || lower.contains("aqa")
                || lower.contains("imagen") || lower.contains("001") || lower.contains("002") {
                return nil
            }
            return CloudRemoteModel(id: name)
        }
        let ids = models.map(\.id)
        return models.sorted { m1, m2 in
            let badge1 = badgeInfo(for: m1.id, groupModelIDs: ids)
            let badge2 = badgeInfo(for: m2.id, groupModelIDs: ids)
            if badge1.isNew != badge2.isNew { return badge1.isNew && !badge2.isNew }
            if badge1.isRecommended != badge2.isRecommended { return badge1.isRecommended && !badge2.isRecommended }
            return m1.id.localizedCaseInsensitiveCompare(m2.id) == .orderedAscending
        }
    }

    // MARK: - Badges & Metadata

    public struct ModelBadgeInfo: Sendable, Equatable {
        public var isRecommended: Bool
        public var isNew: Bool

        public var badgeLabels: [String] {
            var labels: [String] = []
            if isRecommended { labels.append("★ Recommended") }
            if isNew { labels.append("✨ New") }
            return labels
        }

        public var badgeText: String? {
            let labels = badgeLabels
            return labels.isEmpty ? nil : labels.joined(separator: " · ")
        }
    }

    public static func badgeInfo(for modelID: String, groupModelIDs: [String] = []) -> ModelBadgeInfo {
        let lower = modelID.lowercased()

        let isNew: Bool
        let version = extractVersion(from: lower)
        let family = extractFamily(from: lower)

        if let version {
            let familyMax = maxVersion(forFamily: family, in: groupModelIDs)
            if familyMax > 0 {
                isNew = version >= (familyMax - 0.15)
            } else {
                isNew = version >= 3.5 || lower.contains("v4") || lower.contains("v3.5")
            }
        } else {
            isNew = lower.contains("preview") || lower.contains("latest") || lower.contains("3.5") || lower.contains("3.6") || lower.contains("3.7") || lower.contains("3.8") || lower.contains("v4")
        }

        // Recommended badge is ONLY given to models that are BOTH light (Flash/Lite/Nano/Micro/Small/Mini/Haiku/Turbo/Plus) AND new/latest!
        let isFlashOrLight = lower.contains("flash") || lower.contains("lite") || lower.contains("nano") || lower.contains("micro") || lower.contains("small") || lower.contains("mini") || lower.contains("turbo") || lower.contains("haiku") || lower.contains("plus")
        let isHeavy = (lower.contains("-pro") && !lower.contains("flash-pro")) || lower.contains("-max") || lower.contains("-opus") || lower.contains("-r1") || lower.contains("70b") || lower.contains("405b")
        let isRecommended = isFlashOrLight && !isHeavy && isNew

        return ModelBadgeInfo(isRecommended: isRecommended, isNew: isNew)
    }

    private static func extractVersion(from lower: String) -> Double? {
        let pattern = #"(?:gemini|qwen|gpt|claude|deepseek|glm|llama|v)?-?v?(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: lower, options: [], range: NSRange(lower.startIndex..., in: lower)),
              let range = Range(match.range(at: 1), in: lower),
              let value = Double(lower[range]) else {
            return nil
        }
        return value
    }

    private static func extractFamily(from lower: String) -> String {
        if lower.contains("/") {
            let parts = lower.split(separator: "/")
            if parts.count >= 2 {
                let org = String(parts[0])
                let model = String(parts[1])
                for sub in ["gemini", "qwen", "gpt", "claude", "deepseek", "glm", "llama", "mistral"] {
                    if model.contains(sub) { return "\(org)/\(sub)" }
                }
                return org
            }
        }
        for f in ["gemini", "qwen", "gpt", "claude", "deepseek", "glm", "llama", "mistral"] {
            if lower.contains(f) { return f }
        }
        return "default"
    }

    private static func maxVersion(forFamily family: String, in groupIDs: [String]) -> Double {
        var maxVer: Double = 0
        for id in groupIDs {
            let lower = id.lowercased()
            let itemFamily = extractFamily(from: lower)
            if family == "default" || itemFamily == family || lower.contains(family) {
                if let ver = extractVersion(from: lower) {
                    if ver > maxVer { maxVer = ver }
                }
            }
        }
        return maxVer
    }

    // MARK: - OpenRouter balance

    struct OpenRouterBalance: Sendable, Equatable {
        var remainingUSD: Double
        var totalCreditsUSD: Double?
    }

    static func fetchOpenRouterBalance(apiKey: String) async -> OpenRouterBalance? {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.unicodeScalars.allSatisfy(\.isASCII) else { return nil }

        async let creditsData = getJSON(url: "https://openrouter.ai/api/v1/credits", apiKey: key)
        async let keyData = getJSON(url: "https://openrouter.ai/api/v1/key", apiKey: key)

        do {
            let credits = try await creditsData
            let keyBody = try await keyData
            let totalCredits = (credits["data"] as? [String: Any])?["total_credits"] as? Double
                ?? ((credits["data"] as? [String: Any])?["total_credits"] as? NSNumber)?.doubleValue
            let totalUsage = (credits["data"] as? [String: Any])?["total_usage"] as? Double
                ?? ((credits["data"] as? [String: Any])?["total_usage"] as? NSNumber)?.doubleValue
            let limitRemaining = (keyBody["data"] as? [String: Any])?["limit_remaining"] as? Double
                ?? ((keyBody["data"] as? [String: Any])?["limit_remaining"] as? NSNumber)?.doubleValue

            var remaining = max(0, (totalCredits ?? 0) - (totalUsage ?? 0))
            if let limitRemaining {
                remaining = min(remaining, max(0, limitRemaining))
            }
            return OpenRouterBalance(remainingUSD: remaining, totalCreditsUSD: totalCredits)
        } catch {
            return nil
        }
    }

    private static func getJSON(url: String, apiKey: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://bolabol.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Bolabol", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        try throwIfHTTPError(response, data: data)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CatalogError.invalidResponse
        }
        return object
    }

    // MARK: - Helpers

    private static func throwIfHTTPError(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CatalogError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = errorMessage(from: data)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw CatalogError.http(status: http.statusCode, message: message)
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return object["message"] as? String
    }

    private enum CatalogError: LocalizedError {
        case invalidURL
        case invalidResponse
        case http(status: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid provider URL."
            case .invalidResponse: return "The provider returned an invalid models list."
            case .http(let status, let message):
                if status == 401 || status == 403 {
                    return "Could not list models (auth). Check the API key."
                }
                return "Could not list models (\(status)): \(message)"
            }
        }
    }
}

// MARK: - DTOs

private struct OpenAIModelsResponse: Decodable {
    struct Pricing: Decodable {
        let prompt: String?
        let completion: String?
    }

    struct TopProvider: Decodable {
        let contextLength: Int?
    }

    struct Model: Decodable {
        let id: String
        let pricing: Pricing?
        let contextLength: Int?
        let topProvider: TopProvider?
    }

    let data: [Model]
}

private struct AnthropicModelsResponse: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}

private struct GoogleModelsResponse: Decodable {
    struct Model: Decodable {
        let name: String?
        let supportedGenerationMethods: [String]?
    }

    let models: [Model]?
}

extension CloudRemoteModel {
    public var resolvedInputPriceLabel: String {
        if let prompt = promptPricePer1M {
            return String(format: "$%.3f / 1M", prompt)
        }
        return CloudProviderModelCatalog.defaultInputCost(for: id)
    }

    public var resolvedOutputPriceLabel: String {
        if let completion = completionPricePer1M {
            return String(format: "$%.3f / 1M", completion)
        }
        return CloudProviderModelCatalog.defaultOutputCost(for: id)
    }

    public var resolvedContextLabel: String {
        if let contextLength, contextLength > 0 {
            if contextLength >= 1_000_000 {
                let m = Double(contextLength) / 1_000_000
                return String(format: "%.1fM", m)
            }
            if contextLength >= 1_000 {
                return "\(contextLength / 1_000)K"
            }
            return "\(contextLength)"
        }
        return CloudProviderModelCatalog.defaultContextLabel(for: id)
    }
}
