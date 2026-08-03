import Foundation

public enum ProcessingVariant: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case raw
    case variantOne
    case variantTwo

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .raw:
            "Raw"
        case .variantOne:
            "Variant 1"
        case .variantTwo:
            "Variant 2"
        }
    }

    public var systemImage: String {
        switch self {
        case .raw:
            "waveform"
        case .variantOne:
            "text.alignleft"
        case .variantTwo:
            "sparkles"
        }
    }
}
