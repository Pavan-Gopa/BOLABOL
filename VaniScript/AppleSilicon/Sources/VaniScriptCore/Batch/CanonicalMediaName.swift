import Foundation

public struct MediaDateToken: Codable, Equatable, Sendable {
    public enum Precision: String, Codable, Equatable, Sendable {
        case day
        case month
        case year
        case literalPlaceholder
    }

    public let rawValue: String
    public let precision: Precision

    public init(rawValue: String, precision: Precision) {
        self.rawValue = rawValue
        self.precision = precision
    }
}

public struct CanonicalMediaName: Codable, Equatable, Sendable {
    public let date: MediaDateToken
    public let who: String
    public let what: String
    public let whereToken: String
    public let country: String
    public let fileExtension: String

    public init(
        date: MediaDateToken,
        who: String,
        what: String,
        where whereToken: String,
        country: String,
        fileExtension: String
    ) {
        self.date = date
        self.who = who
        self.what = what
        self.whereToken = whereToken
        self.country = country
        self.fileExtension = fileExtension
    }

    public var stem: String {
        "\(date.rawValue)_\(who)_\(what)_\(whereToken)_\(country)"
    }

    public var fileName: String {
        "\(stem).\(fileExtension)"
    }

    public func rendered(fileExtension: String? = nil) -> String {
        "\(stem).\(fileExtension ?? self.fileExtension)"
    }

    public func companionURL(for sourceURL: URL, fileExtension: String = "txt") -> URL {
        sourceURL.deletingPathExtension().appendingPathExtension(fileExtension)
    }
}
