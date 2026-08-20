import SwiftUI
import VaniScriptCore
import VaniScriptRuntime

struct BatchFolderProfileView: View {
    @ObservedObject var store: BatchTranscriptionStore
    let profile: BatchFolderProfile

    var body: some View {
        Form {
            Section("Folder") {
                TextField("Name", text: profileBinding(\.name))
                    .accessibilityLabel("Watched folder name")
                LabeledContent("Location") {
                    Text(profile.displayPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .accessibilityLabel("Folder location \(profile.displayPath)")
                }
            }
            Section {
                Toggle("Watch this folder", isOn: profileBinding(\.enabled))
                Toggle("Include subfolders", isOn: profileBinding(\.recursive))
            }
            Section("Watching") {
                watchStatusRow
            }
            Section {
                Button("Remove Folder", role: .destructive) {
                    store.removeProfile(id: profile.id)
                }
                .accessibilityLabel("Remove watched folder \(profile.name)")
                .disabled(store.isProcessing)
            } footer: {
                if store.isProcessing {
                    Text("Folders cannot be removed while a job is processing.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(profile.name)
    }

    @ViewBuilder
    private var watchStatusRow: some View {
        if let status = store.watchStatuses.first(where: { $0.profileID == profile.id }) {
            Label(statusLabel(status.status), systemImage: statusIcon(status.status))
                .foregroundStyle(status.status == .active || status.status == .staleRefreshed ? Color.secondary : Color.red)
        } else {
            Text(profile.enabled ? "Not currently watching." : "Watching is off for this folder.")
                .foregroundStyle(.secondary)
        }
    }

    private func profileBinding<Value>(_ keyPath: WritableKeyPath<BatchFolderProfile, Value>) -> Binding<Value> {
        Binding {
            profile[keyPath: keyPath]
        } set: { value in
            var updated = profile
            updated[keyPath: keyPath] = value
            store.updateProfile(updated)
        }
    }

    private func statusLabel(_ status: ProfileWatchStatus) -> String {
        switch status {
        case .active: "Watching"
        case .staleRefreshed: "Bookmark refreshed"
        case .revoked: "Folder access revoked"
        case .unavailable: "Folder unavailable"
        case .accessDenied: "Folder access denied"
        case .watchFailed: "Folder watcher failed"
        }
    }

    private func statusIcon(_ status: ProfileWatchStatus) -> String {
        switch status {
        case .active, .staleRefreshed: "checkmark.circle"
        default: "exclamationmark.triangle"
        }
    }
}
