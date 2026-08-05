import AppKit
import Carbon
import ObjectiveC
import SwiftUI
import NativeBolabolCore

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
struct NativeBolabolApp: App {
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
        Window("BOLABOL!", id: "main") {
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
                .environment(\.nativeBolabolUIScale, generalSettingsStore.settings.uiScale)
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
                .environmentObject(transcriptionEngineStore)
                .environmentObject(hotkeySettingsStore)
                .environmentObject(generalSettingsStore)
                .environmentObject(usageStatisticsStore)
                .environmentObject(accessibilityPermissionStore)
                .environmentObject(glossaryStore)
                .environment(\.locale, Locale(identifier: generalSettingsStore.settings.uiLanguage.resolvedLocaleIdentifier()))
                .environment(\.nativeBolabolUIScale, generalSettingsStore.settings.uiScale)
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
    static private(set) weak var shared: AppDelegate?

    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private weak var mainWindow: NSWindow?
    private var localEscMonitor: Any?
    private var lastSettingsToggleTime: Date = .distantPast

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        configureApplicationIcon()
        configureStatusItem()
        observeWindowLifecycle()
        installEscapeMonitor()

        DispatchQueue.main.async { [weak self] in
            self?.captureMainWindowIfNeeded()
            self?.showMainWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = localEscMonitor {
            NSEvent.removeMonitor(monitor)
            localEscMonitor = nil
        }
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

extension AppDelegate {
    func configureApplicationIcon() {
        if let logo = bundledImage(named: "BOLABOL_LOGO", extension: "svg", subdirectory: "Logos") {
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
        button.toolTip = "Bolabol"

        configureStatusMenu()
        statusItem = item
    }

    func configureStatusMenu() {
        statusMenu.removeAllItems()
        statusMenu.addItem(
            withTitle: "Open Bolabol",
            action: #selector(openFromStatusItem),
            keyEquivalent: ""
        ).target = self
        statusMenu.addItem(
            withTitle: "Hide Bolabol",
            action: #selector(hideFromStatusItem),
            keyEquivalent: ""
        ).target = self
        statusMenu.addItem(.separator())
        statusMenu.addItem(
            withTitle: "Quit Bolabol",
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cycleSettingsAndMainWindow),
            name: .nativeBolabolSettingsHotkeyTriggered,
            object: nil
        )
    }

    func captureMainWindowIfNeeded() {
        guard mainWindow == nil else { return }
        guard let window = NSApp.windows.first(where: isPrimaryBolabolWindow(_:)) else { return }
        registerMainWindowIfNeeded(window)
    }

    func registerMainWindowIfNeeded(_ window: NSWindow) {
        guard isPrimaryBolabolWindow(window) else { return }

        if mainWindow !== window {
            mainWindow = window
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.titleVisibility = .visible
        }
        window.minSize = NSSize(width: 820, height: 580)
        configureMainWindowTitle(window)
    }

    func isPrimaryBolabolWindow(_ window: NSWindow) -> Bool {
        !window.isKind(of: NSPanel.self) && window.title == "BOLABOL!"
    }

    func configureMainWindowTitle(_ window: NSWindow) {
        window.title = "BOLABOL!"
        window.titleVisibility = .visible

        DispatchQueue.main.async {
            guard
                let rootView = window.contentView?.superview,
                let titleField = self.titleTextField(in: rootView, matching: window.title),
                let currentFont = titleField.font,
                let roundedDescriptor = currentFont.fontDescriptor.withDesign(.rounded),
                let roundedFont = NSFont(
                    descriptor: roundedDescriptor,
                    size: currentFont.pointSize
                )
            else {
                return
            }

            titleField.font = roundedFont
        }
    }

    func titleTextField(in view: NSView, matching title: String) -> NSTextField? {
        if let textField = view as? NSTextField,
           !textField.isEditable,
           textField.stringValue == title
        {
            return textField
        }

        for subview in view.subviews {
            if let titleField = titleTextField(in: subview, matching: title) {
                return titleField
            }
        }

        return nil
    }

    func showMainWindow() {
        captureMainWindowIfNeeded()
        guard let window = mainWindow else { return }

        window.minSize = NSSize(width: 820, height: 580)
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
        if let logo = bundledImage(
            named: "BOLABOL_status_bar_icon",
            extension: "svg",
            subdirectory: "Logos"
        ) {
            logo.isTemplate = true
            logo.size = NSSize(width: 18, height: 18)
            return logo
        }

        let fallback = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Bolabol")
        fallback?.isTemplate = true
        return fallback
    }

    func bundledImage(
        named name: String,
        extension fileExtension: String,
        subdirectory: String? = nil
    ) -> NSImage? {
        guard
            let url = Bundle.main.url(
                forResource: name,
                withExtension: fileExtension,
                subdirectory: subdirectory
            ),
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

    @objc func cycleSettingsAndMainWindow() {
        let now = Date()
        guard now.timeIntervalSince(lastSettingsToggleTime) > 0.3 else { return }
        lastSettingsToggleTime = now

        NSApp.activate(ignoringOtherApps: true)

        if let settingsWin = findOfficialSettingsWindow(), settingsWin.isVisible {
            settingsWin.orderOut(nil)
            showMainWindow()
        } else {
            hideMainWindow()
            if let settingsWin = findOfficialSettingsWindow() {
                settingsWin.makeKeyAndOrderFront(nil)
            } else {
                openSettingsWindow()
            }
        }
    }

    @objc func closeAllWindowsToTray() {
        NotificationCenter.default.post(name: .nativeBolabolDismissSheets, object: nil)

        hideMainWindow()

        if let settingsWin = findOfficialSettingsWindow() {
            settingsWin.orderOut(nil)
        }

        for window in NSApp.windows {
            let className = String(describing: type(of: window))
            if window.isVisible && !className.contains("NSStatusBar") && !className.contains("NSStatusItem") {
                window.orderOut(nil)
            }
        }
    }

    func installEscapeMonitor() {
        localEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                if self.hasVisibleAppWindows() {
                    self.closeAllWindowsToTray()
                    return nil
                }
            }
            return event
        }
    }

    func hasVisibleAppWindows() -> Bool {
        if mainWindow?.isVisible == true { return true }
        if findOfficialSettingsWindow()?.isVisible == true { return true }
        for window in NSApp.windows {
            let className = String(describing: type(of: window))
            if window.isVisible && !className.contains("NSStatusBar") && !className.contains("NSStatusItem") {
                return true
            }
        }
        return false
    }

    func findOfficialSettingsWindow() -> NSWindow? {
        NSApp.windows.first { window in
            let title = window.title
            let className = String(describing: type(of: window))
            let identifier = window.identifier?.rawValue ?? ""
            return identifier.contains("Settings") ||
                   className.contains("Settings") ||
                   className.contains("Preferences") ||
                   title == "Settings" ||
                   title == "Настройки" ||
                   title == "Ajustes" ||
                   title == "Einstellungen" ||
                   title == "Réglages" ||
                   title.contains("Settings") ||
                   title.contains("Настройки")
        }
    }

    private func openSettingsWindow() {
        if triggerSettingsMenuItem() {
            return
        }
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    private func triggerSettingsMenuItem() -> Bool {
        guard let mainMenu = NSApp.mainMenu else { return false }
        for menuItem in mainMenu.items {
            guard let submenu = menuItem.submenu else { continue }
            for item in submenu.items {
                let actionName = item.action.map { NSStringFromSelector($0) } ?? ""
                if actionName == "showSettingsWindow:" ||
                   actionName == "showPreferencesWindow:" ||
                   (item.keyEquivalent == "," && item.keyEquivalentModifierMask.contains(.command)) {
                    if let action = item.action {
                        NSApp.sendAction(action, to: item.target, from: item)
                        return true
                    }
                }
            }
        }
        return false
    }

    @objc func quitFromStatusItem() {
        NSApp.terminate(nil)
    }
}
