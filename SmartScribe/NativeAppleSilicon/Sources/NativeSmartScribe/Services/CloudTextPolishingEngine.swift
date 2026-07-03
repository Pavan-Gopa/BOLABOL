import Foundation
import NativeSmartScribeCore

struct CloudTextPolishingEngine: PolishingEngine {
    let kind: APIProviderKind
    let configuration: APIProviderConfiguration

    var id: String { kind.polishingEngineID }
    var displayName: String { kind.displayName }

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        let prompt = try request.template.render(transcription: request.rawText)
        let startedAt = Date()
        let response = try await generateText(prompt: prompt)

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

    private func generateText(prompt: String) async throws -> CloudTextResponse {
        switch kind {
        case .google:
            return try await postJSON(
                url: googleURL(),
                headers: [:],
                body: GoogleGenerateRequest(contents: [
                    GoogleContent(parts: [GooglePart(text: prompt)])
                ]),
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
                headers: authorizationHeaders(),
                body: ChatCompletionRequest(
                    model: configuration.textModel,
                    messages: [.init(role: "user", content: prompt)],
                    temperature: 0.3,
                    maxTokens: 1200
                ),
                decode: openAIResponse
            )

        case .anthropic:
            return try await postJSON(
                url: URL(string: "https://api.anthropic.com/v1/messages")!,
                headers: [
                    "x-api-key": configuration.apiKey,
                    "anthropic-version": "2023-06-01"
                ],
                body: AnthropicRequest(
                    model: configuration.textModel,
                    maxTokens: 1200,
                    messages: [.init(role: "user", content: prompt)]
                ),
                decode: { (data: AnthropicResponse) in
                    CloudTextResponse(
                        text: data.content.compactMap(\.text).joined(separator: "\n"),
                        promptTokens: data.usage?.inputTokens,
                        completionTokens: data.usage?.outputTokens
                    )
                }
            )

        case .custom:
            return try await postJSON(
                url: customChatCompletionURL(),
                headers: authorizationHeaders(),
                body: ChatCompletionRequest(
                    model: configuration.textModel,
                    messages: [.init(role: "user", content: prompt)],
                    temperature: 0.3,
                    maxTokens: 1200
                ),
                decode: openAIResponse
            )
        }
    }

    private func postJSON<Request: Encodable, Response: Decodable>(
        url: URL,
        headers: [String: String],
        body: Request,
        decode: (Response) throws -> CloudTextResponse
    ) async throws -> CloudTextResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONEncoder.cloudAPI.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTextPolishingError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CloudTextPolishingError.apiError(
                statusCode: httpResponse.statusCode,
                message: Self.errorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }

        return try decode(try JSONDecoder.cloudAPI.decode(Response.self, from: data))
    }

    private func authorizationHeaders() -> [String: String] {
        ["Authorization": "Bearer \(configuration.apiKey)"]
    }

    private func googleURL() throws -> URL {
        var components = URLComponents(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(configuration.textModel):generateContent"
        )
        components?.queryItems = [URLQueryItem(name: "key", value: configuration.apiKey)]
        guard let url = components?.url else {
            throw CloudTextPolishingError.invalidConfiguration("Invalid Google model name.")
        }
        return url
    }

    private func customChatCompletionURL() throws -> URL {
        let trimmed = configuration.baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmed)/chat/completions") else {
            throw CloudTextPolishingError.invalidConfiguration("Custom provider base URL is invalid.")
        }
        return url
    }

    private func openAIResponse(_ data: ChatCompletionResponse) -> CloudTextResponse {
        CloudTextResponse(
            text: data.choices.first?.message.content ?? "",
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
            let content: String
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

private struct GoogleGenerateRequest: Encodable {
    let contents: [GoogleContent]
}

private struct GoogleContent: Codable {
    let parts: [GooglePart]
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
                return "API key is invalid or missing. Please check Settings > API Providers."
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
