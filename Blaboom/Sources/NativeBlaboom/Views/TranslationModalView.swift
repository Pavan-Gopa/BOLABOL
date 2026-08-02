import AppKit
import NativeBlaboomCore
import SwiftUI

@MainActor
struct TranslationModalView: View {
    struct Provider: Identifiable, Equatable {
        let id: String
        let displayName: String
    }

    struct LanguageOption: Identifiable, Equatable {
        let id: String
        let displayName: String
    }

    // MARK: – MLX tag helpers (shared with ContentView)
    static let localMLXPrefix = "local-mlx:"

    static func localMLXTag(for modelID: String) -> String {
        "\(localMLXPrefix)\(modelID)"
    }

    static func localMLXModelID(from tag: String) -> String? {
        guard tag.hasPrefix(localMLXPrefix) else { return nil }
        return String(tag.dropFirst(localMLXPrefix.count))
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var polishingEngineStore: PolishingEngineStore
    @EnvironmentObject private var glossaryStore: GlossaryStore
    @ObservedObject var audioRecorder: AudioRecorder

    @Binding var providerID: String
    @Binding var targetLanguage: String
    @Binding var originalText: String
    @Binding var translatedText: String
    let onTranslate: (String, String, String) async throws -> PolishingResult
    let onRecordingCompleted: (AudioRecording) async throws -> String

    @State private var selectedOriginalText = ""
    @State private var selectedTranslatedText = ""
    @State private var isTranslating = false
    @State private var isTranscribingRecording = false
    @State private var isTogglingRecording = false
    @State private var errorMessage: String?
    @State private var toastMessage: String?
    @State private var glossaryDraft: TranslationGlossaryDraft?

    // Live list built from the store — always up-to-date
    private var providers: [Provider] {
        // Cloud providers that have a valid API key configured
        let cloudProviders: [Provider] = polishingEngineStore.descriptors
            .filter { descriptor in
                descriptor.id != "local-rule-based-polish"
                    && descriptor.id != PolishingEngineStore.disabledEngineID
                    && descriptor.id != PolishingEngineStore.mlxSwiftEngineID
            }
            .map { Provider(id: $0.id, displayName: $0.displayName) }

        // One entry per downloaded MLX model (catalog + custom local)
        let downloadedCatalog = polishingEngineStore.models
            .filter { polishingEngineStore.installationState(for: $0).isDownloaded }
        let allMLXModels = downloadedCatalog + polishingEngineStore.customModels
        let mlxProviders: [Provider] = allMLXModels
            .map { model in
                Provider(
                    id: Self.localMLXTag(for: model.id),
                    displayName: model.displayName
                )
            }

        return cloudProviders + mlxProviders
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            controls

            HSplitView {
                translationTextPanel(
                    title: generalSettingsStore.text(.originalText),
                    text: $originalText,
                    selectedText: $selectedOriginalText,
                    placeholder: generalSettingsStore.text(.translationOriginalPlaceholder),
                    isEditable: true,
                    side: .source
                )

                translationTextPanel(
                    title: generalSettingsStore.text(.translatedText),
                    text: $translatedText,
                    selectedText: $selectedTranslatedText,
                    placeholder: isTranslating
                        ? generalSettingsStore.text(.translating)
                        : generalSettingsStore.text(.translationPlaceholder),
                    isEditable: false,
                    side: .translation
                )
            }
            .frame(minHeight: 280)

            if let toastMessage {
                Label(toastMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .blaboomFont(.caption)
            } else if let statusMessage {
                Label(statusMessage, systemImage: statusIconName)
                    .foregroundStyle(statusTint)
                    .blaboomFont(.caption)
            } else if let recorderErrorMessage = audioRecorder.errorMessage {
                Label(recorderErrorMessage, systemImage: "mic.slash")
                    .foregroundStyle(.orange)
                    .blaboomFont(.caption)
            } else if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .blaboomFont(.caption)
            }

            footer
        }
        .padding(20)
        .frame(minWidth: 780, minHeight: 520)
        .onAppear {
            audioRecorder.refreshInputDeviceStatus()
            // If saved providerID is no longer in the live list, reset to first available
            if !providers.contains(where: { $0.id == providerID }) {
                providerID = providers.first?.id ?? ""
            }
            if targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                targetLanguage = Self.defaultLanguages.first?.id ?? "English"
            }
        }
        .onChange(of: providers) { _, newProviders in
            // Keep selection valid if the list changes while modal is open
            if !newProviders.contains(where: { $0.id == providerID }) {
                providerID = newProviders.first?.id ?? ""
            }
        }
        .sheet(item: $glossaryDraft) { draft in
            GlossaryDraftModal(
                selectedText: draft.selectedText,
                initialSide: draft.side,
                authorTranscriptionLanguage: glossaryStore.settings.authorTranscriptionLanguage,
                autoTranslationLanguage: targetLanguage,
                entries: glossaryStore.settings.entries,
                categories: glossaryStore.categories,
                onCancel: { glossaryDraft = nil },
                onSave: { request in
                    saveGlossaryDraft(request, draft: draft)
                }
            )
        }
    }

    // MARK: – Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "translate")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            Text(generalSettingsStore.text(.translateSelectionOrClipboard))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            TranslationCloseButton {
                dismiss()
                FloatingTranslationWindowManager.shared.close()
            }
        }
    }

    // MARK: – Controls

    private var activeProviderKind: APIProviderKind? {
        APIProviderKind.allCases.first(where: { $0.polishingEngineID == providerID })
    }

    private var controls: some View {
        HStack(spacing: 16) {
            // 1. Provider Dropdown (Left)
            HStack(spacing: 6) {
                Text(generalSettingsStore.text(.provider))
                    .foregroundStyle(.secondary)
                    .font(.subheadline)

                Picker(generalSettingsStore.text(.provider), selection: $providerID) {
                    ForEach(providers) { provider in
                        Text(provider.displayName).tag(provider.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220, alignment: .leading)
            }

            // 2. Model Dropdown (Center) — Strictly Favorite models only
            if let activeKind = activeProviderKind {
                let favs = favoriteModels(for: activeKind)
                let currentModelID = polishingEngineStore.apiSettings.configuration(for: activeKind).textModel

                HStack(spacing: 6) {
                    Text(generalSettingsStore.text(.model))
                        .foregroundStyle(.secondary)
                        .font(.subheadline)

                    if favs.isEmpty {
                        Text(modelDisplayName(id: currentModelID, kind: activeKind))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    } else {
                        Picker(generalSettingsStore.text(.model), selection: selectedModelBinding(for: activeKind)) {
                            ForEach(favs, id: \.id) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 220, alignment: .leading)
                    }
                }
            }

            Spacer(minLength: 8)

            // 3. Target Language Dropdown (Right)
            HStack(spacing: 6) {
                Text(generalSettingsStore.text(.targetLanguage))
                    .foregroundStyle(.secondary)
                    .font(.subheadline)

                Picker(generalSettingsStore.text(.targetLanguage), selection: $targetLanguage) {
                    ForEach(Self.defaultLanguages) { language in
                        Text(language.displayName).tag(language.id)
                    }
                }
                .labelsHidden()
                .frame(width: 140, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: – Footer

    private var footer: some View {
        HStack(spacing: 8) {
            // Clear
            TranslationIconButton(
                systemImage: "xmark.circle",
                helpText: generalSettingsStore.text(.clear),
                isDisabled: isClearingDisabled
            ) { clearContent() }

            // Record button — morphing style matching ModernRecordButton on main screen
            Button { toggleRecording() } label: {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1.5)
                        .frame(width: 36, height: 36)
                    RoundedRectangle(
                        cornerRadius: audioRecorder.isRecording ? 5 : 14,
                        style: .continuous
                    )
                    .strokeBorder(Color.red, lineWidth: audioRecorder.isRecording ? 7.5 : 2.5)
                    .frame(
                        width: audioRecorder.isRecording ? 16 : 26,
                        height: audioRecorder.isRecording ? 16 : 26
                    )
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.7), value: audioRecorder.isRecording)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isTogglingRecording || isTranslating || isTranscribingRecording)
            .help(audioRecorder.isRecording
                  ? generalSettingsStore.text(.stopRecording)
                  : generalSettingsStore.text(.record))

            // Audio Input Device Status Pill next to Record button
            AudioInputDeviceStatusPill(audioRecorder: audioRecorder, compact: true)
                .frame(maxWidth: 180)

            Spacer()

            // Refresh translation
            TranslationIconButton(
                systemImage: "arrow.clockwise",
                helpText: generalSettingsStore.text(.translate),
                isDisabled: isTranslating
                    || originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || providerID.isEmpty
            ) { Task { await translate() } }

            // Translate button
            ActionPillButton(
                systemImage: "translate",
                label: generalSettingsStore.text(.translate),
                isDisabled: isTranslating
                    || originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || providerID.isEmpty
            ) { Task { await translate() } }

            // Copy button — right next to Translate
            ActionPillButton(
                systemImage: "doc.on.doc",
                label: generalSettingsStore.text(.copy),
                isDisabled: translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) { copyTranslatedTextWithFeedback() }
        }
    }

    // MARK: – Text Panel

    private func translationTextPanel(
        title: String,
        text: Binding<String>,
        selectedText: Binding<String>,
        placeholder: String,
        isEditable: Bool,
        side: GlossaryDraftSide
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .blaboomFont(.headline, weight: .semibold)

                Spacer()

                if side == .source {
                    Button {
                        pasteFromClipboardAndTranslate()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 11))
                            Text(generalSettingsStore.text(.pasteFromClipboard))
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.borderless)
                    .help(generalSettingsStore.text(.pasteFromClipboardHelp))
                }
            }

            SelectableTextView(
                text: text,
                selectedText: selectedText,
                placeholder: placeholder,
                isEditable: isEditable,
                selectionActionTitle: "Add to Glossary",
                onSelectionAction: { selectedText in
                    beginGlossaryDraft(
                        selectedText: selectedText,
                        side: side
                    )
                },
                onDoubleClick: side == .source ? { pasteFromClipboardAndTranslate() } : nil,
                onClick: side == .translation ? { copyTranslatedTextWithFeedback() } : nil,
                textScale: generalSettingsStore.settings.textScale,
                textFont: generalSettingsStore.settings.textFont
            )
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator.opacity(0.45))
            }
        }
        .padding(2)
    }

    // MARK: – Actions

    private func translate() async {
        let text = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !providerID.isEmpty else {
            translatedText = generalSettingsStore.text(.noTranslationProvider)
            errorMessage = nil
            return
        }
        isTranslating = true
        errorMessage = nil
        translatedText = ""
        defer { isTranslating = false }
        do {
            let result = try await onTranslate(text, targetLanguage, providerID)
            translatedText = result.text
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleRecording() {
        guard !isTogglingRecording else { return }
        isTogglingRecording = true
        errorMessage = nil
        Task { @MainActor in
            defer { isTogglingRecording = false }
            if audioRecorder.isRecording {
                guard let recording = audioRecorder.stop() else { return }
                AudioCuePlayer.shared.play(.finish, settings: generalSettingsStore.settings.overlay)
                isTranscribingRecording = true
                translatedText = generalSettingsStore.text(.transcribing)
                do {
                    originalText = try await onRecordingCompleted(recording)
                    if providerID.isEmpty {
                        translatedText = generalSettingsStore.text(.noTranslationProvider)
                    } else {
                        await translate()
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
                isTranscribingRecording = false
            } else {
                translatedText = ""
                errorMessage = nil
                await audioRecorder.start()
                if audioRecorder.isRecording {
                    AudioCuePlayer.shared.play(.start, settings: generalSettingsStore.settings.overlay)
                }
            }
        }
    }

    private var statusMessage: String? {
        if audioRecorder.isRecording { return generalSettingsStore.text(.record) }
        if isTranscribingRecording { return generalSettingsStore.text(.transcribing) }
        if isTranslating { return generalSettingsStore.text(.translating) }
        return nil
    }

    private var statusIconName: String {
        if audioRecorder.isRecording { return "record.circle.fill" }
        if isTranscribingRecording { return "waveform.and.mic" }
        return "translate"
    }

    private var statusTint: Color {
        if audioRecorder.isRecording { return .red }
        if isTranscribingRecording { return .blue }
        return .secondary
    }

    private var isClearingDisabled: Bool {
        let original = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let translated = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return audioRecorder.isRecording || isTogglingRecording || isTranscribingRecording
            || isTranslating
            || (original.isEmpty && translated.isEmpty && errorMessage == nil && audioRecorder.errorMessage == nil)
    }

    private func clearContent() {
        guard !audioRecorder.isRecording else { return }
        originalText = ""
        translatedText = ""
        selectedOriginalText = ""
        selectedTranslatedText = ""
        errorMessage = nil
        isTranscribingRecording = false
    }

    private func copyTranslatedText() {
        copyTranslatedTextWithFeedback()
    }

    private func pasteFromClipboardAndTranslate() {
        guard let clipboardText = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !clipboardText.isEmpty else { return }
        originalText = clipboardText
        showToast("Pasted from clipboard")
        if !providerID.isEmpty {
            Task { await translate() }
        }
    }

    private func copyTranslatedTextWithFeedback() {
        let text = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showToast("Copied to clipboard!")
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    private func beginGlossaryDraft(selectedText: String, side: GlossaryDraftSide) {
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return }
        glossaryDraft = TranslationGlossaryDraft(selectedText: selected, side: side)
    }

    private func saveGlossaryDraft(
        _ request: GlossaryDraftSaveRequest,
        draft: TranslationGlossaryDraft
    ) {
        if let existingEntryID = request.existingEntryID {
            glossaryStore.addGlossaryVariants(
                to: existingEntryID,
                variants: [request.selectedText]
            )
        } else {
            glossaryStore.createGlossaryEntryFromReview(
                selectedText: request.selectedText,
                source: request.source,
                translation: request.translation,
                category: request.category,
                side: request.side
            )
        }

        glossaryDraft = nil

        switch draft.side {
        case .source:
            originalText = glossaryStore.apply(to: originalText, target: .source).text
        case .translation:
            translatedText = glossaryStore.apply(
                to: translatedText,
                target: .translation,
                language: targetLanguage
            ).text
        }
    }

    private struct ModelOption: Identifiable, Equatable {
        let id: String
        let displayName: String
    }

    private func cleanModelDisplayName(_ raw: String) -> String {
        var name = raw
        // If format is provider/model-id (e.g. google/gemini-3.5-flash-lite), strip the provider/ prefix
        if let slashIndex = name.firstIndex(of: "/") {
            name = String(name[name.index(after: slashIndex)...])
        }
        return name
    }

    private func availableModels(for kind: APIProviderKind) -> [ModelOption] {
        switch kind {
        case .google:
            return [
                ModelOption(id: "gemini-3.5-flash", displayName: "Gemini 3.5 Flash"),
                ModelOption(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash"),
                ModelOption(id: "gemini-2.5-flash-lite", displayName: "Gemini 2.5 Flash Lite"),
                ModelOption(id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro"),
                ModelOption(id: "gemini-2.0-flash", displayName: "Gemini 2.0 Flash")
            ]
        case .openAI:
            return [
                ModelOption(id: "gpt-4o-mini", displayName: "GPT-4o Mini"),
                ModelOption(id: "gpt-4o", displayName: "GPT-4o"),
                ModelOption(id: "o3-mini", displayName: "o3-mini"),
                ModelOption(id: "gpt-4-turbo", displayName: "GPT-4 Turbo")
            ]
        case .qwen:
            return [
                ModelOption(id: "qwen3.6-flash", displayName: "Qwen 3.6 Flash"),
                ModelOption(id: "qwen3.7-plus", displayName: "Qwen 3.7 Plus"),
                ModelOption(id: "qwen3.8-max-preview", displayName: "Qwen 3.8 Max"),
                ModelOption(id: "qwen-turbo", displayName: "Qwen Turbo"),
                ModelOption(id: "qwen-max", displayName: "Qwen Max")
            ]
        case .openRouter:
            return [
                ModelOption(id: "google/gemini-3.5-flash", displayName: "Gemini 3.5 Flash"),
                ModelOption(id: "deepseek/deepseek-v4-flash", displayName: "DeepSeek V4 Flash"),
                ModelOption(id: "qwen/qwen3.6-flash", displayName: "Qwen 3.6 Flash"),
                ModelOption(id: "openai/gpt-4o-mini", displayName: "GPT-4o Mini"),
                ModelOption(id: "anthropic/claude-3.5-haiku", displayName: "Claude 3.5 Haiku"),
                ModelOption(id: "google/gemini-2.5-flash", displayName: "Gemini 2.5 Flash"),
                ModelOption(id: "deepseek/deepseek-chat", displayName: "DeepSeek V3")
            ]
        case .custom:
            let current = polishingEngineStore.apiSettings.configuration(for: .custom).textModel
            return [ModelOption(id: current, displayName: cleanModelDisplayName(current))]
        case .anthropic:
            return [
                ModelOption(id: "claude-3-5-haiku-latest", displayName: "Claude 3.5 Haiku"),
                ModelOption(id: "claude-3-5-sonnet-latest", displayName: "Claude 3.5 Sonnet")
            ]
        }
    }

    private func favoriteModels(for kind: APIProviderKind) -> [ModelOption] {
        let favSet = FavoriteModelsStore.loadFavorites()
        let baseOptions = availableModels(for: kind)
        var result = baseOptions.filter { favSet.contains($0.id) }

        // Also dynamically include any starred model IDs from settings matching this provider
        for id in favSet {
            if !result.contains(where: { $0.id == id }) && matchesProvider(modelID: id, kind: kind) {
                result.append(ModelOption(id: id, displayName: modelDisplayName(id: id, kind: kind)))
            }
        }

        // If no favorites are saved for this provider, show all available models
        if result.isEmpty {
            result = baseOptions
        }

        // Always ensure the currently active model is present so SwiftUI Picker tag matches
        let currentID = polishingEngineStore.apiSettings.configuration(for: kind).textModel
        if !currentID.isEmpty && !result.contains(where: { $0.id == currentID }) && matchesProvider(modelID: currentID, kind: kind) {
            result.insert(ModelOption(id: currentID, displayName: modelDisplayName(id: currentID, kind: kind)), at: 0)
        }

        // Clean display names and deduplicate entries by clean display name and ID
        var seenKeys = Set<String>()
        var deduplicated: [ModelOption] = []
        for option in result {
            let cleanName = cleanModelDisplayName(option.displayName)
            let key = cleanName.lowercased()
            if !seenKeys.contains(key) {
                seenKeys.insert(key)
                deduplicated.append(ModelOption(id: option.id, displayName: cleanName))
            }
        }

        return deduplicated
    }

    private func matchesProvider(modelID: String, kind: APIProviderKind) -> Bool {
        let lower = modelID.lowercased()
        // OpenRouter and Custom model IDs contain slashes (e.g. google/gemini-3.5-flash-lite).
        // Direct providers (Google, OpenAI, Anthropic, Qwen) do not use slashes in model IDs.
        if kind != .openRouter && kind != .custom && lower.contains("/") {
            return false
        }
        switch kind {
        case .google:
            return lower.contains("gemini") || lower.contains("gemma") || lower.contains("google") || lower.contains("lyra")
        case .openAI:
            return lower.contains("gpt") || lower.contains("o3") || lower.contains("o1") || lower.contains("openai")
        case .qwen:
            return lower.contains("qwen") || lower.contains("deepseek") || lower.contains("glm")
        case .openRouter:
            return lower.contains("/")
        case .anthropic:
            return lower.contains("claude") || lower.contains("anthropic")
        case .custom:
            return true
        }
    }

    private func modelDisplayName(id: String, kind: APIProviderKind) -> String {
        let available = availableModels(for: kind)
        if let match = available.first(where: { $0.id == id }) {
            return cleanModelDisplayName(match.displayName)
        }
        return id.isEmpty ? generalSettingsStore.text(.defaultModelName) : cleanModelDisplayName(id)
    }

    private func selectedModelBinding(for kind: APIProviderKind) -> Binding<String> {
        Binding(
            get: {
                let current = polishingEngineStore.apiSettings.configuration(for: kind).textModel
                let favs = favoriteModels(for: kind)
                if favs.contains(where: { $0.id == current }) {
                    return current
                }
                return favs.first?.id ?? current
            },
            set: { newModelID in
                var config = polishingEngineStore.apiSettings.configuration(for: kind)
                config.textModel = newModelID
                polishingEngineStore.updateAPIConfiguration(config, for: kind)
            }
        )
    }

    private static let defaultLanguages = [
        LanguageOption(id: "English", displayName: "English"),
        LanguageOption(id: "Russian", displayName: "Русский"),
        LanguageOption(id: "Spanish", displayName: "Español"),
        LanguageOption(id: "French", displayName: "Français"),
        LanguageOption(id: "German", displayName: "Deutsch"),
        LanguageOption(id: "Italian", displayName: "Italiano"),
        LanguageOption(id: "Portuguese", displayName: "Português"),
        LanguageOption(id: "Chinese", displayName: "中文"),
        LanguageOption(id: "Japanese", displayName: "日本語"),
        LanguageOption(id: "Korean", displayName: "한국어"),
        LanguageOption(id: "Hindi", displayName: "हिन्दी")
    ]
}

private struct TranslationGlossaryDraft: Identifiable, Equatable {
    let id = UUID()
    var selectedText: String
    var side: GlossaryDraftSide
}

// MARK: – Private button components

/// Small square icon button — dark glass style matching main screen bottom bar
private struct TranslationIconButton: View {
    let systemImage: String
    let helpText: String
    var isDisabled: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(isHovered && !isDisabled ? 0.1 : 0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDisabled ? .tertiary : .secondary)
        .disabled(isDisabled)
        .help(helpText)
        .onHover { isHovered = $0 }
    }
}

/// Action pill button (Translate, Copy, etc.) — clean balanced style
private struct ActionPillButton: View {
    let systemImage: String
    let label: String
    let isDisabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(isHovered && !isDisabled ? 0.14 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDisabled ? .tertiary : .primary)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
    }
}

/// Close (×) button — square, subtle red tint on hover
private struct TranslationCloseButton: View {
    let action: () -> Void
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.red.opacity(0.15) : Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isHovered ? Color.red.opacity(0.35) : Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .foregroundStyle(isHovered ? Color.red : Color.secondary)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .help(generalSettingsStore.text(.close))
        .onHover { isHovered = $0 }
    }
}
