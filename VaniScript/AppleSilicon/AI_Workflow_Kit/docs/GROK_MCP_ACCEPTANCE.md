# GROK_MCP — Acceptance Smoke

> Track `GROK_MCP` (G1–G6). Companion to `GROK_MCP_STEPS.md`.
> This file is a **manual smoke checklist**, not a spec. No product features are added here.

## Coverage

| Path | Where | Acceptance |
|------|-------|------------|
| External Grok MCP | AS `127.0.0.1:19790/sse` · Electron `127.0.0.1:19789/sse` | Grok connects as an external MCP client and can call VaniScript tools |
| AS embedded chat | `ChatSidebarView` (Codex **and** Grok) | Either agent runs the MCP chat route; Grok uses headless `grok` CLI |
| Electron embedded chat | `ChatSidebar` route selector (`API · Gemini` / `MCP · Grok`) | Grok route launches headless `grok` CLI via main-process IPC |

## Hard invariants (must hold)

1. **No silent MCP→API fallback.** If the active agent is Grok and Grok is unavailable, the UI shows a clear error. Gemini is used **only** when the API route is explicitly selected.
2. **Isolation.** Embedded Grok runs against an isolated `vaniscript_embedded` MCP config / ephemeral project; the access token (when used) lives only in the child-process environment — never written to disk or logged.
3. **Codex parity.** The MCP chat route works identically for Codex and Grok (G4). Selecting Grok does not regress the Codex path.
4. **Port map.** AS = `19790`, Electron = `19789`. External clients point at the matching edition.

## Manual smoke — External Grok MCP

- [ ] AS app running (MCP server on `127.0.0.1:19790/sse`).
- [ ] Run `grok mcp add vaniscript --transport sse --url http://127.0.0.1:19790/sse` (or the stdio bridge from `MCP_INSTRUCTIONS.md`).
- [ ] In Grok, call `get_project_state` and confirm a JSON snapshot of the active project returns.
- [ ] Call `update_chunk_text` / `approve_chunk` and confirm the AS UI reflects the change.
- [ ] Same flow against Electron on `127.0.0.1:19789/sse` (Electron app running).
- [ ] Confirm the VaniScript **Grok** profile appears in Settings → Agents with correct setup copy (G1).

## Manual smoke — AS embedded chat (Codex + Grok)

- [ ] Open the chat sidebar; agent switch shows **Codex** and **Grok** (G4).
- [ ] With Codex selected, send a request that triggers a tool call (e.g. "approve segment 4"); tool executes and reply confirms.
- [ ] Switch to **Grok**; send the same request. Grok launches the headless CLI and the tool executes through the same path (G3/G4).
- [ ] With Grok selected and `grok` CLI missing / not logged in, a clear error is shown (no Gemini fallback).

## Manual smoke — Electron embedded chat (Grok)

- [ ] Electron app running (MCP SSE server on `127.0.0.1:19789`).
- [ ] Chat panel header shows the route selector. Default = `API · Gemini`.
- [ ] Switch to `MCP · Grok`. Send a request; the headless `grok` CLI launches (check main-process logs) and the streamed reply renders in the panel.
- [ ] Grok's tool calls execute via the existing `onMcpCallTool` / `executeMcpTool` bridge (e.g. a VaniScript edit is applied).
- [ ] With `grok` missing / not logged in, the panel shows a clear error and does **not** fall back to Gemini.

## Sign-off

- [ ] All three paths smoke-tested by human.
- [ ] `swift test` / `swift build` green for AS; Electron `npm run compile` clean.
- [ ] Orchestrator sets `GROK_DONE` and opens `UI_AS` only after human confirms.
