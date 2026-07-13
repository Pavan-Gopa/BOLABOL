# Project Context — VaniScript (Apple Silicon + Electron)

## What this is

**VaniScript** — macOS app for lecture/kirtan transcription, translation, review, and Shorts/Reels export.

| Variant | Path | Stack | Local MCP |
|---------|------|-------|-----------|
| **Apple Silicon (primary)** | `VaniScript/AppleSilicon/` | SwiftUI + VaniScriptCore | `127.0.0.1:19790` |
| **Electron** | `VaniScript/Electron/` | React + Electron | `127.0.0.1:19789` |

Workspace root: `AI Projects/` (multi-project). **Do not** put app source in workspace root. Nested Electron has its own `.git`; Apple Silicon is tracked in the workspace repo.

## Active tracks (orchestrated)

| Track | Steps | Goal |
|-------|-------|------|
| **GROK_MCP** | G1 → G6 → `GROK_DONE` | Grok as external MCP client + embedded chat (mirror Codex on AS; Electron functional) |
| **UI_AS** | U0 → U3 → `UI_DONE` | Density / visual polish **Apple Silicon only** (after GROK_DONE) |

Plans: `AI_Workflow_Kit/docs/GROK_MCP_STEPS.md`, `UI_AS_STEPS.md`.  
State of truth: `AI_Workflow_Kit/docs/AI/STATE.yaml`.

## Architecture notes (relevant)

### MCP

- VaniScript is an **MCP server** (SSE / Streamable HTTP) with scoped tools.
- External agents (Codex, Claude, Cursor, Antigravity, **Grok**) connect in.
- **Embedded AS chat (MCP route):** launches **Codex CLI** subprocess with isolated MCP profile `vaniscript_embedded` (`CodexAgentService`).
- **Embedded Electron chat today:** Gemini API function-calling (not Codex CLI).
- Security: no API keys in project state; token only in env / settings; destructive tools need confirmation.

### Codex reference (do not break)

- `Sources/VaniScriptCore/CodexAgentSupport.swift`
- `Sources/VaniScript/Services/CodexAgentService.swift`
- `Sources/VaniScript/Views/ChatSidebarView.swift` (MCP vs API routes)
- `Sources/VaniScriptCore/McpContracts.swift` (`McpClientProfileID`, setupText, classifier)

### Grok target behavior

- External profile like Codex (`grok mcp add …`).
- Embedded: Grok CLI headless (`~/.grok/bin/grok`, `grok -p`, MCP isolated), account via `grok login` — **no silent fallback** to Gemini.
- Isolation: ephemeral project config; token only in child env.

### UI redesign (track UI_AS only)

- Theme: `Sources/VaniScript/Theme/VaniScriptTheme.swift`
- Editor: `Sources/VaniScript/Views/VisualClipEditorView.swift` (`SliderRow`, inspector)
- **Electron visual redesign is out of scope** for this program of work.

## Verify commands

```bash
# Apple Silicon
cd "VaniScript/AppleSilicon" && swift test
# or
cd "VaniScript/AppleSilicon" && swift build

# Electron (only when step G5 / Electron target_files)
cd "VaniScript/Electron" && npm test
```

## Rules

1. One step at a time; only `STATE.yaml` → `target_files`.
2. Agents talk **via files only**; human switches models.
3. **Git checkpoint before every step and after every approved step** (commit + annotated tag + push when remote allows). See `docs/AI/GIT_CHECKPOINTS.md`.
4. No UI density work during GROK_MCP steps.
5. No MCP tools catalog expansion unless a step explicitly says so.
6. Orchestrator does not write product code until `attempts >= 3`.
