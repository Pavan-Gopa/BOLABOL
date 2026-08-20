import Foundation

/// Structured, user-readable diagnostic error for in-app update operations.
/// Prevents exposing raw cryptic codes or stack traces while preserving
/// precise diagnostics for troubleshooting.
public struct UpdateDiagnosticError: Error, Sendable, Equatable, Identifiable {
    public enum ErrorKind: Sendable, Equatable {
        case missingPublicKey
        case feedUnavailable
        case signatureVerificationFailed
        case installationFailed
        case noUpdateAvailable
        case cancelled
        case networkError
        case misconfiguredFeed
        case internalError
    }

    public let id: String
    public let kind: ErrorKind
    public let message: String
    public let recoverySuggestion: String
    public let isConfigurationFailure: Bool

    public init(
        kind: ErrorKind,
        message: String,
        recoverySuggestion: String,
        isConfigurationFailure: Bool = false
    ) {
        self.id = UUID().uuidString
        self.kind = kind
        self.message = message
        self.recoverySuggestion = recoverySuggestion
        self.isConfigurationFailure = isConfigurationFailure
    }

    public static let missingPublicKey = UpdateDiagnosticError(
        kind: .missingPublicKey,
        message: "Update public key (SUPublicEDKey) is not configured in this build.",
        recoverySuggestion: "Configure VANISCRIPT_SPARKLE_PUBLIC_ED_KEY when building release packages.",
        isConfigurationFailure: true
    )

    public static let noUpdateAvailable = UpdateDiagnosticError(
        kind: .noUpdateAvailable,
        message: "You are running the latest version of VaniScript.",
        recoverySuggestion: "No action required. The app will automatically check for updates periodically."
    )

    public static let cancelled = UpdateDiagnosticError(
        kind: .cancelled,
        message: "Update operation was cancelled.",
        recoverySuggestion: "You can check for updates again at any time."
    )

    public static func map(from error: NSError) -> UpdateDiagnosticError {
        let domain = error.domain
        let code = error.code
        let description = error.localizedDescription

        // Sparkle errors
        if domain == "SUSparkleErrorDomain" || domain.contains("Sparkle") {
            switch code {
            case 1, 2: // SUNoPublicDSAFoundError, SUInsufficientSigningError
                return UpdateDiagnosticError(
                    kind: .missingPublicKey,
                    message: "Update signature verification key is missing or invalid.",
                    recoverySuggestion: "Please verify your application installation or contact support.",
                    isConfigurationFailure: true
                )
            case 3, 4: // SUInsecureFeedURLError, SUInvalidFeedURLError
                return UpdateDiagnosticError(
                    kind: .misconfiguredFeed,
                    message: "Update feed URL is invalid or insecure.",
                    recoverySuggestion: "Please check application configuration.",
                    isConfigurationFailure: true
                )
            case 1000, 1002, 1004: // SUAppcastParseError, SUAppcastError, SUResumeAppcastError
                return UpdateDiagnosticError(
                    kind: .feedUnavailable,
                    message: "Unable to parse the update feed (\(description)).",
                    recoverySuggestion: "Please check your network connection or try again later."
                )
            case 1001: // SUNoUpdateError
                return .noUpdateAvailable
            case 2000, 2001: // SUTemporaryDirectoryError, SUDownloadError
                return UpdateDiagnosticError(
                    kind: .networkError,
                    message: "Failed to download update payload.",
                    recoverySuggestion: "Check your internet connection and try downloading again."
                )
            case 3000: // SUUnarchivingError
                return UpdateDiagnosticError(
                    kind: .installationFailed,
                    message: "Failed to extract update package.",
                    recoverySuggestion: "Verify sufficient free disk space and try again."
                )
            case 3001, 3002: // SUSignatureError, SUValidationError
                return UpdateDiagnosticError(
                    kind: .signatureVerificationFailed,
                    message: "Update package signature verification failed.",
                    recoverySuggestion: "The downloaded update may be corrupted or tampered with. Installation aborted for safety."
                )
            case 4000, 4001, 4002, 4003, 4004, 4005, 4006, 4007, 4008, 4009, 4010, 4012:
                return UpdateDiagnosticError(
                    kind: .installationFailed,
                    message: "Installation failed: \(description)",
                    recoverySuggestion: "Please try installing again. If the issue persists, reinstall from the official DMG."
                )
            default:
                return UpdateDiagnosticError(
                    kind: .internalError,
                    message: description.isEmpty ? "An update error occurred (code \(code))." : description,
                    recoverySuggestion: "Please try again later."
                )
            }
        }

        // NSURLErrorDomain
        if domain == NSURLErrorDomain {
            if code == NSURLErrorCancelled {
                return .cancelled
            }
            return UpdateDiagnosticError(
                kind: .networkError,
                message: "Network connection failed while checking for updates.",
                recoverySuggestion: "Please check your internet connection and try again."
            )
        }

        return UpdateDiagnosticError(
            kind: .internalError,
            message: description.isEmpty ? "An unexpected error occurred." : description,
            recoverySuggestion: "Please try again."
        )
    }
}
