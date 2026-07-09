import AppKit
import CoreText
import Foundation

enum NativeFontRegistry {
    private final class RegistrationState: @unchecked Sendable {
        private let lock = NSLock()
        private var didRegister = false

        func claimRegistration() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !didRegister else { return false }
            didRegister = true
            return true
        }
    }

    private static let registrationState = RegistrationState()

    private static let bundledFontFiles: [String] = [
        "Cuprum",
        "Oswald",
        "Unbounded",
        "Montserrat",
        "Inter"
    ]

    static func registerVisualEditorFonts() {
        guard registrationState.claimRegistration() else { return }

        for font in bundledFontFiles {
            guard let url = bundledFontURL(named: font) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func preferredFontName(for family: String, bold: Bool) -> String {
        if let font = resolvedFont(family: family, size: 12, bold: bold) {
            return font.fontName
        }
        return family
    }

    static func resolvedFont(family: String, size: CGFloat, bold: Bool) -> NSFont? {
        registerVisualEditorFonts()

        for name in candidateFontNames(for: family, bold: bold) {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }

        let descriptor = NSFontDescriptor().withFamily(family)
        if let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }

        return nil
    }

    static func candidateFontNames(for family: String, bold: Bool) -> [String] {
        switch family.lowercased() {
        case "oswald":
            return bold
                ? ["Oswald-Bold", "Oswald-SemiBold", "Oswald-Medium", "Oswald-Regular", "Oswald"]
                : ["Oswald-Regular", "Oswald-Medium", "Oswald", "Oswald-SemiBold"]
        case "cuprum":
            return bold
                ? ["Cuprum-Bold", "Cuprum-SemiBold", "Cuprum-Medium", "Cuprum-Regular", "Cuprum"]
                : ["Cuprum-Regular", "Cuprum", "Cuprum-Medium", "Cuprum-SemiBold"]
        case "unbounded":
            return bold
                ? ["Unbounded-Bold", "Unbounded-SemiBold", "Unbounded-Medium", "Unbounded-Regular", "Unbounded"]
                : ["Unbounded-Regular", "Unbounded", "Unbounded-Medium", "Unbounded-SemiBold"]
        case "montserrat":
            return bold
                ? ["Montserrat-Bold", "Montserrat-SemiBold", "Montserrat-Medium", "Montserrat-Regular", "Montserrat"]
                : ["Montserrat-Regular", "Montserrat", "Montserrat-Medium", "Montserrat-SemiBold"]
        case "inter":
            return bold
                ? ["Inter-Bold", "Inter-SemiBold", "Inter-Medium", "Inter-Regular", "Inter"]
                : ["Inter-Regular", "Inter", "Inter-Medium", "Inter-SemiBold"]
        case "arial":
            return bold ? ["Arial-BoldMT", "Arial Bold", "Arial"] : ["ArialMT", "Arial"]
        default:
            return bold
                ? ["\(family)-Bold", "\(family)-SemiBold", "\(family)-Medium", "\(family)-Regular", family]
                : ["\(family)-Regular", family, "\(family)-Medium", "\(family)-SemiBold"]
        }
    }

    private static func bundledFontURL(named name: String) -> URL? {
        // Avoid the generated SwiftPM module bundle accessor here: a distributed
        // executable can assert if that resource bundle is absent on a user's Mac.
        if let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") {
            return url
        }
        if let url = Bundle.main.resourceURL?
            .appendingPathComponent("Fonts", isDirectory: true)
            .appendingPathComponent("\(name).ttf"),
            FileManager.default.fileExists(atPath: url.path)
        {
            return url
        }
        return Bundle.main.url(forResource: name, withExtension: "ttf")
    }
}
