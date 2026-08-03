import Foundation

public struct PolishingModelInstallationState: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case notDownloaded
        case downloading
        case downloaded
        case failed
    }

    public var status: Status
    public var progressFraction: Double?
    public var localURL: URL?
    public var location: SharedModelLocation?
    public var errorMessage: String?

    private enum CodingKeys: String, CodingKey {
        case status
        case progressFraction
        case localURL
        case location
        case errorMessage
    }

    public init(
        status: Status,
        progressFraction: Double? = nil,
        localURL: URL? = nil,
        location: SharedModelLocation? = nil,
        errorMessage: String? = nil
    ) {
        self.status = status
        self.progressFraction = progressFraction.map(Self.clamp)
        self.localURL = localURL
        self.location = location ?? localURL.flatMap { SharedModelsRoot.location(for: $0) }
        self.errorMessage = errorMessage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try container.decode(Status.self, forKey: .status)
        self.progressFraction = try container.decodeIfPresent(Double.self, forKey: .progressFraction).map(Self.clamp)
        self.location = try container.decodeIfPresent(SharedModelLocation.self, forKey: .location)
        self.errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)

        if let location {
            self.localURL = SharedModelsRoot.modelURL(for: location)
        } else {
            self.localURL = try container.decodeIfPresent(URL.self, forKey: .localURL)
            if let localURL {
                self.location = SharedModelsRoot.location(for: localURL)
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(progressFraction, forKey: .progressFraction)
        try container.encodeIfPresent(location, forKey: .location)
        if location == nil {
            try container.encodeIfPresent(localURL, forKey: .localURL)
        }
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
    }

    public var isDownloaded: Bool {
        status == .downloaded
    }

    public static func notDownloaded() -> PolishingModelInstallationState {
        PolishingModelInstallationState(status: .notDownloaded)
    }

    public static func downloading(
        progressFraction: Double?
    ) -> PolishingModelInstallationState {
        PolishingModelInstallationState(
            status: .downloading,
            progressFraction: progressFraction
        )
    }

    public static func downloaded(
        localURL: URL? = nil
    ) -> PolishingModelInstallationState {
        PolishingModelInstallationState(
            status: .downloaded,
            progressFraction: 1,
            localURL: localURL
        )
    }

    public static func failed(
        _ errorMessage: String
    ) -> PolishingModelInstallationState {
        PolishingModelInstallationState(
            status: .failed,
            errorMessage: errorMessage
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
