import SwiftUI

private struct NativeBlaboomUIScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1
}

extension EnvironmentValues {
    var nativeBlaboomUIScale: Double {
        get { self[NativeBlaboomUIScaleKey.self] }
        set { self[NativeBlaboomUIScaleKey.self] = newValue }
    }
}

struct UIScaleModifier: ViewModifier {
    @Environment(\.nativeBlaboomUIScale) private var uiScale

    func body(content: Content) -> some View {
        content
            .font(.system(size: 13 * uiScale))
    }
}

enum BlaboomFontStyle {
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

struct BlaboomScaledFontModifier: ViewModifier {
    @Environment(\.nativeBlaboomUIScale) private var uiScale

    let style: BlaboomFontStyle
    let weight: Font.Weight?
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: style.baseSize * uiScale, weight: weight, design: design))
    }
}

extension View {
    func blaboomFont(
        _ style: BlaboomFontStyle,
        weight: Font.Weight? = nil,
        design: Font.Design = .default
    ) -> some View {
        modifier(BlaboomScaledFontModifier(style: style, weight: weight, design: design))
    }
}
