import Foundation

public enum ThemePreference: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case dark
    case light
    case system

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dark:
            "Dark"
        case .light:
            "Light"
        case .system:
            "System"
        }
    }
}

public enum UILanguagePreference: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case system
    case english = "en"
    case russian = "ru"
    case spanish = "es"
    case german = "de"
    case french = "fr"
    case italian = "it"
    case portuguese = "pt"
    case chinese = "zh"
    case japanese = "ja"
    case korean = "ko"
    case arabic = "ar"
    case hindi = "hi"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system:
            "System language"
        case .english:
            "English"
        case .russian:
            "Русский"
        case .spanish:
            "Español"
        case .german:
            "Deutsch"
        case .french:
            "Français"
        case .italian:
            "Italiano"
        case .portuguese:
            "Português"
        case .chinese:
            "中文"
        case .japanese:
            "日本語"
        case .korean:
            "한국어"
        case .arabic:
            "العربية"
        case .hindi:
            "हिन्दी"
        }
    }

    public func resolvedLocaleIdentifier(for locale: Locale = .current) -> String {
        if self != .system {
            return rawValue
        }

        let identifier = locale.identifier.lowercased()
        for supportedLocale in Self.supportedLocaleIdentifiers where identifier.hasPrefix(supportedLocale) {
            return supportedLocale
        }
        return "en"
    }

    private static let supportedLocaleIdentifiers = [
        "en", "ru", "es", "de", "fr", "it", "pt", "zh", "ja", "ko", "ar", "hi"
    ]
}

public enum OverlayPosition: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case bottomRight = "bottom-right"
    case bottomLeft = "bottom-left"
    case bottomCenter = "bottom-center"
    case topRight = "top-right"
    case topLeft = "top-left"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bottomRight:
            "Bottom-right"
        case .bottomLeft:
            "Bottom-left"
        case .bottomCenter:
            "Bottom-center"
        case .topRight:
            "Top-right"
        case .topLeft:
            "Top-left"
        }
    }
}

public enum AppLogLevel: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case error
    case warn
    case info
    case debug

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .error:
            "Error"
        case .warn:
            "Warn"
        case .info:
            "Info"
        case .debug:
            "Debug"
        }
    }
}

public struct OverlayHUDSettings: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case position
        case lastOrigin
        case scale
        case capsuleOpacity
        case soundEnabled
        case volume
    }

    public var position: OverlayPosition
    public var lastOrigin: OverlayHUDOrigin?
    public var scale: Double
    public var capsuleOpacity: Double
    public var soundEnabled: Bool
    public var volume: Double

    public init(
        position: OverlayPosition = .bottomCenter,
        lastOrigin: OverlayHUDOrigin? = nil,
        scale: Double = 1,
        capsuleOpacity: Double = 0.32,
        soundEnabled: Bool = true,
        volume: Double = 1
    ) {
        self.position = position
        self.lastOrigin = lastOrigin
        self.scale = scale
        self.capsuleOpacity = capsuleOpacity
        self.soundEnabled = soundEnabled
        self.volume = volume
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.position = try container.decodeIfPresent(OverlayPosition.self, forKey: .position) ?? .bottomCenter
        self.lastOrigin = try container.decodeIfPresent(OverlayHUDOrigin.self, forKey: .lastOrigin)
        self.scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        self.capsuleOpacity = try container.decodeIfPresent(Double.self, forKey: .capsuleOpacity) ?? 0.32
        self.soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        self.volume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? 0.55
        normalize()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(position, forKey: .position)
        try container.encodeIfPresent(lastOrigin, forKey: .lastOrigin)
        try container.encode(scale, forKey: .scale)
        try container.encode(capsuleOpacity, forKey: .capsuleOpacity)
        try container.encode(soundEnabled, forKey: .soundEnabled)
        try container.encode(volume, forKey: .volume)
    }

    public mutating func normalize() {
        scale = scale.clamped(to: 0.8...1.6)
        capsuleOpacity = capsuleOpacity.clamped(to: 0.12...1)
        volume = volume.clamped(to: 0.1...2)
    }
}

public struct OverlayHUDOrigin: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct GeneralSettings: Codable, Equatable, Sendable {
    public var theme: ThemePreference
    public var uiScale: Double
    public var uiLanguage: UILanguagePreference
    public var overlay: OverlayHUDSettings
    public var logLevel: AppLogLevel

    public init(
        theme: ThemePreference = .dark,
        uiScale: Double = 1,
        uiLanguage: UILanguagePreference = .system,
        overlay: OverlayHUDSettings = OverlayHUDSettings(),
        logLevel: AppLogLevel = .warn
    ) {
        self.theme = theme
        self.uiScale = uiScale
        self.uiLanguage = uiLanguage
        self.overlay = overlay
        self.logLevel = logLevel
        normalize()
    }

    public mutating func normalize() {
        uiScale = uiScale.clamped(to: 0.8...1.4)
        overlay.normalize()
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
