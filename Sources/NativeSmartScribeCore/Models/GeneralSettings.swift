import Foundation

public enum TextFontPreference: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case system
    case serif
    case monospaced

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system:
            "System"
        case .serif:
            "Serif"
        case .monospaced:
            "Monospaced"
        }
    }
}

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

public enum OverlayHUDStyle: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case capsule
    case tech
    case vertical

    public var id: String { rawValue }
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
        case style
        case styleOrigins
    }

    public var position: OverlayPosition
    public var lastOrigin: OverlayHUDOrigin?
    public var scale: Double
    public var capsuleOpacity: Double
    public var soundEnabled: Bool
    public var volume: Double
    public var style: OverlayHUDStyle
    public var styleOrigins: [String: OverlayHUDOrigin]

    public init(
        position: OverlayPosition = .bottomCenter,
        lastOrigin: OverlayHUDOrigin? = nil,
        scale: Double = 1,
        capsuleOpacity: Double = 0.32,
        soundEnabled: Bool = true,
        volume: Double = 1,
        style: OverlayHUDStyle = .capsule,
        styleOrigins: [String: OverlayHUDOrigin] = [:]
    ) {
        self.position = position
        self.lastOrigin = lastOrigin
        self.scale = scale
        self.capsuleOpacity = capsuleOpacity
        self.soundEnabled = soundEnabled
        self.volume = volume
        self.style = style
        self.styleOrigins = styleOrigins
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.position = try container.decodeIfPresent(OverlayPosition.self, forKey: .position) ?? .bottomCenter
        self.lastOrigin = try container.decodeIfPresent(OverlayHUDOrigin.self, forKey: .lastOrigin)
        self.scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        self.capsuleOpacity = try container.decodeIfPresent(Double.self, forKey: .capsuleOpacity) ?? 0.32
        self.soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        self.volume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? 0.55
        self.style = try container.decodeIfPresent(OverlayHUDStyle.self, forKey: .style) ?? .capsule
        self.styleOrigins =
            try container.decodeIfPresent([String: OverlayHUDOrigin].self, forKey: .styleOrigins)
            ?? [:]
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
        try container.encode(style, forKey: .style)
        try container.encode(styleOrigins, forKey: .styleOrigins)
    }

    public mutating func normalize() {
        scale = scale.clamped(to: 0.8...1.6)
        capsuleOpacity = capsuleOpacity.clamped(to: 0.12...1)
        volume = volume.clamped(to: 0.1...2)
        styleOrigins = styleOrigins.filter { key, _ in
            OverlayHUDStyle(rawValue: key) != nil
        }
    }

    public func origin(for style: OverlayHUDStyle) -> OverlayHUDOrigin? {
        if let origin = styleOrigins[style.rawValue] {
            return origin
        }
        return style == .capsule ? lastOrigin : nil
    }

    public mutating func setOrigin(_ origin: OverlayHUDOrigin, for style: OverlayHUDStyle) {
        styleOrigins[style.rawValue] = origin
        if style == .capsule {
            lastOrigin = origin
        }
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
    public var hasCompletedOnboarding: Bool
    public var textScale: Double
    public var textFont: TextFontPreference

    public init(
        theme: ThemePreference = .dark,
        uiScale: Double = 1,
        uiLanguage: UILanguagePreference = .system,
        overlay: OverlayHUDSettings = OverlayHUDSettings(),
        logLevel: AppLogLevel = .warn,
        hasCompletedOnboarding: Bool = false,
        textScale: Double = 1,
        textFont: TextFontPreference = .system
    ) {
        self.theme = theme
        self.uiScale = uiScale
        self.uiLanguage = uiLanguage
        self.overlay = overlay
        self.logLevel = logLevel
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.textScale = textScale
        self.textFont = textFont
        normalize()
    }

    private enum CodingKeys: String, CodingKey {
        case theme
        case uiScale
        case uiLanguage
        case overlay
        case logLevel
        case hasCompletedOnboarding
        case textScale
        case textFont
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.theme = try container.decodeIfPresent(ThemePreference.self, forKey: .theme) ?? .dark
        self.uiScale = try container.decodeIfPresent(Double.self, forKey: .uiScale) ?? 1
        self.uiLanguage = try container.decodeIfPresent(UILanguagePreference.self, forKey: .uiLanguage) ?? .system
        self.overlay = try container.decodeIfPresent(OverlayHUDSettings.self, forKey: .overlay) ?? OverlayHUDSettings()
        self.logLevel = try container.decodeIfPresent(AppLogLevel.self, forKey: .logLevel) ?? .warn
        self.hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        self.textScale = try container.decodeIfPresent(Double.self, forKey: .textScale) ?? 1
        self.textFont = try container.decodeIfPresent(TextFontPreference.self, forKey: .textFont) ?? .system
        normalize()
    }

    public mutating func normalize() {
        uiScale = uiScale.clamped(to: 0.8...1.4)
        textScale = textScale.clamped(to: 1.0...2.0)
        overlay.normalize()
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
