import SwiftUI
import VaniScriptCore

struct ContentView: View {
    @EnvironmentObject private var workflowStore: WorkflowStore
    @EnvironmentObject private var batchStore: BatchTranscriptionStore
    @Environment(\.openSettings) private var openSettings

    @State private var onboardingFrames: [String: CGRect] = [:]
    @State private var isBatchWorkspacePresented = false

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

                    // Thin status strip only — never a multi-line log wall.
                    if !workflowStore.statusMessage.isEmpty {
                        GlobalStatusStrip(
                            message: workflowStore.statusMessage,
                            isError: Self.isFailureStatus(workflowStore.statusMessage)
                        ) {
                            workflowStore.statusMessage = ""
                        }
                    }
                }

                if workflowStore.workflow.screen != .review && workflowStore.workflow.screen != .visualEditor {
                    VStack {
                        HStack(spacing: 8) {
                            Spacer()

                            UpdateAvailableButton()

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
                                isBatchWorkspacePresented = true
                            } label: {
                                Image(systemName: "waveform.badge.plus")
                            }
                            .buttonStyle(CornerIconButtonStyle())
                            .help("Batch Transcription")
                            .accessibilityLabel("Open Batch Transcription")
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
        .sheet(isPresented: $isBatchWorkspacePresented) {
            BatchWorkspaceView()
                .environmentObject(batchStore)
                .frame(width: 900, height: 620)
        }
    }

    private static func isFailureStatus(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("fail")
            || lower.contains("error")
            || lower.contains("could not")
            || lower.contains("unavailable")
            || lower.contains("mismatch")
    }
}

/// Single-line bottom status. Failures use a calm error surface — never a solid red log dump.
private struct GlobalStatusStrip: View {
    let message: String
    let isError: Bool
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isError ? VaniScriptTheme.errorText : VaniScriptTheme.accent)

            Text(message)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isError ? VaniScriptTheme.errorText : VaniScriptTheme.text1)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(VaniScriptTheme.text2)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(isError ? VaniScriptTheme.errorSurface : VaniScriptTheme.barSurface)
        .overlay(Rectangle().fill(isError ? VaniScriptTheme.errorBorder : VaniScriptTheme.separator).frame(height: 1), alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

private struct CornerIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(configuration.isPressed ? VaniScriptTheme.accent : VaniScriptTheme.text1)
            .frame(width: VaniScriptTheme.Density.controlHeightLG, height: VaniScriptTheme.Density.controlHeightLG)
            .background(configuration.isPressed ? VaniScriptTheme.controlPressed : VaniScriptTheme.control)
            .overlay(
                RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous)
                    .stroke(VaniScriptTheme.controlBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous))
    }
}
