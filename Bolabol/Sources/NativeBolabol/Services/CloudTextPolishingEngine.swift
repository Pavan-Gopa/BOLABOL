import Foundation
import NativeBolabolCore

struct CloudTextPolishingEngine: PolishingEngine {
    let kind: APIProviderKind
    let configuration: APIProviderConfiguration
    /// Custom instance identity (ADR-031). Nil for built-ins and for engines
    /// built directly from a kind + configuration; then the id/displayName
    /// fall back to the kind (with the configuration name for custom),
    /// preserving single-custom behavior.
    let engineIDOverride: String?
    let displayNameOverride: String?
    private static let googleSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest =
            CloudRequestRetryPolicy.googleTextGeneration.timeoutInterval
        configuration.timeoutIntervalForResource = 45
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()


    init(
        kind: APIProviderKind,
        configuration: APIProviderConfiguration,
        engineIDOverride: String? = nil,
        displayNameOverride: String? = nil
    ) {
        self.kind = kind
        self.configuration = configuration
        self.engineIDOverride = engineIDOverride
        self.displayNameOverride = displayNameOverride
    }

    init(
        kind: APIProviderKind,
        configuration: APIProviderConfiguration,
        customInstance: CustomAPIProviderInstance
    ) {
        self.init(
            kind: kind,
            configuration: configuration,
            engineIDOverride: customInstance.engineID,
            displayNameOverride: customInstance.displayName
        )
    }

    var id: String { engineIDOverride ?? kind.polishingEngineID }
    var displayName: String {
        if let displayNameOverride, !displayNameOverride.isEmpty { return displayNameOverride }
        if kind == .custom {
            let name = configuration.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? kind.displayName : name
        }
        return kind.displayName
    }

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        try await polish(
            request,
            keyChainSeconds: CloudKeyFailover.TimeBudget.default.keyChainSeconds,
            deadline: nil
        )
    }

    /// Q5a: deadline-aware polish for the translation-provider step. The key
    /// chain shares `keyChainSeconds` and never starts a new key at or after
    /// `deadline` (the output-language chain cap).
    func polish(
        _ request: PolishingRequest,
        keyChainSeconds: TimeInterval,
        deadline: Date? = nil
    ) async throws -> PolishingResult {
        let prompt = try PolishingPromptPolicy.prepare(
            template: request.template,
            transcription: request.rawText
        )
        let startedAt = Date()
        let response = try await generateText(
            systemInstruction: prompt.systemInstruction,
            userContent: prompt.userContent,
            keyChainSeconds: keyChainSeconds,
            deadline: deadline
        )

        return PolishingResult(
            text: ModelOutputSanitizer.sanitize(response.text),
            diagnostics: EngineDiagnostics(
                backendName: "\(displayName) \(configuration.textModel)",
                loadTimeMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000),
                promptTokens: response.promptTokens,
                completionTokens: response.completionTokens
            )
        )
    }

    private func generateText(
        systemInstruction: String,
        userContent: String,
        keyChainSeconds: TimeInterval,
        deadline: Date?
    ) async throws -> CloudTextResponse {
        let keys = try sanitizedAPIKeys()
        let textModel = configuration.textModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textModel.isEmpty else {
            throw CloudTextPolishingError.invalidConfiguration(
                "Text model is empty. For Qwen Token Plan use a real model id such as qwen3.7-plus or qwen3.7-max (not just \"Qwen\")."
            )
        }

        // ADR-029/Q5a: every cloud provider fails over across its full key list.
        // Timeout / transport / 5xx / 429 / 401-403 / empty-2xx → next key
        // immediately, no same-key retry. Other 4xx / decode → stop.
        // Disabled keys are already excluded by `sanitizedAPIKeys`.
        // No new key starts at or after the chain-cap deadline.
        var lastError: Error?
        let keyChainDeadline = Date().addingTimeInterval(max(0, keyChainSeconds))
        let effectiveDeadline = deadline.map { min($0, keyChainDeadline) } ?? keyChainDeadline
        for (index, apiKey) in keys.enumerated() {
            try Task.checkCancellation()
            guard Date() < effectiveDeadline else { break }
            do {
                // Q5a: the chain cap bounds the in-flight request itself, not
                // just admission of the next key — a reply arriving past the
                // cap is cancelled, never accepted as successful output.
                let remaining = effectiveDeadline.timeIntervalSinceNow
                return try await CloudKeyFailover.withTimeout(seconds: remaining) {
                    try await self.executeGenerateText(
                        systemInstruction: systemInstruction,
                        userContent: userContent,
                        apiKey: apiKey,
                        textModel: textModel
                    )
                }
            } catch {
                lastError = error
                let failure = Self.failoverFailure(for: error)
                let verdict = CloudKeyFailover.action(for: failure)
                NativeBolabolLog.polishing.warning(
                    "\(self.displayName) API Key #\(index + 1)/\(keys.count) failed class=\(String(describing: failure), privacy: .public) verdict=\(String(describing: verdict), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                if verdict == .nextKey, index < keys.count - 1 {
                    continue
                }
                throw error
            }
        }

        if let lastError {
            throw lastError
        }
        throw CloudTextPolishingError.invalidConfiguration("API key is invalid or missing. Please check Settings > API Providers.")
    }

    /// Maps any polishing failure onto the shared pure failover policy.
    static func failoverFailure(for error: any Error) -> CloudKeyFailover.Failure {
        if let polishing = error as? CloudTextPolishingError {
            switch polishing {
            case .apiError(let statusCode, let message):
                return CloudKeyFailover.classifyHTTPStatus(statusCode, message: message)
            case .invalidResponse, .invalidConfiguration:
                return .decodeError
            }
        }
        return CloudKeyFailover.classify(error: error)
    }
    private func executeGenerateText(
        systemInstruction: String,
        userContent: String,
        apiKey: String,
        textModel: String
    ) async throws -> CloudTextResponse {
        switch kind {
        case .google:
            return try await postJSON(
                url: googleURL(model: textModel),
                headers: ["x-goog-api-key": apiKey],
                body: GoogleGenerateRequest(
                    systemInstruction: systemInstruction.isEmpty
                        ? nil
                        : GoogleContent(parts: [GooglePart(text: systemInstruction)]),
                    contents: [
                        GoogleContent(
                            role: "user",
                            parts: [GooglePart(text: userContent)]
                        )
                    ],
                    generationConfig: GoogleGenerationConfig(
                        temperature: PolishingGenerationPolicy.cloudTemperature(
                            provider: kind,
                            modelID: textModel
                        ),
                        maxOutputTokens: 4096,
                        responseMimeType: "text/plain",
                        thinkingConfig: PolishingGenerationPolicy.googleThinkingLevel(
                            for: textModel
                        ).map(GoogleThinkingConfig.init(thinkingLevel:))
                    )
                ),
                useSnakeCaseCoding: false,
                decode: { (data: GoogleGenerateResponse) in
                    // ADR-029: an empty 2xx reply fails over to the next key,
                    // never silently inserts nothing.
                    let text = data.candidates?.first?.content.parts.compactMap(\.text).joined(separator: "\n")
                        ?? data.text
                        ?? ""
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw CloudRequestRetryError.emptySuccessfulResponse
                    }
                    return CloudTextResponse(
                        text: text,
                        promptTokens: data.usageMetadata?.promptTokenCount,
                        completionTokens: data.usageMetadata?.candidatesTokenCount
                    )
                }
            )

        case .openAI:
            return try await postJSON(
                url: URL(string: "https://api.openai.com/v1/chat/completions")!,
                headers: authorizationHeaders(apiKey: apiKey),
                body: ChatCompletionRequest(
                    model: textModel,
                    messages: chatMessages(
                        systemInstruction: systemInstruction,
                        userContent: userContent,
                        modelID: textModel
                    ),
                    temperature: PolishingGenerationPolicy.cloudTemperature(
                        provider: kind,
                        modelID: textModel
                    ),
                    maxTokens: 4096,
                    enableThinking: nil
                ),
                decode: openAIResponse
            )

        case .anthropic:
            return try await postJSON(
                url: URL(string: "https://api.anthropic.com/v1/messages")!,
                headers: [
                    "x-api-key": apiKey,
                    "anthropic-version": "2023-06-01"
                ],
                body: AnthropicRequest(
                    model: textModel,
                    system: systemInstruction.isEmpty ? nil : systemInstruction,
                    maxTokens: 4096,
                    temperature: PolishingGenerationPolicy.cloudTemperature(
                        provider: kind,
                        modelID: textModel
                    ),
                    messages: [.init(role: "user", content: userContent)]
                ),
                decode: { (data: AnthropicResponse) in
                    // ADR-029: an empty 2xx reply fails over to the next key,
                    // never silently inserts nothing.
                    let text = data.content.compactMap(\.text).joined(separator: "\n")
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw CloudRequestRetryError.emptySuccessfulResponse
                    }
                    return CloudTextResponse(
                        text: text,
                        promptTokens: data.usage?.inputTokens,
                        completionTokens: data.usage?.outputTokens
                    )
                }
            )

        case .qwen, .openRouter, .custom:
            return try await postJSON(
                url: try openAICompatibleChatURL(for: kind),
                headers: openAICompatibleHeaders(apiKey: apiKey, kind: kind),
                body: ChatCompletionRequest(
                    model: textModel,
                    messages: chatMessages(
                        systemInstruction: systemInstruction,
                        userContent: userContent,
                        modelID: textModel
                    ),
                    temperature: PolishingGenerationPolicy.cloudTemperature(
                        provider: kind,
                        modelID: textModel
                    ),
                    maxTokens: 4096,
                    enableThinking: PolishingGenerationPolicy.qwenThinkingEnabled(
                        provider: kind,
                        modelID: textModel
                    )
                ),
                decode: openAIResponse
            )
        }
    }

    private func chatMessages(
        systemInstruction: String,
        userContent: String,
        modelID: String
    ) -> [ChatCompletionRequest.Message] {
        var messages: [ChatCompletionRequest.Message] = []
        if !systemInstruction.isEmpty {
            let role = PolishingGenerationPolicy.instructionRole(
                provider: kind,
                modelID: modelID
            )
            messages.append(.init(role: role.rawValue, content: systemInstruction))
        }
        messages.append(.init(role: "user", content: userContent))
        return messages
    }

    /// Trims whitespace and rejects keys that cannot be sent in HTTP headers.
    private func sanitizedAPIKeys() throws -> [String] {
        let keys = configuration.sanitizedAPIKeys
        guard !keys.isEmpty else {
            throw CloudTextPolishingError.invalidConfiguration(
                "API key is invalid or missing. Please check Settings > API Providers."
            )
        }
        for key in keys {
            if key.unicodeScalars.contains(where: { !$0.isASCII }) {
                throw CloudTextPolishingError.invalidConfiguration(
                    "API key contains non-Latin characters (often from a Russian keyboard layout). Re-paste the key carefully — it must be pure ASCII (e.g. sk-sp-H…)."
                )
            }
        }
        return keys
    }

    private func postJSON<Request: Encodable, Response: Decodable>(
        url: URL,
        headers: [String: String],
        body: Request,
        useSnakeCaseCoding: Bool = true,
        decode: (Response) throws -> CloudTextResponse
    ) async throws -> CloudTextResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let encoder = useSnakeCaseCoding ? JSONEncoder.cloudAPI : JSONEncoder()
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await performDataRequest(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTextPolishingError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = Self.errorMessage(from: data)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            NativeBolabolLog.polishing.error(
                "Cloud polishing HTTP \(httpResponse.statusCode) url=\(url.absoluteString, privacy: .public) message=\(message, privacy: .public)"
            )
            throw CloudTextPolishingError.apiError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }

        do {
            let decoder = useSnakeCaseCoding ? JSONDecoder.cloudAPI : JSONDecoder()
            return try decode(try decoder.decode(Response.self, from: data))
        } catch {
            NativeBolabolLog.polishing.error(
                "Cloud polishing decode failed url=\(url.absoluteString, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    /// ADR-029/Q5a: one attempt per key with a 15 s per-request timeout for
    /// every provider. Key failover (not same-key retry) is owned by
    /// `generateText` via `CloudKeyFailover`.
    private func performDataRequest(_ sourceRequest: URLRequest) async throws -> (Data, URLResponse) {
        let policy = CloudRequestRetryPolicy.googleTextGeneration
        var request = sourceRequest
        request.timeoutInterval = policy.timeoutInterval

        let startedAt = Date()
        NativeBolabolLog.polishing.info(
            "Cloud polishing request started provider=\(self.displayName, privacy: .public) model=\(self.configuration.textModel, privacy: .public) requestBytes=\(request.httpBody?.count ?? 0) timeoutSeconds=\(Int(policy.timeoutInterval))"
        )

        do {
            let session = kind == .google ? Self.googleSession : URLSession.shared
            let (data, response) = try await session.data(for: request)
            let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

            if (200..<300).contains(statusCode), data.isEmpty {
                throw CloudRequestRetryError.emptySuccessfulResponse
            }

            NativeBolabolLog.polishing.info(
                "Cloud polishing request completed provider=\(self.displayName, privacy: .public) model=\(self.configuration.textModel, privacy: .public) status=\(statusCode) responseBytes=\(data.count) elapsedMs=\(elapsedMilliseconds)"
            )
            return (data, response)
        } catch {
            let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
            NativeBolabolLog.polishing.error(
                "Cloud polishing request failed provider=\(self.displayName, privacy: .public) model=\(self.configuration.textModel, privacy: .public) elapsedMs=\(elapsedMilliseconds) error=\(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    private func authorizationHeaders(apiKey: String) -> [String: String] {
        ["Authorization": "Bearer \(apiKey)"]
    }

    private func googleURL(model: String) throws -> URL {
        guard let url = URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        ) else {
            throw CloudTextPolishingError.invalidConfiguration("Invalid Google model name.")
        }
        return url
    }

    private func openAICompatibleChatURL(for kind: APIProviderKind) throws -> URL {
        let configured = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawBase: String
        switch kind {
        case .openRouter:
            rawBase = configured.isEmpty ? APIProviderKind.openRouter.defaultBaseURL : configured
        case .qwen:
            rawBase = configured.isEmpty ? APIProviderKind.qwen.defaultBaseURL : configured
        case .custom:
            rawBase = configured
        default:
            rawBase = configured
        }
        let trimmed = rawBase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty, let url = URL(string: "\(trimmed)/chat/completions") else {
            throw CloudTextPolishingError.invalidConfiguration(
                "\(displayName) base URL is invalid."
            )
        }
        return url
    }

    private func openAICompatibleHeaders(apiKey: String, kind: APIProviderKind) -> [String: String] {
        var headers = authorizationHeaders(apiKey: apiKey)
        if kind == .openRouter {
            // Recommended by OpenRouter for ranking / abuse control.
            headers["HTTP-Referer"] = "https://bolabol.app"
            headers["X-Title"] = "Bolabol"
        }
        return headers
    }

    private func openAIResponse(_ data: ChatCompletionResponse) throws -> CloudTextResponse {
        let message = data.choices.first?.message
        // Never surface reasoning_content as polished prose. If a reasoning
        // model produces no final content field (e.g. OpenRouter choices[0]
        // .message.content == ""), that is an empty 2xx: fail over to the
        // next key (ADR-029), never stop the chain or insert nothing.
        let text = message?.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            throw CloudRequestRetryError.emptySuccessfulResponse
        }
        return CloudTextResponse(
            text: text,
            promptTokens: data.usage?.promptTokens,
            completionTokens: data.usage?.completionTokens
        )
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }

        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }

        return object["message"] as? String
    }
}

// Q5a: the key chain respects the output-language chain cap via the
// deadline-aware overload used for the first pass and the strict retry.
extension CloudTextPolishingEngine: DeadlineAwarePolishingEngine {}

private struct CloudTextResponse: Sendable {
    let text: String
    let promptTokens: Int?
    let completionTokens: Int?
}

private struct ChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double?
    let maxTokens: Int
    let enableThinking: Bool?
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            /// OpenAI-style assistant text. Optional because some providers omit
            /// it when only `reasoning_content` is present.
            let content: String?
        }

        let message: Message
    }

    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?
    }

    let choices: [Choice]
    let usage: Usage?
}

private struct AnthropicRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let system: String?
    let maxTokens: Int
    let temperature: Double?
    let messages: [Message]
}

private struct AnthropicResponse: Decodable {
    struct Content: Decodable {
        let text: String?
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
    }

    let content: [Content]
    let usage: Usage?
}

private struct GoogleGenerationConfig: Encodable {
    let temperature: Double?
    let maxOutputTokens: Int
    let responseMimeType: String
    let thinkingConfig: GoogleThinkingConfig?
}

private struct GoogleThinkingConfig: Encodable {
    let thinkingLevel: String
}

private struct GoogleGenerateRequest: Encodable {
    let systemInstruction: GoogleContent?
    let contents: [GoogleContent]
    let generationConfig: GoogleGenerationConfig?
}

private struct GoogleContent: Codable {
    let role: String?
    let parts: [GooglePart]

    init(role: String? = nil, parts: [GooglePart]) {
        self.role = role
        self.parts = parts
    }
}

private struct GooglePart: Codable {
    let text: String?
}

private struct GoogleGenerateResponse: Decodable {
    struct Candidate: Decodable {
        let content: GoogleContent
    }

    struct Usage: Decodable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
    }

    let candidates: [Candidate]?
    let text: String?
    let usageMetadata: Usage?
}

private enum CloudTextPolishingError: LocalizedError {
    case invalidConfiguration(String)
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return message
        case .invalidResponse:
            return "The API provider returned an invalid response."
        case .apiError(let statusCode, let message):
            if statusCode == 401 || statusCode == 403 {
                if message.localizedCaseInsensitiveContains("AccessDenied")
                    || message.localizedCaseInsensitiveContains("eligible")
                    || message.localizedCaseInsensitiveContains("Unpurchased") {
                    return "Model access denied for this API key/plan. Pick a model included in your plan (e.g. qwen3.7-plus) in Settings > API Providers."
                }
                return "API key is invalid or missing. Please check Settings > API Providers."
            }
            if statusCode == 404, message.localizedCaseInsensitiveContains("model") {
                return "Model not found: check the exact model id (for Qwen Token Plan try qwen3.7-plus or qwen3.7-max, not \"Qwen\")."
            }
            if statusCode == 429 {
                return "API quota exceeded. Please check your plan or switch providers."
            }
            if statusCode == 503 || message.range(of: "overloaded|unavailable", options: .regularExpression) != nil {
                return "The provider is temporarily overloaded. Please try again or switch providers."
            }
            return "API Error \(statusCode): \(message)"
        }
    }
}

private extension JSONEncoder {
    static let cloudAPI: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
}

private extension JSONDecoder {
    static let cloudAPI: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
