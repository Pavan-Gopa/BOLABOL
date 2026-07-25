import Foundation

// Role: pure builder for the project-scoped Qwen MCP config (Q3 wiring).
// Layer: VaniScriptCore (no I/O) so it can be unit-tested without spawning `qwen`.
// Why: Qwen Code CLI reads `.qwen/settings.json` in the project cwd. We generate an
// ephemeral, project-scoped `mcpServers` entry pointing at the isolated embedded MCP
// server. The secret is NEVER inlined — it is referenced via `${VANISCRIPT_MCP_TOKEN}`
// env substitution, mirroring the GrokAgentService pattern.

public enum QwenMcpConfig {
    /// Server id the embedded chat is allowed to use (isolated profile).
    public static let embeddedServerID = "vaniscript_embedded"
    /// Env var carrying the bearer token into the child process only.
    public static let accessTokenEnvironmentKey = "VANISCRIPT_MCP_TOKEN"

    /// SSE endpoint for the local Apple Silicon MCP server.
    public static func endpoint(port: Int) -> String {
        "http://127.0.0.1:\(port)/sse"
    }

    /// Builds the `.qwen/settings.json` contents for the embedded run.
    /// - Note: The Authorization header uses `${VANISCRIPT_MCP_TOKEN}` substitution;
    ///   the raw token must never appear in this file (verified by tests).
    public static func projectSettingsJSON(port: Int) -> String {
        // Hand-rolled JSON keeps the env-substitution placeholder literal (no escaping
        // surprises from JSONEncoder) and guarantees a stable, greppable shape.
        """
        {
          "mcpServers": {
            "\(embeddedServerID)": {
              "url": "\(endpoint(port: port))",
              "headers": {
                "Authorization": "Bearer ${\(accessTokenEnvironmentKey)}"
              },
              "trust": true
            }
          }
        }
        """
    }
}
