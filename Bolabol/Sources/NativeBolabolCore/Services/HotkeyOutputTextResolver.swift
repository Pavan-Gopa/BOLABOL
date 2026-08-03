import Foundation

public enum HotkeyOutputTextResolver {
    public static func text(from note: BolabolNote, target: HotkeyTarget) -> String {
        switch target {
        case .raw:
            return note.rawText
        case .note:
            let v1 = note.polishedVariantOne.trimmingCharacters(in: .whitespacesAndNewlines)
            return v1.isEmpty ? note.rawText : note.polishedVariantOne
        case .x2:
            let v2 = note.polishedVariantTwo.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v2.isEmpty { return note.polishedVariantTwo }
            let v1 = note.polishedVariantOne.trimmingCharacters(in: .whitespacesAndNewlines)
            return v1.isEmpty ? note.rawText : note.polishedVariantOne
        }
    }
}
