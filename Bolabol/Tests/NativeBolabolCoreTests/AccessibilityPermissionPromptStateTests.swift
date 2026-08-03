import NativeBolabolCore
import Testing

@Test
func accessibilityPromptStateRequestsPromptOnlyOnceWhenUntrusted() {
    var state = AccessibilityPermissionPromptState()
    let firstRequest = state.shouldRequestPrompt(isTrusted: false)
    let secondRequest = state.shouldRequestPrompt(isTrusted: false)

    #expect(firstRequest)
    #expect(!secondRequest)
    #expect(state.didRequestPrompt)
}

@Test
func accessibilityPromptStateResetsWhenAlreadyTrusted() {
    var state = AccessibilityPermissionPromptState()
    let firstRequest = state.shouldRequestPrompt(isTrusted: false)
    let trustedRequest = state.shouldRequestPrompt(isTrusted: true)

    #expect(firstRequest)
    #expect(!trustedRequest)
    #expect(!state.didRequestPrompt)

    let nextRequest = state.shouldRequestPrompt(isTrusted: false)
    #expect(nextRequest)
}
