import AppKit
import NativeBolabolCore
import SwiftUI

/// Compact title-bar accessory button surfaced when an update is checking, preparing, ready to install, or requires attention.
///
/// Invariants:
/// - Compact capsule with visible version/status.
/// - Accessible label, tooltip help.
/// - Reduce Motion-safe subtle sheen animation.
/// - Stable 28pt height without modifying window titlebar height.
/// - Natural width (never overlaps standard window controls).
/// - Calls `installPreparedUpdate()` only in the `.ready` state.
@MainActor
public struct UpdateTitlebarButton: View {
    @EnvironmentObject private var updateCoordinator: UpdateCoordinator
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHovered: Bool = false
    @State private var isSheenActive: Bool = false

    public init() {}

    private var uiLanguage: UILanguagePreference {
        generalSettingsStore.settings.uiLanguage
    }

    public var body: some View {
        switch updateCoordinator.phase {
        case .idle:
            Color.clear
                .frame(width: 0, height: 28)
                .accessibilityHidden(true)

        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
                Text(AppText.localized(.checkForUpdates, language: uiLanguage))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )
            .overlay(
                Capsule()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(AppText.localized(.checkForUpdates, language: uiLanguage))

        case .preparing(let version):
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
                Text("v\(version)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(AppText.localized(.updateDownloading, language: uiLanguage))
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
            )
            .overlay(
                Capsule()
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(AppText.localized(.updateDownloading, language: uiLanguage)): v\(version)")

        case .ready(let version):
            Button {
                Task {
                    await updateCoordinator.installPreparedUpdate()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                    Text("v\(version)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Text(AppText.localized(.updateReady, language: uiLanguage))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    ZStack {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.accentColor,
                                        Color.accentColor.opacity(0.85)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        if !reduceMotion {
                            // Smooth, subtle shimmer sheen
                            GeometryReader { geo in
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.clear,
                                                Color.white.opacity(0.25),
                                                Color.clear
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .rotationEffect(.degrees(20))
                                    .offset(x: isSheenActive ? geo.size.width * 1.5 : -geo.size.width * 1.5)
                            }
                            .clipShape(Capsule())
                        }
                    }
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: Color.accentColor.opacity(isHovered ? 0.4 : 0.2), radius: 3, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
            .onAppear {
                if !reduceMotion {
                    withAnimation(
                        .linear(duration: 2.2)
                        .repeatForever(autoreverses: false)
                        .delay(1.0)
                    ) {
                        isSheenActive = true
                    }
                }
            }
            .help("\(AppText.localized(.updateReady, language: uiLanguage)) (v\(version))")
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(AppText.localized(.updateReady, language: uiLanguage)): v\(version)")
            .accessibilityHint("Installs update and relaunches application")

        case .waitingForSafeRelaunch(let version):
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
                Text("v\(version) · \(AppText.localized(.updateWaitingRelaunch, language: uiLanguage))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
            )
            .overlay(
                Capsule()
                    .stroke(Color.orange.opacity(0.4), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(AppText.localized(.updateWaitingRelaunch, language: uiLanguage)): v\(version)")

        case .installing(let version):
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
                Text("v\(version) · \(AppText.localized(.updateInstalling, language: uiLanguage))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
            )
            .overlay(
                Capsule()
                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(AppText.localized(.updateInstalling, language: uiLanguage)): v\(version)")

        case .failed(let version, let message):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange)
                    .font(.system(size: 11, weight: .semibold))

                Text(version.map { "v\($0) \(AppText.localized(.updateFailed, language: uiLanguage))" } ?? AppText.localized(.updateFailed, language: uiLanguage))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)

                Button {
                    updateCoordinator.retry()
                } label: {
                    Text(AppText.localized(.updateRetry, language: uiLanguage))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                }
                .buttonStyle(.plain)

                Button {
                    updateCoordinator.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
            )
            .overlay(
                Capsule()
                    .stroke(Color.orange.opacity(0.4), lineWidth: 1)
            )
            .help(message)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(AppText.localized(.updateFailed, language: uiLanguage)): \(message)")
        }
    }
}
