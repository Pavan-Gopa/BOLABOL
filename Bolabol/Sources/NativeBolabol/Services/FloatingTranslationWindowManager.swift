import AppKit
import Carbon
import NativeBolabolCore
import SwiftUI

@MainActor
final class FloatingTranslationWindowManager {
    static let shared = FloatingTranslationWindowManager()

    private var panel: NSPanel?
    private var localEventMonitor: Any?

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    private init() {}

    func show(
        audioRecorder: AudioRecorder,
        providerID: Binding<String>,
        targetLanguage: Binding<String>,
        canarySourceLanguageCode: Binding<String>,
        canaryTargetLanguageCode: Binding<String>,
        originalText: Binding<String>,
        translatedText: Binding<String>,
        generalSettingsStore: GeneralSettingsStore,
        polishingEngineStore: PolishingEngineStore,
        transcriptionModelStore: TranscriptionModelStore,
        glossaryStore: GlossaryStore,
        onTranslate: @escaping (String, String, String) async throws -> PolishingResult,
        onRecordingCompleted: @escaping (AudioRecording) async throws -> String,
        onCanaryTranslation: @escaping (AudioRecording, String, String, String) async throws -> CanaryTranslationOutput
    ) {
        let currentPanel: NSPanel
        if let existing = panel {
            currentPanel = existing
        } else {
            let styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel]
            let newPanel = CustomEscapePanel(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 580),
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )
            newPanel.title = "Bolabol Translation"
            newPanel.isFloatingPanel = true
            newPanel.level = .floating
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            newPanel.isReleasedWhenClosed = false
            newPanel.center()
            panel = newPanel
            currentPanel = newPanel
        }

        let contentView = TranslationModalView(
            audioRecorder: audioRecorder,
            providerID: providerID,
            targetLanguage: targetLanguage,
            canarySourceLanguageCode: canarySourceLanguageCode,
            canaryTargetLanguageCode: canaryTargetLanguageCode,
            originalText: originalText,
            translatedText: translatedText,
            onTranslate: onTranslate,
            onRecordingCompleted: onRecordingCompleted,
            onCanaryTranslation: onCanaryTranslation
        )
        .environmentObject(generalSettingsStore)
        .environmentObject(polishingEngineStore)
        .environmentObject(transcriptionModelStore)
        .environmentObject(glossaryStore)

        currentPanel.contentView = NSHostingView(rootView: contentView)
        currentPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        setupEscapeMonitor()
    }

    func close() {
        removeEscapeMonitor()
        panel?.orderOut(nil)
    }

    func toggle(
        audioRecorder: AudioRecorder,
        providerID: Binding<String>,
        targetLanguage: Binding<String>,
        canarySourceLanguageCode: Binding<String>,
        canaryTargetLanguageCode: Binding<String>,
        originalText: Binding<String>,
        translatedText: Binding<String>,
        generalSettingsStore: GeneralSettingsStore,
        polishingEngineStore: PolishingEngineStore,
        transcriptionModelStore: TranscriptionModelStore,
        glossaryStore: GlossaryStore,
        onTranslate: @escaping (String, String, String) async throws -> PolishingResult,
        onRecordingCompleted: @escaping (AudioRecording) async throws -> String,
        onCanaryTranslation: @escaping (AudioRecording, String, String, String) async throws -> CanaryTranslationOutput
    ) {
        if isVisible {
            close()
        } else {
            show(
                audioRecorder: audioRecorder,
                providerID: providerID,
                targetLanguage: targetLanguage,
                canarySourceLanguageCode: canarySourceLanguageCode,
                canaryTargetLanguageCode: canaryTargetLanguageCode,
                originalText: originalText,
                translatedText: translatedText,
                generalSettingsStore: generalSettingsStore,
                polishingEngineStore: polishingEngineStore,
                transcriptionModelStore: transcriptionModelStore,
                glossaryStore: glossaryStore,
                onTranslate: onTranslate,
                onRecordingCompleted: onRecordingCompleted,
                onCanaryTranslation: onCanaryTranslation
            )
        }
    }

    private func setupEscapeMonitor() {
        removeEscapeMonitor()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) && self.isVisible {
                self.close()
                return nil
            }
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
}

private class CustomEscapePanel: NSPanel {
    override func cancelOperation(_ sender: Any?) {
        if let appDelegate = AppDelegate.shared {
            appDelegate.closeAllWindowsToTray()
        } else {
            FloatingTranslationWindowManager.shared.close()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            if let appDelegate = AppDelegate.shared {
                appDelegate.closeAllWindowsToTray()
            } else {
                FloatingTranslationWindowManager.shared.close()
            }
            return
        }
        super.keyDown(with: event)
    }
}
