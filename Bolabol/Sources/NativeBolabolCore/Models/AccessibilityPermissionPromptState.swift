public struct AccessibilityPermissionPromptState: Codable, Equatable, Sendable {
    public private(set) var didRequestPrompt: Bool

    public init(didRequestPrompt: Bool = false) {
        self.didRequestPrompt = didRequestPrompt
    }

    public mutating func shouldRequestPrompt(isTrusted: Bool) -> Bool {
        if isTrusted {
            didRequestPrompt = false
            return false
        }

        guard !didRequestPrompt else {
            return false
        }

        didRequestPrompt = true
        return true
    }

    public mutating func reset() {
        didRequestPrompt = false
    }
}
