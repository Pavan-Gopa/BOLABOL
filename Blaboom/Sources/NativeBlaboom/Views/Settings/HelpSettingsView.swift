import AppKit
import NativeBlaboomCore
import SwiftUI

@MainActor
struct HelpSettingsView: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore

    @State private var expandedSectionIDs: Set<String> = [
        "start", "modes", "hud", "float", "lang", "tips"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero

                guideSection(
                    id: "start",
                    icon: "flag.checkered",
                    title: generalSettingsStore.text(.helpStartTitle),
                    tint: .accentColor
                ) {
                    HelpNumberedList(items: [
                        generalSettingsStore.text(.helpStart1),
                        generalSettingsStore.text(.helpStart2),
                        generalSettingsStore.text(.helpStart3),
                        generalSettingsStore.text(.helpStart4),
                        generalSettingsStore.text(.helpStart5)
                    ])
                }

                guideSection(
                    id: "modes",
                    icon: "rectangle.split.2x1",
                    title: generalSettingsStore.text(.helpModesTitle),
                    tint: .blue
                ) {
                    VStack(spacing: 10) {
                        HelpModeCard(
                            icon: "macwindow",
                            title: generalSettingsStore.text(.helpModeWindowTitle),
                            detail: generalSettingsStore.text(.helpModeWindowBody)
                        )
                        HelpModeCard(
                            icon: "keyboard",
                            title: generalSettingsStore.text(.helpModeHotkeyTitle),
                            detail: generalSettingsStore.text(.helpModeHotkeyBody)
                        )
                        HelpModeCard(
                            icon: "translate",
                            title: generalSettingsStore.text(.helpModeFloatTitle),
                            detail: generalSettingsStore.text(.helpModeFloatBody)
                        )
                        HelpModeCard(
                            icon: "text.bubble.fill",
                            title: generalSettingsStore.text(.helpModeQuickTitle),
                            detail: generalSettingsStore.text(.helpModeQuickBody)
                        )
                    }
                }

                guideSection(
                    id: "window",
                    icon: "sidebar.left",
                    title: generalSettingsStore.text(.helpWindowTitle),
                    tint: .indigo
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        HelpParagraph(generalSettingsStore.text(.helpWindowBody))
                        HelpBulletList(items: [
                            generalSettingsStore.text(.helpWindowNotes),
                            generalSettingsStore.text(.helpWindowTabs),
                            generalSettingsStore.text(.helpWindowActions),
                            generalSettingsStore.text(.helpWindowPolishingMenus)
                        ])
                    }
                }

                guideSection(
                    id: "hud",
                    icon: "dot.radiowaves.left.and.right",
                    title: generalSettingsStore.text(.helpHUDTitle),
                    tint: .red
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        HelpParagraph(generalSettingsStore.text(.helpHUDIntro))

                        HelpHUDMockup()

                        HelpParagraph(generalSettingsStore.text(.helpHUDAnatomy))

                        HelpSubheading(generalSettingsStore.text(.helpHUDLeftTitle))
                        HelpBulletList(items: [
                            generalSettingsStore.text(.helpHUDLeftA),
                            generalSettingsStore.text(.helpHUDLeftLetter),
                            generalSettingsStore.text(.helpHUDLeftTap)
                        ])

                        HelpSubheading(generalSettingsStore.text(.helpHUDRightTitle))
                        HelpBulletList(items: [
                            generalSettingsStore.text(.helpHUDRightR),
                            generalSettingsStore.text(.helpHUDRightCycle),
                            generalSettingsStore.text(.helpHUDRightTap)
                        ])

                        HelpLegendCard(rows: [
                            ("● red", generalSettingsStore.text(.helpHUDColorRed), Color.red),
                            ("● green", generalSettingsStore.text(.helpHUDColorGreen), Color.green)
                        ])

                        HelpCallout(kind: .tip, text: generalSettingsStore.text(.helpHUDDrag))
                        HelpBulletList(items: [
                            generalSettingsStore.text(.helpHUDSize),
                            generalSettingsStore.text(.helpHUDSound),
                            generalSettingsStore.text(.helpHUDSettingsPath),
                            generalSettingsStore.text(.helpHUDPosition),
                            generalSettingsStore.text(.helpHUDDuration)
                        ])
                    }
                }

                guideSection(
                    id: "lang",
                    icon: "globe",
                    title: generalSettingsStore.text(.helpLangTitle),
                    tint: .teal
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        HelpParagraph(generalSettingsStore.text(.helpLangIntro))
                        HelpBulletList(items: [
                            generalSettingsStore.text(.helpLangAuto),
                            generalSettingsStore.text(.helpLangForced),
                            generalSettingsStore.text(.helpLangEnglishNote),
                            generalSettingsStore.text(.helpLangOtherNote),
                            generalSettingsStore.text(.helpLangWhere)
                        ])
                    }
                }

                guideSection(
                    id: "models",
                    icon: "waveform",
                    title: generalSettingsStore.text(.helpModelsTitle),
                    tint: .purple
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        HelpParagraph(generalSettingsStore.text(.helpModelsIntro))
                        HelpBulletList(items: [
                            generalSettingsStore.text(.helpModelsCatalog),
                            generalSettingsStore.text(.helpModelsRecommend),
                            generalSettingsStore.text(.helpModelsUse)
                        ])
                    }
                }

                guideSection(
                    id: "hotkey",
                    icon: "keyboard.badge.ellipsis",
                    title: generalSettingsStore.text(.helpHotkeyTitle),
                    tint: .mint
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        HelpParagraph(generalSettingsStore.text(.helpHotkeyIntro))
                        HelpBulletList(items: [
                            generalSettingsStore.text(.helpHotkeyPrimary),
                            generalSettingsStore.text(.helpHotkeyPushToTalk),
                            generalSettingsStore.text(.helpHotkeySecondary),
                            generalSettingsStore.text(.helpHotkeyTertiary),
                            generalSettingsStore.text(.helpHotkeySettings),
                            generalSettingsStore.text(.helpHotkeyTarget),
                            generalSettingsStore.text(.helpHotkeyMode),
                            generalSettingsStore.text(.helpHotkeyAccess)
                        ])
                    }
                }

                guideSection(
                    id: "float",
                    icon: "translate",
                    title: generalSettingsStore.text(.helpFloatTitle),
                    tint: .pink
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        HelpParagraph(generalSettingsStore.text(.helpFloatIntro))
                        HelpBulletList(items: [
                            generalSettingsStore.text(.helpFloatHotkey),
                            generalSettingsStore.text(.helpFloatQuick),
                            generalSettingsStore.text(.helpFloatCapture),
                            generalSettingsStore.text(.helpFloatPanel),
                            generalSettingsStore.text(.helpFloatFavorites),
                            generalSettingsStore.text(.helpFloatDoubleClick),
                            generalSettingsStore.text(.helpFloatEscape)
                        ])
                    }
                }

                guideSection(
                    id: "cloud",
                    icon: "cloud",
                    title: generalSettingsStore.text(.helpCloudTitle),
                    tint: .cyan
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        HelpParagraph(generalSettingsStore.text(.helpCloudIntro))
                        HelpBulletList(items: [
                            generalSettingsStore.text(.helpCloudProviders),
                            generalSettingsStore.text(.helpCloudConfigure),
                            generalSettingsStore.text(.helpCloudKeys),
                            generalSettingsStore.text(.helpCloudFavorites),
                            generalSettingsStore.text(.helpCloudOpenRouter),
                            generalSettingsStore.text(.helpCloudBudget),
                            generalSettingsStore.text(.helpCloudCustom),
                            generalSettingsStore.text(.helpCloudStats)
                        ])
                    }
                }

                guideSection(
                    id: "polish",
                    icon: "sparkles",
                    title: generalSettingsStore.text(.helpPolishTitle),
                    tint: .yellow
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        HelpParagraph(generalSettingsStore.text(.helpPolishIntro))
                        HelpBulletList(items: [
                            generalSettingsStore.text(.helpPolishEngines),
                            generalSettingsStore.text(.helpPolishMLX),
                            generalSettingsStore.text(.helpPolishPrompts)
                        ])
                    }
                }

                guideSection(
                    id: "more",
                    icon: "text.book.closed",
                    title: generalSettingsStore.text(.helpMoreTitle),
                    tint: .brown
                ) {
                    HelpBulletList(items: [
                        generalSettingsStore.text(.helpMoreGlossary),
                        generalSettingsStore.text(.helpMoreImport),
                        generalSettingsStore.text(.helpMoreTranslate)
                    ])
                }

                guideSection(
                    id: "privacy",
                    icon: "lock.shield",
                    title: generalSettingsStore.text(.helpPrivacyTitle),
                    tint: .gray
                ) {
                    HelpBulletList(items: [
                        generalSettingsStore.text(.helpPrivacyLocal),
                        generalSettingsStore.text(.helpPrivacyCloud),
                        generalSettingsStore.text(.helpPrivacyClear),
                        generalSettingsStore.text(.helpPrivacyLogs)
                    ])
                }

                guideSection(
                    id: "tips",
                    icon: "lightbulb",
                    title: generalSettingsStore.text(.helpTipsTitle),
                    tint: .orange
                ) {
                    VStack(spacing: 8) {
                        HelpCallout(kind: .tip, text: generalSettingsStore.text(.helpTipEnglish))
                        HelpCallout(kind: .tip, text: generalSettingsStore.text(.helpTipNonEnglish))
                        HelpCallout(kind: .warning, text: generalSettingsStore.text(.helpTipDisk))
                        HelpCallout(kind: .warning, text: generalSettingsStore.text(.helpTipStuck))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .padding(.trailing, 4)
        }
        .overlayScrollbar()
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 2) {
                    Text(generalSettingsStore.text(.helpHeroTitle))
                        .font(.title2.weight(.semibold))
                    Text(generalSettingsStore.text(.settingsHelp))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text(generalSettingsStore.text(.helpHeroSubtitle))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                replayOnboarding()
            } label: {
                Label(generalSettingsStore.text(.onboardingShowTour), systemImage: "sparkles")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.12),
                    Color.accentColor.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
        }
    }

    /// Replays the first-launch welcome tour on the main window.
    private func replayOnboarding() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { !$0.isKind(of: NSPanel.self) && $0.title == "Blaboom" }) {
            window.makeKeyAndOrderFront(nil)
        }
        NotificationCenter.default.post(name: .showOnboarding, object: nil)
    }

    // MARK: - Section shell

    @ViewBuilder
    private func guideSection<Content: View>(
        id: String,
        icon: String,
        title: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isExpanded = expandedSectionIDs.contains(id)

        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded {
                        expandedSectionIDs.remove(id)
                    } else {
                        expandedSectionIDs.insert(id)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 28, height: 28)
                        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }
}

// MARK: - Building blocks

private struct HelpParagraph: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct HelpSubheading: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.top, 4)
    }
}

/// Mini diagram of the real HUD capsule: [A] waveform [R]
private struct HelpHUDMockup: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                mockButton(label: "A")
                mockWaveform
                mockButton(label: "R")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .frame(maxWidth: 280)
            .frame(maxWidth: .infinity)

            HStack(spacing: 0) {
                labelColumn("A ↔ E", subtitle: "tap left")
                Spacer(minLength: 8)
                labelColumn("wave", subtitle: "red / green")
                Spacer(minLength: 8)
                labelColumn("R → 1 → 2", subtitle: "tap right")
            }
            .frame(maxWidth: 280)
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 4)
    }

    private func mockButton(label: String) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background {
                Circle().fill(.ultraThinMaterial)
            }
            .background {
                Circle().fill(Color.white.opacity(0.1))
            }
            .overlay {
                Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1)
            }
    }

    private var mockWaveform: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<12, id: \.self) { index in
                let heights: [CGFloat] = [6, 10, 16, 11, 18, 9, 14, 20, 12, 8, 15, 7]
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.red.opacity(0.9))
                    .frame(width: 2.5, height: heights[index])
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
    }

    private func labelColumn(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HelpNumberedList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.accentColor, in: Circle())
                        .padding(.top, 1)

                    Text(item)
                        .font(.callout)
                        .foregroundStyle(.primary.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct HelpBulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color.secondary.opacity(0.55))
                        .frame(width: 5, height: 5)
                        .padding(.top, 7)

                    Text(item)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct HelpModeCard: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct HelpLegendCard: View {
    let rows: [(badge: String, text: String, color: Color)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top, spacing: 12) {
                    Text(row.badge)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(row.color)
                        .frame(width: 54, alignment: .leading)
                        .padding(.top, 1)

                    Text(row.text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)

                if index < rows.count - 1 {
                    Divider().opacity(0.5)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct HelpCallout: View {
    enum Kind {
        case tip
        case warning

        var icon: String {
            switch self {
            case .tip: "lightbulb.fill"
            case .warning: "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .tip: .orange
            case .warning: .yellow
            }
        }
    }

    let kind: Kind
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(kind.tint)
                .padding(.top, 2)

            Text(text)
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(kind.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(kind.tint.opacity(0.28), lineWidth: 1)
        }
    }
}

#Preview {
    HelpSettingsView()
        .environmentObject(GeneralSettingsStore.live())
        .frame(width: 720, height: 640)
}
