import AppKit
import SwiftUI
import VaniScriptCore

@main
struct VaniScriptApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var workflowStore = WorkflowStore()

    var body: some Scene {
        WindowGroup(AppIdentity.displayName) {
            ContentView()
                .environmentObject(workflowStore)
                .frame(minWidth: 980, minHeight: 680)
                .task {
                    workflowStore.reconcileLocalModelStates()
                    workflowStore.startFirstRunOnboardingIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    workflowStore.reconcileLocalModelStates()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(workflowStore)
                .frame(width: 760, height: 620)
                .task {
                    workflowStore.reconcileLocalModelStates()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    workflowStore.reconcileLocalModelStates()
                }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NativeFontRegistry.registerVisualEditorFonts()

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Dynamic Dock Icon setup to bypass macOS icon caching lag
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        } else if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                  let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
