import Foundation
import Testing
@testable import VaniScriptCore

// Role: Q3 MCP wiring — verifies the ephemeral Qwen project MCP config is correct and
// that the bearer token is never inlined (env substitution only).
@Suite("Qwen embedded MCP config")
struct QwenMcpConfigTests {
    @Test("targets the isolated vaniscript_embedded server over loopback SSE")
    func targetsEmbeddedServer() {
        let json = QwenMcpConfig.projectSettingsJSON(port: 19790)
        #expect(QwenMcpConfig.embeddedServerID == "vaniscript_embedded")
        #expect(json.contains("\"vaniscript_embedded\""))
        #expect(json.contains("\"url\": \"http://127.0.0.1:19790/sse\""))
        #expect(json.contains("\"mcpServers\""))
        #expect(json.contains("\"trust\": true"))
    }

    @Test("uses the configured port in the SSE endpoint")
    func honorsPort() {
        #expect(QwenMcpConfig.endpoint(port: 20500) == "http://127.0.0.1:20500/sse")
        #expect(QwenMcpConfig.projectSettingsJSON(port: 20500)
            .contains("http://127.0.0.1:20500/sse"))
    }

    @Test("references the token via env substitution, never inlines a secret")
    func tokenViaEnvOnly() {
        let json = QwenMcpConfig.projectSettingsJSON(port: 19790)
        #expect(QwenMcpConfig.accessTokenEnvironmentKey == "VANISCRIPT_MCP_TOKEN")
        #expect(json.contains("\"Authorization\": \"Bearer ${VANISCRIPT_MCP_TOKEN}\""))
        // A raw secret must never leak into the generated config.
        #expect(!json.contains("sk-"))
        #expect(!json.lowercased().contains("bearer sk"))
    }

    @Test("produces valid JSON that decodes to the expected shape")
    func decodesToExpectedShape() throws {
        let data = Data(QwenMcpConfig.projectSettingsJSON(port: 19790).utf8)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let servers = object?["mcpServers"] as? [String: Any]
        let embedded = servers?["vaniscript_embedded"] as? [String: Any]
        #expect(embedded?["url"] as? String == "http://127.0.0.1:19790/sse")
        #expect(embedded?["trust"] as? Bool == true)
        let headers = embedded?["headers"] as? [String: String]
        #expect(headers?["Authorization"] == "Bearer ${VANISCRIPT_MCP_TOKEN}")
    }
}
