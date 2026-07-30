import NativeSmartScribeCore
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore

    var body: some View {
        Form {
            Section(generalSettingsStore.text(.theme)) {
                Picker(generalSettingsStore.text(.appearance), selection: themeSelection) {
                    ForEach(ThemePreference.allCases) { theme in
                        Text(themeTitle(theme))
                            .tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(generalSettingsStore.text(.uiFontSize)) {
                HStack {
                    Slider(value: uiScale, in: 0.8...1.4, step: 0.05) {
                        Text(generalSettingsStore.text(.scale))
                    }
                    Text("\(generalSettingsStore.uiScalePercentage)%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
            }

            Section(generalSettingsStore.text(.contentTextSize)) {
                HStack {
                    Slider(value: contentTextScale, in: 1.0...2.0, step: 0.05) {
                        Text(generalSettingsStore.text(.scale))
                    }
                    Text("\(Int(generalSettingsStore.settings.textScale * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }

                Picker(generalSettingsStore.text(.contentFont), selection: contentFontSelection) {
                    Text(generalSettingsStore.text(.fontSystem)).tag(TextFontPreference.system)
                    Text(generalSettingsStore.text(.fontSerif)).tag(TextFontPreference.serif)
                    Text(generalSettingsStore.text(.fontMonospaced)).tag(TextFontPreference.monospaced)
                }
            }

            Section(generalSettingsStore.text(.interfaceLanguage)) {
                Picker(generalSettingsStore.text(.preference), selection: languageSelection) {
                    ForEach(UILanguagePreference.allCases) { language in
                        Text(language.displayName)
                            .tag(language)
                    }
                }
            }

            Section(generalSettingsStore.text(.overlayHUD)) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(generalSettingsStore.text(.hudStyle))
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 12) {
                        ForEach(OverlayHUDStyle.allCases) { style in
                            HUDStyleCardView(
                                style: style,
                                isSelected: generalSettingsStore.settings.overlay.style == style,
                                title: hudStyleTitle(style),
                                action: { overlayStyle.wrappedValue = style }
                            )
                        }
                    }
                }
                .padding(.vertical, 4)

                HStack {
                    Slider(value: overlayScale, in: 0.8...1.6, step: 0.05) {
                        Text(generalSettingsStore.text(.size))
                    }
                    Text("\(generalSettingsStore.overlayScalePercentage)%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }

                HStack {
                    Slider(value: overlayCapsuleOpacity, in: 0.12...1, step: 0.02) {
                        Text(generalSettingsStore.text(.transparency))
                    }
                    Text("\(generalSettingsStore.overlayTransparencyPercentage)%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }

                Toggle(generalSettingsStore.text(.playSound), isOn: overlaySoundEnabled)

                HStack {
                    Slider(value: overlayVolume, in: 0.1...2, step: 0.02) {
                        Text(generalSettingsStore.text(.soundVolume))
                    }
                    Text("\(generalSettingsStore.overlayVolumePercentage)%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
                .disabled(!generalSettingsStore.settings.overlay.soundEnabled)

                Button {
                    generalSettingsStore.testOverlayHUDSounds()
                } label: {
                    Label(generalSettingsStore.text(.testHUDSounds), systemImage: "speaker.wave.2")
                }
                .disabled(!generalSettingsStore.settings.overlay.soundEnabled)
            }

            Section(generalSettingsStore.text(.logLevel)) {
                Picker(generalSettingsStore.text(.level), selection: logLevelSelection) {
                    ForEach(AppLogLevel.allCases) { level in
                        Text(logLevelTitle(level))
                            .tag(level)
                    }
                }
            }

            Section(generalSettingsStore.text(.troubleshooting)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button {
                            generalSettingsStore.exportSystemLogs()
                        } label: {
                            Label(generalSettingsStore.text(.exportSystemLogs), systemImage: "square.and.arrow.down")
                        }

                        Spacer()

                        Button {
                            generalSettingsStore.reset()
                        } label: {
                            Label(generalSettingsStore.text(.resetGeneral), systemImage: "arrow.counterclockwise")
                        }
                    }

                    if let message = generalSettingsStore.logExportMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func hudStyleTitle(_ style: OverlayHUDStyle) -> String {
        switch style {
        case .capsule:
            generalSettingsStore.text(.hudStyleCapsule)
        case .tech:
            generalSettingsStore.text(.hudStyleTech)
        case .vertical:
            generalSettingsStore.text(.hudStyleVertical)
        }
    }

    private var themeSelection: Binding<ThemePreference> {
        Binding(
            get: { generalSettingsStore.settings.theme },
            set: { theme in
                generalSettingsStore.update { $0.theme = theme }
            }
        )
    }

    private func themeTitle(_ theme: ThemePreference) -> String {
        switch theme {
        case .dark:
            generalSettingsStore.text(.themeDark)
        case .light:
            generalSettingsStore.text(.themeLight)
        case .system:
            generalSettingsStore.text(.themeSystem)
        }
    }

    private func logLevelTitle(_ level: AppLogLevel) -> String {
        switch level {
        case .error:
            generalSettingsStore.text(.levelError)
        case .warn:
            generalSettingsStore.text(.levelWarn)
        case .info:
            generalSettingsStore.text(.levelInfo)
        case .debug:
            generalSettingsStore.text(.levelDebug)
        }
    }

    private var uiScale: Binding<Double> {
        Binding(
            get: { generalSettingsStore.settings.uiScale },
            set: { scale in
                generalSettingsStore.update { $0.uiScale = scale }
            }
        )
    }

    private var contentTextScale: Binding<Double> {
        Binding(
            get: { generalSettingsStore.settings.textScale },
            set: { scale in
                generalSettingsStore.update { $0.textScale = scale }
            }
        )
    }

    private var contentFontSelection: Binding<TextFontPreference> {
        Binding(
            get: { generalSettingsStore.settings.textFont },
            set: { font in
                generalSettingsStore.update { $0.textFont = font }
            }
        )
    }

    private var languageSelection: Binding<UILanguagePreference> {
        Binding(
            get: { generalSettingsStore.settings.uiLanguage },
            set: { language in
                generalSettingsStore.update { $0.uiLanguage = language }
            }
        )
    }

    private var overlayScale: Binding<Double> {
        Binding(
            get: { generalSettingsStore.settings.overlay.scale },
            set: { scale in
                generalSettingsStore.update { $0.overlay.scale = scale }
            }
        )
    }

    private var overlayStyle: Binding<OverlayHUDStyle> {
        Binding(
            get: { generalSettingsStore.settings.overlay.style },
            set: { style in
                generalSettingsStore.update { $0.overlay.style = style }
            }
        )
    }

    private var overlayCapsuleOpacity: Binding<Double> {
        Binding(
            get: { generalSettingsStore.settings.overlay.capsuleOpacity },
            set: { opacity in
                generalSettingsStore.update { $0.overlay.capsuleOpacity = opacity }
            }
        )
    }

    private var overlaySoundEnabled: Binding<Bool> {
        Binding(
            get: { generalSettingsStore.settings.overlay.soundEnabled },
            set: { isEnabled in
                generalSettingsStore.update { $0.overlay.soundEnabled = isEnabled }
            }
        )
    }

    private var overlayVolume: Binding<Double> {
        Binding(
            get: { generalSettingsStore.settings.overlay.volume },
            set: { volume in
                generalSettingsStore.update { $0.overlay.volume = volume }
            }
        )
    }

    private var logLevelSelection: Binding<AppLogLevel> {
        Binding(
            get: { generalSettingsStore.settings.logLevel },
            set: { level in
                generalSettingsStore.update { $0.logLevel = level }
            }
        )
    }
}

private struct HUDStyleCardView: View {
    let style: OverlayHUDStyle
    let isSelected: Bool
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.38))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(.white.opacity(isSelected ? 0.14 : 0.06), lineWidth: 1)
                        }

                    HUDStylePreview(style: style, isSelected: isSelected)
                        .padding(6)
                }
                .frame(height: 64)

                HStack(spacing: 6) {
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color.clear)
                        .frame(width: 5, height: 5)
                        .shadow(color: isSelected ? Color.accentColor.opacity(0.8) : .clear, radius: 3)

                    Text(title)
                        .font(.caption.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.18),
                                    Color.accentColor.opacity(0.06),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [
                                    Color.primary.opacity(isHovered ? 0.08 : 0.04),
                                    Color.primary.opacity(isHovered ? 0.04 : 0.02),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected
                            ? LinearGradient(
                                colors: [
                                    Color.accentColor,
                                    Color.accentColor.opacity(0.45),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.20 : 0.08),
                                    Color.white.opacity(isHovered ? 0.10 : 0.03),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .shadow(
                color: isSelected ? Color.accentColor.opacity(0.20) : (isHovered ? .black.opacity(0.15) : .clear),
                radius: isSelected ? 8 : 4,
                x: 0,
                y: isSelected ? 3 : 2
            )
            .scaleEffect(isHovered && !isSelected ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.18), value: isSelected)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct HUDStylePreview: View {
    let style: OverlayHUDStyle
    let isSelected: Bool

    var body: some View {
        GeometryReader { proxy in
            switch style {
            case .capsule:
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.28), lineWidth: 0.8)
                    }
                    .overlay {
                        HStack(spacing: 6) {
                            previewControlCircle(label: "A", size: 19)

                            HStack(spacing: 3) {
                                ForEach([10.0, 20.0, 14.0, 22.0, 12.0], id: \.self) { height in
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.95, green: 0.22, blue: 0.24),
                                                    Color(red: 0.85, green: 0.12, blue: 0.16)
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(width: 3.5, height: height)
                                        .shadow(color: Color.red.opacity(0.65), radius: 2.5)
                                }
                            }
                            .frame(maxWidth: .infinity)

                            previewControlCircle(label: "1", size: 19)
                        }
                        .padding(.horizontal, 6)
                    }
                    .frame(width: min(108, proxy.size.width - 4), height: 34)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

            case .tech:
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(.white.opacity(0.28), lineWidth: 0.8)
                    }
                    .overlay {
                        HStack(spacing: 6) {
                            previewControlSquare(label: "A", size: 19)

                            ZStack {
                                HUDMiniZigzag()
                                    .stroke(
                                        Color(red: 0.96, green: 0.68, blue: 0.18),
                                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                                    )
                                    .shadow(
                                        color: Color(red: 0.96, green: 0.68, blue: 0.18).opacity(0.70),
                                        radius: 3
                                    )
                                    .frame(height: 14)

                                Circle()
                                    .fill(.white)
                                    .frame(width: 3.5, height: 3.5)
                                    .shadow(color: .white, radius: 2)
                            }
                            .frame(maxWidth: .infinity)

                            previewControlSquare(label: "1", size: 19)
                        }
                        .padding(.horizontal, 6)
                    }
                    .frame(width: min(112, proxy.size.width - 4), height: 36)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

            case .vertical:
                VStack(spacing: 0) {
                    previewControlCircle(label: "A", size: 19)

                    VStack(spacing: 2) {
                        ForEach([3.2, 4.8, 3.6, 5.2, 3.2], id: \.self) { diameter in
                            Circle()
                                .fill(.white)
                                .frame(width: diameter, height: diameter)
                                .shadow(color: .white.opacity(0.85), radius: 2.5)
                        }
                    }
                    .frame(height: 18)

                    previewControlCircle(label: "1", size: 19)
                }
                .frame(width: 28, height: 58)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
        .accessibilityHidden(true)
    }

    private func previewControlCircle(label: String, size: CGFloat = 19) -> some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle().stroke(.white.opacity(0.65), lineWidth: 0.9)
                }
            Text(label)
                .font(.system(size: size * 0.52, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .offset(y: 0.3)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.25), radius: 2)
    }

    private func previewControlSquare(label: String, size: CGFloat = 19) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(.white.opacity(0.65), lineWidth: 0.9)
                }
            Text(label)
                .font(.system(size: size * 0.52, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .offset(y: 0.3)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.25), radius: 2)
    }
}

private struct HUDMiniZigzag: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points: [CGPoint] = [
            CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY),
            CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY),
            CGPoint(x: rect.minX + rect.width * 0.56, y: rect.minY + rect.height * 0.18),
            CGPoint(x: rect.minX + rect.width * 0.76, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.midY),
        ]
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}

#Preview {
    GeneralSettingsView()
        .environmentObject(GeneralSettingsStore.live())
}
