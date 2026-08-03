import NativeBolabolCore
import AppKit
import SwiftUI

@MainActor
struct SidebarView: View {
    @ObservedObject var noteStore: NoteStore
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var transcriptionEngineStore: TranscriptionEngineStore
    @EnvironmentObject private var transcriptionModelStore: TranscriptionModelStore
    @EnvironmentObject private var polishingEngineStore: PolishingEngineStore
    @EnvironmentObject private var promptTemplateStore: PromptTemplateStore
    @EnvironmentObject private var hotkeySettingsStore: HotkeySettingsStore
    @EnvironmentObject private var glossaryStore: GlossaryStore
    @State private var isConfirmingClearAll = false
    @State private var copiedNoteID: BolabolNote.ID? = nil
    @State private var isCopyAllCopied = false
    @State private var selectedAudioNote: BolabolNote? = nil

    var body: some View {
        VStack(spacing: 0) {
            List(selection: selectionBinding) {
                ForEach(noteStore.notes) { note in
                    SidebarNoteRow(
                        note: note,
                        copyTitle: generalSettingsStore.text(.copy),
                        deleteTitle: generalSettingsStore.text(.deleteNote),
                        isCopied: copiedNoteID == note.id,
                        onCopy: { copyNote(note) },
                        onDelete: { noteStore.deleteNote(note.id) },
                        onOpenAudio: note.audioRecording != nil ? { selectedAudioNote = note } : nil
                    )
                    .tag(Optional(note.id))
                    .contextMenu {
                        if note.audioRecording != nil {
                            Button {
                                retranscribeNote(note)
                            } label: {
                                Label(
                                    generalSettingsStore.text(.retranscribeNoteLabel),
                                    systemImage: "arrow.clockwise.circle"
                                )
                            }

                            Divider()
                        }

                        Button {
                            copyNote(note)
                        } label: {
                            Label(
                                generalSettingsStore.text(.copy),
                                systemImage: "doc.on.doc"
                            )
                        }
                        .disabled(note.bestDisplayText().isEmpty)

                        Button(role: .destructive) {
                            noteStore.deleteNote(note.id)
                        } label: {
                            Label(
                                generalSettingsStore.text(.deleteNote),
                                systemImage: "trash"
                            )
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(alignment: .center, spacing: 4) {
                Button {
                    _ = noteStore.addEmptyNote(title: generalSettingsStore.text(.untitledNote))
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .help(generalSettingsStore.text(.blankNote))

                Spacer(minLength: 4)

                archiveStatsText

                Spacer(minLength: 4)

                Button {
                    copyAllNotes()
                } label: {
                    Image(systemName: isCopyAllCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isCopyAllCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(noteStore.notes.copyAllText().isEmpty)
                .help(isCopyAllCopied ? generalSettingsStore.text(.copied) : generalSettingsStore.text(.copyAll))
                .animation(.easeInOut(duration: 0.15), value: isCopyAllCopied)

                Button(role: .destructive) {
                    isConfirmingClearAll = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(noteStore.notes.isEmpty ? Color.secondary.opacity(0.3) : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(noteStore.notes.isEmpty)
                .help(generalSettingsStore.text(.clearAll))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .layoutPriority(1)
        }
        .sheet(item: $selectedAudioNote) { note in
            AudioPlaybackModalView(
                note: note,
                noteStore: noteStore,
                isPresented: Binding(
                    get: { selectedAudioNote != nil },
                    set: { if !$0 { selectedAudioNote = nil } }
                )
            )
        }
        .confirmationDialog(
            generalSettingsStore.text(.clearAllConfirmation),
            isPresented: $isConfirmingClearAll,
            titleVisibility: .visible
        ) {
            Button(generalSettingsStore.text(.clearAll), role: .destructive) {
                noteStore.clearAll()
            }

            Button(generalSettingsStore.text(.cancel), role: .cancel) {}
        }
    }

    private var archiveStatsText: some View {
        let stats = noteStore.audioArchiveStats
        let formattedSize = NoteStore.formattedByteSize(stats.totalBytes)
        let megabytes = Double(stats.totalBytes) / 1_048_576.0

        let isCritical = stats.count >= 100 || megabytes >= 500
        let isWarning = stats.count >= 50 || megabytes >= 250

        let textColor: Color = isCritical ? .red : (isWarning ? .orange : .secondary)

        // Positional format args: label is %1$d count + %2$@ size;
        // tooltip is %1$@ size + %2$d count (word order may vary by locale).
        let labelText = String(
            format: generalSettingsStore.text(.archiveStatsLabel),
            locale: nil,
            stats.count as CVarArg,
            formattedSize as CVarArg
        )
        let tooltipText = String(
            format: generalSettingsStore.text(.archiveWarningTooltip),
            locale: nil,
            formattedSize as CVarArg,
            stats.count as CVarArg
        )

        return Text(labelText)
            .font(.system(size: 10, weight: (isWarning || isCritical) ? .bold : .medium, design: .monospaced))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .minimumScaleFactor(0.70)
            .help(tooltipText)
    }

    private var selectionBinding: Binding<BolabolNote.ID?> {
        Binding(
            get: { noteStore.selection },
            set: { noteStore.select($0) }
        )
    }

    private func copyNote(_ note: BolabolNote) {
        let text = note.bestDisplayText()
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) { copiedNoteID = note.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.15)) {
                if copiedNoteID == note.id { copiedNoteID = nil }
            }
        }
    }

    private func retranscribeNote(_ note: BolabolNote) {
        guard let audioRecording = note.audioRecording else { return }

        Task { @MainActor in
            let workflow = RecordingTranscriptionWorkflow(
                noteStore: noteStore,
                engine: transcriptionEngineStore.activeEngine(modelStore: transcriptionModelStore),
                glossarySettingsProvider: { glossaryStore.settings }
            )

            let languageCode = transcriptionModelStore.resolvedLanguageCode
            let forcedLanguageCode = languageCode == "auto" ? nil : languageCode
            await workflow.retranscribeExistingNote(
                noteID: note.id,
                audioFileURL: audioRecording.fileURL,
                forcedLanguageCode: forcedLanguageCode
            )

            let target = hotkeySettingsStore.settings.target
            let requestedVariants = target.requestedPolishingVariants

            if !requestedVariants.isEmpty && polishingEngineStore.canAutoPolishAfterTranscription {
                let polishingWorkflow = PolishingWorkflow(
                    noteStore: noteStore,
                    engine: polishingEngineStore.activeEngine,
                    templateProvider: { variant in
                        promptTemplateStore.template(for: variant)
                    }
                )
                await polishingWorkflow.polishNote(note.id, variants: requestedVariants)
            }
        }
    }

    private func copyAllNotes() {
        let text = noteStore.notes.copyAllText()
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) { isCopyAllCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.15)) { isCopyAllCopied = false }
        }
    }
}

private struct SidebarNoteRow: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    let note: BolabolNote
    let copyTitle: String
    let deleteTitle: String
    let isCopied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    var onOpenAudio: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(note.previewText())
                    .font(.body)
                    .lineLimit(1)

                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .bolabolFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let onOpenAudio {
                Button {
                    onOpenAudio()
                } label: {
                    Image(systemName: "waveform.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help(generalSettingsStore.text(.audioPlaybackModalTitle))
            }

            Button {
                onCopy()
            } label: {
                Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundStyle(isCopied ? .green : .secondary)
                    .animation(.easeInOut(duration: 0.15), value: isCopied)
            }
            .buttonStyle(.plain)
            .help(isCopied ? generalSettingsStore.text(.copied) : copyTitle)
            .disabled(note.bestDisplayText().isEmpty && !isCopied)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .help(deleteTitle)
        }
        .padding(.vertical, 3)
    }
}
