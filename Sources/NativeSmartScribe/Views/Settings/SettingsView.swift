import NativeSmartScribeCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore

    var body: some View {
        TabView {
            GeneralSettingsView()
                .overlayScrollbar()
                .tabItem {
                    Label(generalSettingsStore.text(.settingsGeneral), systemImage: "gearshape")
                }

            APIProvidersSettingsView()
                .overlayScrollbar()
                .tabItem {
                    Label(generalSettingsStore.text(.settingsAPIProviders), systemImage: "network")
                }

            HotkeySettingsView()
                .overlayScrollbar()
                .tabItem {
                    Label(generalSettingsStore.text(.settingsHotkey), systemImage: "keyboard")
                }

            LocalModelsSettingsView()
                .overlayScrollbar()
                .tabItem {
                    Label(generalSettingsStore.text(.settingsLocalModels), systemImage: "square.stack.3d.down.right")
                }

            PolishingSettingsView()
                .tabItem {
                    Label(generalSettingsStore.text(.settingsPolishing), systemImage: "sparkles")
                }

            PromptsSettingsView()
                .tabItem {
                    Label(generalSettingsStore.text(.settingsPrompts), systemImage: "text.quote")
                }

            GlossarySettingsView()
                .tabItem {
                    Label("Glossary", systemImage: "text.book.closed")
                }

            StatisticsSettingsView()
                .overlayScrollbar()
                .tabItem {
                    Label(generalSettingsStore.text(.settingsStatistics), systemImage: "chart.bar")
                }

            HelpSettingsView()
                .tabItem {
                    Label(generalSettingsStore.text(.settingsHelp), systemImage: "questionmark.circle")
                }
        }
        .padding(20)
        .frame(width: 760, height: 640)
        .modifier(UIScaleModifier())
    }
}

#Preview {
    SettingsView()
        .environmentObject(PolishingEngineStore.live())
        .environmentObject(PromptTemplateStore.live())
        .environmentObject(TranscriptionModelStore.live())
        .environmentObject(HotkeySettingsStore.live())
        .environmentObject(GeneralSettingsStore.live())
        .environmentObject(UsageStatisticsStore.live())
        .environmentObject(AccessibilityPermissionStore.live())
        .environmentObject(GlossaryStore(settings: GlossarySettings(enabled: true, entries: [])))
}

private struct ScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            applyToAllScrollViews(in: nsView.window)
        }
    }

    private func applyToAllScrollViews(in window: NSWindow?) {
        guard let contentView = window?.contentView else { return }
        applyRecursively(to: contentView)
    }

    private func applyRecursively(to view: NSView) {
        if let scrollView = view as? NSScrollView {
            scrollView.scrollerStyle = .overlay
            scrollView.scrollerKnobStyle = .dark
            if let scroller = scrollView.verticalScroller {
                scroller.alphaValue = 0.35
            }
        }
        for subview in view.subviews {
            applyRecursively(to: subview)
        }
    }
}

extension View {
    func overlayScrollbar() -> some View {
        self.background(ScrollViewConfigurator())
    }
}
