import Foundation

/// Strict requested-variant text for hotkey output dispatch (ADR-029).
///
/// Returns the requested slot verbatim — no silent V1/V2→Raw fallbacks.
/// Language fallback (Q3a: requested polished variant if polishing succeeded,
/// otherwise Raw) is owned by `TargetLanguageOutputPipeline`, which verifies
/// the output language and signals failure; this resolver never substitutes.
public enum HotkeyOutputTextResolver {
    public static func text(from note: BolabolNote, target: HotkeyTarget) -> String {
        switch target {
        case .raw:
            return note.rawText
        case .note:
            return note.polishedVariantOne
        case .x2:
            return note.polishedVariantTwo
        }
    }
}
