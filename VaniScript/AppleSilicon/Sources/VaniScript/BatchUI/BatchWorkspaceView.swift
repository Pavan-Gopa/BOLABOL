import AppKit
import SwiftUI
import VaniScriptCore
import VaniScriptRuntime

struct BatchWorkspaceView: View {
    @EnvironmentObject private var store: BatchTranscriptionStore
    @EnvironmentObject private var workflowStore: WorkflowStore

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationTitle("Batch")
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 300)
        } content: {
            content
                .navigationTitle("Batch Transcription")
                .navigationSplitViewColumnWidth(min: 360, ideal: 460)
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        }
        .overlay(alignment: .bottom) {
            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
                    .accessibilityLabel("Error: \(error)")
            }
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $store.selectedProfileID) {
            Section {
                if store.profiles.isEmpty {
                    Text("No watched folders")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(store.profiles, id: \.id) { profile in
                    folderRow(profile)
                }
            } header: {
                Text("Watched Folders")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: chooseFolder) {
                Label("Add Folder", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(10)
            .accessibilityLabel("Add watched folder")
            .disabled(!store.isAvailable)
        }
    }

    private func folderRow(_ profile: BatchFolderProfile) -> some View {
        HStack(spacing: 8) {
            Label(profile.name, systemImage: profile.enabled ? "folder.badge.gearshape" : "folder")
                .foregroundStyle(profile.enabled ? .primary : .secondary)
                .lineLimit(1)
            Spacer()
            if let status = watchStatus(for: profile.id), isWatchProblem(status) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .help(statusLabel(status))
                    .accessibilityLabel(statusLabel(status))
            }
        }
        .tag(profile.id)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            statusHeader
            Divider()
            configurationStrip
            Divider()
            listArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Primary zone: live batch state and the single execution affordance.
    private var statusHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIconName)
                .font(.title2)
                .foregroundStyle(statusColor)
                .frame(minWidth: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusHeadline)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                Text("\(store.providerDisplayName) · \(NativeLanguagePolicy.displayName(for: store.configuration.sourceLanguage))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if !store.issues.isEmpty {
                Label("\(store.issues.count) issue\(store.issues.count == 1 ? "" : "s")",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .help("Files rejected by the latest reconciliation are listed below.")
                    .accessibilityLabel("\(store.issues.count) rejected file\(store.issues.count == 1 ? "" : "s")")
            }
            Button {
                Task { store.isRunning ? await store.stop() : await store.start() }
            } label: {
                Label(
                    store.isRunning ? "Stop" : "Start",
                    systemImage: store.isRunning ? "stop.fill" : "play.fill"
                )
                .frame(minWidth: 68)
            }
            .buttonStyle(.borderedProminent)
            .tint(store.isRunning ? .red : .green)
            .accessibilityLabel(store.isRunning ? "Stop batch transcription" : "Start batch transcription")
            .disabled(
                !store.isAvailable
                    || (!store.isRunning && (
                        store.startBlockMessage != nil
                            || !store.jobs.contains(where: { $0.state == .pending })
                    ))
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Secondary zone: execution configuration, visually subordinate to the state row.
    private var configurationStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            providerControls
            chunkingControls
            canonicalToggle
            Text(policyHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
            if let warning = store.startBlockMessage {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(warning)
                    .accessibilityLabel("Batch cannot start: \(warning)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var providerControls: some View {
        let cloudProviders = availableTranscriptionProviders.filter { $0.group == .cloud }
        let localProviders = availableTranscriptionProviders.filter { $0.group == .local }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text("Provider")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Picker("Provider", selection: providerBinding) {
                        if !cloudProviders.isEmpty {
                            Section("Cloud") {
                                ForEach(cloudProviders, id: \.id) { provider in
                                    Text(provider.label).tag(provider.id)
                                }
                            }
                        }
                        if !localProviders.isEmpty {
                            Section("Local") {
                                ForEach(localProviders, id: \.id) { provider in
                                    Text(provider.label).tag(provider.id)
                                }
                            }
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel("Transcription provider")
                }
                if showsModelPicker {
                    HStack(spacing: 6) {
                        Text("Model")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Picker("Model", selection: batchModelBinding) {
                            ForEach(batchModelOptions, id: \.self) { modelID in
                                Text(modelID).tag(modelID)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 240)
                        .accessibilityLabel("Transcription model")
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Provider")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Picker("Provider", selection: providerBinding) {
                        if !cloudProviders.isEmpty {
                            Section("Cloud") {
                                ForEach(cloudProviders, id: \.id) { provider in
                                    Text(provider.label).tag(provider.id)
                                }
                            }
                        }
                        if !localProviders.isEmpty {
                            Section("Local") {
                                ForEach(localProviders, id: \.id) { provider in
                                    Text(provider.label).tag(provider.id)
                                }
                            }
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel("Transcription provider")
                }
                if showsModelPicker {
                    HStack(spacing: 6) {
                        Text("Model")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Picker("Model", selection: batchModelBinding) {
                            ForEach(batchModelOptions, id: \.self) { modelID in
                                Text(modelID).tag(modelID)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 240)
                        .accessibilityLabel("Transcription model")
                    }
                }
            }
        }
    }

    private var chunkingControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                chunkDurationStepper
                silenceThresholdStepper
                minSilenceStepper
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    chunkDurationStepper
                    silenceThresholdStepper
                }
                minSilenceStepper
            }
        }
        .font(.callout)
    }

    private var chunkDurationStepper: some View {
        Stepper("Chunk: \(workflowStore.settings.chunkDurationMin) min", value: chunkDurationBinding, in: 1...60)
            .accessibilityLabel("Chunk duration")
            .accessibilityValue("\(workflowStore.settings.chunkDurationMin) minutes")
    }

    private var silenceThresholdStepper: some View {
        Stepper("Silence: \(workflowStore.settings.silenceThreshDb) dB", value: silenceThreshDbBinding, in: -60 ... -1)
            .accessibilityLabel("Silence threshold")
            .accessibilityValue("\(workflowStore.settings.silenceThreshDb) decibels")
    }

    private var minSilenceStepper: some View {
        Stepper("Min silence: \(workflowStore.settings.minSilenceMs) ms", value: minSilenceMsBinding, in: 100...3000)
            .accessibilityLabel("Minimum silence duration")
            .accessibilityValue("\(workflowStore.settings.minSilenceMs) milliseconds")
    }

    private var canonicalToggle: some View {
        Toggle("Require canonical names", isOn: canonicalNamesBinding)
            .font(.callout)
            .accessibilityLabel("Require canonical names")
            .accessibilityHint("When disabled, accepts any supported audio file and keeps the original filename for the transcript companion.")
            .help("When disabled, accepts any supported audio file and keeps the original filename for the transcript companion.")
    }

    /// Honest description of the naming policy currently in effect.
    private var policyHint: String {
        workflowStore.settings.requireCanonicalNames
            ? "Required format: YYYY-MM-DD_WHO_WHAT_WHERE_cc (e.g. 2023-01-16_KKS_CC-Raghunatha-das-goswami_Amsterdam_nl)."
            : "Canonical names are off: any supported audio file is accepted and the companion transcript keeps the original filename."
    }

    // MARK: - Job and issue list

    @ViewBuilder
    private var listArea: some View {
        if store.profiles.isEmpty, store.jobs.isEmpty, store.issues.isEmpty {
            ContentUnavailableView {
                Label("No Watched Folders", systemImage: "folder.badge.plus")
            } description: {
                Text("Add a folder and VaniScript will watch it for stable audio files to transcribe.")
            } actions: {
                Button("Add Folder…", action: chooseFolder)
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.isAvailable)
                    .accessibilityLabel("Add watched folder")
            }
        } else if store.isReconciling, store.jobs.isEmpty, store.issues.isEmpty {
            ContentUnavailableView {
                Label("Scanning Folders", systemImage: "waveform")
            } description: {
                Text("Looking for stable audio files in your watched folders. They will appear here as soon as the scan finishes.")
            }
        } else if store.jobs.isEmpty, store.issues.isEmpty {
            ContentUnavailableView {
                Label("No Batch Jobs", systemImage: "waveform")
            } description: {
                Text(store.isRunning
                     ? "Watching for stable audio files in your watched folders."
                     : "Audio files from your folders appear here after they are scanned. Press Start to transcribe queued jobs.")
            }
        } else {
            List(selection: $store.selectedJobID) {
                if !store.issues.isEmpty {
                    Section {
                        ForEach(store.issues.indices, id: \.self) { index in
                            issueRow(store.issues[index])
                        }
                    } header: {
                        HStack {
                            Text("Rejected Files")
                            Spacer()
                            Text("\(store.issues.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if !store.jobs.isEmpty {
                    Section {
                        ForEach(store.jobs) { job in
                            BatchJobRowView(job: job) {
                                store.openCompanion(for: job)
                            }
                            .tag(job.id)
                        }
                    } header: {
                        HStack {
                            Text("Batch Jobs")
                            Spacer()
                            Text("\(store.jobs.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func issueRow(_ issue: BatchReconciliationIssue) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.relativePath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(issue.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(issue.relativePath): \(issue.reason)")
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let job = store.selectedJob {
            BatchJobDetailsView(store: store, job: job)
        } else if let activeJob = store.activeProcessingJob {
            BatchJobDetailsView(store: store, job: activeJob)
        } else if let profile = store.selectedProfile {
            BatchFolderProfileView(store: store, profile: profile)
        } else {
            Text(store.profiles.isEmpty
                 ? "Folder details and job progress will appear here."
                 : "Select a watched folder or job to see its details.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
        }
    }

    // MARK: - State presentation
    private var statusHeadline: String {
        if !store.isAvailable { return store.statusMessage }
        if store.isProcessing { return "Transcribing batch jobs…" }
        return store.statusMessage
    }


    private var statusIconName: String {
        if !store.isAvailable { return "exclamationmark.octagon" }
        if store.isProcessing { return "waveform" }
        if store.isRunning { return "dot.radiowaves.left.and.right" }
        return "stop.circle"
    }

    private var statusColor: Color {
        if !store.isAvailable { return .red }
        if store.isProcessing { return .accentColor }
        if store.isRunning { return .green }
        return .secondary
    }

    private var showsModelPicker: Bool {
        workflowStore.settings.transcriptionProvider == "gemini-cloud"
            || workflowStore.settings.transcriptionProvider == "openrouter"
    }

    private func watchStatus(for profileID: String) -> ProfileWatchStatus? {
        store.watchStatuses.first { $0.profileID == profileID }?.status
    }

    private func isWatchProblem(_ status: ProfileWatchStatus) -> Bool {
        switch status {
        case .active, .staleRefreshed: false
        case .revoked, .unavailable, .accessDenied, .watchFailed: true
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

    // MARK: - Bindings

    private var providerBinding: Binding<String> {
        Binding {
            workflowStore.settings.transcriptionProvider
        } set: { newProvider in
            workflowStore.setTranscriptionProvider(newProvider)
        }
    }

    private var batchModelBinding: Binding<String> {
        Binding {
            if workflowStore.settings.transcriptionProvider == "openrouter" {
                let model = workflowStore.settings.transcriptionModel(for: "openrouter")
                return model.isEmpty ? "google/gemini-2.5-flash" : model
            } else {
                let model = workflowStore.settings.geminiTextModel
                return model.isEmpty ? "gemini-2.5-flash" : model
            }
        } set: { newModel in
            if workflowStore.settings.transcriptionProvider == "openrouter" {
                workflowStore.updateSettings { $0.openrouterTranscriptionModel = newModel }
            } else {
                workflowStore.updateSettings { $0.geminiTextModel = newModel }
            }
        }
    }

    private var canonicalNamesBinding: Binding<Bool> {
        Binding {
            workflowStore.settings.requireCanonicalNames
        } set: { newValue in
            workflowStore.updateSettings { $0.requireCanonicalNames = newValue }
            Task {
                await store.scan()
            }
        }
    }
    private var chunkDurationBinding: Binding<Int> {
        Binding {
            workflowStore.settings.chunkDurationMin
        } set: { newValue in
            workflowStore.updateSettings { $0.chunkDurationMin = newValue }
        }
    }

    private var silenceThreshDbBinding: Binding<Int> {
        Binding {
            workflowStore.settings.silenceThreshDb
        } set: { newValue in
            workflowStore.updateSettings { $0.silenceThreshDb = newValue }
        }
    }

    private var minSilenceMsBinding: Binding<Int> {
        Binding {
            workflowStore.settings.minSilenceMs
        } set: { newValue in
            workflowStore.updateSettings { $0.minSilenceMs = newValue }
        }
    }


    private var availableTranscriptionProviders: [ProviderOption] {
        ProviderRegistry.availableTranscriptionProviders(settings: workflowStore.settings)
    }

    private var batchModelOptions: [String] {
        workflowStore.settings.favoriteModels(for: workflowStore.settings.transcriptionProvider)
    }

    // MARK: - Folder selection

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Batch Transcription Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.addFolder(url)
    }
}
