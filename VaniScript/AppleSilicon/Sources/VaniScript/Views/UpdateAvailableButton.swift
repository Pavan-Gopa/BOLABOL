import SwiftUI
import VaniScriptCore

/// Status bar / toolbar button that surfaces available updates, download/extraction progress,
/// ready-to-relaunch actions, and diagnostic errors.
public struct UpdateAvailableButton: View {
    @EnvironmentObject private var coordinator: UpdateCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isDetailPopoverPresented = false

    public init() {}

    @ViewBuilder
    public var body: some View {
        switch coordinator.phase {
        case .idle, .upToDate:
            EmptyView()

        case .checking(let isUserInitiated):
            if isUserInitiated {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking…")
                        .font(.caption)
                        .foregroundStyle(VaniScriptTheme.text2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(VaniScriptTheme.control)
                .clipShape(Capsule())
                .help("Checking for updates…")
                .accessibilityLabel("Checking for software updates")
            } else {
                EmptyView()
            }

        case .available(let descriptor):
            Button {
                isDetailPopoverPresented.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .foregroundStyle(VaniScriptTheme.accent)
                    Text("Update v\(descriptor.displayVersion)")
                        .font(.caption.bold())
                        .foregroundStyle(VaniScriptTheme.text0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(VaniScriptTheme.accent.opacity(0.15))
                .overlay(
                    Capsule()
                        .strokeBorder(VaniScriptTheme.accent.opacity(0.4), lineWidth: 1)
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("New version available: v\(descriptor.displayVersion). Click to view details and install.")
            .accessibilityLabel("Update available: version \(descriptor.displayVersion)")
            .accessibilityHint("Opens update details and installation options")
            .popover(isPresented: $isDetailPopoverPresented) {
                UpdateDetailPopoverContent(descriptor: descriptor)
                    .environmentObject(coordinator)
            }

        case .downloading(let descriptor, let progress, _, _):
            HStack(spacing: 8) {
                if reduceMotion {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(VaniScriptTheme.accent)
                } else {
                    ProgressView(value: progress)
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Downloading v\(descriptor.displayVersion)")
                        .font(.caption.bold())
                        .foregroundStyle(VaniScriptTheme.text0)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(VaniScriptTheme.text2)
                }

                Button {
                    coordinator.cancelActiveOperation()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(VaniScriptTheme.text2)
                }
                .buttonStyle(.plain)
                .help("Cancel download")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(VaniScriptTheme.control)
            .clipShape(Capsule())
            .help("Downloading update v\(descriptor.displayVersion): \(Int(progress * 100))% downloaded")
            .accessibilityLabel("Downloading update: \(Int(progress * 100)) percent complete")

        case .extracting(let descriptor, let progress):
            HStack(spacing: 6) {
                ProgressView(value: progress > 0 ? progress : nil)
                    .controlSize(.small)
                Text("Extracting v\(descriptor.displayVersion)…")
                    .font(.caption)
                    .foregroundStyle(VaniScriptTheme.text1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(VaniScriptTheme.control)
            .clipShape(Capsule())
            .help("Extracting and verifying update package…")
            .accessibilityLabel("Extracting update package")

        case .readyToInstall(let descriptor):
            Button {
                coordinator.installUpdate()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(VaniScriptTheme.green)
                    Text("Restart to Update")
                        .font(.caption.bold())
                        .foregroundStyle(VaniScriptTheme.text0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(VaniScriptTheme.green.opacity(0.2))
                .overlay(
                    Capsule()
                        .strokeBorder(VaniScriptTheme.green.opacity(0.5), lineWidth: 1)
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Update ready. Click to restart VaniScript and apply update v\(descriptor.displayVersion).")
            .accessibilityLabel("Update ready: Restart to install version \(descriptor.displayVersion)")

        case .installing:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Installing…")
                    .font(.caption)
                    .foregroundStyle(VaniScriptTheme.text1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(VaniScriptTheme.control)
            .clipShape(Capsule())
            .help("Installing update and preparing relaunch…")
            .accessibilityLabel("Installing update")

        case .failed(let error):
            Button {
                isDetailPopoverPresented.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(VaniScriptTheme.red)
                    Text("Update Error")
                        .font(.caption.bold())
                        .foregroundStyle(VaniScriptTheme.red)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(VaniScriptTheme.errorSurface)
                .overlay(
                    Capsule()
                        .strokeBorder(VaniScriptTheme.errorBorder, lineWidth: 1)
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Update failed: \(error.message). Click for recovery options.")
            .accessibilityLabel("Update failed: \(error.message)")
            .popover(isPresented: $isDetailPopoverPresented) {
                UpdateErrorPopoverContent(error: error)
                    .environmentObject(coordinator)
            }
        }
    }
}

/// Detail popover presented when user clicks the available update button.
private struct UpdateDetailPopoverContent: View {
    let descriptor: UpdateDescriptor
    @EnvironmentObject private var coordinator: UpdateCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(VaniScriptTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("VaniScript \(descriptor.displayVersion)")
                        .font(.headline)
                        .foregroundStyle(VaniScriptTheme.text0)
                    if !descriptor.humanReadableSize.isEmpty {
                        Text("Download size: \(descriptor.humanReadableSize)")
                            .font(.caption)
                            .foregroundStyle(VaniScriptTheme.text2)
                    }
                }
                Spacer()
            }

            if let notes = descriptor.releaseNotesDescription, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Release Notes:")
                        .font(.caption.bold())
                        .foregroundStyle(VaniScriptTheme.text1)
                    ScrollView {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(VaniScriptTheme.text2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button("Install Update") {
                    dismiss()
                    coordinator.installUpdate()
                }
                .buttonStyle(UpdatePrimaryButtonStyle())

                Button("Later") {
                    dismiss()
                    coordinator.dismissUpdate()
                }
                .buttonStyle(UpdateSecondaryButtonStyle())

                Spacer()

                Button("Skip Version") {
                    dismiss()
                    coordinator.skipUpdate()
                }
                .buttonStyle(UpdateSecondaryButtonStyle())
            }
        }
        .padding(VaniScriptTheme.Density.space12)
        .frame(width: 340)
    }
}

/// Popover presented when user clicks the update error button.
private struct UpdateErrorPopoverContent: View {
    let error: UpdateDiagnosticError
    @EnvironmentObject private var coordinator: UpdateCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(VaniScriptTheme.red)
                Text("Update Diagnostic")
                    .font(.headline)
                    .foregroundStyle(VaniScriptTheme.text0)
            }

            Text(error.message)
                .font(.body)
                .foregroundStyle(VaniScriptTheme.text1)

            if !error.recoverySuggestion.isEmpty {
                Text(error.recoverySuggestion)
                    .font(.caption)
                    .foregroundStyle(VaniScriptTheme.text2)
            }

            Divider()

            HStack(spacing: 8) {
                Button("Retry Check") {
                    dismiss()
                    coordinator.retryLastAction()
                }
                .buttonStyle(UpdatePrimaryButtonStyle())

                Button("Dismiss") {
                    dismiss()
                    coordinator.clearError()
                }
                .buttonStyle(UpdateSecondaryButtonStyle())
            }
        }
        .padding(VaniScriptTheme.Density.space12)
        .frame(width: 320)
    }
}

private struct UpdatePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(VaniScriptTheme.onAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                VaniScriptTheme.accent
                    .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1.0) : 0.4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct UpdateSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(VaniScriptTheme.text1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                VaniScriptTheme.control
                    .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1.0) : 0.4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(VaniScriptTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
