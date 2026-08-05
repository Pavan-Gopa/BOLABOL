import Foundation

/// Ephemeral language presentation state exposed by the HUD.
///
/// `auto` and `target` remain the legacy Whisper-compatible values. The
/// explicit states are used by the immutable Canary/GigaAM session plan and
/// never become persisted settings.
public enum TranscriptionLanguageMode: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case auto
    case target
    case switchable = "explicit-switchable"
    case fixed = "explicit-fixed"
    case unavailable

    public var id: String { rawValue }

    public func toggled() -> TranscriptionLanguageMode {
        switch self {
        case .auto:
            .target
        case .target:
            .auto
        case .switchable, .fixed, .unavailable:
            self
        }
    }

    public static var automatic: TranscriptionLanguageMode { .auto }
    public static var explicitSwitchable: TranscriptionLanguageMode { .switchable }
    public static var explicitFixed: TranscriptionLanguageMode { .fixed }

    public var isExplicit: Bool {
        self == .target || self == .switchable || self == .fixed
    }
}
