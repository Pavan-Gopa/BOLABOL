import Foundation

public enum McpExpandedToolCatalog {
    public static let definitions: [McpToolDefinition] = projectTools + workflowTools + shortsTools + visualEditorTools + playbackAndExportTools + systemTools

    private static let projectTools: [McpToolDefinition] = [
        tool("list_projects", "List saved VaniScript projects with pagination and progress summaries.", .read, props: [
            "cursor": integer(min: 0), "limit": integer(min: 1, max: 100),
        ]),
        tool("get_project_summary", "Get a safe summary for one saved project.", .read, props: ["projectId": string], required: ["projectId"]),
        tool("open_project", "Open a saved project in Review or Export.", .edit, props: [
            "projectId": string,
            "chunkId": string,
            "screen": enumString(["review", "export"]),
            "expectedRevision": revision,
        ], required: ["projectId"]),
        tool("save_project", "Persist the active project immediately.", .edit, props: ["expectedRevision": revision]),
        tool("reset_session", "Preview or confirm closing the active project and returning to Upload.", .destructive, props: confirmationProps),
        tool("import_media_file", "Ask the user to choose one local audio or video file, then load it into VaniScript.", .files),
        tool("import_media_url", "Start a background job that imports a supported media URL.", .network, props: [
            "url": string,
            "audioOnly": boolean,
        ], required: ["url"]),
        tool("get_source_media_info", "Get safe technical information about the active or saved project's source media.", .read, props: ["projectId": string]),
        tool("import_project_bundle", "Ask the user to choose a VaniScript project bundle and import it.", .files),
        tool("export_project_bundle", "Export one project bundle into VaniScript's protected MCP Exports folder.", .files, props: ["projectId": string]),
        tool("delete_project", "Preview or confirm permanent deletion of one saved project record.", .destructive, props: confirmationProps.merging(["projectId": string]) { _, new in new }, required: ["projectId"]),
    ]

    private static let workflowTools: [McpToolDefinition] = [
        tool("get_workflow_config", "Get source language, target language, providers, formats, and chunking configuration without secrets.", .read),
        tool("update_workflow_config", "Update safe workflow configuration fields before or during a project.", .edit, props: [
            "sourceLanguage": string,
            "targetLanguage": string,
            "transcriptionProvider": string,
            "translationProvider": string,
            "formats": array(enumString(["txt", "markdown", "srt", "vtt"]), max: 4),
            "chunkDurationMin": integer(min: 1, max: 120),
            "sliceMode": enumString(["silence", "fixed"]),
            "expectedRevision": revision,
        ]),
        tool("start_processing", "Start segment processing as a background operation using the current workflow configuration.", .processing, props: ["expectedRevision": revision]),
        tool("cancel_processing", "Cancel a background job by jobId, or cancel the active in-app processing/export task.", .processing, props: ["jobId": string]),
        tool("retry_failed_chunks", "Retry all failed project segments in order.", .processing, props: ["expectedRevision": revision]),
        tool("select_chunk", "Select one segment in Review by stable chunkId.", .edit, props: ["chunkId": string, "expectedRevision": revision], required: ["chunkId"]),
    ]

    private static let shortsTools: [McpToolDefinition] = [
        tool("generate_shorts_plans", "Start a background AI job that finds non-overlapping Shorts/Reels moments.", .processing, props: [
            "count": integer(min: 1, max: 20),
            "minDurationSec": integer(min: 10, max: 300),
            "maxDurationSec": integer(min: 10, max: 300),
            "mode": enumString(["source", "target", "bilingual"]),
            "expectedRevision": revision,
        ]),
        tool("get_shorts_plan", "Get one Shorts plan and safe Visual Editor summary by stable planId.", .read, props: ["planId": string], required: ["planId"]),
        tool("create_shorts_plan", "Create one manually defined Shorts plan.", .edit, props: shortsPlanProps.merging(["expectedRevision": revision]) { _, new in new }, required: ["startSec", "endSec", "title"]),
        tool("update_shorts_plan", "Patch Shorts title, summary, hook, category, or caption text.", .edit, props: shortsPlanTextProps.merging(["planId": string, "language": enumString(["source", "target"]), "expectedRevision": revision]) { _, new in new }, required: ["planId"]),
        tool("update_shorts_timing", "Update one Shorts plan range using validated absolute seconds.", .edit, props: [
            "planId": string, "startSec": number(min: 0), "endSec": number(min: 0), "expectedRevision": revision,
        ], required: ["planId", "startSec", "endSec"]),
        tool("remove_shorts_plan", "Move one Shorts plan to the rejected list after preview confirmation.", .destructive, props: confirmationProps.merging(["planId": string]) { _, new in new }, required: ["planId"]),
        tool("list_rejected_shorts_plans", "List removed Shorts plans that remain excluded from future AI planning.", .read),
        tool("restore_shorts_plan", "Restore one rejected Shorts plan if it does not overlap an active plan.", .edit, props: ["planId": string, "expectedRevision": revision], required: ["planId"]),
        tool("translate_shorts_plans", "Start a background job that translates selected Shorts metadata.", .processing, props: [
            "planIds": array(string, max: 100), "language": string, "expectedRevision": revision,
        ], required: ["language"]),
        tool("validate_shorts_plan", "Validate timing, duration, titles, captions, cuts, and source-media bounds for one Shorts plan.", .read, props: ["planId": string], required: ["planId"]),
        tool("open_visual_editor", "Open one Shorts plan in VaniScript's Visual Editor.", .edit, props: [
            "planId": string, "language": enumString(["source", "target"]),
        ], required: ["planId"]),
    ]

    private static let visualEditorTools: [McpToolDefinition] = [
        tool("get_visual_editor_state", "Get an editable, path-safe Visual Editor state for one Shorts plan.", .read, props: ["planId": string], required: ["planId"]),
        tool("update_clip_details", "Patch title, summary, hook, category, or caption text in one Visual Editor clip.", .edit, props: shortsPlanTextProps.merging(["planId": string, "language": enumString(["source", "target"]), "expectedRevision": revision]) { _, new in new }, required: ["planId"]),
        tool("update_clip_timing", "Update the Visual Editor clip range in absolute source seconds.", .edit, props: ["planId": string, "startSec": number(min: 0), "endSec": number(min: 0), "expectedRevision": revision], required: ["planId", "startSec", "endSec"]),
        tool("manage_timeline_cut", "Create, update, or delete a stable timeline cut inside a Shorts clip.", .edit, props: ["planId": string, "action": enumString(["create", "update", "delete"]), "cutId": string, "startSec": number(min: 0), "endSec": number(min: 0), "expectedRevision": revision], required: ["planId", "action"]),
        tool("manage_subtitle_segment", "Create, update, split, merge, or delete an aligned subtitle segment.", .edit, props: ["planId": string, "language": enumString(["source", "target"]), "action": enumString(["create", "update", "split", "merge", "delete"]), "segmentId": string, "secondSegmentId": string, "startSec": number(min: 0), "endSec": number(min: 0), "splitSec": number(min: 0), "text": string, "expectedRevision": revision], required: ["planId", "action"]),
        tool("set_frame_keyframes", "Replace a language frame-keyframe sequence with bounded positions and zoom levels.", .edit, props: ["planId": string, "language": enumString(["source", "target"]), "keyframes": array(object, max: 120), "expectedRevision": revision], required: ["planId", "keyframes"]),
        tool("clear_frame_keyframes", "Reset a language frame sequence to the safe neutral base keyframe.", .edit, props: ["planId": string, "language": enumString(["source", "target"]), "expectedRevision": revision], required: ["planId"]),
        tool("update_visual_background", "Patch validated Visual Editor background settings; colours must be hex values.", .edit, props: ["planId": string, "patch": object, "expectedRevision": revision], required: ["planId", "patch"]),
        tool("update_visual_subtitle_style", "Patch validated typography, caption box, outline, and shadow settings for one Shorts clip.", .edit, props: ["planId": string, "patch": object, "expectedRevision": revision], required: ["planId", "patch"]),
        tool("update_visual_logo", "Edit or clear an already user-selected logo. Adding a new asset requires the Visual Editor file picker.", .edit, props: ["planId": string, "language": enumString(["source", "target"]), "action": enumString(["update", "clear"]), "logoId": string, "size": number(min: 0), "opacity": number(min: 0), "position": string, "hidden": boolean, "expectedRevision": revision], required: ["planId", "action"]),
        tool("update_intro_outro", "Edit or clear an existing intro/outro overlay. Adding a new asset requires the Visual Editor file picker.", .edit, props: ["planId": string, "language": enumString(["source", "target"]), "kind": enumString(["intro", "outro"]), "action": enumString(["update", "clear"]), "overlayId": string, "duration": number(min: 0), "x": number(min: -100), "y": number(min: -100), "scale": number(min: 0), "animation": string, "hidden": boolean, "speed": number(min: 0), "transitionSec": number(min: 0), "expectedRevision": revision], required: ["planId", "kind", "action"]),
        tool("set_visual_sync", "Enable or disable linked source/target Visual Editor synchronization.", .edit, props: ["planId": string, "enabled": boolean, "expectedRevision": revision], required: ["planId", "enabled"]),
        tool("manage_text_track", "Create, update, or delete a Visual Editor text track.", .edit, props: ["planId": string, "language": enumString(["source", "target"]), "action": enumString(["create", "update", "delete"]), "trackId": string, "name": string, "hidden": boolean, "muted": boolean, "expectedRevision": revision], required: ["planId", "action"]),
        tool("manage_text_block", "Create, update, or delete a text block inside a Visual Editor text track.", .edit, props: ["planId": string, "language": enumString(["source", "target"]), "action": enumString(["create", "update", "delete"]), "trackId": string, "blockId": string, "startSec": number(min: 0), "endSec": number(min: 0), "text": string, "hidden": boolean, "expectedRevision": revision], required: ["planId", "action", "trackId"]),
        tool("manage_audio_track", "Update or delete an existing Visual Editor audio track. Adding media remains an explicit user file-picker action.", .edit, props: ["planId": string, "language": enumString(["source", "target"]), "action": enumString(["update", "delete"]), "audioTrackId": string, "name": string, "startSec": number(min: 0), "trimStartSec": number(min: 0), "trimEndSec": number(min: 0), "volume": number(min: 0), "fadeInSec": number(min: 0), "fadeOutSec": number(min: 0), "muted": boolean, "expectedRevision": revision], required: ["planId", "action", "audioTrackId"]),
        tool("save_visual_editor", "Persist the active Visual Editor state to the project archive.", .edit, props: ["planId": string, "expectedRevision": revision], required: ["planId"]),
    ]

    private static let playbackAndExportTools: [McpToolDefinition] = [
        tool("get_playback_state", "Get Review playback state, position, duration, and selected segment.", .read),
        tool("play_chunk", "Select and play a segment through VaniScript's Review player.", .edit, props: ["chunkId": string]),
        tool("pause_playback", "Pause Review playback.", .edit),
        tool("seek_playback", "Seek Review playback to a position inside the selected segment.", .edit, props: ["positionSec": number(min: 0)], required: ["positionSec"]),
        tool("list_export_options", "List transcript, Shorts idea, and video export options available for the active project.", .read),
        tool("validate_export", "Run export preflight without creating files.", .read, props: [
            "kind": enumString(["transcript", "shortsIdeas", "shortsVideos"]),
        ], required: ["kind"]),
        tool("export_transcript", "Export a transcript into VaniScript's protected MCP Exports folder.", .files, props: [
            "side": enumString(["original", "translated"]),
            "format": enumString(["txt", "markdown", "srt", "vtt"]),
            "language": string,
        ], required: ["side", "format"]),
        tool("export_shorts_ideas", "Export selected Shorts ideas as JSON and text into the protected MCP Exports folder.", .files, props: [
            "planIds": array(string, max: 100),
            "language": enumString(["source", "target"]),
        ]),
        tool("export_shorts_videos", "Start a cancellable native video render job in the protected MCP Exports folder.", .files, requiredAccesses: [.files, .processing], props: [
            "planIds": array(string, max: 100),
            "language": enumString(["source", "target"]),
            "format": enumString(["mp4", "mov"]),
            "resolution": enumString(["source", "1080p", "720p"]),
            "frameRate": enumString(["source", "30", "25", "24"]),
        ]),
        tool("reveal_export", "Reveal a completed MCP export in Finder by exportId.", .files, props: ["exportId": string], required: ["exportId"]),
    ]

    private static let systemTools: [McpToolDefinition] = [
        tool("get_safe_settings", "Get editable user preferences without secrets, tokens, paths, or MCP credentials.", .read),
        tool("update_safe_settings", "Update bounded appearance, default language, and chunking preferences without touching secrets or MCP security settings.", .edit, props: ["theme": enumString(["dark", "light"]), "fontSize": enumString(["sm", "md", "lg", "xl"]), "fontScale": number(min: 0.8), "fontFamily": enumString(["mono", "sans", "serif"]), "defaultSourceLanguage": string, "defaultTargetLanguage": string, "chunkDurationMin": integer(min: 1, max: 120), "sliceMode": enumString(["silence", "fixed"]), "silenceThresholdDb": integer(min: -80, max: 0), "minimumSilenceMs": integer(min: 0, max: 10_000)]),
        tool("list_providers", "List configured and local provider readiness without API keys or secrets.", .read),
        tool("select_provider", "Select an already configured transcription or translation provider.", .edit, props: ["kind": enumString(["transcription", "translation"]), "providerId": string], required: ["kind", "providerId"]),
        tool("list_prompt_presets", "List prompt definitions and active preset slots.", .read),
        tool("get_prompt", "Get one built-in or custom prompt preset by promptId and slot.", .read, props: ["promptId": string, "slot": enumString(["active", "default", "custom1", "custom2", "custom3"])], required: ["promptId"]),
        tool("update_prompt", "Write a bounded custom prompt and optionally make that preset active.", .edit, props: ["promptId": string, "slot": enumString(["custom1", "custom2", "custom3"]), "text": string, "activate": boolean], required: ["promptId", "slot", "text"]),
        tool("reset_prompt", "Restore one prompt to the built-in default or clear one custom slot.", .edit, props: ["promptId": string, "slot": enumString(["active", "custom1", "custom2", "custom3"])], required: ["promptId"]),
        tool("get_model_status", "Get local model availability without filesystem paths.", .read),
        tool("scan_local_models", "Rescan standard local model locations and refresh model readiness.", .network),
        tool("download_model", "Start a non-cancellable background download of a known local model.", .network, props: ["modelId": string], required: ["modelId"]),
        tool("locate_model", "Ask the user to choose a local model file or folder, then validate it for one known model.", .files, props: ["modelId": string], required: ["modelId"]),
        tool("remove_model", "Preview or remove a local model reference from VaniScript settings; it never deletes arbitrary files.", .destructive, props: confirmationProps.merging(["modelId": string]) { _, new in new }, required: ["modelId"]),
    ]

    private static func tool(
        _ name: String,
        _ description: String,
        _ access: McpToolAccess,
        requiredAccesses: Set<McpToolAccess>? = nil,
        props: [String: Any] = [:],
        required: [String] = []
    ) -> McpToolDefinition {
        var schema: [String: Any] = ["type": "object", "properties": props]
        if !required.isEmpty { schema["required"] = required }
        return McpToolDefinition(
            name: name,
            description: description,
            access: access,
            requiredAccesses: requiredAccesses,
            inputSchema: schema
        )
    }

    private static var string: [String: Any] { ["type": "string"] }
    private static var boolean: [String: Any] { ["type": "boolean"] }
    private static var object: [String: Any] { ["type": "object"] }
    private static var revision: [String: Any] {
        ["type": "string", "description": "Latest projectRevision from a read tool."]
    }
    private static var confirmationProps: [String: Any] {
        [
            "dryRun": ["type": "boolean", "description": "Defaults to true."],
            "confirmationToken": string,
            "expectedRevision": revision,
        ]
    }
    private static var shortsPlanTextProps: [String: Any] {
        [
            "title": string,
            "summary": string,
            "hook": string,
            "category": string,
            "captionText": string,
        ]
    }
    private static var shortsPlanProps: [String: Any] {
        shortsPlanTextProps.merging([
            "startSec": number(min: 0),
            "endSec": number(min: 0),
            "mode": enumString(["source", "target", "bilingual"]),
        ]) { _, new in new }
    }

    private static func integer(min: Int, max: Int? = nil) -> [String: Any] {
        var result: [String: Any] = ["type": "integer", "minimum": min]
        if let max { result["maximum"] = max }
        return result
    }

    private static func number(min: Double) -> [String: Any] {
        ["type": "number", "minimum": min]
    }

    private static func enumString(_ values: [String]) -> [String: Any] {
        ["type": "string", "enum": values]
    }

    private static func array(_ items: [String: Any], max: Int) -> [String: Any] {
        ["type": "array", "maxItems": max, "items": items]
    }
}
