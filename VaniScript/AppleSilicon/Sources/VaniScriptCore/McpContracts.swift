import Foundation

public enum McpToolAccess: String, CaseIterable, Equatable, Hashable, Sendable {
    case read
    case edit
    case processing
    case files
    case network
    case destructive

    public var displayName: String {
        switch self {
        case .read: "Read Project"
        case .edit: "Edit Project"
        case .processing: "Run Processing"
        case .files: "Files & Export"
        case .network: "Network & Models"
        case .destructive: "Destructive Actions"
        }
    }
}

public struct McpPermissionSet: Equatable, Sendable {
    public let allowed: Set<McpToolAccess>

    public init(allowed: Set<McpToolAccess>) {
        self.allowed = allowed.union([.read])
    }

    public init(settings: AppSettings) {
        var scopes: Set<McpToolAccess> = [.read]
        if settings.mcpAllowMutatingTools { scopes.insert(.edit) }
        if settings.mcpAllowProcessingTools { scopes.insert(.processing) }
        if settings.mcpAllowFileTools { scopes.insert(.files) }
        if settings.mcpAllowNetworkTools { scopes.insert(.network) }
        if settings.mcpAllowDestructiveTools { scopes.insert(.destructive) }
        self.init(allowed: scopes)
    }

    public func allows(_ access: McpToolAccess) -> Bool {
        allowed.contains(access)
    }

    public var safeDictionary: [[String: Any]] {
        McpToolAccess.allCases.map { scope in
            [
                "id": scope.rawValue,
                "label": scope.displayName,
                "enabled": allows(scope),
            ]
        }
    }
}

public struct McpToolDefinition: @unchecked Sendable {
    public let name: String
    public let description: String
    public let access: McpToolAccess
    public let requiredAccesses: Set<McpToolAccess>
    public let inputSchema: [String: Any]

    public init(
        name: String,
        description: String,
        access: McpToolAccess,
        requiredAccesses: Set<McpToolAccess>? = nil,
        inputSchema: [String: Any]
    ) {
        self.name = name
        self.description = description
        self.access = access
        self.requiredAccesses = requiredAccesses ?? [access]
        var schema = inputSchema
        if access != .read, var properties = schema["properties"] as? [String: Any] {
            properties["requestId"] = [
                "type": "string",
                "maxLength": 128,
                "description": "Optional idempotency key. Repeating the same tool and arguments returns the original result.",
            ]
            schema["properties"] = properties
        }
        self.inputSchema = schema
    }

    public var mcpDictionary: [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": inputSchema,
            "annotations": [
                "readOnlyHint": access == .read,
                "destructiveHint": access == .destructive,
                "idempotentHint": access == .read,
                "openWorldHint": access == .network,
            ],
            "_meta": ["vaniscript/requiredPermissions": requiredAccesses.map(\.rawValue).sorted()],
        ]
    }
}

public enum McpClientProfileID: String, CaseIterable, Codable, Equatable, Sendable {
    case antigravity
    case claudeCode = "claude-code"
    case claudeDesktop = "claude-desktop"
    case codex
    case cursor

    public var displayName: String {
        switch self {
        case .antigravity:
            "Antigravity"
        case .claudeCode:
            "Claude Code"
        case .claudeDesktop:
            "Claude Desktop"
        case .codex:
            "Codex"
        case .cursor:
            "Cursor"
        }
    }

    public var symbolName: String {
        switch self {
        case .antigravity:
            "sparkles"
        case .claudeCode:
            "terminal"
        case .claudeDesktop:
            "desktopcomputer"
        case .codex:
            "curlybraces"
        case .cursor:
            "cursorarrow"
        }
    }
}

public struct McpAgentProfile: Identifiable, Equatable, Sendable {
    public let id: McpClientProfileID
    public let displayName: String
    public let detail: String
    public let setupActionTitle: String

    public init(id: McpClientProfileID, detail: String, setupActionTitle: String) {
        self.id = id
        self.displayName = id.displayName
        self.detail = detail
        self.setupActionTitle = setupActionTitle
    }
}

public enum McpAgentConnectionState: String, Equatable, Sendable {
    case disabled
    case ready
    case connected

    public var label: String {
        switch self {
        case .disabled:
            "Disabled"
        case .ready:
            "Ready"
        case .connected:
            "Connected"
        }
    }

    public static func resolve(isServerEnabled: Bool, isConnected: Bool) -> McpAgentConnectionState {
        guard isServerEnabled else { return .disabled }
        return isConnected ? .connected : .ready
    }
}

public struct McpActiveClient: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let profileID: String
    public let displayName: String
    public let connectedAt: Date
    public let lastSeenAt: Date

    public init(
        id: UUID,
        profileID: String,
        displayName: String,
        connectedAt: Date,
        lastSeenAt: Date
    ) {
        self.id = id
        self.profileID = profileID
        self.displayName = displayName
        self.connectedAt = connectedAt
        self.lastSeenAt = lastSeenAt
    }
}

public enum McpClientClassifier {
    public static func profileID(clientName: String?, userAgent: String?) -> String? {
        let combined = [clientName, userAgent]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()

        guard !combined.isEmpty else { return nil }

        if combined.contains("claude desktop") || combined.contains("claude-desktop") {
            return McpClientProfileID.claudeDesktop.rawValue
        }
        if combined.contains("claude code") || combined.contains("claude-code") || combined == "claude" {
            return McpClientProfileID.claudeCode.rawValue
        }
        if combined.contains("codex") {
            return McpClientProfileID.codex.rawValue
        }
        if combined.contains("cursor") {
            return McpClientProfileID.cursor.rawValue
        }
        if combined.contains("antigravity") || combined.contains("gemini") {
            return McpClientProfileID.antigravity.rawValue
        }
        return nil
    }
}

public enum McpAgentProfileCatalog {
    public static let defaultEndpoint = "http://127.0.0.1:19790/sse"
    public static let defaultBridgeScriptPath = "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon/mcp_bridge.py"
    public static let defaultProfileID = McpClientProfileID.codex.rawValue

    public static let all: [McpAgentProfile] = McpClientProfileID.allCases
        .map { profile in
            switch profile {
            case .antigravity:
                McpAgentProfile(
                    id: profile,
                    detail: "Google developer environment via stdio bridge.",
                    setupActionTitle: "Copy Config"
                )
            case .claudeCode:
                McpAgentProfile(
                    id: profile,
                    detail: "Command-line Claude client with direct SSE.",
                    setupActionTitle: "Copy Command"
                )
            case .claudeDesktop:
                McpAgentProfile(
                    id: profile,
                    detail: "Desktop Claude client via stdio bridge.",
                    setupActionTitle: "Copy Config"
                )
            case .codex:
                McpAgentProfile(
                    id: profile,
                    detail: "Codex desktop via local bridge, or CLI via direct Streamable HTTP.",
                    setupActionTitle: "Copy Command"
                )
            case .cursor:
                McpAgentProfile(
                    id: profile,
                    detail: "Cursor MCP client via native SSE or bridge config.",
                    setupActionTitle: "Copy Config"
                )
            }
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

    public static func profile(for id: McpClientProfileID) -> McpAgentProfile {
        all.first { $0.id == id } ?? all.first { $0.id == .codex }!
    }

    public static func profile(forRawID rawID: String) -> McpAgentProfile {
        guard let profileID = McpClientProfileID(rawValue: rawID) else {
            return profile(for: .codex)
        }
        return profile(for: profileID)
    }

    public static func normalizedProfileID(_ rawID: String) -> String {
        if let profileID = McpClientProfileID(rawValue: rawID) {
            return profileID.rawValue
        }
        return defaultProfileID
    }

    public static func setupText(
        for profileID: McpClientProfileID,
        accessToken: String,
        endpoint: String = defaultEndpoint,
        bridgeScriptPath: String = defaultBridgeScriptPath
    ) -> String {
        switch profileID {
        case .codex:
            """
            Recommended for Codex Desktop:
            codex mcp add vaniscript -- python3 "\(bridgeScriptPath)"

            Direct Streamable HTTP for a terminal Codex session:
            export VANISCRIPT_MCP_TOKEN="\(accessToken)"
            codex mcp add --bearer-token-env-var VANISCRIPT_MCP_TOKEN vaniscript --url \(endpoint)
            """
        case .claudeCode:
            """
            claude mcp add --transport sse --header "Authorization: Bearer \(accessToken)" vaniscript \(endpoint)
            """
        case .claudeDesktop:
            bridgeConfig(
                configPath: "~/Library/Application Support/Claude/claude_desktop_config.json",
                bridgeScriptPath: bridgeScriptPath
            )
        case .cursor:
            """
            Native SSE:
            Name: VaniScript
            Type: SSE
            URL: \(endpoint)
            Header: Authorization: Bearer \(accessToken)

            Bridge config:
            \(bridgeConfig(configPath: ".cursor/mcp.json", bridgeScriptPath: bridgeScriptPath))
            """
        case .antigravity:
            bridgeConfig(
                configPath: "~/.gemini/config/mcp_config.json",
                bridgeScriptPath: bridgeScriptPath
            )
        }
    }

    private static func bridgeConfig(configPath: String, bridgeScriptPath: String) -> String {
        """
        \(configPath)

        {
          "mcpServers": {
            "vaniscript": {
              "command": "python3",
              "args": [
                "\(bridgeScriptPath)"
              ]
            }
          }
        }
        """
    }
}

public enum McpToolRegistry {
    public static let allDefinitions: [McpToolDefinition] = [
        McpToolDefinition(
            name: "get_project_state",
            description: "Get the active VaniScript project state without API keys, access tokens, or provider secrets.",
            access: .read,
            inputSchema: objectSchema()
        ),
        McpToolDefinition(
            name: "get_subtitle_style",
            description: "Get active subtitle style settings.",
            access: .read,
            inputSchema: objectSchema()
        ),
        McpToolDefinition(
            name: "get_shorts_plans",
            description: "List vertical shorts clip plans in the active project.",
            access: .read,
            inputSchema: objectSchema()
        ),
        McpToolDefinition(
            name: "get_capabilities",
            description: "List the VaniScript MCP tools available under the current permission policy and summarize the active workspace capabilities.",
            access: .read,
            inputSchema: objectSchema()
        ),
        McpToolDefinition(
            name: "get_ui_state",
            description: "Get the current VaniScript workspace, active segment, selected translation language, and other safe UI context.",
            access: .read,
            inputSchema: objectSchema()
        ),
        McpToolDefinition(
            name: "get_processing_status",
            description: "Get the current VaniScript processing stage, progress, and active segment status.",
            access: .read,
            inputSchema: objectSchema()
        ),
        McpToolDefinition(
            name: "get_change_history",
            description: "List recent MCP changes with change-set IDs and before/after project revisions.",
            access: .read,
            inputSchema: objectSchema(properties: [
                "cursor": ["type": "integer", "minimum": 0],
                "limit": ["type": "integer", "minimum": 1, "maximum": 100],
            ])
        ),
        McpToolDefinition(
            name: "validate_active_project",
            description: "Validate active project integrity, transcript timing, translations, source media, and Shorts ranges without changing anything.",
            access: .read,
            inputSchema: objectSchema()
        ),
        McpToolDefinition(
            name: "list_jobs",
            description: "List recent VaniScript background jobs with progress, status, and safe result summaries.",
            access: .read,
            inputSchema: objectSchema(
                properties: [
                    "limit": ["type": "integer", "minimum": 1, "maximum": 100, "description": "Maximum jobs. Defaults to 20."],
                ]
            )
        ),
        McpToolDefinition(
            name: "get_job",
            description: "Get the current progress, result, or error for one VaniScript background job.",
            access: .read,
            inputSchema: objectSchema(
                properties: ["jobId": ["type": "string"]],
                required: ["jobId"]
            )
        ),
        McpToolDefinition(
            name: "list_help_topics",
            description: "List VaniScript help topics. Use this for feature discovery and beginner questions about what the app can do.",
            access: .read,
            inputSchema: objectSchema(
                properties: [
                    "category": ["type": "string", "description": "Optional exact help category returned by this tool."],
                    "language": languageSchema,
                ]
            )
        ),
        McpToolDefinition(
            name: "get_help_topic",
            description: "Get an accurate step-by-step VaniScript help topic with requirements, troubleshooting, and related topics.",
            access: .read,
            inputSchema: objectSchema(
                properties: [
                    "topicId": ["type": "string", "description": "Required topic ID from list_help_topics or search_help."],
                    "language": languageSchema,
                ],
                required: ["topicId"]
            )
        ),
        McpToolDefinition(
            name: "search_help",
            description: "Search the built-in VaniScript product guide and return relevant step-by-step instructions. Use this before answering how-to questions about the app.",
            access: .read,
            inputSchema: objectSchema(
                properties: [
                    "query": ["type": "string", "description": "The user's VaniScript question or feature name."],
                    "language": languageSchema,
                    "limit": ["type": "integer", "minimum": 1, "maximum": 10, "description": "Maximum number of topics. Defaults to 5."],
                ],
                required: ["query"]
            )
        ),
        McpToolDefinition(
            name: "get_contextual_help",
            description: "Get VaniScript help and exact next actions for the current screen and active project state.",
            access: .read,
            inputSchema: objectSchema(
                properties: ["language": languageSchema]
            )
        ),
        McpToolDefinition(
            name: "get_onboarding_checklist",
            description: "Get the complete beginner workflow from first launch through review and export.",
            access: .read,
            inputSchema: objectSchema(
                properties: ["language": languageSchema]
            )
        ),
        McpToolDefinition(
            name: "list_chunks",
            description: "List active project segments with stable chunk IDs, display numbers, status, approval, timing, and short text previews.",
            access: .read,
            inputSchema: objectSchema(
                properties: [
                    "cursor": ["type": "integer", "minimum": 0, "description": "Zero-based result offset. Defaults to 0."],
                    "limit": ["type": "integer", "minimum": 1, "maximum": 100, "description": "Maximum results. Defaults to 20."],
                    "status": ["type": "string", "enum": ["pending", "processing", "done", "error"], "description": "Optional status filter."],
                    "approved": ["type": "boolean", "description": "Optional approval filter."],
                ]
            )
        ),
        McpToolDefinition(
            name: "get_chunk",
            description: "Get one active project segment by stable chunkId or legacy zero-based chunkIndex.",
            access: .read,
            inputSchema: objectSchema(
                properties: [
                    "chunkId": ["type": "string", "description": "Preferred stable ID returned by list_chunks, for example chunk-4."],
                    "chunkIndex": ["type": "integer", "description": "Legacy zero-based index. Use chunkId when possible."],
                ]
            )
        ),
        McpToolDefinition(
            name: "get_chunk_cues",
            description: "Get timed source or translated cues for one segment with stable cue IDs.",
            access: .read,
            inputSchema: objectSchema(
                properties: [
                    "chunkId": ["type": "string", "description": "Preferred stable chunk ID returned by list_chunks."],
                    "chunkIndex": ["type": "integer", "description": "Legacy zero-based segment index."],
                    "side": ["type": "string", "enum": ["original", "translated"], "description": "Cue side. Defaults to original."],
                    "language": ["type": "string", "description": "Optional translation language when side is translated."],
                ]
            )
        ),
        McpToolDefinition(
            name: "search_transcript",
            description: "Search source and/or translated text across the active project without modifying it.",
            access: .read,
            inputSchema: objectSchema(
                properties: [
                    "query": ["type": "string", "description": "Required non-empty search text."],
                    "side": ["type": "string", "enum": ["all", "original", "translated"], "description": "Search scope. Defaults to all."],
                    "caseSensitive": ["type": "boolean", "description": "Defaults to false."],
                    "wholeWord": ["type": "boolean", "description": "Defaults to false."],
                    "limit": ["type": "integer", "minimum": 1, "maximum": 100, "description": "Maximum matches. Defaults to 50."],
                ],
                required: ["query"]
            )
        ),
        McpToolDefinition(
            name: "get_unrecognized_fragments",
            description: "List transcription fragments marked as unrecognized, grouped by stable chunk ID.",
            access: .read,
            inputSchema: objectSchema(
                properties: [
                    "chunkId": ["type": "string", "description": "Optional stable chunk ID. Omit to inspect the entire project."],
                ]
            )
        ),
        McpToolDefinition(
            name: "list_translation_languages",
            description: "List available, active, and supported translation languages for the current project.",
            access: .read,
            inputSchema: objectSchema()
        ),
        McpToolDefinition(
            name: "list_glossary_entries",
            description: "List glossary entries with stable IDs and pagination.",
            access: .read,
            inputSchema: objectSchema(properties: [
                "cursor": ["type": "integer", "minimum": 0],
                "limit": ["type": "integer", "minimum": 1, "maximum": 200],
                "category": ["type": "string"],
            ])
        ),
        McpToolDefinition(
            name: "search_glossary",
            description: "Search glossary sources, translations, variants, categories, and language-specific translations.",
            access: .read,
            inputSchema: objectSchema(
                properties: [
                    "query": ["type": "string"],
                    "limit": ["type": "integer", "minimum": 1, "maximum": 100],
                ],
                required: ["query"]
            )
        ),
        McpToolDefinition(
            name: "export_glossary",
            description: "Return a portable, secret-free JSON glossary document.",
            access: .read,
            inputSchema: objectSchema()
        ),
        McpToolDefinition(
            name: "create_glossary_entry",
            description: "Create one validated glossary entry.",
            access: .edit,
            inputSchema: glossaryEntrySchema(required: ["source"])
        ),
        McpToolDefinition(
            name: "update_glossary_entry",
            description: "Patch one glossary entry by stable entryId.",
            access: .edit,
            inputSchema: glossaryEntrySchema(required: ["entryId"], includeEntryID: true)
        ),
        McpToolDefinition(
            name: "delete_glossary_entry",
            description: "Preview or confirm deletion of one glossary entry.",
            access: .destructive,
            inputSchema: objectSchema(
                properties: [
                    "entryId": ["type": "string"],
                    "dryRun": ["type": "boolean", "description": "Defaults to true."],
                    "confirmationToken": ["type": "string"],
                    "expectedRevision": revisionSchema,
                ],
                required: ["entryId"]
            )
        ),
        McpToolDefinition(
            name: "apply_glossary_entry",
            description: "Preview or confirm applying one glossary entry to the current segment, selected segments, or project.",
            access: .edit,
            inputSchema: glossaryApplySchema(required: ["entryId"], includeEntryID: true)
        ),
        McpToolDefinition(
            name: "apply_glossary_all",
            description: "Preview or confirm applying every glossary entry to the current segment, selected segments, or project.",
            access: .edit,
            inputSchema: glossaryApplySchema()
        ),
        McpToolDefinition(
            name: "import_glossary",
            description: "Safely merge structured glossary entries. Existing entries with the same ID are updated.",
            access: .edit,
            inputSchema: objectSchema(
                properties: [
                    "entries": [
                        "type": "array",
                        "minItems": 1,
                        "maxItems": 5000,
                        "items": ["type": "object"],
                    ],
                    "expectedRevision": revisionSchema,
                ],
                required: ["entries"]
            )
        ),
        McpToolDefinition(
            name: "cancel_job",
            description: "Cancel a cancellable VaniScript background job.",
            access: .processing,
            inputSchema: objectSchema(
                properties: ["jobId": ["type": "string"]],
                required: ["jobId"]
            )
        ),
        McpToolDefinition(
            name: "select_translation_language",
            description: "Select an existing project translation language without generating new text.",
            access: .edit,
            inputSchema: objectSchema(
                properties: [
                    "language": ["type": "string"],
                    "expectedRevision": revisionSchema,
                ],
                required: ["language"]
            )
        ),
        McpToolDefinition(
            name: "add_translation_language",
            description: "Register and select a translation language. This does not translate text until a translation tool is called.",
            access: .edit,
            inputSchema: objectSchema(
                properties: [
                    "language": ["type": "string"],
                    "expectedRevision": revisionSchema,
                ],
                required: ["language"]
            )
        ),
        McpToolDefinition(
            name: "remove_translation_language",
            description: "Remove one archived translation language and its text/cues from the active project.",
            access: .destructive,
            inputSchema: objectSchema(
                properties: [
                    "language": ["type": "string"],
                    "expectedRevision": revisionSchema,
                ],
                required: ["language"]
            )
        ),
        McpToolDefinition(
            name: "translate_chunk",
            description: "Start a background job that translates one segment using the configured cloud or local translation provider.",
            access: .processing,
            inputSchema: objectSchema(
                properties: [
                    "chunkId": ["type": "string"],
                    "language": ["type": "string", "description": "Optional target language. Defaults to the active project translation."],
                    "expectedRevision": revisionSchema,
                ],
                required: ["chunkId"]
            )
        ),
        McpToolDefinition(
            name: "translate_cue",
            description: "Start a background job that re-translates one source cue into the active target language.",
            access: .processing,
            inputSchema: objectSchema(
                properties: [
                    "chunkId": ["type": "string"],
                    "cueId": ["type": "string"],
                    "cueIndex": ["type": "integer"],
                    "language": ["type": "string"],
                    "expectedRevision": revisionSchema,
                ],
                required: ["chunkId"]
            )
        ),
        McpToolDefinition(
            name: "translate_pending_chunks",
            description: "Start a cancellable background job that translates all matching pending or untranslated segments.",
            access: .processing,
            inputSchema: objectSchema(
                properties: [
                    "language": ["type": "string"],
                    "onlyUntranslated": ["type": "boolean", "description": "Defaults to true."],
                    "expectedRevision": revisionSchema,
                ]
            )
        ),
        McpToolDefinition(
            name: "retry_chunk_translation",
            description: "Start a background job that replaces the selected segment translation using the configured provider.",
            access: .processing,
            inputSchema: objectSchema(
                properties: [
                    "chunkId": ["type": "string"],
                    "language": ["type": "string"],
                    "expectedRevision": revisionSchema,
                ],
                required: ["chunkId"]
            )
        ),
        McpToolDefinition(
            name: "polish_translation",
            description: "Start a background MLX job that polishes a translated cue, segment, or every translated segment while preserving the previous project until each result is ready.",
            access: .processing,
            inputSchema: objectSchema(
                properties: [
                    "scope": ["type": "string", "enum": ["cue", "chunk", "project"], "description": "Defaults to chunk."],
                    "chunkId": ["type": "string"],
                    "cueId": ["type": "string"],
                    "cueIndex": ["type": "integer"],
                    "language": ["type": "string"],
                    "expectedRevision": revisionSchema,
                ]
            )
        ),
        McpToolDefinition(
            name: "replace_transcript_text",
            description: "Preview or apply a project-wide source/translation replacement. The first call must use dryRun=true; applying requires its short-lived confirmationToken and current expectedRevision.",
            access: .edit,
            inputSchema: objectSchema(
                properties: [
                    "query": ["type": "string", "description": "Required text to find."],
                    "replacement": ["type": "string", "description": "Replacement text. May be empty to remove matches."],
                    "side": ["type": "string", "enum": ["original", "translated"], "description": "Text side to change."],
                    "language": ["type": "string", "description": "Optional translation language when side is translated."],
                    "caseSensitive": ["type": "boolean", "description": "Defaults to false."],
                    "wholeWord": ["type": "boolean", "description": "Defaults to false."],
                    "dryRun": ["type": "boolean", "description": "Defaults to true. Returns a preview and confirmationToken without changing the project."],
                    "confirmationToken": ["type": "string", "description": "Required when dryRun is false."],
                    "expectedRevision": revisionSchema,
                ],
                required: ["query", "replacement", "side"]
            )
        ),
        McpToolDefinition(
            name: "batch_update_chunk_text",
            description: "Atomically update source and/or translated text for multiple segments using stable chunk IDs.",
            access: .edit,
            inputSchema: objectSchema(
                properties: [
                    "updates": [
                        "type": "array",
                        "minItems": 1,
                        "maxItems": 100,
                        "items": [
                            "type": "object",
                            "properties": [
                                "chunkId": ["type": "string"],
                                "original": ["type": "string"],
                                "translated": ["type": "string"],
                            ],
                            "required": ["chunkId"],
                        ],
                    ],
                    "expectedRevision": revisionSchema,
                ],
                required: ["updates"]
            )
        ),
        McpToolDefinition(
            name: "update_cue_text",
            description: "Update one source or translated cue by stable cueId and rebuild its word timings.",
            access: .edit,
            inputSchema: objectSchema(
                properties: [
                    "chunkId": ["type": "string", "description": "Stable chunk ID."],
                    "side": ["type": "string", "enum": ["original", "translated"]],
                    "cueId": ["type": "string", "description": "Stable cue ID from get_chunk_cues."],
                    "cueIndex": ["type": "integer", "description": "Legacy zero-based cue index."],
                    "language": ["type": "string", "description": "Optional translated language."],
                    "text": ["type": "string", "description": "New cue text."],
                    "expectedRevision": revisionSchema,
                ],
                required: ["chunkId", "side", "text"]
            )
        ),
        McpToolDefinition(
            name: "insert_cue",
            description: "Insert a timed source or translated cue at a validated position inside a segment.",
            access: .edit,
            inputSchema: objectSchema(
                properties: [
                    "chunkId": ["type": "string"],
                    "side": ["type": "string", "enum": ["original", "translated"]],
                    "insertAt": ["type": "integer", "minimum": 0, "description": "Zero-based insertion position."],
                    "startSec": ["type": "number"],
                    "endSec": ["type": "number"],
                    "text": ["type": "string"],
                    "language": ["type": "string"],
                    "expectedRevision": revisionSchema,
                ],
                required: ["chunkId", "side", "insertAt", "startSec", "endSec", "text"]
            )
        ),
        McpToolDefinition(
            name: "delete_cue",
            description: "Delete one source or translated cue by stable cueId.",
            access: .destructive,
            inputSchema: objectSchema(
                properties: [
                    "chunkId": ["type": "string"],
                    "side": ["type": "string", "enum": ["original", "translated"]],
                    "cueId": ["type": "string"],
                    "cueIndex": ["type": "integer"],
                    "language": ["type": "string"],
                    "expectedRevision": revisionSchema,
                ],
                required: ["chunkId", "side"]
            )
        ),
        McpToolDefinition(
            name: "split_cue",
            description: "Split one cue into two cues using a text character offset and optional split timestamp.",
            access: .edit,
            inputSchema: objectSchema(
                properties: [
                    "chunkId": ["type": "string"],
                    "side": ["type": "string", "enum": ["original", "translated"]],
                    "cueId": ["type": "string"],
                    "cueIndex": ["type": "integer"],
                    "splitAtCharacter": ["type": "integer", "minimum": 1],
                    "splitSec": ["type": "number", "description": "Optional timestamp strictly inside the cue. Defaults to its midpoint."],
                    "language": ["type": "string"],
                    "expectedRevision": revisionSchema,
                ],
                required: ["chunkId", "side", "splitAtCharacter"]
            )
        ),
        McpToolDefinition(
            name: "merge_cues",
            description: "Merge two adjacent cues on the same side into one timed cue.",
            access: .edit,
            inputSchema: objectSchema(
                properties: [
                    "chunkId": ["type": "string"],
                    "side": ["type": "string", "enum": ["original", "translated"]],
                    "firstCueId": ["type": "string", "description": "Stable ID of the first adjacent cue."],
                    "firstCueIndex": ["type": "integer", "description": "Legacy zero-based first cue index."],
                    "language": ["type": "string"],
                    "expectedRevision": revisionSchema,
                ],
                required: ["chunkId", "side"]
            )
        ),
        McpToolDefinition(
            name: "batch_approve_chunks",
            description: "Atomically approve or revoke approval for multiple segments using stable chunk IDs.",
            access: .edit,
            inputSchema: objectSchema(
                properties: [
                    "chunkIds": ["type": "array", "minItems": 1, "maxItems": 500, "items": ["type": "string"]],
                    "approved": ["type": "boolean"],
                    "expectedRevision": revisionSchema,
                ],
                required: ["chunkIds", "approved"]
            )
        ),
        McpToolDefinition(
            name: "update_chunk_text",
            description: "Update the transcription or translation text of a segment. Call list_chunks first and pass its stable chunkId. Legacy chunkIndex remains zero-based.",
            access: .edit,
            inputSchema: objectSchema(
                properties: [
                    "chunkId": ["type": "string", "description": "Preferred stable ID returned by list_chunks."],
                    "chunkIndex": ["type": "integer", "description": "Legacy zero-based session.chunks[].index."],
                    "original": ["type": "string", "description": "New original transcript text."],
                    "translated": ["type": "string", "description": "New translation text."],
                    "expectedRevision": revisionSchema,
                ]
            )
        ),
        McpToolDefinition(
            name: "approve_chunk",
            description: "Approve or revoke approval for a specific segment.",
            access: .edit,
            inputSchema: objectSchema(
                properties: [
                    "chunkId": ["type": "string", "description": "Preferred stable ID returned by list_chunks."],
                    "chunkIndex": ["type": "integer", "description": "Legacy zero-based session.chunks[].index."],
                    "approved": ["type": "boolean", "description": "True to approve, false to revoke."],
                    "expectedRevision": revisionSchema,
                ],
                required: ["approved"]
            )
        ),
        McpToolDefinition(
            name: "update_subtitle_style",
            description: "Update subtitle style properties for active shorts plans.",
            access: .edit,
            inputSchema: objectSchema(
                properties: [
                    "stylePatch": ["type": "object", "description": "Partial patch for subtitle style parameters."],
                    "expectedRevision": revisionSchema,
                ],
                required: ["stylePatch"]
            )
        ),
        McpToolDefinition(
            name: "update_cue_timestamps",
            description: "Update the start and/or end timestamps of a specific cue inside a chunk.",
            access: .edit,
            inputSchema: objectSchema(
                properties: [
                    "chunkId": ["type": "string", "description": "Preferred stable ID returned by list_chunks."],
                    "chunkIndex": ["type": "integer", "description": "Legacy zero-based session.chunks[].index."],
                    "side": ["type": "string", "description": "Side to update: original or translated."],
                    "cueIndex": ["type": "integer", "description": "Index of the cue within the chunk (0-based)."],
                    "startSec": ["type": "number", "description": "New start time in seconds."],
                    "endSec": ["type": "number", "description": "New end time in seconds."],
                    "expectedRevision": revisionSchema,
                ],
                required: ["side", "cueIndex"]
            )
        ),
        McpToolDefinition(
            name: "align_translation_timings",
            description: "Align translation cue timestamps to match original cues for a specific chunk.",
            access: .edit,
            inputSchema: objectSchema(
                properties: [
                    "chunkId": ["type": "string", "description": "Preferred stable ID returned by list_chunks."],
                    "chunkIndex": ["type": "integer", "description": "Legacy zero-based session.chunks[].index."],
                    "expectedRevision": revisionSchema,
                ]
            )
        ),
        McpToolDefinition(
            name: "reprocess_chunk",
            description: "Force reprocessing for a specific chunk from the source audio file.",
            access: .processing,
            inputSchema: objectSchema(
                properties: [
                    "chunkId": ["type": "string", "description": "Preferred stable ID returned by list_chunks."],
                    "chunkIndex": ["type": "integer", "description": "Legacy zero-based session.chunks[].index."],
                    "expectedRevision": revisionSchema,
                ]
            )
        ),
    ] + McpExpandedToolCatalog.definitions

    public static func definitions(permissions: McpPermissionSet) -> [McpToolDefinition] {
        allDefinitions.filter { definition in
            definition.requiredAccesses.allSatisfy(permissions.allows)
        }
    }

    public static func isAllowed(_ name: String, permissions: McpPermissionSet) -> Bool {
        definitions(permissions: permissions).contains { $0.name == name }
    }

    public static func definitions(allowMutatingTools: Bool) -> [McpToolDefinition] {
        definitions(
            permissions: McpPermissionSet(
                allowed: allowMutatingTools ? Set(McpToolAccess.allCases) : [.read]
            )
        )
    }

    public static func isAllowed(_ name: String, allowMutatingTools: Bool) -> Bool {
        isAllowed(
            name,
            permissions: McpPermissionSet(
                allowed: allowMutatingTools ? Set(McpToolAccess.allCases) : [.read]
            )
        )
    }

    public static func definition(named name: String) -> McpToolDefinition? {
        allDefinitions.first { $0.name == name }
    }

    private static func objectSchema(
        properties: [String: Any] = [:],
        required: [String] = []
    ) -> [String: Any] {
        var schema: [String: Any] = [
            "type": "object",
            "properties": properties,
        ]
        if !required.isEmpty {
            schema["required"] = required
        }
        return schema
    }

    private static var languageSchema: [String: Any] {
        [
            "type": "string",
            "enum": ["en", "ru"],
            "description": "Response language. Use ru for Russian; defaults to en.",
        ]
    }

    private static var revisionSchema: [String: Any] {
        [
            "type": "string",
            "description": "Optional projectRevision from the latest read. The mutation is rejected if the project changed.",
        ]
    }

    private static func glossaryEntrySchema(
        required: [String],
        includeEntryID: Bool = false
    ) -> [String: Any] {
        var properties: [String: Any] = [
            "source": ["type": "string"],
            "translation": ["type": "string"],
            "variants": ["type": "array", "maxItems": 100, "items": ["type": "string"]],
            "category": ["type": "string"],
            "translations": ["type": "object"],
            "remember": ["type": "boolean"],
            "expectedRevision": revisionSchema,
        ]
        if includeEntryID { properties["entryId"] = ["type": "string"] }
        return objectSchema(properties: properties, required: required)
    }

    private static func glossaryApplySchema(
        required: [String] = [],
        includeEntryID: Bool = false
    ) -> [String: Any] {
        var properties: [String: Any] = [
            "scope": ["type": "string", "enum": ["currentChunk", "selectedChunks", "project"]],
            "side": ["type": "string", "enum": ["source", "translation", "both"]],
            "chunkIds": ["type": "array", "items": ["type": "string"]],
            "dryRun": ["type": "boolean", "description": "Defaults to true."],
            "confirmationToken": ["type": "string"],
            "expectedRevision": revisionSchema,
        ]
        if includeEntryID { properties["entryId"] = ["type": "string"] }
        return objectSchema(properties: properties, required: required)
    }
}

public enum McpToolArguments {
    /// MCP JSON numbers must be finite whole numbers before they can index local arrays.
    public static func wholeNumber(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let integer = value as? Int {
            return integer
        }
        if let number = value as? Double {
            return wholeNumber(number)
        }
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return wholeNumber(number.doubleValue)
        }
        return nil
    }

    private static func wholeNumber(_ value: Double) -> Int? {
        guard value.isFinite,
              value.rounded(.towardZero) == value,
              value >= Double(Int.min),
              value <= Double(Int.max)
        else {
            return nil
        }
        return Int(value)
    }
}

public struct McpServerConfiguration: Equatable, Sendable {
    public let isEnabled: Bool
    public let permissions: McpPermissionSet
    public let accessToken: String
    public let port: UInt16

    public init(settings: AppSettings, port: UInt16 = 19790) {
        self.isEnabled = settings.mcpServerEnabled
        self.permissions = McpPermissionSet(settings: settings)
        self.accessToken = settings.mcpAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.port = port
    }

    public var canStart: Bool {
        isEnabled && !accessToken.isEmpty
    }

    public var allowMutatingTools: Bool {
        permissions.allows(.edit)
    }

    public func isAuthorized(headers: [String: String], queryItems _: [String: String]) -> Bool {
        guard !accessToken.isEmpty else { return false }
        let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map { key, value in
            (key.lowercased(), value.trimmingCharacters(in: .whitespacesAndNewlines))
        })

        if let authorization = normalizedHeaders["authorization"],
           authorization.dropFirst("Bearer ".count) == accessToken,
           authorization.lowercased().hasPrefix("bearer ") {
            return true
        }
        if normalizedHeaders["x-vaniscript-mcp-token"] == accessToken {
            return true
        }
        return false
    }

    public func isLoopbackHost(_ host: String) -> Bool {
        let clean = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        return clean == "127.0.0.1" || clean == "::1" || clean == "localhost"
    }

    /// Native MCP clients send no Origin header. Browser requests are accepted only from loopback origins.
    public func isAllowedOrigin(_ origin: String?) -> Bool {
        guard let origin = origin?.trimmingCharacters(in: .whitespacesAndNewlines), !origin.isEmpty else {
            return true
        }
        guard let components = URLComponents(string: origin),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host
        else {
            return false
        }
        return isLoopbackHost(host)
    }
}

public enum McpProjectStateSnapshot {
    public static func build(workflow: WorkflowState) -> [String: Any] {
        var result: [String: Any] = [
            "projectRevision": McpProjectRevision.make(workflow: workflow),
            "currentScreen": workflow.screen.rawValue,
            "sourceFileName": workflow.sourceFileName,
            "durationSec": workflow.durationSec,
            "sourceLang": workflow.sourceLang,
            "targetLang": workflow.targetLang,
            "transcriptionProvider": workflow.transcriptionProvider,
            "translationProvider": workflow.translationProvider,
            "settings": sanitizedSettings(workflow.settings),
        ]

        if let session = workflow.session {
            result["session"] = sanitizedSession(session)
        }

        let plans = workflow.session?.shortsPlans ?? []
        result["shortsPlans"] = plans.map(sanitizedShortsPlan)
        return result
    }

    private static func sanitizedSettings(_ settings: AppSettings) -> [String: Any] {
        [
            "providers": [
                "gemini": ["configured": !settings.geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty],
                "openai": ["configured": !settings.openaiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty],
                "anthropic": ["configured": !settings.anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty],
                "mediaResolver": ["configured": !settings.mediaResolverToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty],
            ],
            "customCloudProviders": settings.customCloudProviders.map { provider in
                [
                    "id": provider.id,
                    "label": provider.label,
                    "baseUrl": provider.baseUrl,
                    "modelName": provider.modelName,
                    "configured": !provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "inputCostPerMillion": provider.inputCostPerMillion,
                    "outputCostPerMillion": provider.outputCostPerMillion,
                    "budgetLimitUsd": provider.budgetLimitUsd,
                ] as [String: Any]
            },
            "mcp": [
                "enabled": settings.mcpServerEnabled,
                "mutatingToolsEnabled": settings.mcpAllowMutatingTools,
                "permissions": McpPermissionSet(settings: settings).safeDictionary,
                "requiresAccessToken": true,
            ],
            "defaultSourceLang": settings.defaultSourceLang,
            "defaultTargetLang": settings.defaultTargetLang,
            "chunkDurationMin": settings.chunkDurationMin,
            "sliceMode": settings.sliceMode.rawValue,
        ]
    }

    private static func sanitizedSession(_ session: SessionState) -> [String: Any] {
        [
            "sourceFileName": session.sourceFileName,
            "durationSec": session.durationSec,
            "targetLang": session.targetLang,
            "selectedTranslationLanguage": session.selectedTranslationLanguage ?? "",
            "availableTranslationLanguages": session.availableTranslationLanguages ?? [],
            "currentChunkIndex": session.currentChunkIndex,
            "chunks": session.chunks.enumerated().map { idx, chunk in
                [
                    "index": idx,
                    "startSec": chunk.startSec,
                    "endSec": chunk.endSec,
                    "original": chunk.original,
                    "translated": chunk.translated,
                    "approved": chunk.approved,
                    "status": chunk.status.rawValue,
                    "originalCueCount": chunk.originalCues?.count ?? 0,
                    "translationCueCount": chunk.translationCues(for: session.selectedTranslationLanguage).count,
                ] as [String: Any]
            },
        ]
    }

    private static func sanitizedShortsPlan(_ plan: ShortsClipPlan) -> [String: Any] {
        [
            "id": plan.id,
            "title": plan.title,
            "start": plan.start,
            "end": plan.end,
            "summary": plan.summary,
            "category": plan.category ?? "",
            "hook": plan.hook,
        ]
    }
}
