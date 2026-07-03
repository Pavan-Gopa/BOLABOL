import Combine
import Foundation
import NativeSmartScribeCore

@MainActor
final class AccessibilityPermissionStore: ObservableObject {
    private static let promptStateDefaultsKey = "accessibility.permission.promptState"

    private let userDefaults: UserDefaults

    @Published private(set) var isTrusted: Bool
    @Published private var promptState: AccessibilityPermissionPromptState {
        didSet {
            savePromptState()
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.promptState = Self.loadPromptState(from: userDefaults)
        self.isTrusted = AccessibilityPermissionService.isTrusted()
    }

    static func live() -> AccessibilityPermissionStore {
        AccessibilityPermissionStore()
    }

    func refresh() {
        isTrusted = AccessibilityPermissionService.isTrusted()

        if isTrusted {
            promptState.reset()
        }
    }

    func requestPermission() {
        refresh()

        if promptState.shouldRequestPrompt(isTrusted: isTrusted) {
            isTrusted = AccessibilityPermissionService.requestTrustPrompt()
        } else {
            AccessibilityPermissionService.openPrivacySettings()
        }

        refresh()
    }

    func openSettings() {
        AccessibilityPermissionService.openPrivacySettings()
    }

    private func savePromptState() {
        guard let data = try? JSONEncoder().encode(promptState) else { return }
        userDefaults.set(data, forKey: Self.promptStateDefaultsKey)
    }

    private static func loadPromptState(from userDefaults: UserDefaults) -> AccessibilityPermissionPromptState {
        guard let data = userDefaults.data(forKey: promptStateDefaultsKey),
              let state = try? JSONDecoder().decode(AccessibilityPermissionPromptState.self, from: data)
        else {
            return AccessibilityPermissionPromptState()
        }

        return state
    }
}
