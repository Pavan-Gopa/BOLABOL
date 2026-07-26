import SwiftUI
import VaniScriptCore

struct SettingsView: View {
    @EnvironmentObject private var store: WorkflowStore
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
                    .background(Color.white.opacity(0.04))
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
                    .background(Color.white.opacity(0.04))
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
                    .background(Color.white.opacity(0.04))
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
                    .background(Color.white.opacity(0.04))
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
                    .background(Color.white.opacity(0.04))
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
                    .background(Color.white.opacity(0.04))
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
                                .background(Color.white.opacity(0.08))
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

            SettingsSection(title: "Cloud Usage Statistics") {
                VStack(spacing: VaniScriptTheme.Density.space8) {
                    let defaultProviders = ["gemini", "openai", "anthropic"]
                    let allProviders = defaultProviders + store.settings.customCloudProviders.map { $0.label }

                    ForEach(allProviders, id: \.self) { provider in
                        let stats = store.settings.usage[provider.lowercased()] ?? ProviderUsage()
                        let cost = estimateCost(provider: provider, input: stats.inputTokens, output: stats.outputTokens)

                        let isConfigured: Bool = {
                            switch provider.lowercased() {
                            case "gemini": return !store.settings.geminiKey.isEmpty
                            case "openai": return !store.settings.openaiKey.isEmpty
                            case "anthropic": return !store.settings.anthropicKey.isEmpty
                            default: return true
                            }
                        }()

                        if isConfigured || stats.sessions > 0 {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(provider)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(VaniScriptTheme.accent)
                                    Spacer()
                                    Text(String(format: "$%.4f", cost))
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundStyle(VaniScriptTheme.green)
                                }

                                HStack(spacing: VaniScriptTheme.Density.space12) {
                                    StatItem(title: "Sessions", value: "\(stats.sessions)")
                                    StatItem(title: "Audio Time", value: String(format: "%.1f m", stats.audioMinutes))
                                    StatItem(title: "Input Tokens", value: formatTokens(stats.inputTokens))
                                    StatItem(title: "Output Tokens", value: formatTokens(stats.outputTokens))
                                }
                                .padding(.vertical, 4)

                                let budgetLimit: Double = {
                                    switch provider.lowercased() {
                                    case "gemini": return store.settings.geminiBudgetUsd
                                    case "openai": return store.settings.openaiBudgetUsd
                                    default:
                                        if let custom = store.settings.customCloudProviders.first(where: { $0.label.lowercased() == provider.lowercased() }) {
                                            return custom.budgetLimitUsd
                                        }
                                        return 0.0
                                    }
                                }()

                                if budgetLimit > 0 {
                                    BudgetBar(title: "\(provider) Budget Limit", spent: cost, limit: budgetLimit)
                                }
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.025))
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
                        }
                    }

                    Button(role: .destructive) {
                        store.updateSettings { settings in
                            settings.usage = [:]
                        }
                    } label: {
                        Label("Reset All Statistics", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SettingsPrimaryButtonStyle())
                    .padding(.top, 8)
                }
            }
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
                        .background(Color.white.opacity(0.02))
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
                            isActive: store.settings.isDownloadedLocalASRModelActive(id: id),
                            downloadUrl: modelDownloadUrl(id: id),
                            download: {
                                store.downloadLocalModel(id: id, isTranslation: false)
                            },
                            locate: {
                                store.locateLocalASRModel(id: id)
                            },
                            use: {
                                store.updateSettings { settings in
                                    settings.transcriptionProvider = id
                                }
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
                                store.updateSettings { settings in
                                    settings.translationProvider = id
                                }
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
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
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

                    Picker("", selection: binding(\.transcriptionProvider)) {
                        ForEach(ProviderRegistry.availableTranscriptionProviders(settings: store.settings), id: \.id) { provider in
                            Text(provider.label).tag(provider.id)
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

                    Picker("", selection: binding(\.translationProvider)) {
                        ForEach(ProviderRegistry.availableTranslationProviders(settings: store.settings, targetLang: store.settings.defaultTargetLang).providers, id: \.id) { provider in
                            Text(provider.label).tag(provider.id)
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
                .background(Color.white.opacity(0.12))

            promptEditor
        }
        .padding(.vertical, 8)
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
                                            .foregroundStyle(selectedPromptId == def.id ? Color(red: 10/255, green: 10/255, blue: 18/255) : VaniScriptTheme.text0)
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
                                        .background(Color.white.opacity(0.06))
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
                        .background(Color.white.opacity(0.02))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
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
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))
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

    private func estimateCost(provider: String, input: Int, output: Int) -> Double {
        switch provider.lowercased() {
        case "gemini":
            return (Double(input) * 0.000002) + (Double(output) * 0.000008)
        case "openai":
            return (Double(input) * 0.0000025) + (Double(output) * 0.000010)
        case "anthropic":
            return (Double(input) * 0.000003) + (Double(output) * 0.000015)
        default:
            if let custom = store.settings.customCloudProviders.first(where: { $0.label.lowercased() == provider.lowercased() || $0.id == provider }) {
                return (Double(input) * (custom.inputCostPerMillion / 1_000_000.0)) + (Double(output) * (custom.outputCostPerMillion / 1_000_000.0))
            }
            return 0.0
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.2fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }

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
        .background(Color.white.opacity(0.035))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.09), lineWidth: 1))
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
        .background(Color.white.opacity(0.04))
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
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
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
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .font(.system(size: 13))
    }
}

// A3: card for the currently selected cloud provider in the API & Usage tab.
// Renders the provider's key / budget / usage toggles compactly, reusing the
// existing settings rows. Behavior for existing providers (Gemini/OpenAI/Anthropic)
// is preserved 1:1; new providers (Qwen/OpenRouter/Ollama Cloud) expose a key
// field plus a "coming soon" note — full engine wiring lands in A5. Custom is
// handled separately by SettingsView.customProvidersSection.
private struct ProviderCardView: View {
    @EnvironmentObject private var store: WorkflowStore
    let descriptor: CloudProviderDescriptor

    var body: some View {
        switch descriptor.id {
        case CloudProviderCatalog.geminiID:
            geminiCard
        case CloudProviderCatalog.openaiID:
            openaiCard
        case CloudProviderCatalog.anthropicID:
            anthropicCard
        default:
            comingSoonCard
        }
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
                Text("Gemini API key for cloud transcription, translation, and editing.")
                    .font(.system(size: 11))
                    .foregroundStyle(VaniScriptTheme.text2)
                    .padding(.bottom, 2)

                ApiKeyInputRow(title: "Gemini Key", text: binding(\.geminiKey), urlString: descriptor.getApiKeyURL)
                ReadOnlyRow(title: "Text Model", value: "gemini-2.5-flash")
                SliderRow(title: "Gemini Budget", value: binding(\.geminiBudgetUsd), range: 0...200, format: "$%.0f")

                HStack(spacing: 8) {
                    let hasKey = !store.settings.geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                    Button {
                        store.updateSettings { settings in
                            settings.transcriptionProvider = isTranscription ? "coreml-whisperkit" : "gemini-cloud"
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isTranscription ? "checkmark.circle.fill" : "circle")
                            Text(isTranscription ? "Used for Transcribing" : "Use for Transcribing")
                        }
                    }
                    .buttonStyle(SettingsSmallButtonStyle(primary: isTranscription))
                    .disabled(!hasKey)

                    Button {
                        store.updateSettings { settings in
                            settings.translationProvider = isTranslation ? "mlx-native" : "gemini-cloud"
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isTranslation ? "checkmark.circle.fill" : "circle")
                            Text(isTranslation ? "Used for Translation" : "Use for Translation")
                        }
                    }
                    .buttonStyle(SettingsSmallButtonStyle(primary: isTranslation))
                    .disabled(!hasKey)
                }
                .padding(.top, 4)
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
                ReadOnlyRow(title: "Text Model", value: "gpt-4o-mini / whisper-1")
                SliderRow(title: "OpenAI Budget", value: binding(\.openaiBudgetUsd), range: 0...200, format: "$%.0f")

                HStack(spacing: 8) {
                    let hasKey = !store.settings.openaiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                    Button {
                        store.updateSettings { settings in
                            settings.transcriptionProvider = isTranscription ? "coreml-whisperkit" : "gpt-cloud"
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isTranscription ? "checkmark.circle.fill" : "circle")
                            Text(isTranscription ? "Used for Transcribing" : "Use for Transcribing")
                        }
                    }
                    .buttonStyle(SettingsSmallButtonStyle(primary: isTranscription))
                    .disabled(!hasKey)

                    Button {
                        store.updateSettings { settings in
                            settings.translationProvider = isTranslation ? "mlx-native" : "gpt-cloud"
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isTranslation ? "checkmark.circle.fill" : "circle")
                            Text(isTranslation ? "Used for Translation" : "Use for Translation")
                        }
                    }
                    .buttonStyle(SettingsSmallButtonStyle(primary: isTranslation))
                    .disabled(!hasKey)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Anthropic (behavior 1:1 with the previous "Anthropic" section)
    private var anthropicCard: some View {
        SettingsSection(title: descriptor.label) {
            VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space8) {
                Text("Anthropic API key for cloud text polishing and editing.")
                    .font(.system(size: 11))
                    .foregroundStyle(VaniScriptTheme.text2)
                    .padding(.bottom, 2)

                ApiKeyInputRow(title: "Anthropic Key", text: binding(\.anthropicKey), urlString: descriptor.getApiKeyURL)
                ReadOnlyRow(title: "Text Model", value: "claude-3-5-sonnet")
            }
        }
    }

    // MARK: - Qwen / OpenRouter / Ollama Cloud (stub: key + "coming soon"; full A5)
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

private struct ApiKeyInputRow: View {
    let title: String
    @Binding var text: String
    let urlString: String
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(VaniScriptTheme.text2)
                .frame(width: 140, alignment: .leading)
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
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .frame(height: 34)
            .background(VaniScriptTheme.input)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
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
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .font(.system(size: 13))
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
        .background(Color.white.opacity(0.04))
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
                .background(Color.white.opacity(0.045))
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
        .background(Color.white.opacity(0.04))
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
        .background(Color.white.opacity(0.04))
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
                    .fill(Color.white.opacity(0.05))
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

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(VaniScriptTheme.text2)
                .frame(width: 140, alignment: .leading)
            Slider(value: $value, in: range)
                .tint(VaniScriptTheme.accent)
            Text(String(format: format, value))
                .foregroundStyle(VaniScriptTheme.accent)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .frame(width: 54, alignment: .trailing)
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
                            .background(Color.white.opacity(0.06))
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
                    .fill(i < count ? VaniScriptTheme.accent : Color.white.opacity(0.15))
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
        return "https://huggingface.co/awni/whisperkit-coreml/tree/main/huggingface/models/apple/ml-whisper/small.en"
    case "whisper-small-multilingual":
        return "https://huggingface.co/awni/whisperkit-coreml/tree/main/huggingface/models/apple/ml-whisper/small"
    case "whisper-medium-en":
        return "https://huggingface.co/awni/whisperkit-coreml/tree/main/huggingface/models/apple/ml-whisper/medium.en"
    case "whisper-medium-multilingual":
        return "https://huggingface.co/awni/whisperkit-coreml/tree/main/huggingface/models/apple/ml-whisper/medium"
    case "whisper-large-v3-turbo":
        return "https://huggingface.co/awni/whisperkit-coreml/tree/main/huggingface/models/apple/ml-whisper/large-v3-turbo"
    case "whisper-large-v3":
        return "https://huggingface.co/awni/whisperkit-coreml/tree/main/huggingface/models/apple/ml-whisper/large-v3"
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
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text(model.runtime == .mlx ? "METAL" : "NE/GPU")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(VaniScriptTheme.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.white.opacity(0.06))
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
                                .foregroundStyle(Color(red: 10/255, green: 10/255, blue: 18/255))
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
        .background(Color.white.opacity(isActive ? 0.05 : 0.02))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isActive ? VaniScriptTheme.accent.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1))
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color(red: 10 / 255, green: 10 / 255, blue: 18 / 255))
            .padding(.vertical, 9)
            .background(configuration.isPressed ? VaniScriptTheme.accentHover : VaniScriptTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SettingsSmallButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(primary ? Color(red: 10 / 255, green: 10 / 255, blue: 18 / 255) : VaniScriptTheme.text1)
            .padding(.horizontal, 10)
            .frame(height: VaniScriptTheme.Density.controlHeightMD)
            .background(primary ? VaniScriptTheme.accent : Color.white.opacity(configuration.isPressed ? 0.1 : 0.06))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(primary ? Color.clear : Color.white.opacity(0.12), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct StatItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(VaniScriptTheme.text2)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VaniScriptTheme.text0)
        }
    }
}

private struct BudgetBar: View {
    let title: String
    let spent: Double
    let limit: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(VaniScriptTheme.text2)
                Spacer()
                Text(String(format: "Spent $%.2f of $%.2f", spent, limit))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(spent > limit ? VaniScriptTheme.red : VaniScriptTheme.accent)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.1))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(spent > limit ? VaniScriptTheme.red : VaniScriptTheme.accent)
                        .frame(width: geo.size.width * CGFloat(min(1.0, spent / limit)))
                }
            }
            .frame(height: 6)
        }
        .padding(.top, 4)
    }
}

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
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(configuration.isPressed ? VaniScriptTheme.accent : VaniScriptTheme.text2)
            .frame(width: 32, height: 32)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
