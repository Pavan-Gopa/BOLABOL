import Foundation

public enum APIProviderKind: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case google
    case openAI
    case anthropic
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .google:
            "Google Gemini"
        case .openAI:
            "OpenAI"
        case .anthropic:
            "Anthropic"
        case .custom:
            "Custom"
        }
    }

    public var polishingEngineID: String {
        switch self {
        case .google:
            "cloud-google"
        case .openAI:
            "cloud-openai"
        case .anthropic:
            "cloud-anthropic"
        case .custom:
            "cloud-custom"
        }
    }

    public init?(polishingEngineID: String) {
        guard let kind = Self.allCases.first(where: { $0.polishingEngineID == polishingEngineID }) else {
            return nil
        }

        self = kind
    }
}

public struct APIProviderConfiguration: Codable, Equatable, Sendable {
    public var apiKey: String
    public var textModel: String
    public var baseURL: String
    public var name: String

    public init(
        apiKey: String = "",
        textModel: String = "",
        baseURL: String = "",
        name: String = ""
    ) {
        self.apiKey = apiKey
        self.textModel = textModel
        self.baseURL = baseURL
        self.name = name
    }

    public var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct AvailableAPIProvider: Codable, Equatable, Sendable {
    public var kind: APIProviderKind
    public var displayName: String
    public var modelName: String

    public init(kind: APIProviderKind, displayName: String, modelName: String) {
        self.kind = kind
        self.displayName = displayName
        self.modelName = modelName
    }
}

public struct APIProviderSettings: Codable, Equatable, Sendable {
    public var google: APIProviderConfiguration
    public var openAI: APIProviderConfiguration
    public var anthropic: APIProviderConfiguration
    public var custom: APIProviderConfiguration

    public init(
        google: APIProviderConfiguration = APIProviderConfiguration(textModel: "gemini-2.5-flash"),
        openAI: APIProviderConfiguration = APIProviderConfiguration(textModel: "gpt-4o-mini"),
        anthropic: APIProviderConfiguration = APIProviderConfiguration(textModel: "claude-3-haiku-20240307"),
        custom: APIProviderConfiguration = APIProviderConfiguration()
    ) {
        self.google = google
        self.openAI = openAI
        self.anthropic = anthropic
        self.custom = custom
    }

    public var availablePolishingProviders: [AvailableAPIProvider] {
        var providers: [AvailableAPIProvider] = []

        if google.hasAPIKey, !google.textModel.isEmpty {
            providers.append(
                AvailableAPIProvider(
                    kind: .google,
                    displayName: "Google \(google.textModel)",
                    modelName: google.textModel
                )
            )
        }

        if openAI.hasAPIKey, !openAI.textModel.isEmpty {
            providers.append(
                AvailableAPIProvider(
                    kind: .openAI,
                    displayName: "OpenAI \(openAI.textModel)",
                    modelName: openAI.textModel
                )
            )
        }

        if anthropic.hasAPIKey, !anthropic.textModel.isEmpty {
            providers.append(
                AvailableAPIProvider(
                    kind: .anthropic,
                    displayName: "Anthropic \(anthropic.textModel)",
                    modelName: anthropic.textModel
                )
            )
        }

        if custom.hasAPIKey,
           !custom.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !custom.textModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let name = custom.name.trimmingCharacters(in: .whitespacesAndNewlines)
            providers.append(
                AvailableAPIProvider(
                    kind: .custom,
                    displayName: "\(name.isEmpty ? "Custom" : name) \(custom.textModel)",
                    modelName: custom.textModel
                )
            )
        }

        return providers
    }

    public func configuration(for kind: APIProviderKind) -> APIProviderConfiguration {
        switch kind {
        case .google:
            google
        case .openAI:
            openAI
        case .anthropic:
            anthropic
        case .custom:
            custom
        }
    }
}
