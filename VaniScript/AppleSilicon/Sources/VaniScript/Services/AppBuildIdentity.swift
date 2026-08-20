import Foundation

/// Provides release identity, semantic version, and build numbering for VaniScript.
enum AppBuildIdentity {
    /// Backward-compatible build identifier string (e.g., "20260818123456" or "dev-1723900000").
    static var current: String {
        buildIdentifier(in: .main)
    }

    /// Semantic version string (e.g., "1.0.0"), read from `CFBundleShortVersionString`.
    static var semanticVersion: String {
        semanticVersion(in: .main)
    }

    /// Strictly numeric build number (e.g., 20260818123456 or 42), read from `CFBundleVersion` or `VaniScriptBuildID`.
    static var buildNumber: Int? {
        buildNumber(in: .main)
    }

    /// Raw build number string from `CFBundleVersion` or `VaniScriptBuildID`.
    static var buildNumberString: String? {
        buildNumberString(in: .main)
    }

    /// Formatted display string combining semantic version and build identity (e.g., "1.0.0 (42)").
    static var formattedDisplayVersion: String {
        formattedDisplayVersion(in: .main)
    }

    // MARK: - Bundle-parameterized accessors

    /// Returns the build identifier for the given bundle.
    static func buildIdentifier(in bundle: Bundle = .main) -> String {
        if let value = bundle.object(forInfoDictionaryKey: "VaniScriptBuildID") as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let value = bundle.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let url = bundle.executableURL,
           let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let modifiedAt = attributes[.modificationDate] as? Date {
            return "dev-\(Int(modifiedAt.timeIntervalSince1970))"
        }
        return "development"
    }

    /// Returns the semantic version for the given bundle (defaults to "0.0.0-dev" if absent).
    static func semanticVersion(in bundle: Bundle = .main) -> String {
        if let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return version.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "0.0.0-dev"
    }

    /// Returns the build number as an Int if numeric.
    static func buildNumber(in bundle: Bundle = .main) -> Int? {
        guard let string = buildNumberString(in: bundle) else { return nil }
        return Int(string)
    }

    /// Returns the build number string from the given bundle.
    static func buildNumberString(in bundle: Bundle = .main) -> String? {
        if let buildID = bundle.object(forInfoDictionaryKey: "VaniScriptBuildID") as? String,
           !buildID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return buildID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let version = bundle.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String,
           !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return version.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// Returns formatted display version for the given bundle.
    static func formattedDisplayVersion(in bundle: Bundle = .main) -> String {
        let version = semanticVersion(in: bundle)
        let build = buildNumberString(in: bundle) ?? buildIdentifier(in: bundle)
        return "\(version) (\(build))"
    }
}
