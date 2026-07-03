import AppKit
import ObjectiveC
import SwiftUI
import NativeSmartScribeCore

// Swizzle NSScrollView so that setScrollerStyle: ALWAYS enforces .overlay,
// no matter when or how the scroll view is created. This is the only reliable
// way to prevent the flash of the default wide scrollbar when switching tabs.
private extension NSScrollView {
    static let enforceOverlayStyle: Void = {
        guard
            let original = class_getInstanceMethod(NSScrollView.self, #selector(setter: scrollerStyle)),
            let replacement = class_getInstanceMethod(NSScrollView.self, #selector(_setScrollerStyleForced(_:)))
        else { return }
        method_exchangeImplementations(original, replacement)
    }()

    @objc func _setScrollerStyleForced(_ style: NSScroller.Style) {
        // After swizzle: this selector points to the original setter — call with .overlay
        _setScrollerStyleForced(.overlay)
        if let v = verticalScroller { v.alphaValue = 0.35 }
    }
}

@main
struct NativeSmartScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var polishingEngineStore = PolishingEngineStore.live()
    @StateObject private var promptTemplateStore = PromptTemplateStore.live()
    @StateObject private var transcriptionModelStore = TranscriptionModelStore.live()
    @StateObject private var transcriptionEngineStore = TranscriptionEngineStore.live()
    @StateObject private var hotkeySettingsStore = HotkeySettingsStore.live()
    @StateObject private var generalSettingsStore = GeneralSettingsStore.live()
    @StateObject private var usageStatisticsStore = UsageStatisticsStore.live()
    @StateObject private var accessibilityPermissionStore = AccessibilityPermissionStore.live()
    @StateObject private var glossaryStore = GlossaryStore.live()

    init() {
        // Trigger swizzle once at the earliest possible moment
        NSScrollView.enforceOverlayStyle
    }

    var body: some Scene {
        Window("SmartScribe", id: "main") {
            ContentView()
                .environmentObject(polishingEngineStore)
                .environmentObject(promptTemplateStore)
                .environmentObject(transcriptionModelStore)
                .environmentObject(transcriptionEngineStore)
                .environmentObject(hotkeySettingsStore)
                .environmentObject(generalSettingsStore)
                .environmentObject(usageStatisticsStore)
                .environmentObject(accessibilityPermissionStore)
                .environmentObject(glossaryStore)
                .environment(\.locale, Locale(identifier: generalSettingsStore.settings.uiLanguage.resolvedLocaleIdentifier()))
                .environment(\.nativeSmartScribeUIScale, generalSettingsStore.settings.uiScale)
                .preferredColorScheme(generalSettingsStore.preferredColorScheme)
                .task {
                    transcriptionModelStore.reconcileModelStates()
                    polishingEngineStore.reconcileModelStates()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    transcriptionModelStore.reconcileModelStates()
                    polishingEngineStore.reconcileModelStates()
                }
        }
        .commands {
            SidebarCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(polishingEngineStore)
                .environmentObject(promptTemplateStore)
                .environmentObject(transcriptionModelStore)
                .environmentObject(hotkeySettingsStore)
                .environmentObject(generalSettingsStore)
                .environmentObject(usageStatisticsStore)
                .environmentObject(accessibilityPermissionStore)
                .environmentObject(glossaryStore)
                .environment(\.locale, Locale(identifier: generalSettingsStore.settings.uiLanguage.resolvedLocaleIdentifier()))
                .environment(\.nativeSmartScribeUIScale, generalSettingsStore.settings.uiScale)
                .preferredColorScheme(generalSettingsStore.preferredColorScheme)
                .task {
                    transcriptionModelStore.reconcileModelStates()
                    polishingEngineStore.reconcileModelStates()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    transcriptionModelStore.reconcileModelStates()
                    polishingEngineStore.reconcileModelStates()
                }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private weak var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        configureApplicationIcon()
        configureStatusItem()
        observeWindowLifecycle()

        DispatchQueue.main.async { [weak self] in
            self?.captureMainWindowIfNeeded()
            self?.showMainWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === mainWindow else { return true }
        hideMainWindow()
        return false
    }
}

private extension AppDelegate {
    func configureApplicationIcon() {
        if let logo = bundledImage(named: "New_Logo", extension: "svg") {
            NSApp.applicationIconImage = logo
            return
        }

        if let icon = bundledImage(named: "AppIcon", extension: "icns") {
            NSApp.applicationIconImage = icon
        }
    }

    func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }

        button.image = statusItemImage()
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "SmartScribe"

        configureStatusMenu()
        statusItem = item
    }

    func configureStatusMenu() {
        statusMenu.removeAllItems()
        statusMenu.addItem(
            withTitle: "Open SmartScribe",
            action: #selector(openFromStatusItem),
            keyEquivalent: ""
        ).target = self
        statusMenu.addItem(
            withTitle: "Hide SmartScribe",
            action: #selector(hideFromStatusItem),
            keyEquivalent: ""
        ).target = self
        statusMenu.addItem(.separator())
        statusMenu.addItem(
            withTitle: "Quit SmartScribe",
            action: #selector(quitFromStatusItem),
            keyEquivalent: "q"
        ).target = self
    }

    func observeWindowLifecycle() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidBecomeMain(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
    }

    func captureMainWindowIfNeeded() {
        guard mainWindow == nil else { return }
        guard let window = NSApp.windows.first(where: isPrimarySmartScribeWindow(_:)) else { return }
        registerMainWindowIfNeeded(window)
    }

    func registerMainWindowIfNeeded(_ window: NSWindow) {
        guard isPrimarySmartScribeWindow(window) else { return }

        if mainWindow !== window {
            mainWindow = window
            window.delegate = self
            window.isReleasedWhenClosed = false
        }
    }

    func isPrimarySmartScribeWindow(_ window: NSWindow) -> Bool {
        !window.isKind(of: NSPanel.self) && window.title == "SmartScribe"
    }

    func showMainWindow() {
        captureMainWindowIfNeeded()
        guard let window = mainWindow else { return }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func hideMainWindow() {
        mainWindow?.orderOut(nil)
    }

    func toggleMainWindowVisibility() {
        captureMainWindowIfNeeded()
        guard let window = mainWindow else { return }

        if window.isVisible && NSApp.isActive {
            hideMainWindow()
        } else {
            showMainWindow()
        }
    }

    func statusItemImage() -> NSImage? {
        if let logo = bundledImage(named: "New_Logo", extension: "svg") {
            logo.isTemplate = true
            logo.size = NSSize(width: 18, height: 18)
            return logo
        }

        for name in ["trayTemplate@2x", "trayTemplate"] {
            if let image = bundledImage(named: name, extension: "png") {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                return image
            }
        }

        let fallback = NSImage(systemSymbolName: "waveform", accessibilityDescription: "SmartScribe")
        fallback?.isTemplate = true
        return fallback
    }

    func bundledImage(named name: String, extension fileExtension: String) -> NSImage? {
        guard
            let url = Bundle.main.url(forResource: name, withExtension: fileExtension),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        return image
    }

    @objc func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            toggleMainWindowVisibility()
            return
        }

        switch event.type {
        case .rightMouseUp:
            statusMenu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.maxY + 6),
                in: sender
            )
        default:
            toggleMainWindowVisibility()
        }
    }

    @objc func handleWindowDidBecomeMain(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        registerMainWindowIfNeeded(window)
    }

    @objc func openFromStatusItem() {
        showMainWindow()
    }

    @objc func hideFromStatusItem() {
        hideMainWindow()
    }

    @objc func quitFromStatusItem() {
        NSApp.terminate(nil)
    }
}
