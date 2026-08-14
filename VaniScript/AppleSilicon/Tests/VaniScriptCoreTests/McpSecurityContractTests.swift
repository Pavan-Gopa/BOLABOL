import Foundation
import Testing
@testable import VaniScriptCore

@Suite("VaniScript MCP security contract")
struct McpSecurityContractTests {
    @Test("MCP is disabled by default and only becomes startable with a token")
    func mcpDefaultsAreClosed() {
        let settings = AppSettings.defaults

        #expect(!settings.mcpServerEnabled)
        #expect(!settings.mcpAllowMutatingTools)
        #expect(!settings.mcpAllowProcessingTools)
        #expect(!settings.mcpAllowFileTools)
        #expect(!settings.mcpAllowNetworkTools)
        #expect(!settings.mcpAllowDestructiveTools)
        #expect(settings.mcpAccessToken.isEmpty)
        #expect(!McpServerConfiguration(settings: settings).canStart)
    }

    @Test("normalization generates an access token only when MCP is enabled")
    func mcpNormalizationGeneratesTokenOnlyWhenEnabled() {
        var disabledSettings = AppSettings.defaults
        disabledSettings.normalizeMcpSettings(generateToken: { "generated-token" })
        #expect(disabledSettings.mcpAccessToken.isEmpty)

        var enabledSettings = AppSettings.defaults
        enabledSettings.mcpServerEnabled = true
        enabledSettings.normalizeMcpSettings(generateToken: { "generated-token" })

        #expect(enabledSettings.mcpAccessToken == "generated-token")
        #expect(McpServerConfiguration(settings: enabledSettings).canStart)
    }

    @Test("normalization keeps a valid preferred MCP agent")
    func mcpNormalizationKeepsValidPreferredAgent() {
        var settings = AppSettings.defaults
        #expect(settings.mcpPreferredAgentID == McpClientProfileID.codex.rawValue)

        settings.mcpPreferredAgentID = "missing-agent"
        settings.normalizeMcpSettings(generateToken: { "generated-token" })
        #expect(settings.mcpPreferredAgentID == McpClientProfileID.codex.rawValue)

        settings.mcpPreferredAgentID = McpClientProfileID.antigravity.rawValue
        settings.normalizeMcpSettings(generateToken: { "generated-token" })
        #expect(settings.mcpPreferredAgentID == McpClientProfileID.antigravity.rawValue)
    }

    @Test("project state snapshot exposes provider readiness without secrets")
    func projectStateSnapshotDoesNotExposeSecrets() throws {
        var settings = AppSettings.defaults
        settings.geminiKey = "gemini-secret"
        settings.openaiKey = "openai-secret"
        settings.anthropicKey = "anthropic-secret"
        settings.mediaResolverToken = "resolver-secret"
        settings.mcpServerEnabled = true
        settings.mcpAllowMutatingTools = true
        settings.mcpAccessToken = "mcp-secret"
        settings.customCloudProviders = [
            CustomCloudProvider(
                label: "Private Model",
                baseUrl: "https://models.example/v1",
                apiKey: "custom-secret",
                modelName: "private-model",
                inputCostPerMillion: 0.1,
                outputCostPerMillion: 0.2
            )
        ]

        var workflow = WorkflowState.initial(settings: settings)
        workflow.selectSource(path: "/audio/lecture.mp3", durationSec: 120)
        workflow.startSession()

        let snapshot = McpProjectStateSnapshot.build(workflow: workflow)
        let json = String(data: try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]), encoding: .utf8) ?? ""

        for secret in ["gemini-secret", "openai-secret", "anthropic-secret", "resolver-secret", "mcp-secret", "custom-secret"] {
            #expect(!json.contains(secret), "MCP project snapshot leaked \(secret)")
        }
        #expect(json.contains("\"configured\":true"))
        #expect(json.contains("\"mutatingToolsEnabled\":true"))
        #expect(json.contains("\"Private Model\""))
    }

    @Test("project state snapshot reports Gemini readiness from enabled bank keys only")
    func projectStateSnapshotGeminiReadinessFollowsEnabledBankKeys() throws {
        func geminiConfigured(_ settings: AppSettings) throws -> Bool {
            let snapshot = McpProjectStateSnapshot.build(workflow: WorkflowState.initial(settings: settings))
            let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let settingsDict = try #require(object["settings"] as? [String: Any])
            let providers = try #require(settingsDict["providers"] as? [String: Any])
            let gemini = try #require(providers["gemini"] as? [String: Any])
            return try #require(gemini["configured"] as? Bool)
        }

        // Any single enabled key marks Gemini configured, even when later keys are disabled.
        var enabled = AppSettings.defaults
        enabled.geminiKeyBank = GeminiAPIKeyBank(entries: [
            "live-key",
            "\(GeminiAPIKeyBank.disabledPrefix)mothballed-key"
        ])
        #expect(try geminiConfigured(enabled))

        // A bank where every stored key is disabled reports not configured...
        var allDisabled = AppSettings.defaults
        allDisabled.geminiKeyBank = GeminiAPIKeyBank(entries: [
            "\(GeminiAPIKeyBank.disabledPrefix)only-disabled-key"
        ])
        #expect(try !geminiConfigured(allDisabled))

        // ...even though the synced legacy primary string is non-empty (the
        // synced value still carries the disabled marker as its clean text path).
        #expect(allDisabled.geminiKey.isEmpty || !allDisabled.geminiKeyBank.hasEnabledKey)

        // An empty bank reports not configured.
        #expect(try !geminiConfigured(.defaults))
    }

    @Test("tool registry exposes the same complete catalog and filters mutating tools")
    func toolRegistryFiltersMutatingTools() {
        let readOnlyTools = McpToolRegistry.definitions(allowMutatingTools: false).map(\.name)
        let allTools = McpToolRegistry.definitions(allowMutatingTools: true).map(\.name)

        // Pre-existing drift fixed alongside Q2: the committed catalog already
        // ships 122 tools (incl. analyze_clip_speech_regions); Q2 adds none.
        #expect(allTools.count == 122)

        #expect(readOnlyTools == [
            "get_project_state",
            "get_subtitle_style",
            "get_shorts_plans",
            "get_capabilities",
            "get_ui_state",
            "get_processing_status",
            "get_change_history",
            "validate_active_project",
            "list_jobs",
            "get_job",
            "list_help_topics",
            "get_help_topic",
            "search_help",
            "get_contextual_help",
            "get_onboarding_checklist",
            "list_chunks",
            "get_chunk",
            "get_chunk_cues",
            "search_transcript",
            "get_unrecognized_fragments",
            "list_translation_languages",
            "list_glossary_entries",
            "search_glossary",
            "export_glossary",
            "list_projects",
            "get_project_summary",
            "get_source_media_info",
            "get_workflow_config",
            "get_shorts_plan",
            "list_rejected_shorts_plans",
            "validate_shorts_plan",
            "get_visual_editor_state",
            "analyze_clip_speech_regions",
            "get_playback_state",
            "list_export_options",
            "validate_export",
            "get_safe_settings",
            "list_providers",
            "list_prompt_presets",
            "get_prompt",
            "get_model_status",
        ])
        #expect(allTools.contains("update_chunk_text"))
        #expect(allTools.contains("approve_chunk"))
        #expect(allTools.contains("update_subtitle_style"))
        #expect(allTools.contains("update_cue_timestamps"))
        #expect(allTools.contains("align_translation_timings"))
        #expect(allTools.contains("reprocess_chunk"))
        #expect(allTools.contains("replace_transcript_text"))
        #expect(allTools.contains("batch_update_chunk_text"))
        #expect(allTools.contains("update_cue_text"))
        #expect(allTools.contains("insert_cue"))
        #expect(allTools.contains("delete_cue"))
        #expect(allTools.contains("split_cue"))
        #expect(allTools.contains("merge_cues"))
        #expect(allTools.contains("batch_approve_chunks"))
        #expect(allTools.contains("cancel_job"))
        #expect(allTools.contains("select_translation_language"))
        #expect(allTools.contains("add_translation_language"))
        #expect(allTools.contains("remove_translation_language"))
        #expect(allTools.contains("translate_chunk"))
        #expect(allTools.contains("translate_cue"))
        #expect(allTools.contains("translate_pending_chunks"))
        #expect(allTools.contains("retry_chunk_translation"))
        #expect(allTools.contains("polish_translation"))
        #expect(allTools.contains("create_glossary_entry"))
        #expect(allTools.contains("update_glossary_entry"))
        #expect(allTools.contains("delete_glossary_entry"))
        #expect(allTools.contains("apply_glossary_entry"))
        #expect(allTools.contains("apply_glossary_all"))
        #expect(allTools.contains("import_glossary"))
        #expect(allTools.contains("open_project"))
        #expect(allTools.contains("start_processing"))
        #expect(allTools.contains("export_transcript"))
        #expect(allTools.contains("export_shorts_videos"))
        #expect(allTools.contains("generate_shorts_plans"))
        #expect(allTools.contains("create_shorts_plan"))
        #expect(allTools.contains("open_visual_editor"))
        #expect(allTools.contains("manage_timeline_cut"))
        #expect(allTools.contains("manage_subtitle_segment"))
        #expect(allTools.contains("set_frame_keyframes"))
        #expect(allTools.contains("update_visual_background"))
        #expect(allTools.contains("update_visual_subtitle_style"))
        #expect(allTools.contains("manage_text_track"))
        #expect(allTools.contains("manage_text_block"))
        #expect(allTools.contains("manage_audio_track"))
        #expect(allTools.contains("update_safe_settings"))
        #expect(allTools.contains("select_provider"))
        #expect(allTools.contains("update_prompt"))
        #expect(allTools.contains("download_model"))
        #expect(allTools.contains("remove_model"))
        #expect(McpToolRegistry.isAllowed("get_project_state", allowMutatingTools: false))
        #expect(McpToolRegistry.isAllowed("search_help", allowMutatingTools: false))
        #expect(McpToolRegistry.isAllowed("search_transcript", allowMutatingTools: false))
        #expect(!McpToolRegistry.isAllowed("reprocess_chunk", allowMutatingTools: false))

        let editOnly = McpPermissionSet(allowed: [.read, .edit])
        #expect(McpToolRegistry.isAllowed("update_chunk_text", permissions: editOnly))
        #expect(McpToolRegistry.isAllowed("manage_timeline_cut", permissions: editOnly))
        #expect(!McpToolRegistry.isAllowed("translate_chunk", permissions: editOnly))
        #expect(!McpToolRegistry.isAllowed("delete_cue", permissions: editOnly))

        let processing = McpPermissionSet(allowed: [.read, .processing])
        #expect(McpToolRegistry.isAllowed("translate_chunk", permissions: processing))
        #expect(!McpToolRegistry.isAllowed("update_chunk_text", permissions: processing))
        #expect(!McpToolRegistry.isAllowed("export_shorts_videos", permissions: processing))

        let filesAndProcessing = McpPermissionSet(allowed: [.read, .files, .processing])
        #expect(McpToolRegistry.isAllowed("export_shorts_videos", permissions: filesAndProcessing))

        let networkOnly = McpPermissionSet(allowed: [.read, .network])
        #expect(McpToolRegistry.isAllowed("download_model", permissions: networkOnly))
        #expect(!McpToolRegistry.isAllowed("locate_model", permissions: networkOnly))

        let filesOnly = McpPermissionSet(allowed: [.read, .files])
        #expect(McpToolRegistry.isAllowed("locate_model", permissions: filesOnly))
        #expect(!McpToolRegistry.isAllowed("remove_model", permissions: filesOnly))
    }

    @Test("authorization accepts headers but never URL tokens and rejects non-loopback hosts")
    func authorizationAndLoopbackPolicy() {
        var settings = AppSettings.defaults
        settings.mcpServerEnabled = true
        settings.mcpAccessToken = "secret-token"

        let configuration = McpServerConfiguration(settings: settings)

        #expect(configuration.isAuthorized(headers: ["authorization": "Bearer secret-token"], queryItems: [:]))
        #expect(configuration.isAuthorized(headers: ["x-vaniscript-mcp-token": "secret-token"], queryItems: [:]))
        #expect(!configuration.isAuthorized(headers: [:], queryItems: ["token": "secret-token"]))
        #expect(!configuration.isAuthorized(headers: ["authorization": "Bearer wrong"], queryItems: [:]))
        #expect(configuration.isLoopbackHost("127.0.0.1"))
        #expect(configuration.isLoopbackHost("::1"))
        #expect(!configuration.isLoopbackHost("192.168.1.42"))
        #expect(configuration.isAllowedOrigin(nil))
        #expect(configuration.isAllowedOrigin("http://127.0.0.1:5173"))
        #expect(configuration.isAllowedOrigin("https://localhost"))
        #expect(!configuration.isAllowedOrigin("https://example.com"))
        #expect(!configuration.isAllowedOrigin("not a URL"))
    }

    @Test("MCP tool indexes accept only whole JSON numbers")
    func mcpToolIndexesRequireWholeNumbers() throws {
        #expect(McpToolArguments.wholeNumber(4) == 4)
        #expect(McpToolArguments.wholeNumber(4.0) == 4)
        #expect(McpToolArguments.wholeNumber(4.5) == nil)
        #expect(McpToolArguments.wholeNumber(true) == nil)
        #expect(McpToolArguments.wholeNumber("4") == nil)

        let json = try JSONSerialization.jsonObject(with: Data("{\"chunkIndex\":4}".utf8)) as? [String: Any]
        #expect(McpToolArguments.wholeNumber(json?["chunkIndex"]) == 4)
    }

    @Test("agent profiles are alphabetized and generate client-specific setup")
    func agentProfilesAreAlphabetizedAndGenerateSetup() {
        let profiles = McpAgentProfileCatalog.all
        #expect(profiles.map(\.displayName) == [
            "Antigravity",
            "Claude Code",
            "Claude Desktop",
            "Codex",
            "Cursor",
            "Grok",
            "Qwen", // Q2: embedded Qwen provider added to the profile catalog
        ])

        let bridgePath = "/tmp/VaniScript/mcp_bridge.py"
        let token = "secret-token"

        let codexSetup = McpAgentProfileCatalog.setupText(
            for: .codex,
            accessToken: token,
            bridgeScriptPath: bridgePath
        )
        #expect(codexSetup.contains("codex mcp add"))
        #expect(codexSetup.contains("VANISCRIPT_MCP_TOKEN"))
        #expect(codexSetup.contains(token))

        let antigravitySetup = McpAgentProfileCatalog.setupText(
            for: .antigravity,
            accessToken: token,
            bridgeScriptPath: bridgePath
        )
        #expect(antigravitySetup.contains("~/.gemini/config/mcp_config.json"))
        #expect(antigravitySetup.contains(bridgePath))
        #expect(!antigravitySetup.contains(token))

        let grokSetup = McpAgentProfileCatalog.setupText(
            for: .grok,
            accessToken: token,
            bridgeScriptPath: bridgePath
        )
        #expect(grokSetup.contains("grok mcp add"))
        #expect(grokSetup.contains("Authorization: Bearer \(token)"))
        #expect(grokSetup.contains("http://127.0.0.1:19790/sse"))
        #expect(grokSetup.contains(bridgePath))
    }

    @Test("client classifier maps known MCP clients")
    func clientClassifierMapsKnownClients() {
        #expect(McpClientClassifier.profileID(clientName: "Codex", userAgent: nil) == McpClientProfileID.codex.rawValue)
        #expect(McpClientClassifier.profileID(clientName: "Claude Code", userAgent: nil) == McpClientProfileID.claudeCode.rawValue)
        #expect(McpClientClassifier.profileID(clientName: "Claude Desktop", userAgent: nil) == McpClientProfileID.claudeDesktop.rawValue)
        #expect(McpClientClassifier.profileID(clientName: nil, userAgent: "Cursor/1.0") == McpClientProfileID.cursor.rawValue)
        #expect(McpClientClassifier.profileID(clientName: "Grok", userAgent: nil) == McpClientProfileID.grok.rawValue)
        #expect(McpClientClassifier.profileID(clientName: nil, userAgent: "Grok/1.0") == McpClientProfileID.grok.rawValue)
        #expect(McpClientClassifier.profileID(clientName: "Gemini Developer Environment", userAgent: nil) == McpClientProfileID.antigravity.rawValue)
        #expect(McpClientClassifier.profileID(clientName: "Unknown Client", userAgent: nil) == nil)
    }

    @Test("agent connection state separates disabled, ready, and connected")
    func agentConnectionStateLabels() {
        #expect(McpAgentConnectionState.resolve(isServerEnabled: false, isConnected: false) == .disabled)
        #expect(McpAgentConnectionState.resolve(isServerEnabled: true, isConnected: false) == .ready)
        #expect(McpAgentConnectionState.resolve(isServerEnabled: true, isConnected: true) == .connected)
        #expect(McpAgentConnectionState.connected.label == "Connected")
        #expect(McpAgentConnectionState.ready.label == "Ready")
        #expect(McpAgentConnectionState.disabled.label == "Disabled")
    }
}
