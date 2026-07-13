import SwiftUI
import VaniScriptCore

enum VaniScriptTheme {
    static let accent = Color(red: 245 / 255, green: 166 / 255, blue: 35 / 255)
    static let accentHover = Color(red: 1, green: 183 / 255, blue: 51 / 255)
    static let background = Color.dynamic(light: Color(red: 245 / 255, green: 246 / 255, blue: 250 / 255), dark: Color(red: 8 / 255, green: 12 / 255, blue: 26 / 255))
    static let card = Color.dynamic(light: Color.white.opacity(0.95), dark: Color(red: 22 / 255, green: 26 / 255, blue: 50 / 255).opacity(0.78))
    static let input = Color.dynamic(light: Color.black.opacity(0.04), dark: Color.white.opacity(0.06))
    static let border = Color.dynamic(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.09))
    static let text0 = Color.dynamic(light: Color(red: 17 / 255, green: 24 / 255, blue: 39 / 255), dark: Color.white)
    static let text1 = Color.dynamic(light: Color(red: 55 / 255, green: 65 / 255, blue: 81 / 255), dark: Color.white.opacity(0.75))
    static let text2 = Color.dynamic(light: Color(red: 107 / 255, green: 114 / 255, blue: 128 / 255), dark: Color.white.opacity(0.45))
    static let green = Color.dynamic(light: Color(red: 22 / 255, green: 163 / 255, blue: 74 / 255), dark: Color(red: 74 / 255, green: 222 / 255, blue: 128 / 255))
    static let red = Color.dynamic(light: Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255), dark: Color(red: 1, green: 92 / 255, blue: 92 / 255))
}

extension VaniScriptTheme {
    /// Density tokens for visual compaction (U0). Tokens only — no screen restyle yet.
    /// Later steps (U1–U3) consume these for sliders, inspector, and app chrome.
    /// Accent orange + glass aesthetic are intentionally preserved.
    enum Density {
        // MARK: Spacing scale (pt)
        static let space4: CGFloat = 4
        static let space6: CGFloat = 6
        static let space8: CGFloat = 8
        static let space12: CGFloat = 12

        // MARK: Control heights (pt) — compact range 22–28
        static let controlHeightSM: CGFloat = 22
        static let controlHeightMD: CGFloat = 25
        static let controlHeightLG: CGFloat = 28

        // MARK: Corner radii (pt) — 8–12
        static let radiusSM: CGFloat = 8
        static let radiusMD: CGFloat = 10
        static let radiusLG: CGFloat = 12

        // MARK: Hairlines / muted borders
        static let hairlineWidth: CGFloat = 1
        static let hairline = Color.dynamic(
            light: Color.black.opacity(0.10),
            dark: Color.white.opacity(0.12)
        )
        static let mutedBorder = Color.dynamic(
            light: Color.black.opacity(0.06),
            dark: Color.white.opacity(0.08)
        )
    }
}

extension Color {
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let best = appearance.bestMatch(from: [.darkAqua, .aqua])
            return best == .darkAqua ? NSColor(dark) : NSColor(light)
        })
    }
}

extension Font {
    public static func customAppFont(family: FontFamily, size: FontSize, scale: Double) -> Font {
        let baseSize: CGFloat
        switch size {
        case .sm: baseSize = 11
        case .md: baseSize = 13
        case .lg: baseSize = 15
        case .xl: baseSize = 18
        }
        let finalSize = baseSize * CGFloat(scale)
        switch family {
        case .mono:
            return .system(size: finalSize, weight: .regular, design: .monospaced)
        case .sans:
            return .system(size: finalSize, weight: .regular, design: .default)
        case .serif:
            return .system(size: finalSize, weight: .regular, design: .serif)
        }
    }
}

struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            VaniScriptTheme.background
            if colorScheme == .dark {
                RadialGradient(
                    colors: [Color(red: 20 / 255, green: 30 / 255, blue: 80 / 255).opacity(0.9), .clear],
                    center: .bottomLeading,
                    startRadius: 20,
                    endRadius: 700
                )
                RadialGradient(
                    colors: [Color(red: 30 / 255, green: 20 / 255, blue: 70 / 255).opacity(0.7), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 620
                )
            } else {
                RadialGradient(
                    colors: [VaniScriptTheme.accent.opacity(0.12), .clear],
                    center: .bottomLeading,
                    startRadius: 20,
                    endRadius: 700
                )
                RadialGradient(
                    colors: [Color(red: 180 / 255, green: 200 / 255, blue: 255 / 255).opacity(0.2), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 620
                )
            }
        }
        .ignoresSafeArea()
    }
}

struct GlassPanel: ViewModifier {
    var radius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(VaniScriptTheme.card)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(VaniScriptTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func glassPanel(radius: CGFloat = 16) -> some View {
        modifier(GlassPanel(radius: radius))
    }
}

struct VaniScriptLogoMark: View {
    var size: CGFloat = 52

    var body: some View {
        if let url = Bundle.main.url(forResource: "VaniScript_Logo", withExtension: "svg"),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else if let url = Bundle.main.url(forResource: "New_Logo", withExtension: "svg"),
                  let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            ZStack {
                Circle()
                    .fill(VaniScriptTheme.accent.opacity(0.13))
                    .overlay(Circle().stroke(VaniScriptTheme.accent.opacity(0.35), lineWidth: 1.5))
                Image(systemName: "waveform.and.document")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(VaniScriptTheme.accent)
            }
            .frame(width: size, height: size)
        }
    }
}

struct LogoHeader: View {
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            HStack(spacing: 10) {
                VaniScriptLogoMark(size: compact ? 36 : 52)
                Text("VaniScript")
                    .font(.system(size: compact ? 22 : 32, weight: .heavy, design: .default))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [VaniScriptTheme.accent, Color(red: 1, green: 204 / 255, blue: 102 / 255)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            Text("Professional Audio Transcription & Translation Engine with\nextreme verbatim accuracy.")
                .font(.system(size: compact ? 11 : 13, weight: .regular))
                .foregroundStyle(VaniScriptTheme.text2)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
    }
}

struct AppFooter: View {
    var body: some View {
        Text("© 2026 VaniScript Audio Processor • Version 1.0.0\nOptimized for Gaudiya Vaishnava Philosophical Lexicon & Technical Terminology")
            .font(.system(size: 10, weight: .regular))
            .foregroundStyle(VaniScriptTheme.text2.opacity(0.6))
            .multilineTextAlignment(.center)
            .lineSpacing(3)
    }
}
