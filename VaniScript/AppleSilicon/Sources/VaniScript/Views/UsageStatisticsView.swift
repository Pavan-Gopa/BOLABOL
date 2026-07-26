import SwiftUI
import VaniScriptCore

// MARK: - Role
//
// A6: Usage statistics section for the API & Usage settings tab, rebuilt to match
// the Electron reference (SettingsModal.tsx tab 7 — "Statistics"). Replaces the
// old "Cloud Usage Statistics" section in SettingsView.
//
// UI ONLY (invariant: no real-balance API — that is A7; no recording logic — A2/A5
// already fill `settings.usage` via UsageRecorder). All data is read from
// `settings.usage` ([usageKey: ProviderUsage], usageKey = "providerId:model").
//
// Structure (Electron tab 7 parity):
//   1. Last Transaction Details — the usage entry with the max lastTransactionAt,
//      lastModel badge, Prompt / Completion / Total tokens.
//   2. Active providers summary — Transcribing / Translation & Editing via
//      CloudProviderCatalog.providerDisplayName.
//   3. Per-model cards — one per usage key: "N transactions" badge, grid with
//      Prompt / Completion / Total / Audio min / Estimated spent / remaining.
//   4. Exact disclaimer string + Reset Statistics (usage = [:], as before).
struct UsageStatisticsView: View {
    @EnvironmentObject private var store: WorkflowStore

    var body: some View {
        VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space12) {
            sectionTitle("Cloud API Usage")

            // A6: Last Transaction Details — entry with the newest lastTransactionAt.
            if let latest = latestUsageEntry {
                lastTransactionCard(key: latest.key, stats: latest.value)
            }

            // A6: active provider summary (Electron "api-active-summary" card).
            activeProvidersSummary

            if sortedUsageEntries.isEmpty {
                Text("No usage recorded yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(VaniScriptTheme.text2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                // A6: per-model cards, one for each usage key ("providerId:model").
                ForEach(sortedUsageEntries, id: \.key) { entry in
                    usageCard(key: entry.key, stats: entry.value)
                }
            }

            Button(role: .destructive) {
                // A6: keep the existing reset behavior — wipe the whole usage map.
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

    /// Usage entries in a stable order: newest transaction first, then by key so
    /// entries without timestamps still render deterministically.
    private var sortedUsageEntries: [(key: String, value: ProviderUsage)] {
        store.settings.usage.sorted { lhs, rhs in
            let l = lhs.value.lastTransactionAt ?? ""
            let r = rhs.value.lastTransactionAt ?? ""
            if l != r { return l > r }
            return lhs.key < rhs.key
        }
    }

    /// The entry with the maximum lastTransactionAt (ISO-8601 strings sort
    /// lexicographically). Nil when nothing has been recorded yet.
    private var latestUsageEntry: (key: String, value: ProviderUsage)? {
        store.settings.usage
            .filter { $0.value.lastTransactionAt != nil }
            .max { ($0.value.lastTransactionAt ?? "") < ($1.value.lastTransactionAt ?? "") }
            .map { (key: $0.key, value: $0.value) }
    }

    // MARK: - Subviews

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(VaniScriptTheme.text2)
    }

    private func lastTransactionCard(key: String, stats: ProviderUsage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Last Transaction Details")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VaniScriptTheme.text0)
                Spacer()
                // A6: Electron shows the provider badge; we also have lastModel —
                // prefer it (per-model stats), falling back to the provider name.
                UsageBadge(text: stats.lastModel ?? displayName(forUsageKey: key))
            }

            let prompt = stats.lastInputTokens ?? 0
            let completion = stats.lastOutputTokens ?? 0
            HStack(spacing: VaniScriptTheme.Density.space12) {
                UsageStatCell(value: formatCount(prompt), label: "Prompt tokens")
                UsageStatCell(value: formatCount(completion), label: "Completion tokens")
                UsageStatCell(value: formatCount(prompt + completion), label: "Total tokens")
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.025))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private var activeProvidersSummary: some View {
        HStack(spacing: VaniScriptTheme.Density.space12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Transcribing")
                    .font(.system(size: 10))
                    .foregroundStyle(VaniScriptTheme.text2)
                Text(engineDisplayName(store.settings.transcriptionProvider))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VaniScriptTheme.text0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text("Translation / Editing")
                    .font(.system(size: 10))
                    .foregroundStyle(VaniScriptTheme.text2)
                Text(engineDisplayName(store.settings.translationProvider))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VaniScriptTheme.text0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.white.opacity(0.025))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func usageCard(key: String, stats: ProviderUsage) -> some View {
        let spent = estimateCost(usageKey: key, input: stats.inputTokens, output: stats.outputTokens)
        let budget = budgetLimit(forUsageKey: key)
        let remaining = max(0, budget - spent)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(displayName(forUsageKey: key))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VaniScriptTheme.text0)
                Spacer()
                UsageBadge(text: "\(stats.sessions) transactions")
            }

            // A6: Electron usage-grid — 6 metrics per card.
            let columns = [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading),
            ]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                UsageStatCell(value: formatCount(stats.inputTokens), label: "Prompt / input tokens")
                UsageStatCell(value: formatCount(stats.outputTokens), label: "Completion tokens")
                UsageStatCell(value: formatCount(stats.inputTokens + stats.outputTokens), label: "Total tokens")
                UsageStatCell(value: String(format: "%.1f", stats.audioMinutes), label: "Audio min")
                UsageStatCell(value: String(format: "$%.4f", spent), label: "Estimated spent")
                UsageStatCell(
                    value: budget > 0 ? String(format: "$%.2f", remaining) : "—",
                    label: "Estimated remaining"
                )
            }

            // A6: disclaimer — must match the Electron reference string EXACTLY.
            Text("Cost is an estimate based on locally counted text tokens; provider billing can differ.")
                .font(.system(size: 10))
                .foregroundStyle(VaniScriptTheme.text2)
        }
        .padding(12)
        .background(Color.white.opacity(0.025))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    // MARK: - Helpers

    /// Provider id part of a usage key ("providerId:model" → "providerId";
    /// keys without a model are the provider id itself). See UsageRecorder.usageKey.
    private func providerId(forUsageKey key: String) -> String {
        key.split(separator: ":", maxSplits: 1).first.map(String.init) ?? key
    }

    /// Model part of a usage key, if present.
    private func model(forUsageKey key: String) -> String? {
        let parts = key.split(separator: ":", maxSplits: 1)
        return parts.count == 2 ? String(parts[1]) : nil
    }

    /// Card title: "Provider Label · model" for per-model keys, catalog display
    /// name otherwise. Falls back to the raw id for custom/legacy keys.
    private func displayName(forUsageKey key: String) -> String {
        let provider = CloudProviderCatalog.providerDisplayName(providerId(forUsageKey: key))
        if let model = model(forUsageKey: key) {
            return "\(provider) · \(model)"
        }
        return provider
    }

    /// Display name for the transcription/translation engine ids stored in
    /// settings. Legacy engine ids are normalized to catalog ids; local engines
    /// get explicit labels (catalog only knows cloud providers).
    private func engineDisplayName(_ engineId: String) -> String {
        switch engineId {
        case "gemini-cloud": return CloudProviderCatalog.providerDisplayName(CloudProviderCatalog.geminiID)
        case "gpt-cloud": return CloudProviderCatalog.providerDisplayName(CloudProviderCatalog.openaiID)
        case "coreml-whisperkit": return "Local Whisper (Core ML)"
        case "mlx-native": return "Local MLX"
        default: return CloudProviderCatalog.providerDisplayName(engineId)
        }
    }

    /// Estimated spend for one usage entry. Same local pricing as before the A6
    /// rebuild (old SettingsView.estimateCost); providers without a local price
    /// table (qwen/openrouter/ollama) estimate as $0 until A7 brings real balances.
    private func estimateCost(usageKey key: String, input: Int, output: Int) -> Double {
        let provider = providerId(forUsageKey: key)
        switch provider {
        case CloudProviderCatalog.geminiID:
            return (Double(input) * 0.000002) + (Double(output) * 0.000008)
        case CloudProviderCatalog.openaiID:
            return (Double(input) * 0.0000025) + (Double(output) * 0.000010)
        case CloudProviderCatalog.anthropicID:
            return (Double(input) * 0.000003) + (Double(output) * 0.000015)
        default:
            if let custom = store.settings.customCloudProviders.first(where: {
                $0.label.lowercased() == provider.lowercased() || $0.id == provider
            }) {
                return (Double(input) * (custom.inputCostPerMillion / 1_000_000.0))
                    + (Double(output) * (custom.outputCostPerMillion / 1_000_000.0))
            }
            return 0.0
        }
    }

    /// Budget limit for the provider behind a usage key; 0 means "no budget set"
    /// and renders as "—" in the remaining cell (Electron behavior).
    private func budgetLimit(forUsageKey key: String) -> Double {
        let provider = providerId(forUsageKey: key)
        switch provider {
        case CloudProviderCatalog.geminiID: return store.settings.geminiBudgetUsd
        case CloudProviderCatalog.openaiID: return store.settings.openaiBudgetUsd
        case CloudProviderCatalog.qwenID: return store.settings.qwenBudgetUsd
        case CloudProviderCatalog.openrouterID: return store.settings.openrouterBudgetUsd
        default:
            if let custom = store.settings.customCloudProviders.first(where: {
                $0.label.lowercased() == provider.lowercased() || $0.id == provider
            }) {
                return custom.budgetLimitUsd
            }
            return 0.0
        }
    }

    private func formatCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}

// MARK: - Local building blocks (private, mirroring SettingsView card style)

/// Small pill badge — Electron ".s-badge" equivalent.
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

/// One value/label metric cell — Electron ".s-stats-cell" equivalent.
private struct UsageStatCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(VaniScriptTheme.text0)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(VaniScriptTheme.text2)
        }
    }
}

/// Destructive reset button — matches the old "Reset All Statistics" look.
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

