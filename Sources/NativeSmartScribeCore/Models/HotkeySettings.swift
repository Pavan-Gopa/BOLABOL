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
    public var enabled: Bool
    public var target: HotkeyTarget
    public var mode: HotkeyOutputMode
    public var hotkey: String
    public var secondaryHotkey: String

    public init(
        enabled: Bool = false,
        target: HotkeyTarget = .note,
        mode: HotkeyOutputMode = .typing,
        hotkey: String = "Alt+S",
        secondaryHotkey: String = "Alt+Shift+S"
    ) {
        self.enabled = enabled
        self.target = target
        self.mode = mode
        self.hotkey = hotkey
        self.secondaryHotkey = secondaryHotkey
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case target
        case mode
        case hotkey
        case secondaryHotkey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decode(Bool.self, forKey: .enabled)
        self.target = try container.decode(HotkeyTarget.self, forKey: .target)
        self.mode = try container.decode(HotkeyOutputMode.self, forKey: .mode)
        self.hotkey = try container.decode(String.self, forKey: .hotkey)
        self.secondaryHotkey = try container.decodeIfPresent(String.self, forKey: .secondaryHotkey) ?? "Alt+Shift+S"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(target, forKey: .target)
        try container.encode(mode, forKey: .mode)
        try container.encode(hotkey, forKey: .hotkey)
        try container.encode(secondaryHotkey, forKey: .secondaryHotkey)
    }
}
