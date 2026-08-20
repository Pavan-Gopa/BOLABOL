import SwiftUI
import VaniScriptCore

struct SettingsView: View {
    @EnvironmentObject private var store: WorkflowStore
    @EnvironmentObject private var batchStore: BatchTranscriptionStore
    @EnvironmentObject private var updateCoordinator: UpdateCoordinator
    @State private var onboardingFrames: [String: CGRect] = [:]
    @State private var glossarySource = ""
    @State private var glossaryTranslation = ""
    @State private var glossaryCategory = ""
    @State private var glossaryVariants = ""
    @State private var selectedPromptId = "transcriptionSystem"
    @State private var glossarySearch = ""
    @State private var glossaryCategoryFilter = "all"
    @State private var glossarySortMode = GlossarySortMode.newest
    @State private var editingEntry: GlossaryEntry? = nil

    @State private var customLabel = ""
    @State private var customBaseUrl = ""
    @State private var customApiKey = ""
    @State private var customModelName = ""
    @State private var customInputCost = ""
    @State private var customOutputCost = ""
    @State private var customBudgetLimit = ""

    // A3: currently selected cloud provider for the API & Usage dropdown (fixed
    // catalog order). Defaults to Gemini to preserve the previous top section.
    @State private var selectedProviderId = CloudProviderCatalog.geminiID

    private let mcpOverviewColumns = [
        GridItem(.flexible(minimum: 220), spacing: VaniScriptTheme.Density.space8),
        GridItem(.flexible(minimum: 220), spacing: VaniScriptTheme.Density.space8),
    ]
    private let activeTargetColumns = [
        GridItem(.flexible(minimum: 220), spacing: VaniScriptTheme.Density.space8),
        GridItem(.flexible(minimum: 220), spacing: VaniScriptTheme.Density.space8),
    ]

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                header

                TabView(selection: $store.selectedSettingsTab) {
                    agentsTab
                        .onboardingTarget("settings-tab-0")
                        .tabItem { Label("Agents", systemImage: "person.2.wave.2") }
                        .tag(SettingsTab.agents)
                    apiKeysTab
                        .onboardingTarget("settings-tab-1")
                        .tabItem { Label("API & Usage", systemImage: "key.fill") }
                        .tag(SettingsTab.apiKeys)
                    appearanceTab
                        .onboardingTarget("settings-tab-2")
                        .tabItem { Label("Appearance", systemImage: "paintpalette") }
                        .tag(SettingsTab.appearance)
                    chunkingTab
                        .onboardingTarget("settings-tab-3")
                        .tabItem { Label("Chunking", systemImage: "scissors") }
                        .tag(SettingsTab.chunking)
                    glossaryTab
                        .onboardingTarget("settings-tab-4")
                        .tabItem { Label("Glossary", systemImage: "text.book.closed") }
                        .tag(SettingsTab.glossary)
                    modelsTab
                        .onboardingTarget("settings-tab-5")
                        .tabItem { Label("Models", systemImage: "cpu") }
                        .tag(SettingsTab.models)
                    promptsTab
                        .onboardingTarget("settings-tab-6")
                        .tabItem { Label("Prompts", systemImage: "doc.text") }
                        .tag(SettingsTab.prompts)
                    transcriptionTab
                        .onboardingTarget("settings-tab-7")
                        .tabItem { Label("Transcription", systemImage: "waveform.badge.mic") }
                        .tag(SettingsTab.transcription)
                    updatesTab
                        .onboardingTarget("settings-tab-8")
                        .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath.circle") }
                        .tag(SettingsTab.updates)
                }
                .tint(VaniScriptTheme.accent)
            }
            .padding(VaniScriptTheme.Density.space12)
            .glassPanel()
            .padding(VaniScriptTheme.Density.space12)

            if store.isTourActive {
                OnboardingTourView(
                    screen: "settings",
                    store: store,
                    frames: onboardingFrames
                )
            }
        }
        .coordinateSpace(name: "OnboardingSpace")
        .onPreferenceChange(OnboardingFramesPreferenceKey.self) { dict in
            onboardingFrames = dict
        }
        .preferredColorScheme(store.settings.theme == .dark ? .dark : .light)
        .onAppear {
            if let catalogID = ProviderRegistry.cloudProviderCatalogID(for: store.settings.translationProvider) {
                selectedProviderId = catalogID
            }
        }
        .onChange(of: store.settings.translationProvider) { _, newProvider in
            if let catalogID = ProviderRegistry.cloudProviderCatalogID(for: newProvider) {
                selectedProviderId = catalogID
            }
        }
        .onChange(of: store.selectedSettingsTab) { _, newTab in
            if store.isTourActive && store.activeTourScreen == "settings" {
                if let stepIndex = SettingsTab.alphabetized.firstIndex(of: newTab),
                   store.tourStepIndex != stepIndex {
                    store.tourStepIndex = stepIndex
                }
            }
        }
        .sheet(item: $editingEntry) { entry in
            GlossaryEditSheet(entry: entry) { updatedEntry in
                var finalEntry = updatedEntry
                finalEntry.translations[store.workflow.targetLang] = updatedEntry.translation
                if store.workflow.targetLang.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "russian" {
                    finalEntry.translations["Russian"] = updatedEntry.translation
                }
                store.updateSettings { settings in
                    if let index = settings.glossary.firstIndex(where: { $0.id == entry.id }) {
                        settings.glossary[index] = finalEntry
                    }
                }
                editingEntry = nil
            } onCancel: {
                editingEntry = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: VaniScriptTheme.Density.space8) {
            VaniScriptLogoMark(size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("VaniScript Settings")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(VaniScriptTheme.text0)
                Text("Universal workflow settings for the native Apple Silicon app")
                    .font(.system(size: 11))
                    .foregroundStyle(VaniScriptTheme.text2)
                Text("Batch: \(batchStore.isRunning ? "watching" : "stopped") · \(batchStore.profiles.count) folder\(batchStore.profiles.count == 1 ? "" : "s") · \(batchStore.jobs.count) job\(batchStore.jobs.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(VaniScriptTheme.text2)
                    .accessibilityLabel("Batch transcription \(batchStore.isRunning ? "watching" : "stopped"), \(batchStore.profiles.count) folders, \(batchStore.jobs.count) jobs")
            }
            Spacer()

            Button {
                store.startTour(for: "settings")
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(CornerIconButtonStyle())
            .help("Help Tour")
        }
        .padding(.bottom, 12)
    }

    private var agentsTab: some View {
        SettingsScroll {
            mcpIntegrationSection

            SettingsSection(title: "Embedded Codex Chat") {
                LazyVGrid(columns: activeTargetColumns, alignment: .leading, spacing: VaniScriptTheme.Density.space8) {
                    VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space6) {
                        Label("Chat Model", systemImage: "cpu")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(VaniScriptTheme.text2)

                        Picker("", selection: Binding(
                            get: { store.settings.codexChatModelID },
                            set: { modelID in
                                guard let option = CodexChatModelCatalog.option(id: modelID) else { return }
                                store.updateSettings { settings in
                                    settings.codexChatModelID = option.id
                                    settings.codexChatReasoningEffort = option.defaultReasoningEffort
                                }
                            }
                        )) {
                            ForEach(CodexChatModelCatalog.options) { option in
                                Text(option.displayName).tag(option.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                    .background(VaniScriptTheme.control)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(VaniScriptTheme.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous))

                    VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space6) {
                        Label("Reasoning", systemImage: "brain")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(VaniScriptTheme.text2)

                        let selectedModelID = CodexChatModelCatalog.normalizedModelID(store.settings.codexChatModelID)
                        let selectedModel = CodexChatModelCatalog.option(id: selectedModelID) ?? CodexChatModelCatalog.options[0]
                        Picker("", selection: Binding(
                            get: { store.settings.codexChatReasoningEffort },
                            set: { effort in
                                store.updateSettings { settings in
                                    settings.codexChatReasoningEffort = CodexChatModelCatalog.normalizedReasoningEffort(
                                        modelID: selectedModel.id,
                                        effort: effort
                                    )
                                }
                            }
                        )) {
                            ForEach(selectedModel.reasoningEfforts, id: \.self) { effort in
                                Text(effort.capitalized).tag(effort)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                    .background(VaniScriptTheme.control)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(VaniScriptTheme.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous))
                }
            }

            SettingsSection(title: "Embedded Grok Chat") {
                LazyVGrid(columns: activeTargetColumns, alignment: .leading, spacing: VaniScriptTheme.Density.space8) {
                    VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space6) {
                        Label("Chat Model", systemImage: "cpu")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(VaniScriptTheme.text2)

                        Picker("", selection: Binding(
                            get: { store.settings.grokChatModelID },
                            set: { modelID in
                                guard let option = GrokChatModelCatalog.option(id: modelID) else { return }
                                store.updateSettings { settings in
                                    settings.grokChatModelID = option.id
                                    settings.grokChatReasoningEffort = option.defaultReasoningEffort
                                }
                            }
                        )) {
                            ForEach(GrokChatModelCatalog.options) { option in
                                Text(option.displayName).tag(option.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                    .background(VaniScriptTheme.control)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(VaniScriptTheme.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous))

                    VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space6) {
                        Label("Reasoning", systemImage: "brain")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(VaniScriptTheme.text2)

                        let selectedGrokModelID = GrokChatModelCatalog.normalizedModelID(store.settings.grokChatModelID)
                        let selectedGrokModel = GrokChatModelCatalog.option(id: selectedGrokModelID) ?? GrokChatModelCatalog.options[0]
                        Picker("", selection: Binding(
                            get: { store.settings.grokChatReasoningEffort },
                            set: { effort in
                                store.updateSettings { settings in
                                    settings.grokChatReasoningEffort = GrokChatModelCatalog.normalizedReasoningEffort(
                                        modelID: selectedGrokModel.id,
                                        effort: effort
                                    )
                                }
                            }
                        )) {
                            ForEach(selectedGrokModel.reasoningEfforts, id: \.self) { effort in
                                Text(effort.capitalized).tag(effort)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                    .background(VaniScriptTheme.control)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(VaniScriptTheme.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous))
                }
            }

            // Q2: Qwen section has no reasoning picker — the Qwen CLI has no such flag.
            SettingsSection(title: "Embedded Qwen Chat") {
                LazyVGrid(columns: activeTargetColumns, alignment: .leading, spacing: VaniScriptTheme.Density.space8) {
                    VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space6) {
                        Label("Chat Model", systemImage: "cpu")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(VaniScriptTheme.text2)

                        Picker("", selection: Binding(
                            get: { store.settings.qwenChatModelID },
                            set: { modelID in
                                guard let option = QwenChatModelCatalog.option(id: modelID) else { return }
                                store.updateSettings { settings in
                                    settings.qwenChatModelID = option.id
                                }
                            }
                        )) {
                            ForEach(QwenChatModelCatalog.options) { option in
                                Text(option.displayName).tag(option.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                    .background(VaniScriptTheme.control)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(VaniScriptTheme.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous))
                }
            }

            SettingsSection(title: "Active Target") {
                LazyVGrid(columns: activeTargetColumns, alignment: .leading, spacing: VaniScriptTheme.Density.space8) {
                    VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space6) {
                        Label("Preferred Agent", systemImage: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(VaniScriptTheme.text2)

                        Picker("", selection: Binding(
                            get: { store.settings.mcpPreferredAgentID },
                            set: { value in
                                store.updateSettings { settings in
                                    settings.mcpPreferredAgentID = value
                                }
                            }
                        )) {
                            ForEach(McpAgentProfileCatalog.all) { profile in
                                Text(profile.displayName).tag(profile.id.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                    .background(VaniScriptTheme.control)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(VaniScriptTheme.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous))

                    McpStatusSummaryTile(
                        title: "Status",
                        value: mcpConnectionSummary,
                        systemImage: "point.3.connected.trianglepath.dotted",
                        tint: mcpConnectionColor
                    )
                }
            }

            SettingsSection(title: "Agent Profiles") {
                VStack(spacing: 0) {
                    ForEach(McpAgentProfileCatalog.all) { profile in
                        McpAgentProfileRow(
                            profile: profile,
                            state: mcpConnectionState(for: profile),
                            isPreferred: store.settings.mcpPreferredAgentID == profile.id.rawValue,
                            activeClient: mcpActiveClient(for: profile),
                            canCopySetup: store.settings.mcpServerEnabled && !store.settings.mcpAccessToken.isEmpty,
                            setActive: {
                                store.updateSettings { settings in
                                    settings.mcpPreferredAgentID = profile.id.rawValue
                                }
                            },
                            copySetup: {
                                copyMcpSetup(for: profile)
                            }
                        )

                        if profile.id != McpAgentProfileCatalog.all.last?.id {
                            Divider()
                                .background(VaniScriptTheme.separator)
                                .padding(.leading, 44)
                        }
                    }
                }
            }
        }
    }

    private var apiKeysTab: some View {
        SettingsScroll {
            // A3: single Provider dropdown (fixed catalog order) + only the selected card.
            SettingsSection(title: "Cloud Provider") {
                Picker("Provider", selection: $selectedProviderId) {
                    ForEach(CloudProviderCatalog.providers) { descriptor in
                        Text(descriptor.label).tag(descriptor.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(VaniScriptTheme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if selectedProviderId == CloudProviderCatalog.customID {
                customProvidersSection
            } else if let descriptor = CloudProviderCatalog.descriptor(for: selectedProviderId) {
                ProviderCardView(descriptor: descriptor)
            }

            // A6: usage statistics rebuilt to Electron tab 7 parity — the old
            // "Cloud Usage Statistics" section is replaced by UsageStatisticsView
            // (per-model cards from settings.usage, last transaction, disclaimer).
            UsageStatisticsView()
        }
    }

    // A3: custom cloud providers section (existing mechanism, unchanged) — shown
    // only when "Custom" is picked in the provider dropdown.
    private var customProvidersSection: some View {
        SettingsSection(title: "Custom Cloud Providers") {
            VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space8) {
                if store.settings.customCloudProviders.isEmpty {
                    Text("No custom cloud providers configured.")
                        .font(.system(size: 12))
                        .foregroundStyle(VaniScriptTheme.text2)
                        .padding(.bottom, 6)
                } else {
                    ForEach(store.settings.customCloudProviders) { provider in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.label)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(VaniScriptTheme.text0)
                                Text("Model: \(provider.modelName) • URL: \(provider.baseUrl)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(VaniScriptTheme.text2)
                                Text("Pricing per 1M tokens: In $\(String(format: "%.2f", provider.inputCostPerMillion)) / Out $\(String(format: "%.2f", provider.outputCostPerMillion))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(VaniScriptTheme.accent)
                            }
                            Spacer()
                            if provider.budgetLimitUsd > 0 {
                                Text("Limit: $\(String(format: "%.0f", provider.budgetLimitUsd))")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(VaniScriptTheme.text1)
                                    .padding(.trailing, 8)
                            }
                            Button(role: .destructive) {
                                store.updateSettings { settings in
                                    settings.customCloudProviders.removeAll { $0.id == provider.id }
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(VaniScriptTheme.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(8)
                        .background(VaniScriptTheme.surfaceSubtle)
                        .cornerRadius(6)
                    }
                }

                Divider().padding(.vertical, 4)

                Text("Add Custom Cloud Model")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(VaniScriptTheme.accent)

                VStack(spacing: 8) {
                    TextInputRow(title: "Provider Name", text: $customLabel)
                    TextInputRow(title: "API Endpoint URL", text: $customBaseUrl)
                    SecureInputRow(title: "API Key", text: $customApiKey)
                    TextInputRow(title: "Model Name", text: $customModelName)
                    TextInputRow(title: "Input cost / 1M tokens ($)", text: $customInputCost)
                    TextInputRow(title: "Output cost / 1M tokens ($)", text: $customOutputCost)
                    TextInputRow(title: "Monthly Budget Limit ($)", text: $customBudgetLimit)

                    Button {
                        addCustomProvider()
                    } label: {
                        Label("Add Custom Provider", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SettingsPrimaryButtonStyle())
                    .disabled(customLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || customBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var mcpIntegrationSection: some View {
        SettingsSection(title: "Local MCP Server") {
            VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space8) {
                LazyVGrid(columns: mcpOverviewColumns, alignment: .leading, spacing: VaniScriptTheme.Density.space8) {
                    CompactMcpToggleCard(
                        title: "Enable MCP",
                        subtitle: store.settings.mcpServerEnabled ? "Listening locally" : "Server disabled",
                        systemImage: "network",
                        isEnabled: true,
                        isOn: Binding {
                            store.settings.mcpServerEnabled
                        } set: { value in
                            store.updateSettings { settings in
                                settings.mcpServerEnabled = value
                            }
                        }
                    )

                    CompactMcpToggleCard(
                        title: "Edit Project",
                        subtitle: store.settings.mcpAllowMutatingTools ? "Text and settings" : "Read-only",
                        systemImage: "pencil.and.outline",
                        isEnabled: store.settings.mcpServerEnabled,
                        isOn: Binding {
                            store.settings.mcpAllowMutatingTools
                        } set: { value in
                            store.updateSettings { settings in
                                settings.mcpAllowMutatingTools = value
                            }
                        }
                    )

                    CompactMcpToggleCard(
                        title: "Run Processing",
                        subtitle: store.settings.mcpAllowProcessingTools ? "AI and media jobs" : "Blocked",
                        systemImage: "gearshape.2",
                        isEnabled: store.settings.mcpServerEnabled,
                        isOn: Binding {
                            store.settings.mcpAllowProcessingTools
                        } set: { value in
                            store.updateSettings { settings in
                                settings.mcpAllowProcessingTools = value
                            }
                        }
                    )

                    CompactMcpToggleCard(
                        title: "Files & Export",
                        subtitle: store.settings.mcpAllowFileTools ? "Approved locations" : "Blocked",
                        systemImage: "folder",
                        isEnabled: store.settings.mcpServerEnabled,
                        isOn: Binding {
                            store.settings.mcpAllowFileTools
                        } set: { value in
                            store.updateSettings { settings in
                                settings.mcpAllowFileTools = value
                            }
                        }
                    )

                    CompactMcpToggleCard(
                        title: "Network & Models",
                        subtitle: store.settings.mcpAllowNetworkTools ? "Downloads enabled" : "Blocked",
                        systemImage: "network",
                        isEnabled: store.settings.mcpServerEnabled,
                        isOn: Binding {
                            store.settings.mcpAllowNetworkTools
                        } set: { value in
                            store.updateSettings { settings in
                                settings.mcpAllowNetworkTools = value
                            }
                        }
                    )

                    CompactMcpToggleCard(
                        title: "Destructive Actions",
                        subtitle: store.settings.mcpAllowDestructiveTools ? "Confirmation required" : "Blocked",
                        systemImage: "trash",
                        isEnabled: store.settings.mcpServerEnabled,
                        isOn: Binding {
                            store.settings.mcpAllowDestructiveTools
                        } set: { value in
                            store.updateSettings { settings in
                                settings.mcpAllowDestructiveTools = value
                            }
                        }
                    )
                }

                ReadOnlyRow(title: "Endpoint", value: "http://127.0.0.1:19790/sse")
                SecureInputRow(title: "Access Token", text: binding(\.mcpAccessToken))
                    .disabled(!store.settings.mcpServerEnabled)
                    .opacity(store.settings.mcpServerEnabled ? 1 : 0.5)

                HStack(spacing: 8) {
                    Button {
                        store.updateSettings { settings in
                            settings.mcpAccessToken = AppSettings.generateMcpAccessToken()
                        }
                    } label: {
                        Label("Regenerate Token", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SettingsSmallButtonStyle(primary: false))
                    .disabled(!store.settings.mcpServerEnabled)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(store.settings.mcpAccessToken, forType: .string)
                    } label: {
                        Label("Copy Token", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SettingsSmallButtonStyle(primary: store.settings.mcpServerEnabled))
                    .disabled(!store.settings.mcpServerEnabled || store.settings.mcpAccessToken.isEmpty)
                }
            }
        }
    }

    private var modelsTab: some View {
        SettingsScroll {
            SettingsSection(title: "Scan Local Models") {
                VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space8) {
                    Text("Already downloaded models in another VaniScript workspace or stored in common system folders? Run a fast native scan to discover and automatically connect them.")
                        .font(.subheadline)
                        .foregroundStyle(VaniScriptTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)

                    if store.isScanning {
                        HStack(spacing: VaniScriptTheme.Density.space8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Scanning system folders for Whisper and MLX models...")
                                .font(.subheadline)
                                .foregroundStyle(VaniScriptTheme.accent)
                        }
                        .padding(.vertical, 4)
                    } else {
                        Button {
                            store.scanForLocalModels()
                        } label: {
                            Label("Scan Computer for Local Models", systemImage: "magnifyingglass.and.waveform")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SettingsPrimaryButtonStyle())
                    }
                }
            }

            SettingsSection(title: "Core ML Transcription Models") {
                ForEach(store.settings.localAsrModels.keys.sorted(), id: \.self) { id in
                    if let model = store.settings.localAsrModels[id] {
                        ModelSettingsRow(
                            id: id,
                            model: model,
                            isActive: store.effectiveTranscriptionProvider == id && store.settings.isDownloadedLocalASRModelActive(id: id),
                            downloadUrl: modelDownloadUrl(id: id),
                            download: {
                                store.downloadLocalModel(id: id, isTranslation: false)
                            },
                            locate: {
                                store.locateLocalASRModel(id: id)
                            },
                            use: {
                                store.setTranscriptionProvider(id)
                            },
                            remove: {
                                store.removeLocalASRModel(id: id)
                            }
                        )
                    }
                }
            }

            SettingsSection(title: "MLX Translation Models") {
                ForEach(store.settings.localTranslationModels.keys.sorted(), id: \.self) { id in
                    if let model = store.settings.localTranslationModels[id] {
                        ModelSettingsRow(
                            id: id,
                            model: model,
                            isActive: store.settings.isDownloadedLocalTranslationModelActive(id: id),
                            downloadUrl: modelDownloadUrl(id: id),
                            download: {
                                store.downloadLocalModel(id: id, isTranslation: true)
                            },
                            locate: {
                                store.locateLocalTranslationModel(id: id)
                            },
                            use: {
                                store.setTranslationProvider(id)
                            },
                            remove: {
                                store.removeLocalTranslationModel(id: id)
                            }
                        )
                    }
                }
            }

            SettingsSection(title: "Native Runtime Info") {
                SettingsRow(title: "Application", value: AppIdentity.displayName)
                SettingsRow(title: "Bundle", value: AppIdentity.bundleIdentifier)
                SettingsRow(title: "Architecture", value: AppleSiliconRuntimePolicy.requiredArchitecture)
                SettingsRow(title: "macOS", value: AppIdentity.minimumMacOSVersion)
                SettingsRow(title: "Transcription Backend", value: NativeEngineCatalog.transcriptionBackend)
                SettingsRow(title: "LLM Backend", value: NativeEngineCatalog.polishingBackend)
            }
        }
        .onAppear {
            store.reconcileLocalModelStates()
        }
    }

    private var appearanceTab: some View {
        SettingsScroll {
            SettingsSection(title: "Appearance Options") {
                PickerRow(title: "Theme", selection: binding(\.theme), values: Theme.allCases)
                PickerRow(title: "Reading Font", selection: binding(\.fontFamily), values: FontFamily.allCases)
                PickerRow(title: "Font Size", selection: binding(\.fontSize), values: FontSize.allCases)
                SliderRow(title: "Font Scale", value: binding(\.fontScale), range: 0.5...3.0, format: "%.2f")
            }

            SettingsSection(title: "System Diagnostics & Logs") {
                PickerRow(title: "Log Level", selection: binding(\.logLevel), values: LogLevel.allCases)

                HStack(spacing: VaniScriptTheme.Density.space8) {
                    Button {
                        store.exportSystemLogs()
                    } label: {
                        Label("Export System Logs", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SettingsPrimaryButtonStyle())

                    Button {
                        AppLogger.shared.clearLogs()
                        store.statusMessage = "Logs cleared successfully."
                    } label: {
                        Label("Clear Logs", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SettingsPrimaryButtonStyle())
                }
                .padding(.top, 6)
            }
        }
    }

    private var uniqueCategories: [String] {
        let allCats = store.settings.glossary.compactMap(\.category).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return Array(Set(allCats)).sorted()
    }

    private var filteredAndSortedGlossary: [GlossaryEntry] {
        var entries = store.settings.glossary

        let query = glossarySearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            entries = entries.filter {
                $0.source.lowercased().contains(query) ||
                $0.translation.lowercased().contains(query) ||
                $0.variants.contains { $0.lowercased().contains(query) }
            }
        }

        if glossaryCategoryFilter != "all" {
            entries = entries.filter { $0.category == glossaryCategoryFilter }
        }

        switch glossarySortMode {
        case .newest:
            break
        case .oldest:
            entries.reverse()
        case .alphabetical:
            entries.sort { $0.source.localizedCaseInsensitiveCompare($1.source) == .orderedAscending }
        }

        return entries
    }

    private var glossaryTab: some View {
        SettingsScroll {
            SettingsSection(title: "Active Glossary Language") {
                HStack(spacing: VaniScriptTheme.Density.space8) {
                    Text("Select Target Language:")
                        .foregroundStyle(VaniScriptTheme.text2)
                        .font(.system(size: 13))

                    Picker("", selection: glossaryLanguageBinding) {
                        ForEach(glossaryLangs, id: \.self) { lang in
                            Text(lang == "same" ? "Original / Latin Fallback" : lang).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    Spacer()
                }
                .padding(.vertical, 4)
            }

            SettingsSection(title: "Add Glossary Entry") {
                TextInputRow(title: "Source", text: $glossarySource)
                TextInputRow(title: "Translation", text: $glossaryTranslation)
                TextInputRow(title: "Category", text: $glossaryCategory)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Variants")
                            .foregroundStyle(VaniScriptTheme.text2)
                            .frame(width: 140, alignment: .leading)
                        TextField("Comma-separated variations...", text: $glossaryVariants)
                            .textFieldStyle(.plain)
                            .foregroundStyle(VaniScriptTheme.text0)
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(VaniScriptTheme.input)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(VaniScriptTheme.controlBorder, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Text("Comma-separated spelling variations or incorrect spellings (e.g. Srila Prabhupada, Prabhupad)")
                        .font(.system(size: 10))
                        .foregroundStyle(VaniScriptTheme.text2.opacity(0.75))
                        .padding(.leading, 140)
                }
                .font(.system(size: 13))

                Button {
                    addGlossaryEntry()
                } label: {
                    Label("Add Term", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .disabled(glossarySource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            SettingsSection(title: "Glossary Backup") {
                HStack(spacing: VaniScriptTheme.Density.space8) {
                    Button {
                        importGlossaryJSON()
                    } label: {
                        Label("Import JSON", systemImage: "arrow.down.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SettingsSmallButtonStyle(primary: false))

                    Button {
                        exportGlossaryJSON()
                    } label: {
                        Label("Export JSON", systemImage: "arrow.up.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SettingsSmallButtonStyle(primary: false))
                }
            }

            SettingsSection(title: "Terms") {
                VStack(spacing: VaniScriptTheme.Density.space8) {
                    HStack(spacing: 8) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(VaniScriptTheme.text2)
                                .font(.system(size: 11))
                            TextField("Search glossary...", text: $glossarySearch)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                            if !glossarySearch.isEmpty {
                                Button {
                                    glossarySearch = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(VaniScriptTheme.text2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                        .frame(height: VaniScriptTheme.Density.controlHeightMD)
                        .background(VaniScriptTheme.input)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        Picker("Category", selection: $glossaryCategoryFilter) {
                            Text("All Categories").tag("all")
                            ForEach(uniqueCategories, id: \.self) { cat in
                                Text(cat).tag(cat)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 130)

                        Picker("Sort", selection: $glossarySortMode) {
                            ForEach(GlossarySortMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 110)
                    }
                    .padding(.bottom, 6)

                    if filteredAndSortedGlossary.isEmpty {
                        Text("No matching terms in glossary.")
                            .font(.system(size: 12))
                            .foregroundStyle(VaniScriptTheme.text2)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(filteredAndSortedGlossary) { entry in
                            GlossarySettingsRow(
                                entry: entry,
                                edit: {
                                    editingEntry = entry
                                },
                                delete: {
                                    store.updateSettings { settings in
                                        settings.glossary.removeAll { $0.id == entry.id }
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private var chunkingTab: some View {
        SettingsScroll {
            SettingsSection(title: "Audio Chunking Settings") {
                StepperRow(title: "Chunk Duration", value: binding(\.chunkDurationMin), range: 1...60, suffix: "min")
                PickerRow(title: "Slice Mode", selection: binding(\.sliceMode), values: SliceMode.allCases)
                StepperRow(title: "Silence Threshold", value: binding(\.silenceThreshDb), range: -60 ... -1, suffix: "dB")
                StepperRow(title: "Minimum Silence", value: binding(\.minSilenceMs), range: 100...3000, suffix: "ms")
            }
        }
    }

    private var transcriptionTab: some View {
        SettingsScroll {
            SettingsSection(title: "Default Languages") {
                TextInputRow(title: "Default Source", text: binding(\.defaultSourceLang))
                TextInputRow(title: "Default Target", text: binding(\.defaultTargetLang))
            }

            SettingsSection(title: "Default Engines") {
                HStack(spacing: VaniScriptTheme.Density.space8) {
                    Text("Default Transcription Engine")
                        .foregroundStyle(VaniScriptTheme.text2)
                        .font(.system(size: 13))
                        .frame(width: 220, alignment: .leading)

                    let transcriptionOptions = ProviderRegistry.availableTranscriptionProviders(settings: store.settings)
                    let cloudTranscription = transcriptionOptions.filter { $0.group == .cloud }
                    let localTranscription = transcriptionOptions.filter { $0.group == .local }

                    Picker("", selection: binding(\.transcriptionProvider)) {
                        if !cloudTranscription.isEmpty {
                            Section("Cloud") {
                                ForEach(cloudTranscription, id: \.id) { provider in
                                    Text(provider.label).tag(provider.id)
                                }
                            }
                        }
                        if !localTranscription.isEmpty {
                            Section("Local") {
                                ForEach(localTranscription, id: \.id) { provider in
                                    Text(provider.label).tag(provider.id)
                                }
                            }
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                HStack(spacing: VaniScriptTheme.Density.space8) {
                    Text("Default Translation Engine")
                        .foregroundStyle(VaniScriptTheme.text2)
                        .font(.system(size: 13))
                        .frame(width: 220, alignment: .leading)

                    let translationOptions = ProviderRegistry.availableTranslationProviders(settings: store.settings, targetLang: store.settings.defaultTargetLang).providers
                    let cloudTranslation = translationOptions.filter { $0.group == .cloud }
                    let localTranslation = translationOptions.filter { $0.group == .local }

                    Picker("", selection: binding(\.translationProvider)) {
                        if !cloudTranslation.isEmpty {
                            Section("Cloud") {
                                ForEach(cloudTranslation, id: \.id) { provider in
                                    Text(provider.label).tag(provider.id)
                                }
                            }
                        }
                        if !localTranslation.isEmpty {
                            Section("Local") {
                                ForEach(localTranslation, id: \.id) { provider in
                                    Text(provider.label).tag(provider.id)
                                }
                            }
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private var promptsTab: some View {
        HStack(spacing: VaniScriptTheme.Density.space8) {
            promptsSidebar

            Divider()
                .background(VaniScriptTheme.separator)

            promptEditor
        }
        .padding(.vertical, 8)
    }

    private var updatesTab: some View {
        SettingsScroll {
            SettingsSection(title: "Version & Status") {
                SettingsRow(title: "Installed Version", value: "v\(updateCoordinator.currentVersion) (Build \(updateCoordinator.currentBuildNumber))")
                SettingsRow(title: "Architecture", value: "Apple Silicon (arm64)")
                if let lastCheck = updateCoordinator.lastCheckDate {
                    SettingsRow(title: "Last Checked", value: lastCheck.formatted(date: .abbreviated, time: .shortened))
                } else {
                    SettingsRow(title: "Last Checked", value: "Never")
                }
                SettingsRow(title: "Update Channel", value: "Official Release (HTTPS Feed)")
            }

            SettingsSection(title: "Automatic Updates") {
                SettingsToggleRow(
                    title: "Check for Updates Automatically",
                    systemImage: "arrow.triangle.2.circlepath",
                    isOn: Binding(
                        get: { updateCoordinator.automaticallyChecksForUpdates },
                        set: { updateCoordinator.automaticallyChecksForUpdates = $0 }
                    )
                )
            }

            SettingsSection(title: "Check for Updates") {
                VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space12) {
                    HStack {
                        Button {
                            updateCoordinator.checkForUpdates()
                        } label: {
                            HStack(spacing: 6) {
                                if updateCoordinator.phase.isBusy {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                                Text("Check for Updates Now")
                            }
                        }
                        .buttonStyle(SettingsPrimaryButtonStyle())
                        .disabled(updateCoordinator.phase.isBusy)

                        Spacer()
                    }

                    switch updateCoordinator.phase {
                    case .idle:
                        EmptyView()
                    case .checking:
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking for updates…")
                                .font(.caption)
                                .foregroundStyle(VaniScriptTheme.text2)
                        }
                    case .upToDate:
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(VaniScriptTheme.green)
                            Text("VaniScript is up to date (v\(updateCoordinator.currentVersion)).")
                                .font(.body)
                                .foregroundStyle(VaniScriptTheme.text1)
                        }
                    case .available(let descriptor):
                        VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space8) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(VaniScriptTheme.accent)
                                Text("Update Available: v\(descriptor.displayVersion)")
                                    .font(.headline)
                                    .foregroundStyle(VaniScriptTheme.text0)
                                if !descriptor.humanReadableSize.isEmpty {
                                    Text("(\(descriptor.humanReadableSize))")
                                        .font(.caption)
                                        .foregroundStyle(VaniScriptTheme.text2)
                                }
                            }
                            if let notes = descriptor.releaseNotesDescription, !notes.isEmpty {
                                Text(notes)
                                    .font(.body)
                                    .foregroundStyle(VaniScriptTheme.text1)
                                    .lineLimit(4)
                            }
                            HStack(spacing: 8) {
                                Button("Install Update") {
                                    updateCoordinator.installUpdate()
                                }
                                .buttonStyle(SettingsPrimaryButtonStyle())

                                Button("Dismiss") {
                                    updateCoordinator.dismissUpdate()
                                }
                                .buttonStyle(SettingsSmallButtonStyle(primary: false))

                                Button("Skip This Version") {
                                    updateCoordinator.skipUpdate()
                                }
                                .buttonStyle(SettingsSmallButtonStyle(primary: false))
                            }
                        }
                        .padding(VaniScriptTheme.Density.space12)
                        .background(VaniScriptTheme.control)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .downloading(let descriptor, let progress, let received, let total):
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Downloading v\(descriptor.displayVersion)…")
                                .font(.headline)
                                .foregroundStyle(VaniScriptTheme.text0)
                            ProgressView(value: progress)
                            HStack {
                                Text("\(Int(progress * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(VaniScriptTheme.text2)
                                Spacer()
                                if total > 0 {
                                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(received), countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))")
                                        .font(.caption)
                                        .foregroundStyle(VaniScriptTheme.text2)
                                }
                                Button("Cancel") {
                                    updateCoordinator.cancelActiveOperation()
                                }
                                .buttonStyle(SettingsSmallButtonStyle(primary: false))
                            }
                        }
                    case .extracting(let descriptor, let progress):
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Extracting update v\(descriptor.displayVersion)…")
                                .font(.headline)
                                .foregroundStyle(VaniScriptTheme.text0)
                            ProgressView(value: progress > 0 ? progress : nil)
                        }
                    case .readyToInstall(let descriptor):
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(VaniScriptTheme.green)
                                Text("Ready to Install: v\(descriptor.displayVersion)")
                                    .font(.headline)
                                    .foregroundStyle(VaniScriptTheme.text0)
                            }
                            Text("The update package has been verified and extracted. Click Restart & Install to apply.")
                                .font(.caption)
                                .foregroundStyle(VaniScriptTheme.text2)
                            Button("Restart & Install Update") {
                                updateCoordinator.installUpdate()
                            }
                            .buttonStyle(SettingsPrimaryButtonStyle())
                        }
                    case .installing:
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Installing update and preparing relaunch…")
                                .font(.body)
                                .foregroundStyle(VaniScriptTheme.text1)
                        }
                    case .failed(let error):
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(VaniScriptTheme.red)
                                Text(error.message)
                                    .font(.headline)
                                    .foregroundStyle(VaniScriptTheme.red)
                            }
                            if !error.recoverySuggestion.isEmpty {
                                Text(error.recoverySuggestion)
                                    .font(.caption)
                                    .foregroundStyle(VaniScriptTheme.text2)
                            }
                            HStack(spacing: 8) {
                                Button("Retry") {
                                    updateCoordinator.retryLastAction()
                                }
                                .buttonStyle(SettingsSmallButtonStyle(primary: false))

                                Button("Dismiss") {
                                    updateCoordinator.clearError()
                                }
                                .buttonStyle(SettingsSmallButtonStyle(primary: false))
                            }
                        }
                        .padding(VaniScriptTheme.Density.space8)
                        .background(VaniScriptTheme.errorSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    if !updateCoordinator.isPublicKeyConfigured {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(VaniScriptTheme.warningText)
                                Text("Diagnostic Note: Development Build")
                                    .font(.caption.bold())
                                    .foregroundStyle(VaniScriptTheme.warningText)
                            }
                            Text("SUPublicEDKey is not configured in this bundle. In-app update verification requires a valid release signature.")
                                .font(.caption)
                                .foregroundStyle(VaniScriptTheme.text2)
                        }
                        .padding(VaniScriptTheme.Density.space8)
                        .background(VaniScriptTheme.warningSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            SettingsSection(title: "Feed Configuration") {
                ReadOnlyRow(
                    title: "Feed URL",
                    value: updateCoordinator.feedURL?.absoluteString ?? UpdateConfiguration.defaultFeedURL.absoluteString
                )
                ReadOnlyRow(
                    title: "Verification Key (SUPublicEDKey)",
                    value: updateCoordinator.isPublicKeyConfigured ? "Configured" : "Not configured (Dev mode)"
                )
            }
        }
    }

    private var promptsSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space12) {
                let stages = ["Transcription", "Translation", "Editing", "Shorts & Reels", "Export"]
                ForEach(stages, id: \.self) { stage in
                    let stageDefs = DefaultPrompts.definitions.filter { $0.stage == stage }
                    if !stageDefs.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(stage)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(VaniScriptTheme.accent)
                                .textCase(.uppercase)
                                .padding(.horizontal, 4)

                            ForEach(stageDefs) { def in
                                Button(action: {
                                    selectedPromptId = def.id
                                }) {
                                    HStack {
                                        Text(def.label)
                                            .font(.system(size: 12, weight: selectedPromptId == def.id ? .bold : .regular))
                                            .foregroundStyle(selectedPromptId == def.id ? VaniScriptTheme.onAccent : VaniScriptTheme.text0)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(selectedPromptId == def.id ? VaniScriptTheme.accent : Color.clear)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.trailing, 4)
            .background(ThinScrollbarTuner())
        }
        .frame(width: 180)
    }

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space8) {
            if let def = DefaultPrompts.definitions.first(where: { $0.id == selectedPromptId }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(def.label)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(VaniScriptTheme.text0)
                    Text(def.description)
                        .font(.system(size: 11))
                        .foregroundStyle(VaniScriptTheme.text2)
                        .lineLimit(2)
                }

                if !def.variables.isEmpty {
                    HStack(spacing: 6) {
                        Text("Variables:")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(VaniScriptTheme.text2)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(def.variables, id: \.self) { variable in
                                    Text("{{\(variable)}}")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(VaniScriptTheme.accent)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(VaniScriptTheme.control)
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                }

                let activePreset = store.settings.promptPresets[selectedPromptId] ?? PromptPresetSettings()

                HStack(spacing: VaniScriptTheme.Density.space8) {
                    Text("Slot")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VaniScriptTheme.text2)

                    Picker("", selection: Binding(
                        get: { activePreset.active },
                        set: { value in
                            store.updateSettings { settings in
                                if settings.promptPresets[selectedPromptId] == nil {
                                    settings.promptPresets[selectedPromptId] = PromptPresetSettings(active: value)
                                } else {
                                    settings.promptPresets[selectedPromptId]?.active = value
                                }
                            }
                        }
                    )) {
                        Text("Default").tag("default")
                        Text("Slot 1").tag("custom1")
                        Text("Slot 2").tag("custom2")
                        Text("Slot 3").tag("custom3")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 250)

                    Spacer()

                    if activePreset.active != "default" {
                        Button(action: {
                            store.updateSettings { settings in
                                if settings.promptPresets[selectedPromptId] == nil {
                                    var customMap = ["custom1": "", "custom2": "", "custom3": ""]
                                    customMap[activePreset.active] = def.defaultText
                                    settings.promptPresets[selectedPromptId] = PromptPresetSettings(active: activePreset.active, custom: customMap)
                                } else {
                                    settings.promptPresets[selectedPromptId]?.custom[activePreset.active] = def.defaultText
                                }
                            }
                        }) {
                            Label("Copy Default", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(SettingsSmallButtonStyle(primary: false))
                    }
                }

                if activePreset.active == "default" {
                    TextEditor(text: .constant(def.defaultText))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(VaniScriptTheme.text1)
                        .padding(6)
                        .background(VaniScriptTheme.surfaceSubtle)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(VaniScriptTheme.controlBorder, lineWidth: 1))
                        .disabled(true)
                } else {
                    TextEditor(text: Binding(
                        get: { activePreset.custom[activePreset.active] ?? "" },
                        set: { value in
                            store.updateSettings { settings in
                                if settings.promptPresets[selectedPromptId] == nil {
                                    var customMap = ["custom1": "", "custom2": "", "custom3": ""]
                                    customMap[activePreset.active] = value
                                    settings.promptPresets[selectedPromptId] = PromptPresetSettings(active: activePreset.active, custom: customMap)
                                } else {
                                    settings.promptPresets[selectedPromptId]?.custom[activePreset.active] = value
                                }
                            }
                        }
                    ))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(VaniScriptTheme.text0)
                    .padding(6)
                    .background(VaniScriptTheme.input)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(VaniScriptTheme.controlBorder, lineWidth: 1))
                }
            } else {
                Spacer()
                Text("Select a prompt from the sidebar to edit")
                    .font(.system(size: 13))
                    .foregroundStyle(VaniScriptTheme.text2)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addCustomProvider() {
        let label = customLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseUrl = customBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = customApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelName = customModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let inputCost = Double(customInputCost.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
        let outputCost = Double(customOutputCost.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
        let budgetLimit = Double(customBudgetLimit.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0

        guard !label.isEmpty, !baseUrl.isEmpty else { return }

        let newProvider = CustomCloudProvider(
            label: label,
            baseUrl: baseUrl,
            apiKey: apiKey,
            modelName: modelName.isEmpty ? "default" : modelName,
            inputCostPerMillion: inputCost,
            outputCostPerMillion: outputCost,
            budgetLimitUsd: budgetLimit
        )

        store.updateSettings { settings in
            settings.customCloudProviders.append(newProvider)
        }

        customLabel = ""
        customBaseUrl = ""
        customApiKey = ""
        customModelName = ""
        customInputCost = ""
        customOutputCost = ""
        customBudgetLimit = ""
    }

    // A6: estimateCost/formatTokens moved into UsageStatisticsView (per-usage-key
    // pricing); the old "Cloud Usage Statistics" section that used them is gone.

    private var mcpConnectionSummary: String {
        guard store.settings.mcpServerEnabled else {
            return "Disabled"
        }
        let connected = store.mcpActiveClients
            .filter { McpAgentProfileCatalog.normalizedProfileID($0.profileID) == $0.profileID }
            .map(\.displayName)
        guard !connected.isEmpty else {
            return "Ready"
        }
        return "Connected: \(connected.joined(separator: ", "))"
    }

    private var mcpConnectionColor: Color {
        guard store.settings.mcpServerEnabled else {
            return VaniScriptTheme.red
        }
        return store.mcpActiveClients.isEmpty ? VaniScriptTheme.text2 : VaniScriptTheme.green
    }

    private func mcpConnectionState(for profile: McpAgentProfile) -> McpAgentConnectionState {
        let isConnected = mcpActiveClient(for: profile) != nil
        return McpAgentConnectionState.resolve(
            isServerEnabled: store.settings.mcpServerEnabled,
            isConnected: isConnected
        )
    }

    private func mcpActiveClient(for profile: McpAgentProfile) -> McpActiveClient? {
        store.mcpActiveClients.first { $0.profileID == profile.id.rawValue }
    }

    private func copyMcpSetup(for profile: McpAgentProfile) {
        let setupText = McpAgentProfileCatalog.setupText(
            for: profile.id,
            accessToken: store.settings.mcpAccessToken,
            bridgeScriptPath: McpAgentProfileCatalog.defaultBridgeScriptPath
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(setupText, forType: .string)
        store.statusMessage = "\(profile.displayName) MCP setup copied."
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding {
            store.settings[keyPath: keyPath]
        } set: { value in
            store.updateSettings { settings in
                settings[keyPath: keyPath] = value
            }
        }
    }

    private func addGlossaryEntry() {
        let source = glossarySource.trimmingCharacters(in: .whitespacesAndNewlines)
        let translation = glossaryTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        var translations: [String: String] = [:]
        if !translation.isEmpty {
            translations[store.workflow.targetLang] = translation
            if store.workflow.targetLang.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "russian" {
                translations["Russian"] = translation
            }
        }

        let parsedVariants = glossaryVariants
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let entry = GlossaryEntry(
            id: UUID().uuidString,
            variants: parsedVariants,
            source: source,
            translation: translation,
            category: glossaryCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : glossaryCategory,
            translations: translations,
            remember: true,
            createdAt: now,
            updatedAt: now
        )
        store.updateSettings { settings in
            settings.glossary.insert(entry, at: 0)
        }
        glossarySource = ""
        glossaryTranslation = ""
        glossaryCategory = ""
        glossaryVariants = ""
    }

    private func exportGlossaryJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "vaniscript-glossary.json"
        panel.message = "Export VaniScript Glossary"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try JSONEncoder().encode(store.settings.glossary)
            try data.write(to: url)
        } catch {
            print("Failed to export glossary: \(error.localizedDescription)")
        }
    }

    private func importGlossaryJSON() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a VaniScript Glossary JSON file"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let imported = try JSONDecoder().decode([GlossaryEntry].self, from: data)

            store.updateSettings { settings in
                var current = settings.glossary
                for entry in imported {
                    if let index = current.firstIndex(where: { $0.id == entry.id || $0.source.lowercased() == entry.source.lowercased() }) {
                        current[index] = entry
                    } else {
                        current.append(entry)
                    }
                }
                settings.glossary = current
            }
        } catch {
            print("Failed to import glossary: \(error.localizedDescription)")
        }
    }

    private let glossaryLangs = ["same", "Russian", "Czech", "French", "German", "Polish", "English", "Hindi", "Spanish", "Swedish", "Italian", "Portuguese", "Dutch"]

    private var glossaryLanguageBinding: Binding<String> {
        Binding {
            store.workflow.targetLang
        } set: { value in
            store.setTargetLanguage(value)
        }
    }
}


private struct SettingsScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space12) {
                content
            }
            .padding(.top, 10)
            .padding(.bottom, 18)
            .background(ThinScrollbarTuner())
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    var headerAccessory: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(VaniScriptTheme.accent)
                    .textCase(.uppercase)
                Spacer()
                if let accessory = headerAccessory {
                    accessory
                }
            }
            VStack(spacing: 8) {
                content
            }
        }
        .padding(14)
        .background(VaniScriptTheme.control)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(VaniScriptTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusMD, style: .continuous))
    }
}

private struct SettingsRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(VaniScriptTheme.text2)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(VaniScriptTheme.text0)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(height: VaniScriptTheme.Density.controlHeightLG)
        .background(VaniScriptTheme.control)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(VaniScriptTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous))
    }
}

private struct TextInputRow: View {
    let title: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(VaniScriptTheme.text2)
                .frame(width: 140, alignment: .leading)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(VaniScriptTheme.text0)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(VaniScriptTheme.input)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(VaniScriptTheme.controlBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .font(.system(size: 13))
    }
}

private struct SecureInputRow: View {
    let title: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(VaniScriptTheme.text2)
                .frame(width: 140, alignment: .leading)
            SecureField("", text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(VaniScriptTheme.text0)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(VaniScriptTheme.input)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(VaniScriptTheme.controlBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .font(.system(size: 13))
    }
}

// A3: card for the currently selected cloud provider in the API & Usage tab.
// Renders the provider's key / budget / usage toggles compactly, reusing the
// existing settings rows. Behavior for existing providers (Gemini/OpenAI/Anthropic)
// is preserved 1:1; new providers (Qwen/OpenRouter/Ollama Cloud) get the full A5
// card (key + validation + models + honest capability toggles). Custom is
// handled separately by SettingsView.customProvidersSection.
private struct ProviderCardView: View {
    @EnvironmentObject private var store: WorkflowStore
    let descriptor: CloudProviderDescriptor
    @State private var validationStatus: CloudKeyValidationStatus = .idle
    @State private var fetchedBalance: Double? = nil

    var body: some View {
        switch descriptor.id {
        case CloudProviderCatalog.geminiID:
            geminiCard
        case CloudProviderCatalog.openaiID:
            openaiCard
        case CloudProviderCatalog.anthropicID:
            anthropicCard
        case CloudProviderCatalog.qwenID,
             CloudProviderCatalog.openrouterID,
             CloudProviderCatalog.ollamaCloudID:
            // A5: full key + model + toggles card (stub retired).
            cloudProviderCard
        default:
            comingSoonCard
        }
    }

    private var isValidKey: Bool {
        validationStatus == .valid
    }

    // MARK: - Gemini (behavior 1:1 with the previous "Google Gemini" section)
    private var geminiCard: some View {
        let isTranscription = store.settings.transcriptionProvider == "gemini-cloud"
        let isTranslation = store.settings.translationProvider == "gemini-cloud"
        return SettingsSection(title: descriptor.label, headerAccessory: AnyView(
            HStack(spacing: 4) {
                if isTranscription { statusBadge("Transcribing") }
                if isTranslation { statusBadge("Translation") }
            }
        )) {
            VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space8) {
                Text("Google Gemini API keys for cloud transcription, translation, and editing. When one key hits quota, VaniScript rotates to the next enabled key automatically.")
                    .font(.system(size: 11))
                    .foregroundStyle(VaniScriptTheme.text2)
                    .padding(.bottom, 2)

                GeminiAPIKeysEditor(
                    bank: geminiKeyBankBinding,
                    getApiKeyURL: descriptor.getApiKeyURL
                )
                CloudKeyModelRow(
                    descriptor: descriptor,
                    apiKey: store.settings.geminiKey,
                    selectedModel: binding(\.geminiTextModel),
                    fallbackModel: "gemini-2.5-flash",
                    validationStatus: $validationStatus,
                    customLeadingView: AnyView(
                        stackedProviderToggles(
                            providerID: "gemini-cloud",
                            isTranscription: isTranscription,
                            isTranslation: isTranslation,
                            isValidKey: isValidKey
                        )
                    )
                )
                SliderRow(title: "Gemini Budget", value: binding(\.geminiBudgetUsd), range: 0...200, format: "$%.0f")
            }
        }
    }

    // MARK: - OpenAI (behavior 1:1 with the previous "OpenAI" section)
    private var openaiCard: some View {
        let isTranscription = store.settings.transcriptionProvider == "gpt-cloud"
        let isTranslation = store.settings.translationProvider == "gpt-cloud"
        return SettingsSection(title: descriptor.label, headerAccessory: AnyView(
            HStack(spacing: 4) {
                if isTranscription { statusBadge("Transcribing") }
                if isTranslation { statusBadge("Translation") }
            }
        )) {
            VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space8) {
                Text("OpenAI API key for cloud transcription, translation, and editing.")
                    .font(.system(size: 11))
                    .foregroundStyle(VaniScriptTheme.text2)
                    .padding(.bottom, 2)

                ApiKeyInputRow(title: "OpenAI Key", text: binding(\.openaiKey), urlString: descriptor.getApiKeyURL)
                CloudKeyModelRow(
                    descriptor: descriptor,
                    apiKey: store.settings.openaiKey,
                    selectedModel: binding(\.openaiTextModel),
                    fallbackModel: "gpt-4o-mini",
                    validationStatus: $validationStatus,
                    customLeadingView: AnyView(
                        stackedProviderToggles(
                            providerID: "gpt-cloud",
                            isTranscription: isTranscription,
                            isTranslation: isTranslation,
                            isValidKey: isValidKey
                        )
                    )
                )
                SliderRow(title: "OpenAI Budget", value: binding(\.openaiBudgetUsd), range: 0...200, format: "$%.0f")
            }
        }
    }

    // MARK: - Anthropic (key + ReadOnly model; workflow route is CPS / OBS-005)
    private var anthropicCard: some View {
        SettingsSection(title: descriptor.label) {
            VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space8) {
                Text("Anthropic API key for cloud translation and editing. Workflow routing is being stabilized (OBS-005).")
                    .font(.system(size: 11))
                    .foregroundStyle(VaniScriptTheme.text2)
                    .padding(.bottom, 2)

                ApiKeyInputRow(title: "Anthropic Key", text: binding(\.anthropicKey), urlString: descriptor.getApiKeyURL)
                ReadOnlyRow(title: "Text Model", value: descriptor.defaultTextModel)
            }
        }
    }

    // MARK: - Qwen / OpenRouter / Ollama Cloud (A5: full integration card)
    private var cloudProviderCard: some View {
        let engineID = descriptor.id
        let isTranscription = store.settings.transcriptionProvider == engineID
        let isTranslation = store.settings.translationProvider == engineID
        let isExceeded = ProviderRegistry.isBudgetExceeded(providerID: engineID, settings: store.settings)
        let spent = ProviderRegistry.providerSpent(providerID: engineID, settings: store.settings)
        let isEnabled = isValidKey && !isExceeded

        return SettingsSection(title: descriptor.label, headerAccessory: AnyView(
            HStack(spacing: 4) {
                if isTranscription { statusBadge("Transcribing") }
                if isTranslation { statusBadge("Translation") }
            }
        )) {
            VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space8) {
                Text("\(descriptor.label) API key for cloud translation and editing.")
                    .font(.system(size: 11))
                    .foregroundStyle(VaniScriptTheme.text2)
                    .padding(.bottom, 2)

                if let keyPath = apiKeyPath {
                    ApiKeyInputRow(text: binding(keyPath), urlString: descriptor.getApiKeyURL)
                }
                if descriptor.id == CloudProviderCatalog.ollamaCloudID {
                    TextInputRow(title: "Base URL", text: binding(\.ollamaCloudBaseUrl))
                }

                if descriptor.balanceKind == .openrouterCredits || descriptor.balanceKind == .ollamaPlan {
                    CloudBalanceRow(
                        descriptor: descriptor,
                        apiKey: apiKeyPath.map { store.settings[keyPath: $0] } ?? "",
                        onBalanceFetched: { remaining in
                            self.fetchedBalance = remaining
                            if let remaining, remaining > 0, let budgetPath = budgetPath {
                                let curr = store.settings[keyPath: budgetPath]
                                if curr == 0 || curr > remaining {
                                    store.updateSettings { settings in
                                        settings[keyPath: budgetPath] = remaining
                                    }
                                }
                            }
                        }
                    )
                }

                if isExceeded, let budgetPath = budgetPath {
                    let limit = store.settings[keyPath: budgetPath]
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(VaniScriptTheme.red)
                        Text("Budget limit reached (\(String(format: "$%.2f", spent)) spent of \(String(format: "$%.2f", limit)) budget). \(descriptor.label) processing is locked.")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(VaniScriptTheme.red)
                    }
                    .padding(8)
                    .background(VaniScriptTheme.red.opacity(0.1))
                    .cornerRadius(6)
                }

                if descriptor.id == CloudProviderCatalog.openrouterID {
                    if let budgetPath = budgetPath {
                        let maxVal = fetchedBalance ?? 50.0
                        let rangeLimit = max(maxVal, 1.0)
                        let formatStr = fetchedBalance != nil ? "$%.2f" : "$%.0f"
                        let maxLabelStr = fetchedBalance != nil ? String(format: "$%.2f balance", maxVal) : nil

                        SliderRow(
                            title: "\(descriptor.label) Budget",
                            value: binding(budgetPath),
                            range: 0...rangeLimit,
                            format: formatStr,
                            maxLabel: maxLabelStr
                        )
                    }

                    // Block 1: Transcription Model & Activation Section
                    let transcriptionModel = store.settings.transcriptionModel(for: engineID)
                    let sttSupported = CloudProviderCatalog.supportsTranscription(providerID: engineID, modelID: transcriptionModel)
                    let activeTranscription = isTranscription && sttSupported

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(activeTranscription ? VaniScriptTheme.accent : VaniScriptTheme.text2)
                                Text("Audio Transcription Section")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(activeTranscription ? VaniScriptTheme.text0 : VaniScriptTheme.text2)
                            }
                            Spacer()
                            if activeTranscription {
                                statusBadge("Active Transcribing")
                            }
                        }

                        CloudKeyModelRow(
                            descriptor: descriptor,
                            apiKey: store.settings[keyPath: apiKeyPath ?? \.openrouterApiKey],
                            selectedModel: binding(\.openrouterTranscriptionModel),
                            fallbackModel: "x-ai/grok-stt-1.0",
                            validationStatus: $validationStatus,
                            initialCategory: .transcribing,
                            customLeadingView: AnyView(
                                Button {
                                    store.updateSettings { settings in
                                        let fallback = ProviderRegistry.availableTranscriptionProviders(settings: settings).first(where: { $0.id != engineID })?.id ?? ""
                                        settings.transcriptionProvider = isTranscription ? fallback : engineID
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: activeTranscription ? "checkmark.circle.fill" : "circle")
                                        Text(activeTranscription ? "Used for Transcribing" : "Use for Transcribing")
                                            .font(.system(size: 11, weight: .medium))
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(width: 142, alignment: .leading)
                                }
                                .buttonStyle(SettingsSmallButtonStyle(primary: activeTranscription))
                                .disabled(!isEnabled || !sttSupported)
                                .help(!sttSupported ? "Model does not support audio transcription." : "")
                            )
                        )

                        if !sttSupported {
                            Text("Model '\(transcriptionModel)' does not support audio transcription.")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(VaniScriptTheme.red)
                        }
                    }
                    .padding(10)
                    .background(activeTranscription ? VaniScriptTheme.accent.opacity(0.08) : VaniScriptTheme.surfaceSubtle)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(activeTranscription ? VaniScriptTheme.accent : VaniScriptTheme.border, lineWidth: activeTranscription ? 1.5 : 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Block 2: Translation Model & Activation Section
                    let translationModel = store.settings.translationModel(for: engineID)
                    let textSupported = CloudProviderCatalog.supportsTranslation(providerID: engineID, modelID: translationModel)
                    let activeTranslation = isTranslation && textSupported

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "character.bubble")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(activeTranslation ? VaniScriptTheme.accent : VaniScriptTheme.text2)
                                Text("Text Translation Section")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(activeTranslation ? VaniScriptTheme.text0 : VaniScriptTheme.text2)
                            }
                            Spacer()
                            if activeTranslation {
                                statusBadge("Active Translation")
                            }
                        }

                        CloudKeyModelRow(
                            descriptor: descriptor,
                            apiKey: store.settings[keyPath: apiKeyPath ?? \.openrouterApiKey],
                            selectedModel: binding(\.openrouterTranslationModel),
                            fallbackModel: "google/gemini-2.5-flash",
                            validationStatus: $validationStatus,
                            initialCategory: .translation,
                            customLeadingView: AnyView(
                                Button {
                                    store.updateSettings { settings in
                                        let fallback = ProviderRegistry.availableTranslationProviders(settings: settings, targetLang: store.workflow.targetLang).providers.first(where: { $0.id != engineID })?.id ?? ""
                                        settings.translationProvider = isTranslation ? fallback : engineID
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: activeTranslation ? "checkmark.circle.fill" : "circle")
                                        Text(activeTranslation ? "Used for Translation" : "Use for Translation")
                                            .font(.system(size: 11, weight: .medium))
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(width: 142, alignment: .leading)
                                }
                                .buttonStyle(SettingsSmallButtonStyle(primary: activeTranslation))
                                .disabled(!isEnabled || !textSupported)
                                .help(!textSupported ? "Model does not support text translation." : "")
                            )
                        )

                        if !textSupported {
                            Text("Model '\(translationModel)' is audio-only and does not support text translation.")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(VaniScriptTheme.red)
                        }
                    }
                    .padding(10)
                    .background(activeTranslation ? VaniScriptTheme.accent.opacity(0.08) : VaniScriptTheme.surfaceSubtle)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(activeTranslation ? VaniScriptTheme.accent : VaniScriptTheme.border, lineWidth: activeTranslation ? 1.5 : 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    let selectedModel = textModelPath.map { store.settings[keyPath: $0] } ?? descriptor.defaultTextModel
                    let supportsTranscription = CloudProviderCatalog.supportsTranscription(providerID: engineID, modelID: selectedModel)

                    if let modelPath = textModelPath {
                        CloudKeyModelRow(
                            descriptor: descriptor,
                            apiKey: store.settings[keyPath: apiKeyPath ?? \.geminiKey],
                            selectedModel: binding(modelPath),
                            fallbackModel: descriptor.defaultTextModel,
                            validationStatus: $validationStatus,
                            customLeadingView: AnyView(
                                cloudProviderToggles(
                                    engineID: engineID,
                                    isTranscription: isTranscription,
                                    isTranslation: isTranslation,
                                    hasKey: isValidKey,
                                    supportsTranscription: supportsTranscription
                                )
                            )
                        )
                    }

                    if !supportsTranscription {
                        Text("Transcribing is unavailable for this provider/model (no verified audio transcription endpoint).")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(VaniScriptTheme.text2)
                    }

                    if let budgetPath = budgetPath {
                        let maxVal = fetchedBalance ?? 50.0
                        let rangeLimit = max(maxVal, 1.0)
                        let formatStr = fetchedBalance != nil ? "$%.2f" : "$%.0f"
                        let maxLabelStr = fetchedBalance != nil ? String(format: "$%.2f balance", maxVal) : nil

                        SliderRow(
                            title: "\(descriptor.label) Budget",
                            value: binding(budgetPath),
                            range: 0...rangeLimit,
                            format: formatStr,
                            maxLabel: maxLabelStr
                        )
                    }
                }
            }
        }
    }

    /// A5 honesty toggles for Qwen / Ollama (and shared Gemini/OpenAI stacked layout).
    /// Transcribing is disabled when `!supportsTranscription`; Translation only needs a key.
    private func cloudProviderToggles(
        engineID: String,
        isTranscription: Bool,
        isTranslation: Bool,
        hasKey: Bool,
        supportsTranscription: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                store.updateSettings { settings in
                    let fallback = ProviderRegistry.availableTranscriptionProviders(settings: settings).first(where: { $0.id != engineID })?.id ?? ""
                    settings.transcriptionProvider = isTranscription ? fallback : engineID
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isTranscription ? "checkmark.circle.fill" : "circle")
                    Text(isTranscription ? "Used for Transcribing" : "Use for Transcribing")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(width: 142, alignment: .leading)
            }
            .buttonStyle(SettingsSmallButtonStyle(primary: isTranscription))
            .disabled(!hasKey || !supportsTranscription)
            .help(supportsTranscription
                  ? "Use this provider for audio transcription."
                  : "No verified audio transcription endpoint for this provider/model.")

            Button {
                store.updateSettings { settings in
                    let fallback = ProviderRegistry.availableTranslationProviders(settings: settings, targetLang: store.workflow.targetLang).providers.first(where: { $0.id != engineID })?.id ?? ""
                    settings.translationProvider = isTranslation ? fallback : engineID
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isTranslation ? "checkmark.circle.fill" : "circle")
                    Text(isTranslation ? "Used for Translation" : "Use for Translation")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(width: 142, alignment: .leading)
            }
            .buttonStyle(SettingsSmallButtonStyle(primary: isTranslation))
            .disabled(!hasKey)
        }
        .frame(width: 170, alignment: .leading)
    }

    /// Compact stacked toggles for Gemini/OpenAI (always supports transcription).
    private func stackedProviderToggles(
        providerID: String,
        isTranscription: Bool,
        isTranslation: Bool,
        isValidKey: Bool,
        supportsTranscription: Bool = true
    ) -> some View {
        cloudProviderToggles(
            engineID: providerID,
            isTranscription: isTranscription,
            isTranslation: isTranslation,
            hasKey: isValidKey,
            supportsTranscription: supportsTranscription
        )
    }

    // A5: settings keyPath for the provider's text model (written by CloudKeyModelRow).
    private var textModelPath: WritableKeyPath<AppSettings, String>? {
        switch descriptor.id {
        case CloudProviderCatalog.qwenID: return \.qwenCloudModel
        case CloudProviderCatalog.openrouterID: return \.openrouterModel
        case CloudProviderCatalog.ollamaCloudID: return \.ollamaCloudModel
        default: return nil
        }
    }

    // A5: budget keyPath where AppSettings has one (Ollama Cloud is plan-based — none).
    private var budgetPath: WritableKeyPath<AppSettings, Double>? {
        switch descriptor.id {
        case CloudProviderCatalog.qwenID: return \.qwenBudgetUsd
        case CloudProviderCatalog.openrouterID: return \.openrouterBudgetUsd
        default: return nil
        }
    }

    // MARK: - Fallback card for ids without a dedicated card (defensive only)
    private var comingSoonCard: some View {
        SettingsSection(title: descriptor.label) {
            VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space8) {
                Text("\(descriptor.label) support is coming soon. You can save your API key now; model selection and usage tracking arrive in a later update.")
                    .font(.system(size: 11))
                    .foregroundStyle(VaniScriptTheme.text2)
                    .padding(.bottom, 2)

                if let keyPath = apiKeyPath {
                    ApiKeyInputRow(title: "\(descriptor.label) Key", text: binding(keyPath), urlString: descriptor.getApiKeyURL)
                }
            }
        }
    }

    // Key storage keyPath for the not-yet-wired providers.
    private var apiKeyPath: WritableKeyPath<AppSettings, String>? {
        switch descriptor.id {
        case CloudProviderCatalog.qwenID: return \.qwenApiKey
        case CloudProviderCatalog.openrouterID: return \.openrouterApiKey
        case CloudProviderCatalog.ollamaCloudID: return \.ollamaCloudApiKey
        default: return nil
        }
    }

    // Two-way binding into AppSettings via the shared store (matches SettingsView).
    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding {
            store.settings[keyPath: keyPath]
        } set: { value in
            store.updateSettings { settings in
                settings[keyPath: keyPath] = value
            }
        }
    }

    private var geminiKeyBankBinding: Binding<GeminiAPIKeyBank> {
        Binding {
            store.settings.geminiKeyBank
        } set: { bank in
            store.updateSettings { settings in
                settings.geminiKeyBank = bank
            }
        }
    }

    private func statusBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(Color.dynamic(light: .white, dark: Color(red: 10/255, green: 10/255, blue: 18/255)))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(VaniScriptTheme.green)
            .cornerRadius(4)
    }
}

private struct GeminiAPIKeysEditor: View {
    @Binding var bank: GeminiAPIKeyBank
    let getApiKeyURL: String
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(bank.entries.count > 1 ? "API Keys (\(bank.configuredCount)/\(GeminiAPIKeyBank.maxKeys))" : "API Key")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VaniScriptTheme.text2)

                Spacer()

                if bank.entries.count > 1 {
                    Menu {
                        Button("Enable All Keys") {
                            bank.enableAll()
                        }
                        Divider()
                        ForEach(Array(bank.entries.indices), id: \.self) { index in
                            let preview = String(bank.cleanKey(at: index).suffix(6))
                            Button("Test Only Key #\(index + 1)" + (preview.isEmpty ? "" : " (…\(preview))")) {
                                bank.disableAllExcept(at: index)
                            }
                        }
                    } label: {
                        Label("Manage Keys", systemImage: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .help("Enable all keys or isolate one key for testing.")
                }

                if bank.entries.count < GeminiAPIKeyBank.maxKeys {
                    Button {
                        if bank.entries.isEmpty {
                            bank.entries = ["", ""]
                        } else {
                            bank.addKey("")
                        }
                    } label: {
                        Label("Add Key", systemImage: "plus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .help("Add another Gemini API key for automatic quota rotation (up to 10).")
                }

                Button {
                    if let url = URL(string: getApiKeyURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Get API Key", systemImage: "arrow.up.right.square")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
            }

            let keyCount = max(1, bank.entries.count)
            ForEach(0..<keyCount, id: \.self) { index in
                let disabled = bank.isDisabled(at: index)
                HStack(spacing: 8) {
                    Button {
                        ensureSlot(index)
                        bank.toggleDisabled(at: index)
                    } label: {
                        Image(systemName: disabled ? "circle.slash" : "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(disabled ? VaniScriptTheme.text2.opacity(0.55) : VaniScriptTheme.green)
                    }
                    .buttonStyle(.plain)
                    .help(disabled ? "Key disabled" : "Key active")

                    Group {
                        if isRevealed {
                            TextField(keyPlaceholder(at: index), text: keyBinding(at: index))
                        } else {
                            SecureField(keyPlaceholder(at: index), text: keyBinding(at: index))
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(VaniScriptTheme.text0)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(VaniScriptTheme.input)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(VaniScriptTheme.controlBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .opacity(disabled ? 0.5 : 1)

                    if disabled {
                        Text("Disabled")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(VaniScriptTheme.text2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VaniScriptTheme.control, in: RoundedRectangle(cornerRadius: 4))
                    }

                    Button {
                        isRevealed.toggle()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(VaniScriptTheme.text2)
                    }
                    .buttonStyle(.plain)
                    .help(isRevealed ? "Hide API keys" : "Show API keys")

                    if keyCount > 1 {
                        Button {
                            bank.removeKey(at: index)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.red.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                        .help("Remove API key")
                    }
                }
            }
        }
    }

    private func keyPlaceholder(at index: Int) -> String {
        if max(1, bank.entries.count) == 1 {
            return "Enter Gemini API key"
        }
        return index == 0 ? "Primary key #1" : "API key #\(index + 1)"
    }

    private func ensureSlot(_ index: Int) {
        if bank.entries.isEmpty {
            bank.entries = [""]
        }
        while bank.entries.count <= index && bank.entries.count < GeminiAPIKeyBank.maxKeys {
            bank.addKey("")
        }
    }

    private func keyBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                if bank.entries.indices.contains(index) {
                    return bank.cleanKey(at: index)
                }
                return ""
            },
            set: { newValue in
                if bank.entries.isEmpty {
                    bank.entries = [newValue]
                } else if bank.entries.indices.contains(index) {
                    bank.updateKey(newValue, at: index)
                } else if bank.entries.count < GeminiAPIKeyBank.maxKeys {
                    bank.addKey(newValue)
                }
            }
        )
    }
}

private struct ApiKeyInputRow: View {
    var title: String = "API Key"
    @Binding var text: String
    let urlString: String
    var showTitle: Bool = true
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 8) {
            if showTitle && !title.isEmpty {
                Text(title)
                    .foregroundStyle(VaniScriptTheme.text2)
                    .frame(width: 170, alignment: .leading)
            } else {
                Spacer()
                    .frame(width: 170)
            }
            HStack(spacing: 6) {
                Group {
                    if isRevealed {
                        TextField("", text: $text)
                    } else {
                        SecureField("", text: $text)
                    }
                }
                .textFieldStyle(.plain)
                .foregroundStyle(VaniScriptTheme.text0)

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(VaniScriptTheme.text2)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isRevealed ? "Hide API key" : "Show API key")
                .accessibilityLabel(isRevealed ? "Hide API key" : "Show API key")
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(VaniScriptTheme.input)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(VaniScriptTheme.controlBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                if let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                    Text("Get API Key")
                }
            }
            .buttonStyle(SettingsSmallButtonStyle(primary: false))
        }
        .font(.system(size: 13))
    }
}

private struct ReadOnlyRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(VaniScriptTheme.text2)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .foregroundStyle(VaniScriptTheme.text1)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 34)
                .background(VaniScriptTheme.input)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(VaniScriptTheme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .font(.system(size: 13))
    }
}

// A7 (§11): real-balance row for a cloud provider. Shared between the provider cards
// (SettingsView) and UsageStatisticsView, so it is `internal` (module-visible), not
// `private`. Honesty rules baked in:
//   - Only fetches for `.openrouterCredits` / `.ollamaPlan`; any other kind renders
//     nothing and never touches the network.
//   - OpenRouter → "$X remaining / $Y limit"; Ollama → plan label. No fake "$".
//   - Error / no data → quiet: shows a subtle "estimated only" hint, never a crash.
// Lazy: loads in `.task(id: apiKey)`; Refresh forces a cache-bypassing reload.
struct CloudBalanceRow: View {
    let descriptor: CloudProviderDescriptor
    let apiKey: String
    var showTitleLabel: Bool = true
    var onBalanceFetched: ((Double?) -> Void)? = nil

    @State private var info: BalanceInfo = .unavailable
    @State private var isLoading = false
    @State private var service = CloudBalanceService()

    private var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if showTitleLabel {
                Text("Balance")
                    .foregroundStyle(VaniScriptTheme.text2)
                    .frame(width: 140, alignment: .leading)
            }

            HStack(spacing: 6) {
                Text(displayText)
                    .foregroundStyle(!showTitleLabel ? balanceColor : VaniScriptTheme.text1)
                    .font(.system(size: !showTitleLabel ? 16 : 12, weight: .bold, design: .monospaced))
                    .lineLimit(1)

                if isLoading {
                    ProgressView().controlSize(.small)
                }

                Spacer(minLength: 0)

                Button {
                    Task { await load(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(SettingsSmallButtonStyle(primary: false))
                .disabled(isLoading)
                .help("Refresh balance")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 13))
        .task(id: apiKey) {
            await load(force: false)
        }
    }

    private var balanceColor: Color {
        switch info {
        case let .usd(remaining, _):
            if remaining <= 0 {
                return VaniScriptTheme.red
            } else if remaining <= 5.0 {
                return VaniScriptTheme.accent
            } else {
                return VaniScriptTheme.green
            }
        default:
            return VaniScriptTheme.text0
        }
    }

    /// Human-readable balance line by `BalanceInfo` case (§11 wording).
    private var displayText: String {
        switch info {
        case let .usd(remaining, _):
            if !showTitleLabel {
                return Self.usd(remaining)
            }
            return "\(Self.usd(remaining)) remaining (Account Balance)"
        case let .planLimits(label, detail):
            return detail.isEmpty ? label : "\(label) — \(detail)"
        case .unavailable:
            // Quiet fallback: no real number, so point the user at Estimated spent.
            return "Estimated only"
        }
    }

    private func load(force: Bool) async {
        isLoading = true
        defer { isLoading = false }
        let result = await service.balance(for: descriptor, apiKey: trimmedKey, force: force)
        guard !Task.isCancelled else { return }
        info = result
        if case let .usd(remaining, _) = result {
            onBalanceFetched?(remaining)
        } else {
            onBalanceFetched?(nil)
        }
    }

    /// Format a USD amount with two decimals (never fabricates precision).
    static func usd(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}


// A4 (§9): validity badge + model dropdown for a cloud provider.
private struct CloudKeyModelRow: View {
    @EnvironmentObject private var store: WorkflowStore
    let descriptor: CloudProviderDescriptor
    let apiKey: String
    var title: String = "Text Model"
    @Binding var selectedModel: String
    let fallbackModel: String
    @Binding var validationStatus: CloudKeyValidationStatus
    var initialCategory: SmartModelPickerSheet.ModelFilterCategory = .all
    var customLeadingView: AnyView? = nil

    @State private var status: CloudKeyValidationStatus = .idle
    @State private var models: [CloudModel] = []
    @State private var isLoadingModels = false
    @State private var loadFailed = false
    // User forced free-text entry even though a list is available (advanced users).
    @State private var manualEntry = false
    @State private var showPickerSheet = false

    // Session-scoped services (constructed once; @State preserves the first instance).
    @State private var validator = CloudKeyValidator()
    @State private var catalog = CloudModelCatalog()

    private var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var showsCombo: Bool { manualEntry || loadFailed || models.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                if let leading = customLeadingView {
                    leading
                        .frame(width: 170, alignment: .leading)
                } else {
                    Text(title)
                        .foregroundStyle(VaniScriptTheme.text2)
                        .frame(width: 170, alignment: .leading)
                }

                HStack(alignment: .center, spacing: 8) {
                    modelControl
                    validationBadge
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if status == .valid {
                modelPricingInfoRow
            }
        }
        .font(.system(size: 13))
        .task(id: apiKey) {
            await runValidationAndLoad()
        }
    }

    @ViewBuilder
    private var modelPricingInfoRow: some View {
        let currentModelID = selectedModel.isEmpty ? fallbackModel : selectedModel
        let isSTT = initialCategory == .transcribing
            || title.lowercased().contains("audio")
            || title.lowercased().contains("transcrib")
            || (CloudProviderCatalog.supportsTranscription(providerID: descriptor.id, modelID: currentModelID) && !CloudProviderCatalog.supportsTranslation(providerID: descriptor.id, modelID: currentModelID))

        if isSTT {
            let sttPrice = CloudProviderCatalog.sttPricing(for: currentModelID)
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 10))
                        .foregroundStyle(VaniScriptTheme.accent)
                    Text("Audio Rate:")
                        .foregroundStyle(VaniScriptTheme.text2)
                    Text("\(sttPrice.formattedPerMin) (\(sttPrice.formattedPerHour))")
                        .foregroundStyle(VaniScriptTheme.text0)
                        .fontWeight(.semibold)
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .padding(.leading, 178)
        } else {
            let loaded = models.first(where: { $0.id == currentModelID })
            let info = CloudProviderCatalog.modelPricingDetails(
                providerID: descriptor.id,
                modelID: currentModelID,
                loadedModel: loaded
            )

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                        .font(.system(size: 10))
                        .foregroundStyle(VaniScriptTheme.accent)
                    Text("Context:")
                        .foregroundStyle(VaniScriptTheme.text2)
                    Text(info.context)
                        .foregroundStyle(VaniScriptTheme.text0)
                        .fontWeight(.semibold)
                }

                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(VaniScriptTheme.green)
                    Text("Input:")
                        .foregroundStyle(VaniScriptTheme.text2)
                    Text(info.inputCost)
                        .foregroundStyle(VaniScriptTheme.text0)
                        .fontWeight(.semibold)
                }

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.blue)
                    Text("Output:")
                        .foregroundStyle(VaniScriptTheme.text2)
                    Text(info.outputCost)
                        .foregroundStyle(VaniScriptTheme.text0)
                        .fontWeight(.semibold)
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .padding(.leading, 178)
        }
    }

    // MARK: - Badge

    @ViewBuilder
    private var validationBadge: some View {
        switch status {
        case .idle:
            EmptyView()
        case .checking:
            badge(text: "Checking…", color: VaniScriptTheme.text2)
        case .valid:
            badge(text: "● Valid", color: VaniScriptTheme.green)
        case let .invalid(reason):
            badge(text: "● Invalid", color: VaniScriptTheme.red)
                .help(reason)
        }
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
    }

    // MARK: - Model control (Smart Picker Sheet or editable combo + Retry)

    @ViewBuilder
    private var modelControl: some View {
        if showsCombo {
            // Editable combo: free-text model id + Retry (auto-load failed/empty, or
            // the user opted into manual entry).
            HStack(spacing: 6) {
                TextField(fallbackModel, text: $selectedModel)
                    .textFieldStyle(.plain)
                    .foregroundStyle(VaniScriptTheme.text0)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(VaniScriptTheme.input)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(VaniScriptTheme.controlBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    manualEntry = false
                    Task { await loadModels(force: true) }
                } label: {
                    HStack(spacing: 4) {
                        if isLoadingModels {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Retry")
                    }
                }
                .buttonStyle(SettingsSmallButtonStyle(primary: false))
                .disabled(trimmedKey.isEmpty || isLoadingModels)
            }
        } else if descriptor.id == CloudProviderCatalog.qwenID {
            Picker("", selection: $selectedModel) {
                ForEach(models, id: \.id) { model in
                    Text(model.id)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .tag(model.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 6) {
                let currentModelID = selectedModel.isEmpty ? fallbackModel : selectedModel
                let isAudio = CloudProviderCatalog.supportsTranscription(providerID: descriptor.id, modelID: currentModelID)
                let isVision = CloudProviderCatalog.supportsVision(modelID: currentModelID)

                Button {
                    showPickerSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Text(currentModelID)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(VaniScriptTheme.text0)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        HStack(spacing: 4) {
                            if isAudio {
                                HStack(spacing: 3) {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 8, weight: .bold))
                                    Text("Audio STT")
                                }
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(VaniScriptTheme.green.opacity(0.22))
                                .foregroundStyle(VaniScriptTheme.green)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            if isVision {
                                HStack(spacing: 3) {
                                    Image(systemName: "camera")
                                        .font(.system(size: 8, weight: .bold))
                                    Text("Vision")
                                }
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.22))
                                .foregroundStyle(Color(red: 0.35, green: 0.72, blue: 1.0))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(VaniScriptTheme.text2)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(VaniScriptTheme.input)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(VaniScriptTheme.controlBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showPickerSheet, arrowEdge: .bottom) {
                    SmartModelPickerSheet(
                        descriptor: descriptor,
                        models: models,
                        selectedModel: $selectedModel,
                        isPresented: $showPickerSheet,
                        initialCategory: initialCategory
                    )
                }
            }
        }
    }

    // MARK: - Async validation + load

    private func runValidationAndLoad() async {
        guard !trimmedKey.isEmpty else {
            status = .idle
            validationStatus = .idle
            models = []
            loadFailed = false
            autoResetIfInvalid(status: .idle)
            return
        }
        status = .checking
        validationStatus = .checking
        // Debounce: wait for typing to pause. If the key changes, SwiftUI cancels this
        // task (throwing CancellationError) and starts a fresh one — newest wins.
        do {
            try await Task.sleep(nanoseconds: 500_000_000)
        } catch {
            return
        }
        let baseURL = descriptor.id == CloudProviderCatalog.qwenID ? store.settings.resolvedQwenBaseUrl(apiKey: trimmedKey) : nil
        let result = await validator.validate(descriptor: descriptor, apiKey: trimmedKey, baseURL: baseURL)
        guard !Task.isCancelled else { return }
        status = result
        validationStatus = result
        if case .valid = result {
            await loadModels(force: false)
        } else {
            models = []
            loadFailed = false
            autoResetIfInvalid(status: result)
        }
    }

    private func autoResetIfInvalid(status: CloudKeyValidationStatus) {
        guard status != .valid else { return }
        let engineID: String = {
            switch descriptor.id {
            case CloudProviderCatalog.geminiID: return "gemini-cloud"
            case CloudProviderCatalog.openaiID: return "gpt-cloud"
            default: return descriptor.id
            }
        }()
        if store.settings.transcriptionProvider == engineID {
            let fallback = ProviderRegistry.availableTranscriptionProviders(settings: store.settings).first(where: { $0.id != engineID })?.id ?? ""
            store.updateSettings { $0.transcriptionProvider = fallback }
        }
        if store.settings.translationProvider == engineID {
            let fallback = ProviderRegistry.availableTranslationProviders(settings: store.settings, targetLang: store.workflow.targetLang).providers.first(where: { $0.id != engineID })?.id ?? ""
            store.updateSettings { $0.translationProvider = fallback }
        }
    }

    private func loadModels(force: Bool) async {
        guard !trimmedKey.isEmpty else { return }
        isLoadingModels = true
        defer { isLoadingModels = false }
        do {
            let baseURL = descriptor.id == CloudProviderCatalog.qwenID ? store.settings.resolvedQwenBaseUrl(apiKey: trimmedKey) : nil
            let fetched = try await catalog.listModels(descriptor: descriptor, apiKey: trimmedKey, baseURL: baseURL, useCache: !force)
            guard !Task.isCancelled else { return }
            models = fetched
            loadFailed = fetched.isEmpty
            // Default the selection to the fallback when nothing valid is chosen yet.
            if selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedModel = fetched.first(where: { $0.id == fallbackModel })?.id ?? fetched.first?.id ?? fallbackModel
            }
        } catch {
            guard !Task.isCancelled else { return }
            models = []
            loadFailed = true
        }
    }
}

// MARK: - Smart Model Picker Sheet (A5: Search bar + capability filter chips)

private struct SmartModelPickerSheet: View {
    @EnvironmentObject private var store: WorkflowStore
    let descriptor: CloudProviderDescriptor
    let models: [CloudModel]
    @Binding var selectedModel: String
    @Binding var isPresented: Bool
    var initialCategory: ModelFilterCategory = .all

    @State private var searchText = ""
    @State private var showFavoritesOnly = false
    @State private var selectedFilter: ModelFilterCategory

    init(
        descriptor: CloudProviderDescriptor,
        models: [CloudModel],
        selectedModel: Binding<String>,
        isPresented: Binding<Bool>,
        initialCategory: ModelFilterCategory = .all
    ) {
        self.descriptor = descriptor
        self.models = models
        self._selectedModel = selectedModel
        self._isPresented = isPresented
        self.initialCategory = initialCategory
        self._selectedFilter = State(initialValue: initialCategory)
    }

    enum ModelFilterCategory: String, CaseIterable, Identifiable {
        case all = "All"
        case transcribing = "For Transcribing"
        case translation = "For Translation"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .transcribing: return "waveform"
            case .translation: return "character.bubble"
            }
        }
    }

    private var filteredModels: [CloudModel] {
        var result = models
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { $0.id.localizedCaseInsensitiveContains(query) }
        }
        if showFavoritesOnly {
            result = result.filter { store.settings.isFavoriteModel($0.id) }
        }
        switch selectedFilter {
        case .all:
            break
        case .transcribing:
            result = result.filter { CloudProviderCatalog.supportsTranscription(providerID: descriptor.id, modelID: $0.id) }
        case .translation:
            let lowerDedicatedSTT = ["whisper", "grok-stt", "deepgram", "parakeet", "mai-transcribe", "voxtral-mini", "chirp", "asr-flash", "mini-transcribe"]
            result = result.filter { model in
                let lower = model.id.lowercased()
                return !lowerDedicatedSTT.contains(where: { lower.contains($0) })
            }
        }
        return result.sorted { a, b in
            let aFav = store.settings.isFavoriteModel(a.id)
            let bFav = store.settings.isFavoriteModel(b.id)
            if aFav != bFav { return aFav }
            return a.id.localizedCaseInsensitiveCompare(b.id) == .orderedAscending
        }
    }

    private var favoriteCount: Int {
        models.filter { store.settings.isFavoriteModel($0.id) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Select Model for \(descriptor.label)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(VaniScriptTheme.text0)
                    HStack(spacing: 8) {
                        Text("\(filteredModels.count) of \(models.count) models matching filter")
                        if favoriteCount > 0 {
                            Text("•")
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                Text("\(favoriteCount) favorite\(favoriteCount == 1 ? "" : "s")")
                            }
                            .foregroundStyle(.yellow)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(VaniScriptTheme.text2)
                }
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(VaniScriptTheme.text2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().background(VaniScriptTheme.separator)

            // Search Bar & Favorites Filter Bar
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(VaniScriptTheme.text2)
                            .font(.system(size: 13))
                        TextField("Search models (e.g. omni, gemini, qwen, flash)...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(VaniScriptTheme.text0)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(VaniScriptTheme.text2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(VaniScriptTheme.input)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(VaniScriptTheme.controlBorder, lineWidth: 1))

                    Button {
                        showFavoritesOnly.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                                .font(.system(size: 11, weight: .semibold))
                            Text(showFavoritesOnly ? "Favorites" : "All")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            showFavoritesOnly ? Color.yellow.opacity(0.18) : VaniScriptTheme.input,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .foregroundStyle(showFavoritesOnly ? .yellow : VaniScriptTheme.text2)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(showFavoritesOnly ? Color.yellow.opacity(0.4) : VaniScriptTheme.controlBorder, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(showFavoritesOnly ? "Show all models" : "Filter by favorites")
                }

                // Filter Chips
                HStack(spacing: 6) {
                    ForEach(ModelFilterCategory.allCases) { category in
                        let count: Int = {
                            switch category {
                            case .all:
                                return models.count
                            case .transcribing:
                                return models.filter { CloudProviderCatalog.supportsTranscription(providerID: descriptor.id, modelID: $0.id) }.count
                            case .translation:
                                return models.filter { model in
                                    let lower = model.id.lowercased()
                                    let isDedicatedAudioSTT = lower.contains("whisper")
                                        || lower.contains("grok-stt")
                                        || lower.contains("deepgram")
                                        || lower.contains("parakeet")
                                        || lower.contains("mai-transcribe")
                                        || lower.contains("voxtral-mini")
                                        || lower.contains("chirp")
                                        || lower.contains("asr-flash")
                                        || lower.contains("mini-transcribe")
                                    return !isDedicatedAudioSTT
                                }.count
                            }
                        }()
                        Button {
                            selectedFilter = category
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: category.icon)
                                Text("\(category.rawValue) (\(count))")
                                    .lineLimit(1)
                            }
                            .font(.system(size: 11, weight: selectedFilter == category ? .bold : .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity)
                            .background(selectedFilter == category ? VaniScriptTheme.accent.opacity(0.25) : VaniScriptTheme.input)
                            .foregroundStyle(selectedFilter == category ? VaniScriptTheme.onAccent : VaniScriptTheme.text2)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(selectedFilter == category ? VaniScriptTheme.accent : VaniScriptTheme.controlBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)

            Divider().background(VaniScriptTheme.separator)

            // Models List
            if filteredModels.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: showFavoritesOnly ? "star.slash" : "slash.circle")
                        .font(.system(size: 26))
                        .foregroundStyle(VaniScriptTheme.text2)
                    Text(showFavoritesOnly ? "No favorite models for \(descriptor.label)" : "No matching models found")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(VaniScriptTheme.text1)
                    Text(showFavoritesOnly ? "Star models to quickly find them here." : "Try clearing your search query or filter.")
                        .font(.system(size: 11))
                        .foregroundStyle(VaniScriptTheme.text2)
                    if showFavoritesOnly {
                        Button("Show All Models") {
                            showFavoritesOnly = false
                        }
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.borderless)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredModels, id: \.id) { model in
                            let isFav = store.settings.isFavoriteModel(model.id)
                            let isSelected = selectedModel == model.id
                            let isAudio = CloudProviderCatalog.supportsTranscription(providerID: descriptor.id, modelID: model.id)
                            let isVision = CloudProviderCatalog.supportsVision(modelID: model.id)

                            HStack(spacing: 8) {
                                Button {
                                    store.updateSettings { $0.toggleFavoriteModel(model.id) }
                                } label: {
                                    Image(systemName: isFav ? "star.fill" : "star")
                                        .font(.system(size: 14))
                                        .foregroundStyle(isFav ? .yellow : VaniScriptTheme.text2.opacity(0.35))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(isFav ? "Remove from favorites" : "Add to favorites")

                                Button {
                                    selectedModel = model.id
                                    isPresented = false
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(isSelected ? VaniScriptTheme.accent : VaniScriptTheme.text2)
                                            .font(.system(size: 14))

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(model.id)
                                                .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .monospaced))
                                                .foregroundStyle(isSelected ? VaniScriptTheme.onAccent : VaniScriptTheme.text0)

                                            HStack(spacing: 4) {
                                                if isAudio {
                                                    HStack(spacing: 3) {
                                                        Image(systemName: "waveform")
                                                            .font(.system(size: 8, weight: .bold))
                                                        Text("Audio STT")
                                                    }
                                                    .font(.system(size: 9, weight: .bold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(VaniScriptTheme.green.opacity(0.22))
                                                    .foregroundStyle(VaniScriptTheme.green)
                                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                                } else {
                                                    HStack(spacing: 3) {
                                                        Image(systemName: "text.bubble")
                                                            .font(.system(size: 8, weight: .semibold))
                                                        Text("Text LLM")
                                                    }
                                                    .font(.system(size: 9))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(VaniScriptTheme.control)
                                                    .foregroundStyle(VaniScriptTheme.text2)
                                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                                }

                                                if isVision {
                                                    HStack(spacing: 3) {
                                                        Image(systemName: "camera")
                                                            .font(.system(size: 8, weight: .bold))
                                                        Text("Vision")
                                                    }
                                                    .font(.system(size: 9, weight: .bold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(Color.blue.opacity(0.22))
                                                    .foregroundStyle(Color(red: 0.35, green: 0.72, blue: 1.0))
                                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                                }
                                            }
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isSelected ? VaniScriptTheme.accent.opacity(0.18) : Color.clear)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 580, height: 500)
        .background(VaniScriptTheme.card)
    }
}


private struct SettingsToggleRow: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(VaniScriptTheme.text2)
                .font(.system(size: 13, weight: .semibold))
        }
        .toggleStyle(.switch)
        .tint(VaniScriptTheme.accent)
        .padding(.horizontal, 12)
        .frame(height: VaniScriptTheme.Density.controlHeightLG)
        .background(VaniScriptTheme.control)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(VaniScriptTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous))
    }
}

private struct CompactMcpToggleCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isEnabled: Bool
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: VaniScriptTheme.Density.space8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isEnabled ? VaniScriptTheme.accent : VaniScriptTheme.text2)
                .frame(width: 24, height: 24)
                .background(VaniScriptTheme.control)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(VaniScriptTheme.text1)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(VaniScriptTheme.text2)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(VaniScriptTheme.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(VaniScriptTheme.control)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(VaniScriptTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.52)
    }
}

private struct McpStatusSummaryTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: VaniScriptTheme.Density.space8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VaniScriptTheme.text2)
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(VaniScriptTheme.text0)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(VaniScriptTheme.control)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(VaniScriptTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous))
    }
}

private struct McpAgentProfileRow: View {
    let profile: McpAgentProfile
    let state: McpAgentConnectionState
    let isPreferred: Bool
    let activeClient: McpActiveClient?
    let canCopySetup: Bool
    let setActive: () -> Void
    let copySetup: () -> Void

    private var isConnected: Bool {
        if case .connected = state {
            return true
        }
        return false
    }

    var body: some View {
        HStack(alignment: .center, spacing: VaniScriptTheme.Density.space8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(VaniScriptTheme.control)
                Image(systemName: profile.id.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(VaniScriptTheme.accent)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(VaniScriptTheme.text0)

                Text(profile.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(VaniScriptTheme.text2)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if isConnected {
                HStack(spacing: 6) {
                    Circle()
                        .fill(VaniScriptTheme.green)
                        .frame(width: 8, height: 8)
                    Text(activeClient?.displayName ?? "Connected")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(VaniScriptTheme.text1)
                        .lineLimit(1)
                }
                .frame(width: 104, alignment: .leading)
            } else {
                Color.clear
                    .frame(width: 104, height: 1)
            }

            Button(isPreferred ? "Active" : "Set Active") {
                setActive()
            }
            .buttonStyle(SettingsSmallButtonStyle(primary: isPreferred))
            .disabled(isPreferred)

            Button("Copy Setup") {
                copySetup()
            }
            .buttonStyle(SettingsSmallButtonStyle(primary: state != .disabled))
            .disabled(!canCopySetup)
        }
        .padding(.vertical, 9)
    }
}

private struct PickerRow<Value: RawRepresentable & CaseIterable & Hashable>: View where Value.RawValue == String, Value.AllCases: RandomAccessCollection {
    let title: String
    @Binding var selection: Value
    let values: Value.AllCases

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(VaniScriptTheme.text2)
                .frame(width: 140, alignment: .leading)
            Picker(title, selection: $selection) {
                ForEach(Array(values), id: \.self) { value in
                    Text(value.rawValue.capitalized).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
        .font(.system(size: 13))
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var maxLabel: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(VaniScriptTheme.text2)
                .frame(width: 140, alignment: .leading)
            Slider(value: $value, in: range)
                .tint(VaniScriptTheme.accent)
            HStack(spacing: 2) {
                Text(String(format: format, value))
                    .foregroundStyle(VaniScriptTheme.accent)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                if let maxLabel {
                    Text("/ \(maxLabel)")
                        .foregroundStyle(VaniScriptTheme.text2)
                        .font(.system(size: 10, design: .monospaced))
                }
            }
            .frame(minWidth: 54, alignment: .trailing)
        }
        .font(.system(size: 13))
    }
}

private struct StepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let suffix: String

    var body: some View {
        Stepper(value: $value, in: range) {
            HStack {
                Text(title)
                    .foregroundStyle(VaniScriptTheme.text2)
                Spacer()
                Text("\(value) \(suffix)")
                    .foregroundStyle(VaniScriptTheme.accent)
                    .fontWeight(.bold)
            }
        }
        .font(.system(size: 13))
    }
}

private struct ProviderList: View {
    let title: String
    let providers: [ProviderOption]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(VaniScriptTheme.text2)
            if providers.isEmpty {
                Text("No providers available")
                    .font(.system(size: 12))
                    .foregroundStyle(VaniScriptTheme.text2)
            } else {
                ForEach(providers, id: \.id) { provider in
                    HStack {
                        Text(provider.label)
                            .foregroundStyle(VaniScriptTheme.text0)
                        Spacer()
                        Text(provider.group.rawValue.capitalized)
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(provider.group == .local ? VaniScriptTheme.accent : VaniScriptTheme.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(VaniScriptTheme.control)
                            .clipShape(Capsule())
                    }
                    .font(.system(size: 12))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ModelMeta: Sendable {
    let size: String
    let accuracy: Int
    let speed: Int
    let badge: String
    let description: String
}

private struct RatingDotsView: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(i < count ? VaniScriptTheme.accent : VaniScriptTheme.border)
                    .frame(width: 5, height: 5)
            }
        }
    }
}

private func modelDownloadUrl(id: String) -> String {
    switch id {
    case "qwen35-08b-4bit":
        return "https://huggingface.co/mlx-community/Qwen3.5-0.8B-4bit"
    case "qwen35-2b-4bit":
        return "https://huggingface.co/mlx-community/Qwen3.5-2B-4bit"
    case "qwen35-4b-4bit":
        return "https://huggingface.co/mlx-community/Qwen3.5-4B-4bit"
    case "qwen35-9b-4bit":
        return "https://huggingface.co/mlx-community/Qwen3.5-9B-4bit"
    case "nemotron3-nano-4b-4bit":
        return "https://huggingface.co/mlx-community/NVIDIA-Nemotron-3-Nano-4B-4bit"
    case "whisper-small-en":
        return "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-small.en"
    case "whisper-small-multilingual":
        return "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-small"
    case "whisper-medium-en":
        return "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-medium.en"
    case "whisper-medium-multilingual":
        return "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-medium"
    case "whisper-large-v3-turbo":
        return "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3_turbo"
    case "whisper-large-v3":
        return "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3"
    default:
        return "https://huggingface.co"
    }
}

private func getModelMeta(id: String) -> ModelMeta {
    switch id {
    case "qwen35-9b-4bit":
        return ModelMeta(size: "≈ 5.54 GiB", accuracy: 5, speed: 2, badge: "Quality 9B", description: "Highest quality within the 9B cap. Best for Gaudiya Vaishnava translation.")
    case "qwen35-4b-4bit":
        return ModelMeta(size: "≈ 2.83 GiB", accuracy: 4, speed: 4, badge: "Recommended 4B", description: "Balanced default. Strong quality, comfortable speed.")
    case "nemotron3-nano-4b-4bit":
        return ModelMeta(size: "≈ 2.08 GiB", accuracy: 4, speed: 4, badge: "NVIDIA 4B", description: "Strong compact NVIDIA model.")
    case "qwen35-2b-4bit":
        return ModelMeta(size: "≈ 1.60 GiB", accuracy: 3, speed: 5, badge: "Fast 2B", description: "Fast and light. Good for quick passes.")
    case "qwen35-08b-4bit":
        return ModelMeta(size: "≈ 0.58 GiB", accuracy: 2, speed: 5, badge: "Tiny 0.8B", description: "Ultra-light for tests and low-memory machines.")

    case "whisper-small-en":
        return ModelMeta(size: "≈ 240 MiB", accuracy: 3, speed: 4, badge: "Light EN", description: "English speech only. Fast, low memory footprint.")
    case "whisper-small-multilingual":
        return ModelMeta(size: "≈ 240 MiB", accuracy: 3, speed: 4, badge: "Light ML", description: "Multilingual. Moderate accuracy, highly responsive.")
    case "whisper-medium-en":
        return ModelMeta(size: "≈ 760 MiB", accuracy: 4, speed: 3, badge: "Balanced EN", description: "English speech only. Highly accurate balanced model.")
    case "whisper-medium-multilingual":
        return ModelMeta(size: "≈ 760 MiB", accuracy: 4, speed: 3, badge: "Balanced ML", description: "Multilingual. Strong accuracy with a balanced Apple Silicon footprint.")
    case "whisper-large-v3-turbo":
        return ModelMeta(size: "≈ 800 MiB", accuracy: 4, speed: 3, badge: "Fast Very Good", description: "Multilingual. Fast with excellent accuracy.")
    case "whisper-large-v3":
        return ModelMeta(size: "≈ 1.5 GiB", accuracy: 5, speed: 2, badge: "Max accuracy", description: "Multilingual. Maximum possible precision for complex terms.")

    default:
        return ModelMeta(size: "Unknown", accuracy: 1, speed: 1, badge: "Custom", description: "Custom local model folder.")
    }
}

private struct ModelSettingsRow: View {
    let id: String
    let model: LocalModelState
    let isActive: Bool
    let downloadUrl: String
    let download: () -> Void
    let locate: () -> Void
    let use: () -> Void
    let remove: () -> Void

    var body: some View {
        let meta = getModelMeta(id: id)

        VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space8) {
            HStack(alignment: .top, spacing: VaniScriptTheme.Density.space8) {
                // Left column: Icon & Compute badge
                VStack(spacing: 6) {
                    Image(systemName: model.runtime == .whisper ? "waveform" : "brain")
                        .font(.system(size: 16))
                        .foregroundStyle(VaniScriptTheme.accent)
                        .frame(width: 32, height: 32)
                        .background(VaniScriptTheme.control)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text(model.runtime == .mlx ? "METAL" : "NE/GPU")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(VaniScriptTheme.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(VaniScriptTheme.control)
                        .clipShape(Capsule())
                }

                // Middle column: Details
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(model.label)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(VaniScriptTheme.text0)

                        if !meta.badge.isEmpty {
                            Text(meta.badge)
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(VaniScriptTheme.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 0.5)
                                .background(VaniScriptTheme.accent.opacity(0.12))
                                .cornerRadius(4)
                        }

                        if isActive {
                            Text("Active")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(VaniScriptTheme.onAccent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 0.5)
                                .background(VaniScriptTheme.green)
                                .cornerRadius(4)
                        }
                    }

                    Text(meta.description)
                        .font(.system(size: 11))
                        .foregroundStyle(VaniScriptTheme.text2)
                        .lineLimit(2)
                        .padding(.bottom, 2)

                    HStack(spacing: VaniScriptTheme.Density.space8) {
                        HStack(spacing: 4) {
                            Image(systemName: "internaldrive")
                            Text(meta.size)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "scope")
                            RatingDotsView(count: meta.accuracy)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "bolt")
                            RatingDotsView(count: meta.speed)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(VaniScriptTheme.text2)
                }

                Spacer()

                // Right column: Actions
                VStack(alignment: .trailing, spacing: 6) {
                    if model.status == .downloading {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(model.progressLabel ?? "Downloading...")
                                .font(.system(size: 10))
                                .foregroundStyle(VaniScriptTheme.text2)
                                .lineLimit(1)

                            ProgressView(value: model.progress ?? 0.0, total: 1.0)
                                .progressViewStyle(.linear)
                                .tint(VaniScriptTheme.accent)
                                .frame(width: 90)
                        }
                    } else if model.status != .downloaded {
                        Button {
                            download()
                        } label: {
                            Label("Download", systemImage: "arrow.down.circle")
                                .frame(width: 90)
                        }
                        .buttonStyle(SettingsSmallButtonStyle(primary: true))

                        HStack(spacing: 4) {
                            Button("Locate") {
                                locate()
                            }
                            .buttonStyle(SettingsSmallButtonStyle(primary: false))
                            .frame(width: 62)

                            Button {
                                if let url = URL(string: downloadUrl) {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Image(systemName: "globe")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(SettingsSmallButtonStyle(primary: false))
                            .frame(width: 24)
                            .help("Open Hugging Face in Browser")
                        }
                    } else {
                        Button {
                            use()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                Text(isActive ? "Active" : "Use")
                            }
                            .frame(width: 90)
                        }
                        .buttonStyle(SettingsSmallButtonStyle(primary: isActive))

                        Button(role: .destructive) {
                            remove()
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .frame(width: 90)
                        }
                        .buttonStyle(SettingsSmallButtonStyle(primary: false))
                        .foregroundStyle(VaniScriptTheme.red)
                    }
                }
            }
        }
        .padding(12)
        .background(isActive ? VaniScriptTheme.accent.opacity(0.08) : VaniScriptTheme.surfaceSubtle)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isActive ? VaniScriptTheme.accent.opacity(0.4) : VaniScriptTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusMD, style: .continuous))
    }
}

private struct GlossarySettingsRow: View {
    let entry: GlossaryEntry
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: VaniScriptTheme.Density.space8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.source)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(VaniScriptTheme.text0)

                    Text("→")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VaniScriptTheme.accent)

                    Text(entry.translation.isEmpty ? "No translation" : entry.translation)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(VaniScriptTheme.text1)
                }

                if !entry.variants.isEmpty {
                    Text("Variants: " + entry.variants.joined(separator: ", "))
                        .font(.system(size: 10.5))
                        .foregroundStyle(VaniScriptTheme.text2)
                        .lineLimit(2)
                }
            }

            Spacer()

            if let category = entry.category, !category.isEmpty {
                Text(category)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(VaniScriptTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(VaniScriptTheme.accent.opacity(0.12))
                    .clipShape(Capsule())
            }

            Button(action: edit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .foregroundStyle(VaniScriptTheme.accent)

            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(VaniScriptTheme.red)
        }
        .padding(10)
        .background(VaniScriptTheme.card)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(VaniScriptTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous))
    }
}

private struct SettingsPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(isEnabled ? VaniScriptTheme.onAccent : VaniScriptTheme.disabledText)
            .padding(.vertical, 9)
            .background(
                isEnabled
                    ? (configuration.isPressed ? VaniScriptTheme.accentHover : VaniScriptTheme.accent)
                    : VaniScriptTheme.disabledSurface
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isEnabled ? Color.clear : VaniScriptTheme.controlBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SettingsSmallButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(
                isEnabled
                    ? (primary ? VaniScriptTheme.onAccent : VaniScriptTheme.text1)
                    : VaniScriptTheme.disabledText
            )
            .padding(.horizontal, 10)
            .frame(height: VaniScriptTheme.Density.controlHeightMD)
            .background(
                isEnabled
                    ? (primary ? VaniScriptTheme.accent : (configuration.isPressed ? VaniScriptTheme.controlPressed : VaniScriptTheme.control))
                    : VaniScriptTheme.disabledSurface
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isEnabled ? (primary ? Color.clear : VaniScriptTheme.controlBorder) : VaniScriptTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// A6: StatItem/BudgetBar removed — superseded by UsageStatCell/usage cards in
// UsageStatisticsView (Electron tab 7 parity).

enum GlossarySortMode: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case oldest = "Oldest"
    case alphabetical = "Alphabetical"

    var id: String { self.rawValue }
}

private struct GlossaryEditSheet: View {
    let entry: GlossaryEntry
    let onSave: (GlossaryEntry) -> Void
    let onCancel: () -> Void

    @State private var source: String
    @State private var translation: String
    @State private var category: String
    @State private var variantsString: String

    init(entry: GlossaryEntry, onSave: @escaping (GlossaryEntry) -> Void, onCancel: @escaping () -> Void) {
        self.entry = entry
        self.onSave = onSave
        self.onCancel = onCancel
        _source = State(initialValue: entry.source)
        _translation = State(initialValue: entry.translation)
        _category = State(initialValue: entry.category ?? "")
        _variantsString = State(initialValue: entry.variants.joined(separator: ", "))
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: VaniScriptTheme.Density.space8) {
                Text("Edit Glossary Entry")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(VaniScriptTheme.text0)

                VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space8) {
                    TextInputRow(title: "Source Text", text: $source)
                    TextInputRow(title: "Translation", text: $translation)
                    TextInputRow(title: "Category", text: $category)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Variants (comma-separated list of spelling variations / incorrect spellings)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(VaniScriptTheme.text2)

                        TextEditor(text: $variantsString)
                            .font(.system(size: 12))
                            .foregroundStyle(VaniScriptTheme.text0)
                            .padding(6)
                            .frame(height: 100)
                            .scrollContentBackground(.hidden)
                            .background(VaniScriptTheme.input)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(VaniScriptTheme.controlBorder, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 8)

                HStack(spacing: VaniScriptTheme.Density.space8) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(SecondaryActionButtonStyle())

                    Button("Save") {
                        let parsedVariants = variantsString
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }

                        let updated = GlossaryEntry(
                            id: entry.id,
                            variants: parsedVariants,
                            source: source.trimmingCharacters(in: .whitespacesAndNewlines),
                            translation: translation.trimmingCharacters(in: .whitespacesAndNewlines),
                            category: category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : category.trimmingCharacters(in: .whitespacesAndNewlines),
                            translations: entry.translations,
                            remember: entry.remember,
                            createdAt: entry.createdAt,
                            updatedAt: isoString(Date())
                        )
                        onSave(updated)
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(VaniScriptTheme.Density.space12)
            .frame(width: 540)
            .glassPanel()
            .padding(VaniScriptTheme.Density.space12)
        }
        .frame(width: 600, height: 480)
    }

    private func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
}

private struct CornerIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(
                isEnabled
                    ? (configuration.isPressed ? VaniScriptTheme.accent : VaniScriptTheme.text1)
                    : VaniScriptTheme.disabledText
            )
            .frame(width: 32, height: 32)
            .background(
                isEnabled
                    ? (configuration.isPressed ? VaniScriptTheme.controlPressed : VaniScriptTheme.control)
                    : VaniScriptTheme.disabledSurface
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isEnabled ? VaniScriptTheme.controlBorder : VaniScriptTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
