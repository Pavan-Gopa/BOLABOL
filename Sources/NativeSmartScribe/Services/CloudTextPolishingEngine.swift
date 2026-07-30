import Foundation
import NativeSmartScribeCore

struct CloudTextPolishingEngine: PolishingEngine {
    let kind: APIProviderKind
    let configuration: APIProviderConfiguration

    private static let googleSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest =
            CloudRequestRetryPolicy.googleTextGeneration.timeoutInterval
        configuration.timeoutIntervalForResource = 45
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    var id: String { kind.polishingEngineID }
    var displayName: String { kind.displayName }

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        let prompt = try request.template.renderForChat(transcription: request.rawText)
        let startedAt = Date()
        let response = try await generateText(
            systemInstruction: prompt.systemInstruction,
            userContent: prompt.userContent
        )

        return PolishingResult(
            text: ModelOutputSanitizer.sanitize(response.text),
            diagnostics: EngineDiagnostics(
                backendName: "\(kind.displayName) \(configuration.textModel)",
                loadTimeMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000),
                promptTokens: response.promptTokens,
                completionTokens: response.completionTokens
            )
        )
    }

    private func generateText(
        systemInstruction: String,
        userContent: String
    ) async throws -> CloudTextResponse {
        let keys = try sanitizedAPIKeys()
        let textModel = configuration.textModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textModel.isEmpty else {
            throw CloudTextPolishingError.invalidConfiguration(
                "Text model is empty. For Qwen Token Plan use a real model id such as qwen3.7-plus or qwen3.7-max (not just \"Qwen\")."
            )
        }

        var lastError: Error?
        for (index, apiKey) in keys.enumerated() {
            do {
                return try await executeGenerateText(
                    systemInstruction: systemInstruction,
                    userContent: userContent,
                    apiKey: apiKey,
                    textModel: textModel
                )
            } catch let error as CloudTextPolishingError {
                lastError = error
                let isQuotaError: Bool
                switch error {
                case .apiError(let statusCode, let message):
                    isQuotaError = statusCode == 429
                        || message.localizedCaseInsensitiveContains("RESOURCE_EXHAUSTED")
                        || message.localizedCaseInsensitiveContains("quota")
                        || message.localizedCaseInsensitiveContains("rate limit")
                default:
                    isQuotaError = false
                }

                if isQuotaError && index < keys.count - 1 {
                    NativeSmartScribeLog.polishing.warning(
                        "\(self.kind.displayName) API Key #\(index + 1) quota exhausted. Rotating to Key #\(index + 2)."
                    )
                    continue
                }
                throw error
            } catch {
                throw error
            }
        }

        if let lastError {
            throw lastError
        }
        throw CloudTextPolishingError.invalidConfiguration("API key is invalid or missing. Please check Settings > API Providers.")
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
                        temperature: 0.0,
                        maxOutputTokens: 4096,
                        responseMimeType: "text/plain"
                    )
                ),
                useSnakeCaseCoding: false,
                decode: { (data: GoogleGenerateResponse) in
                    CloudTextResponse(
                        text: data.candidates?.first?.content.parts.compactMap(\.text).joined(separator: "\n")
                            ?? data.text
                            ?? "",
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
                        userContent: userContent
                    ),
                    temperature: 0.3,
                    maxTokens: 4096
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
                    messages: [.init(role: "user", content: userContent)]
                ),
                decode: { (data: AnthropicResponse) in
                    CloudTextResponse(
                        text: data.content.compactMap(\.text).joined(separator: "\n"),
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
                        userContent: userContent
                    ),
                    temperature: 0.3,
                    maxTokens: 4096
                ),
                decode: openAIResponse
            )
        }
    }

    private func chatMessages(
        systemInstruction: String,
        userContent: String
    ) -> [ChatCompletionRequest.Message] {
        var messages: [ChatCompletionRequest.Message] = []
        if !systemInstruction.isEmpty {
            messages.append(.init(role: "system", content: systemInstruction))
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
            NativeSmartScribeLog.polishing.error(
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
            NativeSmartScribeLog.polishing.error(
                "Cloud polishing decode failed url=\(url.absoluteString, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    private func performDataRequest(_ sourceRequest: URLRequest) async throws -> (Data, URLResponse) {
        guard kind == .google else {
            return try await URLSession.shared.data(for: sourceRequest)
        }

        let policy = CloudRequestRetryPolicy.googleTextGeneration
        var request = sourceRequest
        request.timeoutInterval = policy.timeoutInterval

        for attempt in 1...policy.maxAttempts {
            let startedAt = Date()
            NativeSmartScribeLog.polishing.info(
                "Cloud polishing request started provider=\(self.kind.displayName, privacy: .public) model=\(self.configuration.textModel, privacy: .public) attempt=\(attempt)/\(policy.maxAttempts) requestBytes=\(request.httpBody?.count ?? 0) timeoutSeconds=\(Int(policy.timeoutInterval))"
            )

            do {
                let (data, response) = try await Self.googleSession.data(for: request)
                let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

                if (200..<300).contains(statusCode), data.isEmpty {
                    throw CloudRequestRetryError.emptySuccessfulResponse
                }

                NativeSmartScribeLog.polishing.info(
                    "Cloud polishing request completed provider=\(self.kind.displayName, privacy: .public) model=\(self.configuration.textModel, privacy: .public) attempt=\(attempt)/\(policy.maxAttempts) status=\(statusCode) responseBytes=\(data.count) elapsedMs=\(elapsedMilliseconds)"
                )
                return (data, response)
            } catch {
                let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
                let willRetry = attempt < policy.maxAttempts && policy.shouldRetry(error)

                if willRetry {
                    NativeSmartScribeLog.polishing.warning(
                        "Cloud polishing request retry provider=\(self.kind.displayName, privacy: .public) model=\(self.configuration.textModel, privacy: .public) attempt=\(attempt)/\(policy.maxAttempts) elapsedMs=\(elapsedMilliseconds) error=\(error.localizedDescription, privacy: .public)"
                    )
                    try await Task.sleep(nanoseconds: policy.retryDelayNanoseconds)
                    continue
                }

                NativeSmartScribeLog.polishing.error(
                    "Cloud polishing request failed provider=\(self.kind.displayName, privacy: .public) model=\(self.configuration.textModel, privacy: .public) attempt=\(attempt)/\(policy.maxAttempts) elapsedMs=\(elapsedMilliseconds) error=\(error.localizedDescription, privacy: .public)"
                )
                throw error
            }
        }

        throw CloudTextPolishingError.invalidResponse
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
                "\(kind.displayName) base URL is invalid."
            )
        }
        return url
    }

    private func openAICompatibleHeaders(apiKey: String, kind: APIProviderKind) -> [String: String] {
        var headers = authorizationHeaders(apiKey: apiKey)
        if kind == .openRouter {
            // Recommended by OpenRouter for ranking / abuse control.
            headers["HTTP-Referer"] = "https://smartscribe.app"
            headers["X-Title"] = "SmartScribe"
        }
        return headers
    }

    private func openAIResponse(_ data: ChatCompletionResponse) throws -> CloudTextResponse {
        let message = data.choices.first?.message
        // Prefer normal content; some Qwen/reasoning models put text only in
        // `reasoning_content` or stream final answer after thinking.
        let candidates = [
            message?.content,
            message?.reasoningContent
        ]
        let text = candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        guard !text.isEmpty else {
            throw CloudTextPolishingError.invalidConfiguration(
                "The provider returned an empty completion. Check the model id (e.g. qwen3.7-plus) and that your plan includes that model."
            )
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

private struct CloudTextResponse {
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
    let temperature: Double
    let maxTokens: Int
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            /// OpenAI-style assistant text. Optional because some providers omit
            /// it when only `reasoning_content` is present.
            let content: String?
            /// Qwen / reasoning-model field (snake_case → reasoningContent).
            let reasoningContent: String?
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
    let temperature: Double
    let maxOutputTokens: Int
    let responseMimeType: String
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
    static var cloudAPI: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}

private extension JSONDecoder {
    static var cloudAPI: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
