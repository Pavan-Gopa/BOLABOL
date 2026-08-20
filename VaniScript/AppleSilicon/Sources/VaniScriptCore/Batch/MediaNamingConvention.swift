import Foundation

public enum MediaNamingMode: String, Codable, Equatable, Sendable {
    case strictReject
    case safeNormalize
    case profileAssistedRename
}

public enum MediaNameViolation: Codable, Equatable, Sendable {
    case filenameTooLong(actual: Int, maximum: Int)
    case missingExtension
    case uppercaseExtension
    case invalidExtension
    case spaceNotAllowed
    case dotInStem
    case invalidStructure
    case invalidDate
    case invalidWho
    case invalidWhat
    case invalidWhere
    case invalidCountry
    case ambiguousLegacyName
}

public enum MediaNameWarning: Codable, Equatable, Sendable {
    case longFilename(actual: Int, recommendedMaximum: Int)
    case legacyWhoWhatSeparator
}

public struct MediaNameParseResult: Codable, Equatable, Sendable {
    public let name: CanonicalMediaName?
    public let violations: [MediaNameViolation]
    public let warnings: [MediaNameWarning]

    public init(
        name: CanonicalMediaName?,
        violations: [MediaNameViolation] = [],
        warnings: [MediaNameWarning] = []
    ) {
        self.name = name
        self.violations = violations
        self.warnings = warnings
    }

    public var isAccepted: Bool { name != nil && violations.isEmpty }
}

public struct MediaNameCollision: Codable, Equatable, Sendable {
    public let normalizedOutputName: String
    public let sourceNames: [String]

    public init(normalizedOutputName: String, sourceNames: [String]) {
        self.normalizedOutputName = normalizedOutputName
        self.sourceNames = sourceNames
    }
}

public enum MediaNamingConvention {
    public static let defaultMode: MediaNamingMode = .strictReject
    public static let maximumFilenameLength = 128
    public static let recommendedFilenameLength = 25

    public static func parse(
        _ filename: String,
        mode: MediaNamingMode = defaultMode
    ) -> MediaNameParseResult {
        var violations: [MediaNameViolation] = []
        var warnings: [MediaNameWarning] = []
        let length = filename.count

        if length > maximumFilenameLength {
            violations.append(.filenameTooLong(actual: length, maximum: maximumFilenameLength))
        } else if length > recommendedFilenameLength {
            warnings.append(.longFilename(actual: length, recommendedMaximum: recommendedFilenameLength))
        }
        if filename.contains(where: { $0.isWhitespace }) {
            violations.append(.spaceNotAllowed)
        }

        let dotParts = filename.split(separator: ".", omittingEmptySubsequences: false)
        guard dotParts.count >= 2, let extensionPart = dotParts.last, !extensionPart.isEmpty else {
            violations.append(.missingExtension)
            return MediaNameParseResult(name: nil, violations: violations, warnings: warnings)
        }
        guard dotParts.count == 2 else {
            violations.append(.dotInStem)
            return MediaNameParseResult(name: nil, violations: violations, warnings: warnings)
        }

        let stem = String(dotParts[0])
        let fileExtension = String(extensionPart)
        if fileExtension != fileExtension.lowercased() {
            violations.append(.uppercaseExtension)
        }
        if !isASCIIAlphanumeric(fileExtension) {
            violations.append(.invalidExtension)
        }

        var fields = stem.split(separator: "_", omittingEmptySubsequences: false).map(String.init)
        var usedLegacySeparator = false
        if fields.count == 4, mode != .strictReject,
           let split = splitUnambiguousLegacyWhoWhat(fields[1]) {
            fields.insert(split.what, at: 2)
            fields[1] = split.who
            usedLegacySeparator = true
            warnings.append(.legacyWhoWhatSeparator)
        }

        guard fields.count >= 5 else {
            violations.append(fields.count == 4 && fields.indices.contains(1) && fields[1].contains("-")
                ? .ambiguousLegacyName
                : .invalidStructure)
            return MediaNameParseResult(name: nil, violations: violations, warnings: warnings)
        }

        let dateRaw = fields[0]
        let who = fields[1]
        let what = fields[2..<(fields.count - 2)].joined(separator: "_")
        let whereToken = fields[fields.count - 2]
        let country = fields[fields.count - 1]

        let date = parseDate(dateRaw)
        if date == nil { violations.append(.invalidDate) }
        if !isHyphenatedToken(who) { violations.append(.invalidWho) }
        if !isWhat(what) { violations.append(.invalidWhat) }
        if !isHyphenatedToken(whereToken) { violations.append(.invalidWhere) }
        if country.count != 2 || country != country.lowercased() || !country.allSatisfy({ $0.isASCII && $0.isLetter }) {
            violations.append(.invalidCountry)
        }

        guard violations.isEmpty, let date else {
            return MediaNameParseResult(name: nil, violations: violations, warnings: warnings)
        }

        let name = CanonicalMediaName(
            date: date,
            who: who,
            what: what,
            where: whereToken,
            country: country,
            fileExtension: fileExtension
        )
        if usedLegacySeparator {
            return MediaNameParseResult(name: name, warnings: warnings)
        }
        return MediaNameParseResult(name: name, warnings: warnings)
    }

    public static func collisions(
        among names: [CanonicalMediaName],
        outputExtension: String = "txt"
    ) -> [MediaNameCollision] {
        let groups = Dictionary(grouping: names) {
            $0.rendered(fileExtension: outputExtension).lowercased()
        }
        return groups.compactMap { normalized, matches in
            guard matches.count > 1 else { return nil }
            return MediaNameCollision(
                normalizedOutputName: normalized,
                sourceNames: matches.map(\.fileName)
            )
        }.sorted { $0.normalizedOutputName < $1.normalizedOutputName }
    }

    private static func splitUnambiguousLegacyWhoWhat(_ field: String) -> (who: String, what: String)? {
        guard let separator = field.firstIndex(of: "-") else { return nil }
        let who = String(field[..<separator])
        let what = String(field[field.index(after: separator)...])
        guard isHyphenatedToken(who), isHyphenatedToken(what) else { return nil }
        return (who, what)
    }

    private static func parseDate(_ value: String) -> MediaDateToken? {
        if value == "YYYY-MM-DD" {
            return MediaDateToken(rawValue: value, precision: .literalPlaceholder)
        }
        let components = value.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count <= 3,
              components[0].count == 4,
              components.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              let year = Int(components[0]), year >= 1
        else { return nil }

        switch components.count {
        case 1:
            return MediaDateToken(rawValue: value, precision: .year)
        case 2:
            guard components[1].count == 2,
                  let month = Int(components[1]), (1...12).contains(month)
            else { return nil }
            return MediaDateToken(rawValue: value, precision: .month)
        case 3:
            guard components[1].count == 2, components[2].count == 2,
                  let month = Int(components[1]), let day = Int(components[2]),
                  let calendarDate = DateComponents(calendar: Calendar(identifier: .gregorian), year: year, month: month, day: day).date
            else { return nil }
            let calendar = Calendar(identifier: .gregorian)
            guard calendar.component(.year, from: calendarDate) == year,
                  calendar.component(.month, from: calendarDate) == month,
                  calendar.component(.day, from: calendarDate) == day
            else { return nil }
            return MediaDateToken(rawValue: value, precision: .day)
        default:
            return nil
        }
    }

    private static func isASCIIAlphanumeric(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func isHyphenatedToken(_ value: String) -> Bool {
        let tokens = value.split(separator: "-", omittingEmptySubsequences: false)
        return !tokens.isEmpty && tokens.allSatisfy { isASCIIAlphanumeric(String($0)) }
    }

    private static func isWhat(_ value: String) -> Bool {
        let components = value.split(separator: "_", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy { isHyphenatedToken(String($0)) }
    }
}
