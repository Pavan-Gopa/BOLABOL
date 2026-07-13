import Testing
@testable import VaniScriptCore

@Suite("VaniScript MCP network policy")
struct McpNetworkPolicyTests {
    @Test("accepts public media URLs and rejects local network targets")
    func publicMediaURLPolicy() {
        #expect(McpNetworkPolicy.validatedPublicMediaURL("https://example.com/lecture.mp4") != nil)
        #expect(McpNetworkPolicy.validatedPublicMediaURL("file:///tmp/private.mp4") == nil)
        #expect(McpNetworkPolicy.validatedPublicMediaURL("http://127.0.0.1/video.mp4") == nil)
        #expect(McpNetworkPolicy.validatedPublicMediaURL("http://192.168.1.2/video.mp4") == nil)
        #expect(McpNetworkPolicy.validatedPublicMediaURL("http://169.254.169.254/latest.mp4") == nil)
        #expect(McpNetworkPolicy.validatedPublicMediaURL("https://user:pass@example.com/video.mp4") == nil)
    }
}
