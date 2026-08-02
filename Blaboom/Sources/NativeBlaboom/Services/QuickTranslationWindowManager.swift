import AppKit
import Carbon
import NativeBlaboomCore
import SwiftUI

@MainActor
final class QuickTranslationWindowManager {
  static let shared = QuickTranslationWindowManager()

  private var panel: NSPanel?
  private var localEventMonitor: Any?

  var isVisible: Bool {
    panel?.isVisible ?? false
  }

  private init() {}

  func show(text: String, generalSettingsStore: GeneralSettingsStore) {
    let currentPanel: NSPanel
    if let existing = panel {
      currentPanel = existing
    } else {
      let styleMask: NSWindow.StyleMask = [
        .titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel,
      ]
      let newPanel = QuickEscapePanel(
        contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
        styleMask: styleMask,
        backing: .buffered,
        defer: false
      )
      newPanel.title = "Blaboom Quick Translation"
      newPanel.isFloatingPanel = true
      newPanel.level = .floating
      newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      newPanel.isReleasedWhenClosed = false
      newPanel.center()
      panel = newPanel
      currentPanel = newPanel
    }

    let contentView = QuickTranslationContentView(
      text: text,
      generalSettingsStore: generalSettingsStore
    )

    currentPanel.contentView = NSHostingView(rootView: contentView)
    currentPanel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    setupEscapeMonitor()
  }

  func close() {
    removeEscapeMonitor()
    panel?.orderOut(nil)
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

private struct QuickTranslationContentView: View {
  let text: String
  @ObservedObject var generalSettingsStore: GeneralSettingsStore

  private var font: Font {
    let size = 16.0 * generalSettingsStore.settings.textScale
    switch generalSettingsStore.settings.textFont {
    case .system:
      return .system(size: size)
    case .serif:
      return .system(size: size, design: .serif)
    case .monospaced:
      return .system(size: size, design: .monospaced)
    }
  }

  var body: some View {
    Group {
      if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        VStack(spacing: 14) {
          BlaboomLogoWithWordmarkView(height: 38)

          Text(generalSettingsStore.text(.onboardingWelcomeTitle))
            .font(.title2.bold())

          Text(generalSettingsStore.text(.translationPlaceholder))
            .font(.body)
            .foregroundStyle(.secondary)

          Text(generalSettingsStore.text(.translationOriginalPlaceholder))
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          Text(text)
            .font(font)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

private class QuickEscapePanel: NSPanel {
  override func cancelOperation(_ sender: Any?) {
    if let appDelegate = AppDelegate.shared {
      appDelegate.closeAllWindowsToTray()
    } else {
      QuickTranslationWindowManager.shared.close()
    }
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == UInt16(kVK_Escape) {
      if let appDelegate = AppDelegate.shared {
        appDelegate.closeAllWindowsToTray()
      } else {
        QuickTranslationWindowManager.shared.close()
      }
      return
    }
    super.keyDown(with: event)
  }
}
