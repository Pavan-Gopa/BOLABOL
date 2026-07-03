import VaniScriptCore

extension UniversalWorkflowScreen: Identifiable {
    public var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .upload:
            "square.and.arrow.up"
        case .config:
            "slider.horizontal.3"
        case .processing:
            "gearshape.2"
        case .review:
            "text.magnifyingglass"
        case .export:
            "square.and.arrow.down"
        case .visualEditor:
            "rectangle.3.group"
        }
    }
}
