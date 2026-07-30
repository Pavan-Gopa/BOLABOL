import Foundation

public enum HotkeyTarget: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case raw
    case note
    case x2

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .raw:
            "Raw transcription"
        case .note:
            "Variant 1"
        case .x2:
            "Variant 2"
        }
    }

    public var processingVariant: ProcessingVariant {
        switch self {
        case .raw:
            .raw
        case .note:
            .variantOne
        case .x2:
            .variantTwo
        }
    }

    public var requestedPolishingVariants: [ProcessingVariant] {
        switch self {
        case .raw:
            []
        case .note:
            [.variantOne]
        case .x2:
            [.variantTwo]
        }
    }

    /// Short label rendered on the HUD control button: R (raw), 1 (variant one), 2 (variant two).
    public var hudLabel: String {
        switch self {
        case .raw:
            "R"
        case .note:
            "1"
        case .x2:
            "2"
        }
    }

    /// Next target in the HUD cycle: raw -> variant one -> variant two -> raw.
    public func next() -> HotkeyTarget {
        switch self {
        case .raw:
            .note
        case .note:
            .x2
        case .x2:
            .raw
        }
    }
}

public enum HotkeyOutputMode: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case clipboard
    case typing

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .clipboard:
            "Copy to Clipboard"
        case .typing:
            "Type into Active App"
        }
    }
}

public struct HotkeySettings: Codable, Equatable, Sendable {
    public static let defaultPrimaryHotkey = "Option+S"
    public static let defaultSecondaryHotkey = "Option+1"
    public static let defaultTertiaryHotkey = "Option+2"
    public static let defaultSettingsHotkey = "Option+~"

    /// Unicode Option key glyph used in macOS UI (⌥).
    public static let optionSymbol = "⌥"

    public var enabled: Bool
    public var target: HotkeyTarget
    public var mode: HotkeyOutputMode
    public var hotkey: String
    public var secondaryHotkey: String
    public var tertiaryHotkey: String
    public var settingsHotkey: String

    public init(
        enabled: Bool = false,
        target: HotkeyTarget = .note,
        mode: HotkeyOutputMode = .typing,
        hotkey: String = HotkeySettings.defaultPrimaryHotkey,
        secondaryHotkey: String = HotkeySettings.defaultSecondaryHotkey,
        tertiaryHotkey: String = HotkeySettings.defaultTertiaryHotkey,
        settingsHotkey: String = HotkeySettings.defaultSettingsHotkey
    ) {
        self.enabled = enabled
        self.target = target
        self.mode = mode
        self.hotkey = Self.normalizeMacModifiers(hotkey)
        self.secondaryHotkey = Self.normalizeMacModifiers(secondaryHotkey)
        self.tertiaryHotkey = Self.normalizeMacModifiers(tertiaryHotkey)
        self.settingsHotkey = Self.normalizeMacModifiers(settingsHotkey)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case target
        case mode
        case hotkey
        case secondaryHotkey
        case tertiaryHotkey
        case settingsHotkey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decode(Bool.self, forKey: .enabled)
        self.target = try container.decode(HotkeyTarget.self, forKey: .target)
        self.mode = try container.decode(HotkeyOutputMode.self, forKey: .mode)
        self.hotkey = Self.normalizeMacModifiers(try container.decode(String.self, forKey: .hotkey))
        self.secondaryHotkey = Self.normalizeMacModifiers(
            try container.decodeIfPresent(String.self, forKey: .secondaryHotkey) ?? Self.defaultSecondaryHotkey
        )
        self.tertiaryHotkey = Self.normalizeMacModifiers(
            try container.decodeIfPresent(String.self, forKey: .tertiaryHotkey) ?? Self.defaultTertiaryHotkey
        )
        self.settingsHotkey = Self.normalizeMacModifiers(
            try container.decodeIfPresent(String.self, forKey: .settingsHotkey) ?? Self.defaultSettingsHotkey
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(target, forKey: .target)
        try container.encode(mode, forKey: .mode)
        try container.encode(Self.normalizeMacModifiers(hotkey), forKey: .hotkey)
        try container.encode(Self.normalizeMacModifiers(secondaryHotkey), forKey: .secondaryHotkey)
        try container.encode(Self.normalizeMacModifiers(tertiaryHotkey), forKey: .tertiaryHotkey)
        try container.encode(Self.normalizeMacModifiers(settingsHotkey), forKey: .settingsHotkey)
    }

    /// Canonical Mac wording: `Alt` → `Option` (parser still accepts both).
    public static func normalizeMacModifiers(_ hotkey: String) -> String {
        hotkey
            .split(separator: "+", omittingEmptySubsequences: false)
            .map { token -> String in
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                switch trimmed.lowercased() {
                case "alt", "opt", "option", "⌥":
                    return "Option"
                case "cmd", "command", "⌘":
                    return "Command"
                case "ctrl", "control", "⌃":
                    return "Control"
                case "shift", "⇧":
                    return "Shift"
                default:
                    return trimmed
                }
            }
            .filter { !$0.isEmpty }
            .joined(separator: "+")
    }

    /// Compact macOS-style display, e.g. `Option+S` → `⌥S`, `Command+Option+S` → `⌘⌥S`.
    public static func displayString(for hotkey: String) -> String {
        let parts = normalizeMacModifiers(hotkey)
            .split(separator: "+")
            .map(String.init)
        guard let key = parts.last, parts.count > 1 else {
            return normalizeMacModifiers(hotkey)
        }
        let symbols = parts.dropLast().map { part -> String in
            switch part {
            case "Option": return optionSymbol
            case "Command": return "⌘"
            case "Control": return "⌃"
            case "Shift": return "⇧"
            default: return part
            }
        }.joined()
        return symbols + key
    }
}
