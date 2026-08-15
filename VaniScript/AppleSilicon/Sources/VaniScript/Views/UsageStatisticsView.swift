import SwiftUI
import VaniScriptCore

// MARK: - Role (A6 + post-A7 redesign)
//
// Usage statistics section for the API & Usage settings tab (A6 Electron tab 7 parity,
// extended with dual Last Transaction cards and real balance).
// Displays:
//   1. Last Transaction Details — separate cards for Last Transcription & Last Translation (with spent in USD).
//   2. Active providers summary (Transcribing / Translation / Editing).
//   3. 3-Cell Summary Row — OpenRouter Balance | Total Transcription Spent | Total Translation Spent.
//   4. Compact per-model usageCard — transactions, Prompt / input tokens, Completion, Total, Audio min,
//      Estimated spent / Estimated remaining.
// Honesty: "Cost is an estimate based on locally counted text tokens; provider billing can differ."
struct UsageStatisticsView: View {
    @EnvironmentObject private var store: WorkflowStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Cloud API Usage")

            // 1. Last Transaction Details (Transcription & Translation sub-cards)
            lastTransactionsSection

            // Active providers summary (A6: Transcribing / Translation / Editing)
            activeProvidersSummary

            // Real balance section (A7) — reuses CloudBalanceRow, gated by kind + key
            realBalanceSection

            // 2. 3-Cell Summary Row: Balance | Total STT Spent | Total Translation Spent
            summaryTotalsRow

            if sortedUsageEntries.isEmpty {
                Text("No usage recorded yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(VaniScriptTheme.text2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 8) {
                    ForEach(sortedUsageEntries, id: \.key) { entry in
                        usageCard(key: entry.key, stats: entry.value)
                    }
                }
            }

            Text("Cost is an estimate based on locally counted text tokens; provider billing can differ.")
                .font(.system(size: 11))
                .foregroundStyle(VaniScriptTheme.text2)
                .padding(.top, 2)

            Button(role: .destructive) {
                store.updateSettings { settings in
                    settings.usage = [:]
                }
            } label: {
                Label("Reset Statistics", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(UsageResetButtonStyle())
            .padding(.top, 4)
        }
    }

    // MARK: - Derived data

    private var sortedUsageEntries: [(key: String, value: ProviderUsage)] {
        store.settings.usage.sorted { lhs, rhs in
            let l = lhs.value.lastTransactionAt ?? ""
            let r = rhs.value.lastTransactionAt ?? ""
            if l != r { return l > r }
            return lhs.key < rhs.key
        }
    }

    /// Latest transcription transaction
    private var latestTranscriptionEntry: (key: String, value: ProviderUsage)? {
        store.settings.usage
            .filter { $0.value.lastTransactionAt != nil && ($0.value.lastPurpose == "transcription" || $0.value.audioMinutes > 0) }
            .max { ($0.value.lastTransactionAt ?? "") < ($1.value.lastTransactionAt ?? "") }
            .map { (key: $0.key, value: $0.value) }
    }

    /// Latest translation transaction
    private var latestTranslationEntry: (key: String, value: ProviderUsage)? {
        store.settings.usage
            .filter { $0.value.lastTransactionAt != nil && ($0.value.lastPurpose == "translation" || ($0.value.lastPurpose == nil && ($0.value.lastOutputTokens ?? 0) > 0)) }
            .max { ($0.value.lastTransactionAt ?? "") < ($1.value.lastTransactionAt ?? "") }
            .map { (key: $0.key, value: $0.value) }
    }


    /// A6 alias: latest transaction by lastTransactionAt (any purpose).
    private var latestUsageEntry: (key: String, value: ProviderUsage)? { latestGenericEntry }

    private var latestGenericEntry: (key: String, value: ProviderUsage)? {
        store.settings.usage
            .filter { $0.value.lastTransactionAt != nil }
            .max { ($0.value.lastTransactionAt ?? "") < ($1.value.lastTransactionAt ?? "") }
            .map { (key: $0.key, value: $0.value) }
    }

    /// Total USD spent on transcription across all STT models
    private var totalTranscriptionSpent: Double {
        store.settings.usage.reduce(0.0) { sum, entry in
            let provider = providerId(forUsageKey: entry.key)
            let modelID = model(forUsageKey: entry.key) ?? ""
            let isSTT = entry.value.audioMinutes > 0
                || (CloudProviderCatalog.supportsTranscription(providerID: provider, modelID: modelID) && !CloudProviderCatalog.supportsTranslation(providerID: provider, modelID: modelID))
            if isSTT {
                return sum + estimateCost(usageKey: entry.key, input: entry.value.inputTokens, output: entry.value.outputTokens, audioMinutes: entry.value.audioMinutes)
            }
            return sum
        }
    }

    /// Total USD spent on translation across all text LLM models
    private var totalTranslationSpent: Double {
        store.settings.usage.reduce(0.0) { sum, entry in
            let provider = providerId(forUsageKey: entry.key)
            let modelID = model(forUsageKey: entry.key) ?? ""
            let isSTT = entry.value.audioMinutes > 0
                || (CloudProviderCatalog.supportsTranscription(providerID: provider, modelID: modelID) && !CloudProviderCatalog.supportsTranslation(providerID: provider, modelID: modelID))
            if !isSTT {
                return sum + estimateCost(usageKey: entry.key, input: entry.value.inputTokens, output: entry.value.outputTokens, audioMinutes: entry.value.audioMinutes)
            }
            return sum
        }
    }

    // MARK: - Subviews

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(VaniScriptTheme.text2)
    }


    // MARK: - A6 active providers summary

    private var activeProvidersSummary: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Transcribing")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(VaniScriptTheme.text2)
                Text(engineDisplayName(store.settings.transcriptionProvider))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VaniScriptTheme.text0)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Translation / Editing")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(VaniScriptTheme.text2)
                Text(engineDisplayName(store.settings.translationProvider))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VaniScriptTheme.text0)
            }
            Spacer()
        }
        .padding(10)
        .background(VaniScriptTheme.surfaceSubtle)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(VaniScriptTheme.border, lineWidth: 1))
    }

    /// A7: real balance section reuses CloudBalanceRow for openrouterCredits / ollamaPlan with a configured key.
    @ViewBuilder
    private var realBalanceSection: some View {
        let providers = realBalanceProviders
        if !providers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Real Balance")
                ForEach(providers) { descriptor in
                    CloudBalanceRow(descriptor: descriptor, apiKey: apiKey(forProviderID: descriptor.id))
                }
            }
        }
    }

    @ViewBuilder
    private var lastTransactionsSection: some View {
        let stt = latestTranscriptionEntry
        let txt = latestTranslationEntry

        VStack(alignment: .leading, spacing: 8) {
        Text("Last Transaction Details")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(VaniScriptTheme.text0)

        if let stt = stt, let txt = txt, stt.key != txt.key {
            HStack(spacing: 8) {
                lastTransactionSubCard(
                    title: "Last Transcription",
                    icon: "waveform",
                    key: stt.key,
                    stats: stt.value,
                    isSTT: true
                )
                lastTransactionSubCard(
                    title: "Last Translation",
                    icon: "character.bubble",
                    key: txt.key,
                    stats: txt.value,
                    isSTT: false
                )
            }
        } else if let latest = stt ?? txt ?? latestGenericEntry {
            let isSTT = latest.value.lastPurpose == "transcription" || (latest.value.lastAudioMinutes ?? 0) > 0
            lastTransactionSubCard(
                title: isSTT ? "Last Transcription Transaction" : "Last Translation Transaction",
                icon: isSTT ? "waveform" : "character.bubble",
                key: latest.key,
                stats: latest.value,
                isSTT: isSTT
            )
        }
        } // Last Transaction Details
    }

    private func lastTransactionSubCard(
        title: String,
        icon: String,
        key: String,
        stats: ProviderUsage,
        isSTT: Bool
    ) -> some View {
        let modelName = stats.lastModel ?? displayName(forUsageKey: key)
        let prompt = stats.lastInputTokens ?? 0
        let completion = stats.lastOutputTokens ?? 0
        let audioMins = stats.lastAudioMinutes ?? (isSTT ? stats.audioMinutes : 0)
        let spent = estimateCost(
            usageKey: key,
            input: prompt > 0 ? prompt : (stats.sessions > 0 ? stats.inputTokens / stats.sessions : stats.inputTokens),
            output: completion > 0 ? completion : (stats.sessions > 0 ? stats.outputTokens / stats.sessions : stats.outputTokens),
            audioMinutes: audioMins
        )

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(VaniScriptTheme.accent)
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(VaniScriptTheme.text0)
                }
                Spacer()
                UsageBadge(text: modelName)
            }

            HStack(spacing: 12) {
                if isSTT && audioMins > 0 {
                    UsageStatCell(value: String(format: "%.1f min", audioMins), label: "Audio duration")
                }
                if prompt > 0 {
                    UsageStatCell(value: formatCount(prompt), label: "Prompt tokens")
                }
                if completion > 0 {
                    UsageStatCell(value: formatCount(completion), label: "Completion tokens")
                }
                if prompt > 0 || completion > 0 {
                    UsageStatCell(value: formatCount(prompt + completion), label: "Total tokens")
                }
                UsageStatCell(value: spent > 0 ? String(format: "$%.4f", spent) : "Free", label: "Spent ($)")
            }
        }
        .padding(10)
        .background(VaniScriptTheme.surfaceSubtle)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(VaniScriptTheme.accent.opacity(0.3), lineWidth: 1))
    }

    private var realBalanceProviders: [CloudProviderDescriptor] {
        CloudProviderCatalog.providers.filter { descriptor in
            let realKind = descriptor.balanceKind == .openrouterCredits || descriptor.balanceKind == .ollamaPlan
            guard realKind else { return false }
            return !apiKey(forProviderID: descriptor.id).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    @ViewBuilder
    private var summaryTotalsRow: some View {
        HStack(spacing: 8) {
            // Box 1: OpenRouter Balance
            let providers = realBalanceProviders
            if let openrouter = providers.first(where: { $0.id == CloudProviderCatalog.openrouterID }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(openrouter.label + " Balance")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(VaniScriptTheme.text2)
                    CloudBalanceRow(
                        descriptor: openrouter,
                        apiKey: apiKey(forProviderID: openrouter.id),
                        showTitleLabel: false
                    )
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(VaniScriptTheme.surfaceSubtle)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(VaniScriptTheme.border, lineWidth: 1))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenRouter Balance")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(VaniScriptTheme.text2)
                    Text("No API Key configured")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(VaniScriptTheme.text1)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(VaniScriptTheme.surfaceSubtle)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(VaniScriptTheme.border, lineWidth: 1))
            }

            // Box 2: Total Spent on Transcription
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(VaniScriptTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total STT Spent")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(VaniScriptTheme.text2)
                    Text(totalTranscriptionSpent > 0 ? String(format: "$%.4f", totalTranscriptionSpent) : "Free")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(VaniScriptTheme.text0)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VaniScriptTheme.surfaceSubtle)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(VaniScriptTheme.accent.opacity(0.25), lineWidth: 1))
            // Box 3: Total Spent on Translation
            HStack(spacing: 8) {
                Image(systemName: "character.bubble")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Translation Spent")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(VaniScriptTheme.text2)
                    Text(totalTranslationSpent > 0 ? String(format: "$%.4f", totalTranslationSpent) : "Free")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(VaniScriptTheme.text0)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VaniScriptTheme.surfaceSubtle)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.25), lineWidth: 1))
        }
    }

    private func apiKey(forProviderID id: String) -> String {
        switch id {
        case CloudProviderCatalog.openrouterID: return store.settings.openrouterApiKey
        case CloudProviderCatalog.ollamaCloudID: return store.settings.ollamaCloudApiKey
        default: return ""
        }
    }

    /// A6 per-model usageCard (alias kept via call sites).
    private func usageCard(key: String, stats: ProviderUsage) -> some View {
        compactUsageCard(key: key, stats: stats)
    }

    private func compactUsageCard(key: String, stats: ProviderUsage) -> some View {
        let provider = providerId(forUsageKey: key)
        let modelID = model(forUsageKey: key) ?? ""
        let isSTT = stats.audioMinutes > 0
            || (CloudProviderCatalog.supportsTranscription(providerID: provider, modelID: modelID) && !CloudProviderCatalog.supportsTranslation(providerID: provider, modelID: modelID))

        let spent = estimateCost(
            usageKey: key,
            input: stats.inputTokens,
            output: stats.outputTokens,
            audioMinutes: stats.audioMinutes
        )
        let budget = budgetLimit(forProviderID: provider)
        let remaining = max(0, budget - spent)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(displayName(forUsageKey: key))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(VaniScriptTheme.text0)
                Spacer()
                UsageBadge(text: "\(stats.sessions) transactions")
            }

            HStack(spacing: 14) {
                if isSTT {
                    let sttPrice = CloudProviderCatalog.sttPricing(for: modelID)
                    UsageStatCell(value: String(format: "%.1f min", stats.audioMinutes), label: "Audio min")
                    UsageStatCell(value: sttPrice.formattedPerMin, label: "Rate / min")
                    UsageStatCell(value: sttPrice.formattedPerHour, label: "Rate / hour")
                } else {
                    UsageStatCell(value: formatCount(stats.inputTokens), label: "Prompt / input tokens")
                    UsageStatCell(value: formatCount(stats.outputTokens), label: "Completion tokens")
                    UsageStatCell(value: formatCount(stats.inputTokens + stats.outputTokens), label: "Total tokens")
                }
                UsageStatCell(
                    value: spent > 0 ? String(format: "$%.4f", spent) : "Free",
                    label: "Estimated spent"
                )
                if budget > 0 {
                    UsageStatCell(
                        value: String(format: "$%.4f", remaining),
                        label: "Estimated remaining"
                    )
                }
            }
        }
        .padding(9)
        .background(VaniScriptTheme.surfaceSubtle)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(VaniScriptTheme.border, lineWidth: 1))
    }

    private func budgetLimit(forProviderID provider: String) -> Double {
        switch provider {
        case CloudProviderCatalog.geminiID, "gemini-cloud": return store.settings.geminiBudgetUsd
        case CloudProviderCatalog.openaiID, "gpt-cloud": return store.settings.openaiBudgetUsd
        case CloudProviderCatalog.qwenID: return store.settings.qwenBudgetUsd
        case CloudProviderCatalog.openrouterID: return store.settings.openrouterBudgetUsd
        default:
            if let custom = store.settings.customCloudProviders.first(where: { $0.id == provider || $0.label.lowercased() == provider.lowercased() }) {
                return custom.budgetLimitUsd
            }
            return 0
        }
    }

    // MARK: - Pricing Estimation Helper

    private func estimateCost(usageKey key: String, input: Int, output: Int, audioMinutes: Double = 0) -> Double {
        let provider = providerId(forUsageKey: key)
        let modelID = model(forUsageKey: key) ?? ""

        // Custom provider cost
        if let custom = store.settings.customCloudProviders.first(where: {
            $0.label.lowercased() == provider.lowercased() || $0.id == provider
        }) {
            return (Double(input) * (custom.inputCostPerMillion / 1_000_000.0))
                + (Double(output) * (custom.outputCostPerMillion / 1_000_000.0))
        }

        let lowerModel = modelID.lowercased()

        // Explicit free models check
        if lowerModel.contains("free") {
            return 0.0
        }

        // 1. Audio STT Models pricing
        if CloudProviderCatalog.supportsTranscription(providerID: provider, modelID: modelID) && !CloudProviderCatalog.supportsTranslation(providerID: provider, modelID: modelID) {
            if lowerModel.contains("grok-stt") || lowerModel.contains("parakeet") || lowerModel.contains("deepgram") {
                let tokenCost = (Double(input) * 0.00000010) + (Double(output) * 0.00000010)
                if tokenCost > 0 { return tokenCost }
                return audioMinutes * (0.10 / 60.0) // Grok / Nova STT default rate
            }
            if lowerModel.contains("whisper") {
                return audioMinutes * 0.006
            }
            let tokenCost = (Double(input) * 0.00000015) + (Double(output) * 0.00000060)
            return tokenCost > 0 ? tokenCost : audioMinutes * 0.002
        }

        // 2. Text Translation Models pricing
        if lowerModel.contains("gemini-2.5-flash") || lowerModel.contains("gemini-1.5-flash") || lowerModel.contains("gemini-3.5-flash") {
            return (Double(input) * 0.000000075) + (Double(output) * 0.000000300)
        }
        if lowerModel.contains("gemini-2.5-pro") || lowerModel.contains("gemini-1.5-pro") {
            return (Double(input) * 0.00000125) + (Double(output) * 0.00000500)
        }
        if lowerModel.contains("gpt-4o-mini") {
            return (Double(input) * 0.00000015) + (Double(output) * 0.00000060)
        }
        if lowerModel.contains("gpt-4o") {
            return (Double(input) * 0.0000025) + (Double(output) * 0.0000100)
        }
        if lowerModel.contains("claude-3-5-sonnet") || lowerModel.contains("sonnet") {
            return (Double(input) * 0.0000030) + (Double(output) * 0.0000150)
        }
        if lowerModel.contains("qwen") {
            return (Double(input) * 0.00000035) + (Double(output) * 0.00000105)
        }

        // Default cloud provider fallback calculation
        switch provider {
        case CloudProviderCatalog.geminiID:
            return (Double(input) * 0.000000075) + (Double(output) * 0.000000300)
        case CloudProviderCatalog.openaiID:
            return (Double(input) * 0.00000015) + (Double(output) * 0.00000060)
        case CloudProviderCatalog.anthropicID:
            return (Double(input) * 0.0000030) + (Double(output) * 0.0000150)
        default:
            let tokenCost = (Double(input) * 0.00000020) + (Double(output) * 0.00000080)
            if tokenCost > 0 { return tokenCost }
            return audioMinutes * 0.002
        }
    }

    private func providerId(forUsageKey key: String) -> String {
        key.split(separator: ":", maxSplits: 1).first.map(String.init) ?? key
    }

    private func model(forUsageKey key: String) -> String? {
        let parts = key.split(separator: ":", maxSplits: 1)
        return parts.count == 2 ? String(parts[1]) : nil
    }


    private func engineDisplayName(_ providerID: String) -> String {
        switch providerID {
        case "gemini-cloud": return CloudProviderCatalog.providerDisplayName(CloudProviderCatalog.geminiID)
        case "gpt-cloud": return CloudProviderCatalog.providerDisplayName(CloudProviderCatalog.openaiID)
        default: return CloudProviderCatalog.providerDisplayName(providerID)
        }
    }

    private func displayName(forUsageKey key: String) -> String {
        let provider = CloudProviderCatalog.providerDisplayName(providerId(forUsageKey: key))
        if let model = model(forUsageKey: key) {
            return "\(provider) · \(model)"
        }
        return provider
    }

    private func formatCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}

private struct UsageBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(VaniScriptTheme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(VaniScriptTheme.accent.opacity(0.12))
            .clipShape(Capsule())
            .lineLimit(1)
    }
}

private struct UsageStatCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(VaniScriptTheme.text0)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(VaniScriptTheme.text2)
        }
    }
}

private struct UsageResetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(VaniScriptTheme.red)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(VaniScriptTheme.red.opacity(configuration.isPressed ? 0.18 : 0.10))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(VaniScriptTheme.red.opacity(0.3), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
