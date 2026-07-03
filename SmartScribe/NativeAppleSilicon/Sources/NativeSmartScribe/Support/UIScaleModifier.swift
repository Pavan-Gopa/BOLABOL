import SwiftUI

private struct NativeSmartScribeUIScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1
}

extension EnvironmentValues {
    var nativeSmartScribeUIScale: Double {
        get { self[NativeSmartScribeUIScaleKey.self] }
        set { self[NativeSmartScribeUIScaleKey.self] = newValue }
    }
}

struct UIScaleModifier: ViewModifier {
    @Environment(\.nativeSmartScribeUIScale) private var uiScale

    func body(content: Content) -> some View {
        content
            .font(.system(size: 13 * uiScale))
    }
}

enum SmartScribeFontStyle {
    case largeTitle
    case title2
    case headline
    case body
    case callout
    case caption
    case caption2

    var baseSize: CGFloat {
        switch self {
        case .largeTitle:
            26
        case .title2:
            20
        case .headline:
            13
        case .body:
            13
        case .callout:
            12
        case .caption:
            11
        case .caption2:
            10
        }
    }
}

struct SmartScribeScaledFontModifier: ViewModifier {
    @Environment(\.nativeSmartScribeUIScale) private var uiScale

    let style: SmartScribeFontStyle
    let weight: Font.Weight?
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: style.baseSize * uiScale, weight: weight, design: design))
    }
}

extension View {
    func smartScribeFont(
        _ style: SmartScribeFontStyle,
        weight: Font.Weight? = nil,
        design: Font.Design = .default
    ) -> some View {
        modifier(SmartScribeScaledFontModifier(style: style, weight: weight, design: design))
    }
}
