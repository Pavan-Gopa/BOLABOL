import NativeBolabolCore
import SwiftUI

@MainActor
struct PromptsSettingsView: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var promptTemplateStore: PromptTemplateStore
    @State private var selectedPromptTarget = "variantOne"

    var body: some View {
        // Center the content block symmetrically in the settings window
        HStack {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Spacer(minLength: 0)
                    Picker(generalSettingsStore.text(.prompt), selection: $selectedPromptTarget) {
                        Text(generalSettingsStore.text(.variantOne))
                            .tag("variantOne")
                        Text(generalSettingsStore.text(.variantTwo))
                            .tag("variantTwo")
                        Text(generalSettingsStore.text(.markdown))
                            .tag("markdown")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 280)
                    Spacer(minLength: 0)
                }

                if selectedPromptTarget == "markdown" {
                    PromptEditorCard(
                        text: Binding(
                            get: { promptTemplateStore.markdownBody() },
                            set: { promptTemplateStore.setMarkdownBody($0) }
                        ),
                        containsPlaceholder: promptTemplateStore.markdownContainsTranscriptionPlaceholder(),
                        resetTitle: generalSettingsStore.text(.reset),
                        placeholderWarning: generalSettingsStore.text(.promptMustIncludeTranscription),
                        characterCountLabel: generalSettingsStore.formattedText(
                            .charactersCount,
                            promptTemplateStore.markdownBody().count
                        ),
                        onReset: { promptTemplateStore.resetMarkdown() }
                    )
                } else {
                    let variant: ProcessingVariant = selectedPromptTarget == "variantOne"
                        ? .variantOne
                        : .variantTwo

                    PromptSlotEditor(
                        variant: variant,
                        title: generalSettingsStore.text(variant == .variantOne ? .variantOne : .variantTwo)
                    )
                }
            }
            .frame(maxWidth: 640)
            .padding(.vertical, 4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PromptSlotEditor: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var promptTemplateStore: PromptTemplateStore
    let variant: ProcessingVariant
    let title: String

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                PromptSlotSelector(
                    selectedSlot: Binding(
                        get: { promptTemplateStore.activeSlot(for: variant) },
                        set: { promptTemplateStore.setActiveSlot($0, for: variant) }
                    ),
                    nameProvider: { promptTemplateStore.slotName(in: $0, for: variant) }
                )

                // Inline name field — only for custom slots
                if activeSlot == .default {
                    Text(promptTemplateStore.slotName(in: .default, for: variant))
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else {
                    TextField(
                        "",
                        text: Binding(
                            get: { promptTemplateStore.slotName(in: activeSlot, for: variant) },
                            set: { promptTemplateStore.setSlotName($0, in: activeSlot, for: variant) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                }

                Spacer(minLength: 0)
            }

            PromptEditorCard(
                text: Binding(
                    get: {
                        promptTemplateStore.body(
                            in: promptTemplateStore.activeSlot(for: variant),
                            for: variant
                        )
                    },
                    set: {
                        promptTemplateStore.setBody(
                            $0,
                            in: promptTemplateStore.activeSlot(for: variant),
                            for: variant
                        )
                    }
                ),
                containsPlaceholder: promptTemplateStore.containsTranscriptionPlaceholder(
                    in: promptTemplateStore.activeSlot(for: variant),
                    for: variant
                ),
                resetTitle: generalSettingsStore.text(.reset),
                placeholderWarning: generalSettingsStore.text(.promptMustIncludeTranscription),
                characterCountLabel: generalSettingsStore.formattedText(
                    .charactersCount,
                    promptTemplateStore.body(
                        in: promptTemplateStore.activeSlot(for: variant),
                        for: variant
                    ).count
                ),
                showsReset: activeSlot == .default,
                onReset: { promptTemplateStore.reset(variant) }
            )
        }
    }

    private var activeSlot: PromptSlot {
        promptTemplateStore.activeSlot(for: variant)
    }
}

private struct PromptSlotSelector: View {
    @Binding var selectedSlot: PromptSlot
    let nameProvider: (PromptSlot) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PromptSlot.allCases) { slot in
                Button {
                    selectedSlot = slot
                } label: {
                    Text(slot.shortTitle)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedSlot == slot ? .green : .secondary)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(selectedSlot == slot ? Color.green.opacity(0.16) : Color.white.opacity(0.05))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(selectedSlot == slot ? Color.green.opacity(0.55) : Color.white.opacity(0.10), lineWidth: 0.8)
                }
                .help(nameProvider(slot))
            }
        }
    }
}

private struct PromptEditorCard: View {
    let text: Binding<String>
    let containsPlaceholder: Bool
    let resetTitle: String
    let placeholderWarning: String
    let characterCountLabel: String
    var showsReset = true
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 360)
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))

            if !containsPlaceholder {
                Label(placeholderWarning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            HStack {
                if showsReset {
                    Button {
                        onReset()
                    } label: {
                        Label(resetTitle, systemImage: "arrow.counterclockwise")
                    }
                }

                Spacer()

                Text(characterCountLabel)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.45))
        }
    }
}
