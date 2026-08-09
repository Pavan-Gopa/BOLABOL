import SwiftUI
import VaniScriptCore

struct ProjectSidebarView: View {
    @EnvironmentObject private var store: WorkflowStore
    @State private var expandedProjectID: String?

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture {
                    store.dismissProjectSidebar()
                }

            VStack(alignment: .leading, spacing: 14) {
                header
                actionRow

                if store.projectSummaries.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(store.projectSummaries) { summary in
                                ProjectSidebarRow(
                                    summary: summary,
                                    isExpanded: expandedProjectID == summary.id,
                                    isActive: store.activeProjectID == summary.id,
                                    toggleExpanded: {
                                        withAnimation(.easeOut(duration: 0.16)) {
                                            expandedProjectID = expandedProjectID == summary.id ? nil : summary.id
                                        }
                                    }
                                )
                                    .environmentObject(store)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(width: 380)
            .frame(maxHeight: .infinity)
            .padding(18)
            .background(Color.dynamic(light: Color.white.opacity(0.97), dark: Color(red: 12 / 255, green: 17 / 255, blue: 34 / 255).opacity(0.97)))
            .overlay(Rectangle().fill(VaniScriptTheme.border).frame(width: 1), alignment: .leading)
            .shadow(color: .black.opacity(0.36), radius: 34, x: -18, y: 0)
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sessions")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(VaniScriptTheme.text0)
                Text("Autosaved in Documents/VaniScript Projects")
                    .font(.system(size: 15))
                    .foregroundStyle(VaniScriptTheme.text2)
            }
            Spacer()
            Button {
                store.dismissProjectSidebar()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(SidebarIconButtonStyle())
            .help("Close")
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                store.importProjects()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(SidebarSmallButtonStyle(primary: true))

            Button {
                store.exportAllProjects()
            } label: {
                Label("Export All", systemImage: "archivebox")
            }
            .buttonStyle(SidebarSmallButtonStyle(primary: false))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(VaniScriptTheme.text2)
            Text("No saved sessions yet")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(VaniScriptTheme.text1)
            Text("A project is saved automatically after the engine is initialized.")
                .font(.system(size: 11))
                .foregroundStyle(VaniScriptTheme.text2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }
}

private struct ProjectSidebarRow: View {
    @EnvironmentObject private var store: WorkflowStore
    let summary: ProjectSummary
    let isExpanded: Bool
    let isActive: Bool
    let toggleExpanded: () -> Void
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: isExpanded ? .top : .center, spacing: 0) {
            // Clickable header area
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundStyle(VaniScriptTheme.text2)
                    .frame(width: 16)
                    .padding(.top, 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.name)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(VaniScriptTheme.text0)
                        .lineLimit(1)
                    Text("\(summary.currentIndex + 1)/\(max(1, summary.totalChunks)) chunks · \(summary.approvedChunks) approved · \(summary.targetLang)")
                        .font(.system(size: 12))
                        .foregroundStyle(VaniScriptTheme.text2)
                        .lineLimit(1)
                    Text(formatDate(summary.updatedAt))
                        .font(.system(size: 12))
                        .foregroundStyle(VaniScriptTheme.text2)
                        .lineLimit(1)
                    if let mediaInfo = summary.sourceMediaInfo {
                        Label(mediaSummary(mediaInfo), systemImage: mediaInfo.kind == .video ? "film" : "waveform")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(VaniScriptTheme.accent.opacity(0.9))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                toggleExpanded()
            }
            .layoutPriority(1)

            // Action Buttons
            VStack(spacing: 6) {
                Button {
                    store.exportProject(id: summary.id)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(SidebarIconButtonStyle())
                .help("Share project")

                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(SidebarIconButtonStyle())
                .help("Delete project")
            }
        }
        .frame(maxWidth: .infinity)

            if isExpanded {
                if let mediaInfo = summary.sourceMediaInfo {
                    sourceMediaCard(mediaInfo)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(0..<max(0, summary.totalChunks), id: \.self) { index in
                        chunkButton(index: index)
                    }
                }

                if summary.totalChunks > 0 {
                    Button {
                        store.openProject(id: summary.id, openExport: true)
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ProjectSidebarExportButtonStyle())
                }
            }
        }
        .confirmationDialog(
            "Are you sure you want to delete this project? It will be permanently removed from your computer and cannot be recovered.",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive) {
                store.deleteProject(id: summary.id)
            }
            Button("Cancel", role: .cancel) { }
        }
        .padding(12)
        .background(isActive ? VaniScriptTheme.accent.opacity(0.08) : Color.dynamic(light: Color.black.opacity(0.045), dark: Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isActive ? VaniScriptTheme.accent.opacity(0.38) : Color.dynamic(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.08)), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sourceMediaCard(_ mediaInfo: SourceMediaInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: mediaInfo.kind == .video ? "film.stack" : "waveform")
                    .foregroundStyle(VaniScriptTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mediaInfo.fileName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(VaniScriptTheme.text1)
                        .lineLimit(1)
                    Text(mediaSummary(mediaInfo))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(VaniScriptTheme.text2)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }

            Text(mediaInfo.filePath)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(VaniScriptTheme.text2)
                .lineLimit(2)
                .textSelection(.enabled)

            HStack(spacing: 6) {
                Button {
                    store.showProjectSourceInfo(id: summary.id)
                } label: {
                    Label("Info", systemImage: "info.circle")
                }
                .buttonStyle(ProjectSidebarTinyButtonStyle())

                Button {
                    store.openProjectSourceFile(id: summary.id)
                } label: {
                    Label("Open", systemImage: "play.rectangle")
                }
                .buttonStyle(ProjectSidebarTinyButtonStyle())

                Button {
                    store.revealProjectSourceFile(id: summary.id)
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .buttonStyle(ProjectSidebarTinyButtonStyle())
            }
        }
        .padding(10)
        .background(Color.dynamic(light: Color.black.opacity(0.035), dark: Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.dynamic(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.08)), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func chunkButton(index: Int) -> some View {
        let canOpen = canOpenChunk(index)
        let isCurrent = isActive && store.session?.currentChunkIndex == index
        return Button {
            store.openProject(id: summary.id, chunkIndex: index)
        } label: {
            HStack {
                Text("Chunk \(index + 1)")
                    .lineLimit(1)
                Spacer()
                if summary.shouldShowLastBadge(at: index) {
                    Text("LAST")
                        .font(.system(size: 9, weight: .heavy))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(VaniScriptTheme.accent.opacity(0.18))
                        .clipShape(Capsule())
                }
            }
        }
        .buttonStyle(ProjectSidebarChunkButtonStyle(active: isCurrent))
        .disabled(!canOpen)
    }

    private func canOpenChunk(_ index: Int) -> Bool {
        summary.canOpenChunk(at: index)
    }

    private func mediaSummary(_ info: SourceMediaInfo) -> String {
        var parts: [String] = [info.qualityLabel]
        if !info.resolutionLabel.isEmpty {
            parts.append(info.resolutionLabel)
        }
        if let frameRate = info.frameRate {
            parts.append("\(String(format: "%.0f", frameRate)) fps")
        }
        if let container = info.container, !container.isEmpty {
            parts.append(container.uppercased())
        }
        if let fileSizeBytes = info.fileSizeBytes {
            parts.append(ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    private func formatDate(_ value: String) -> String {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) {
            return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .medium)
        }
        return value.replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "Z", with: "")
    }
}

private struct ProjectSidebarTinyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(configuration.isPressed ? Color.black : VaniScriptTheme.text1)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(configuration.isPressed ? VaniScriptTheme.accent : Color.dynamic(light: Color.black.opacity(0.045), dark: Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.dynamic(light: Color.black.opacity(0.12), dark: Color.white.opacity(0.12)), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct SidebarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 30, height: 30)
            .foregroundStyle(configuration.isPressed ? VaniScriptTheme.accent : VaniScriptTheme.text1)
            .background(Color.dynamic(light: Color.black.opacity(configuration.isPressed ? 0.08 : 0.03), dark: Color.white.opacity(configuration.isPressed ? 0.12 : 0.07)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.dynamic(light: Color.black.opacity(0.12), dark: Color.white.opacity(0.12)), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SidebarSmallButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(primary ? Color(red: 10 / 255, green: 10 / 255, blue: 18 / 255) : VaniScriptTheme.text1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(primary ? VaniScriptTheme.accent : Color.dynamic(light: Color.black.opacity(configuration.isPressed ? 0.08 : 0.03), dark: Color.white.opacity(configuration.isPressed ? 0.1 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(primary ? Color.clear : Color.dynamic(light: Color.black.opacity(0.12), dark: Color.white.opacity(0.12)), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ProjectSidebarChunkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(configuration.isPressed || active ? VaniScriptTheme.text0 : VaniScriptTheme.text1)
            .padding(.horizontal, 9)
            .frame(height: 38)
            .background(active ? VaniScriptTheme.accent.opacity(0.13) : Color.dynamic(light: Color.black.opacity(configuration.isPressed ? 0.08 : 0.035), dark: Color.white.opacity(configuration.isPressed ? 0.08 : 0.035)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? VaniScriptTheme.accent.opacity(0.44) : Color.dynamic(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.08)), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(!isEnabled ? 0.48 : (configuration.isPressed ? 0.86 : 1))
    }
}

private struct ProjectSidebarExportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(VaniScriptTheme.accent)
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(VaniScriptTheme.accent.opacity(configuration.isPressed ? 0.26 : 0.18))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(VaniScriptTheme.accent.opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
