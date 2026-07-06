import Foundation

public enum HotkeyOutputTextResolver {
    public static func text(from note: SmartScribeNote, target: HotkeyTarget) -> String {
        switch target {
        case .raw:
            note.rawText
        case .note:
            note.polishedVariantOne
        case .x2:
            note.polishedVariantTwo
        }
    }
}
