import SwiftUI
import VaniScriptCore

struct ContentView: View {
    @EnvironmentObject private var workflowStore: WorkflowStore
    @Environment(\.openSettings) private var openSettings

    @State private var onboardingFrames: [String: CGRect] = [:]

    var body: some View {
        HStack(spacing: 0) {
            if workflowStore.showChatSidebar {
                ChatSidebarView()
                    .environmentObject(workflowStore)
                    .transition(.move(edge: .leading))
            }

            ZStack {
                AppBackground()

                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: workflowStore.workflow.screen == .review || workflowStore.workflow.screen == .visualEditor ? 0 : 38)

                    DetailRouterView()
                        .environmentObject(workflowStore)
                }

                if workflowStore.workflow.screen != .review && workflowStore.workflow.screen != .visualEditor {
                    VStack {
                        HStack(spacing: 8) {
                            Spacer()

                            Button {
                                workflowStore.showChatSidebar.toggle()
                            } label: {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(workflowStore.showChatSidebar ? VaniScriptTheme.accent : VaniScriptTheme.text2)
                            }
                            .buttonStyle(CornerIconButtonStyle())
                            .help("AI Assistant")

                            Button {
                                workflowStore.startTour(for: workflowStore.workflow.screen.rawValue)
                            } label: {
                                Image(systemName: "questionmark.circle")
                            }
                            .buttonStyle(CornerIconButtonStyle())
                            .help("Help Tour")

                            Button {
                                workflowStore.presentProjectSidebar()
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(CornerIconButtonStyle())
                            .help("Projects")

                            Button {
                                if workflowStore.isTourActive && workflowStore.activeTourScreen != "settings" {
                                    workflowStore.startTour(for: "settings")
                                }
                                openSettings()
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .buttonStyle(CornerIconButtonStyle())
                            .help("Settings")
                            .onboardingTarget("settings-btn")
                        }
                        .padding(.top, VaniScriptTheme.Density.space8)
                        .padding(.trailing, VaniScriptTheme.Density.space12)

                        Spacer()
                    }
                }

                if workflowStore.isProjectSidebarPresented {
                    ProjectSidebarView()
                        .environmentObject(workflowStore)
                }

                if workflowStore.isTourActive {
                    OnboardingTourView(
                        screen: workflowStore.workflow.screen.rawValue,
                        store: workflowStore,
                        frames: onboardingFrames
                    )
                }
            }
        }
        .coordinateSpace(name: "OnboardingSpace")
        .onPreferenceChange(OnboardingFramesPreferenceKey.self) { dict in
            onboardingFrames = dict
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: workflowStore.showChatSidebar)
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: workflowStore.isProjectSidebarPresented)
        .preferredColorScheme(workflowStore.settings.theme == .dark ? .dark : .light)
        .alert("Transcription Failed", isPresented: $workflowStore.isErrorAlertPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(workflowStore.errorMessage)
        }
        .alert("Scan Local Models", isPresented: $workflowStore.isScanResultAlertPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(workflowStore.scanResultMessage)
        }
    }
}

private struct CornerIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(configuration.isPressed ? VaniScriptTheme.accent : VaniScriptTheme.text2)
            .frame(width: VaniScriptTheme.Density.controlHeightLG, height: VaniScriptTheme.Density.controlHeightLG)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.07))
            .overlay(
                RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous))
    }
}
