import Combine
import Foundation
import NativeBolabolCore

@MainActor
final class PromptTemplateStore: ObservableObject {
    private static let settingsDefaultsKey = "polishing.promptTemplateSettings"

    private let userDefaults: UserDefaults

    @Published private(set) var settings: PromptTemplateSettings {
        didSet {
            saveSettings()
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.settings = Self.loadSettings(from: userDefaults)
    }

    static func live() -> PromptTemplateStore {
        PromptTemplateStore()
    }

    func body(for variant: ProcessingVariant) -> String {
        settings.body(for: variant)
    }

    func body(in slot: PromptSlot, for variant: ProcessingVariant) -> String {
        settings.body(in: slot, for: variant)
    }

    func activeSlot(for variant: ProcessingVariant) -> PromptSlot {
        settings.activeSlot(for: variant)
    }

    func slotName(in slot: PromptSlot, for variant: ProcessingVariant) -> String {
        settings.slotName(in: slot, for: variant)
    }

    func template(for variant: ProcessingVariant) -> PromptTemplate {
        settings.template(for: variant)
    }

    func markdownTemplate() -> PromptTemplate {
        settings.markdownTemplate()
    }

    func setBody(_ body: String, for variant: ProcessingVariant) {
        settings.setBody(body, for: variant)
    }

    func setBody(_ body: String, in slot: PromptSlot, for variant: ProcessingVariant) {
        settings.setBody(body, in: slot, for: variant)
    }

    func setActiveSlot(_ slot: PromptSlot, for variant: ProcessingVariant) {
        settings.setActiveSlot(slot, for: variant)
    }

    func setSlotName(_ name: String, in slot: PromptSlot, for variant: ProcessingVariant) {
        settings.setSlotName(name, in: slot, for: variant)
    }

    func reset(_ variant: ProcessingVariant) {
        settings.reset(variant)
    }

    func markdownBody() -> String {
        settings.markdownBody
    }

    func setMarkdownBody(_ body: String) {
        settings.setMarkdownBody(body)
    }

    func resetMarkdown() {
        settings.resetMarkdown()
    }

    func containsTranscriptionPlaceholder(for variant: ProcessingVariant) -> Bool {
        body(for: variant).contains(PromptTemplate.transcriptionPlaceholder)
    }

    func containsTranscriptionPlaceholder(in slot: PromptSlot, for variant: ProcessingVariant) -> Bool {
        let body = body(in: slot, for: variant)
        return body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || body.contains(PromptTemplate.transcriptionPlaceholder)
    }

    func markdownContainsTranscriptionPlaceholder() -> Bool {
        markdownBody().contains(PromptTemplate.transcriptionPlaceholder)
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: Self.settingsDefaultsKey)
    }

    private static func loadSettings(from userDefaults: UserDefaults) -> PromptTemplateSettings {
        guard let data = userDefaults.data(forKey: settingsDefaultsKey),
              let settings = try? JSONDecoder().decode(PromptTemplateSettings.self, from: data)
        else {
            return PromptTemplateSettings()
        }

        return settings.migratedToLatestDefaults()
    }
}
