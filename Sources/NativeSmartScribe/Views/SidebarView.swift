import NativeSmartScribeCore
import AppKit
import SwiftUI

struct SidebarView: View {
    @ObservedObject var noteStore: NoteStore
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @State private var isConfirmingClearAll = false
    @State private var copiedNoteID: SmartScribeNote.ID? = nil
    @State private var isCopyAllCopied = false

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
                        onDelete: { noteStore.deleteNote(note.id) }
                    )
                        .tag(Optional(note.id))
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 8) {
                Button {
                    _ = noteStore.addEmptyNote(title: generalSettingsStore.text(.untitledNote))
                } label: {
                    Label(generalSettingsStore.text(.blankNote), systemImage: "square.and.pencil")
                }
                .help(generalSettingsStore.text(.blankNote))

                Spacer()

                Button {
                    copyAllNotes()
                } label: {
                    Label(
                        generalSettingsStore.text(.copyAll),
                        systemImage: isCopyAllCopied ? "checkmark.circle.fill" : "doc.on.doc"
                    )
                }
                .disabled(noteStore.notes.copyAllText().isEmpty)
                .help(isCopyAllCopied ? generalSettingsStore.text(.copied) : generalSettingsStore.text(.copyAll))
                .foregroundStyle(isCopyAllCopied ? .green : .primary)
                .animation(.easeInOut(duration: 0.15), value: isCopyAllCopied)

                Button(role: .destructive) {
                    isConfirmingClearAll = true
                } label: {
                    Label(generalSettingsStore.text(.clearAll), systemImage: "trash")
                }
                .disabled(noteStore.notes.isEmpty)
                .help(generalSettingsStore.text(.clearAll))
            }
            .labelStyle(.iconOnly)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
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

    private var selectionBinding: Binding<SmartScribeNote.ID?> {
        Binding(
            get: { noteStore.selection },
            set: { noteStore.select($0) }
        )
    }

    private func copyNote(_ note: SmartScribeNote) {
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
    let note: SmartScribeNote
    let copyTitle: String
    let deleteTitle: String
    let isCopied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: note.audioRecording == nil ? "doc.text" : "waveform")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(note.previewText())
                    .font(.body)
                    .lineLimit(1)

                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .smartScribeFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

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
