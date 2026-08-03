import SwiftUI

private struct NativeBolabolUIScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1
}

extension EnvironmentValues {
    var nativeBolabolUIScale: Double {
        get { self[NativeBolabolUIScaleKey.self] }
        set { self[NativeBolabolUIScaleKey.self] = newValue }
    }
}

struct UIScaleModifier: ViewModifier {
    @Environment(\.nativeBolabolUIScale) private var uiScale

    func body(content: Content) -> some View {
        content
            .font(.system(size: 13 * uiScale))
    }
}

enum BolabolFontStyle {
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

struct BolabolScaledFontModifier: ViewModifier {
    @Environment(\.nativeBolabolUIScale) private var uiScale

    let style: BolabolFontStyle
    let weight: Font.Weight?
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: style.baseSize * uiScale, weight: weight, design: design))
    }
}

extension View {
    func bolabolFont(
        _ style: BolabolFontStyle,
        weight: Font.Weight? = nil,
        design: Font.Design = .default
    ) -> some View {
        modifier(BolabolScaledFontModifier(style: style, weight: weight, design: design))
    }
}
