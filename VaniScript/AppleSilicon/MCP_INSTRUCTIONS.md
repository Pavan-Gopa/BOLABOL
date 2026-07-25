# VaniScript Local MCP Integration

VaniScript can expose a local Model Context Protocol server for trusted AI tools on the same Mac.

The server is disabled by default. Enable it in **VaniScript Settings -> Agents -> Local MCP Server**.

## Security Model

- Endpoint: `http://127.0.0.1:19790/sse`
- Transport: Streamable HTTP for direct clients, plus legacy HTTP/SSE for compatible bridges
- Bind policy: loopback only
- Authentication: required access token
- Browser policy: requests with a non-loopback `Origin` are rejected
- Local secret storage: the VaniScript support directory is owner-only (`0700`) and `settings.json` is owner-read/write only (`0600`)
- Default tool policy: read-only
- Permission scopes: **Edit Project**, **Run Processing**, **Files & Export**,
  **Network & Models**, and **Destructive Actions** are independently enabled
- Destructive commands use a two-step preview and short-lived confirmation token
- Secret handling: project state never returns API keys, provider keys, media resolver tokens, or MCP access tokens
- Asset handling: MCP never accepts arbitrary local paths for visual assets; the
  user chooses a logo, intro/outro, or audio asset through the native file picker

## Tools

VaniScript currently exposes 120 typed MCP tools. The exact tools visible to an
agent are filtered by the permissions enabled in VaniScript Settings. Start with
`get_capabilities`; it returns the active permission scopes and the available
tool groups without exposing secrets.

- **Help & onboarding:** bilingual product help, contextual next steps, and a
  beginner checklist.
- **Projects & workflow:** open/save/import/export projects, inspect source
  media, configure languages and providers, and run/cancel processing jobs.
- **Transcript & translation:** inspect/search chunks and cues, correct text and
  timings, batch approve, translate, retry, and polish.
- **Glossary:** search, CRUD, import/export, preview, and confirmed application
  to a chunk or project.
- **Shorts & Visual Editor:** plan clips, validate timing, edit captions, cuts,
  keyframes, background, typography, tracks, overlays, sync, and export.
- **Playback & export:** control Review playback and create protected exports in
  VaniScript's application-support folder.
- **Settings & models:** view safe preferences, select already configured
  providers, edit prompt presets, inspect/scan/download/locate models, and
  preview removal of a model reference.

Every mutation can accept `expectedRevision` to prevent overwriting a newer
user change and `requestId` for idempotent retries. Long-running work returns a
`jobId`; use `get_job`, `list_jobs`, or `cancel_job` to follow it. Calls that
delete a project, model reference, or Visual Editor entity additionally require
the `Destructive Actions` scope at execution time.

## Setup

1. Open VaniScript.
2. Open **Settings -> Agents -> Local MCP Server**.
3. Turn on **Enable MCP**.
4. Copy the access token.
5. Turn on only the permission scopes required for this agent session. Begin
   with read-only access; enable **Edit Project** for edits, then the more
   powerful scopes only when needed.
6. Use **Settings -> Agents -> Agent Profiles** to copy the setup command or config for the MCP client you want to use.

## Switching Agents

VaniScript does not force external apps to connect or disconnect. The **Active Target** selector marks the profile you are currently setting up, and the green status dot appears only when that client has an active MCP session.

To move from one agent to another:

1. Stop or close the current MCP client if you do not want it to keep the session.
2. Select the next profile in **Active Target**.
3. Click **Copy Setup** for that profile.
4. Apply the command or config in that client.
5. Open or restart the client. When it connects, its status changes to **Connected**.

## Chat Behavior

The embedded panel has explicit **MCP** and **API** routes. It never falls back from MCP to API automatically.

The **MCP** route is a full embedded Codex chat, not MCP sampling. VaniScript launches the locally installed Codex CLI through the signed-in ChatGPT/Codex account, sends the conversation history with each ephemeral request, and displays Codex's response in the VaniScript panel. Codex connects back to the same VaniScript process through a separate direct Streamable HTTP profile named `vaniscript_embedded`.

The embedded route is deliberately isolated from the user's global Codex configuration:

- it uses `--ignore-user-config`, so unrelated plugins, bridges, and MCP servers are not inherited;
- it runs Codex with the `read-only` sandbox and instructs Codex not to use shell, files, browser, or external tools;
- the VaniScript access token exists only in the child process environment and is never written to a Codex config file or command line;
- only the `vaniscript_embedded` MCP server receives automatic tool approval;
- VaniScript remains the write boundary: a tool is exposed only when its required
  permission scope is enabled.

The **API** route is separate and uses only the API key explicitly configured in Settings. It is never selected by a failed or unavailable Codex request.

For product help, the embedded Codex route uses VaniScript's bilingual built-in guide instead of guessing how the interface works. It can search feature documentation, return a complete beginner checklist, and combine the current workspace state with exact step-by-step next actions. Button and screen names remain identical to the labels visible in the app, while the explanation follows the language of the user's question.

The MCP chat route requires the local Codex CLI supplied with the ChatGPT desktop app and an active Codex/ChatGPT account. If the account has no remaining Codex capacity, VaniScript shows that error in the panel instead of silently switching providers.

## Codex

Recommended for Codex Desktop: a local stdio bridge. It reads the owner-only VaniScript settings file and sends the token only to the loopback server.

```bash
codex mcp add vaniscript -- python3 "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon/mcp_bridge.py"
```

Direct Streamable HTTP connection for a terminal Codex session with a bearer token:

```bash
export VANISCRIPT_MCP_TOKEN="<paste token from VaniScript Settings>"
codex mcp add --bearer-token-env-var VANISCRIPT_MCP_TOKEN vaniscript --url http://127.0.0.1:19790/sse
```

The bridge reads `VANISCRIPT_MCP_TOKEN` when provided. If it is not provided, it reads the saved token from `~/Library/Application Support/VaniScript/settings.json`.

## Claude Code

Direct SSE connection:

```bash
claude mcp add --transport sse --header "Authorization: Bearer <paste token from VaniScript Settings>" vaniscript http://127.0.0.1:19790/sse
```

Stdio bridge alternative:

```bash
claude mcp add vaniscript -- python3 "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon/mcp_bridge.py"
```

## Claude Desktop

Edit:

```text
~/Library/Application Support/Claude/claude_desktop_config.json
```

Add:

```json
{
  "mcpServers": {
    "vaniscript": {
      "command": "python3",
      "args": [
        "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon/mcp_bridge.py"
      ]
    }
  }
}
```

## Cursor

Use the native SSE server if your Cursor MCP configuration supports custom headers:

- Name: `VaniScript`
- Type: `SSE`
- URL: `http://127.0.0.1:19790/sse`
- Header: `Authorization: Bearer <paste token from VaniScript Settings>`

If custom headers are unavailable, use the stdio bridge:

```json
{
  "mcpServers": {
    "vaniscript": {
      "command": "python3",
      "args": [
        "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon/mcp_bridge.py"
      ]
    }
  }
}
```

## Antigravity

For Antigravity/Gemini developer environments, add the stdio bridge to:

```text
~/.gemini/config/mcp_config.json
```

Example:

```json
{
  "mcpServers": {
    "vaniscript": {
      "command": "python3",
      "args": [
        "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon/mcp_bridge.py"
      ]
    }
  }
}
```

The bridge uses the local VaniScript settings token, so the app must be opened once after enabling MCP.

## Grok

Recommended for Grok CLI (stdio bridge):

```bash
grok mcp add vaniscript --transport stdio -- python3 "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon/mcp_bridge.py"
```

Direct Streamable HTTP/SSE connection for a terminal Grok session with a bearer token:

```bash
grok mcp add vaniscript --transport sse --header "Authorization: Bearer <paste token from VaniScript Settings>" --url http://127.0.0.1:19790/sse
```

The bridge reads `VANISCRIPT_MCP_TOKEN` when provided; otherwise it reads the saved token from `~/Library/Application Support/VaniScript/settings.json`.

## External Qwen CLI

This section documents how a **manually launched Qwen CLI** (not the in-app embedded
Qwen chat from Q2–Q4) can connect to the VaniScript MCP server and use its tools.
The embedded chat is already wired through `.qwen/settings.json` with env-var token
substitution; this is the equivalent setup for a terminal Qwen session you start yourself.

### Prerequisites

- The **VaniScript application must be running** so the MCP server is active on its SSE port.
- The Qwen CLI must be installed and authenticated:

  ```bash
  npm install -g @qwen-code/qwen-code
  qwen login
  ```

- The access token is taken from VaniScript **Settings → MCP → Access Token** (or it is
  generated automatically the first time the Local MCP Server is enabled). It is the same
  bearer token used by the embedded chat.

### Option A — `qwen mcp add` (project scope)

```bash
# Add the VaniScript MCP server to Qwen CLI (project scope):
qwen mcp add vaniscript http://127.0.0.1:19789/sse \
  --transport sse \
  --header "Authorization: Bearer <YOUR_TOKEN>" \
  --scope project \
  --trust
```

### Option B — `.qwen/settings.json`

```json
{
  "mcpServers": {
    "vaniscript": {
      "url": "http://127.0.0.1:19789/sse",
      "transport": "sse",
      "headers": {
        "Authorization": "Bearer <YOUR_TOKEN>"
      },
      "trust": true
    }
  }
}
```

> **Port note:** the example above uses `19789` (the desktop web build). The native Apple
> Silicon app listens on `19790` — see the Security Model section. Always copy the exact
> port shown in VaniScript **Settings → MCP** for your build. The auth model, CORS policy,
> and tool catalog are identical across both builds.

### Available tools

Once connected, Qwen can call the VaniScript MCP tools. The exact set visible to the agent
is filtered by the permission scopes enabled in VaniScript Settings. Start from
`get_capabilities`, which returns the active scopes and available tool groups without
exposing secrets. Representative tools include:

- `get_project_state` — current project, source media, languages, and providers.
- `get_subtitle_style` — read the active subtitle/caption style.
- `get_shorts_plans` — list planned shorts/clip plans.
- `apply_subtitle_edits` — apply timed subtitle text/timing edits.
- `apply_glossary` — apply a confirmed glossary entry to a chunk or the project.
- `update_chunk_text`, `approve_chunk`, `update_subtitle_style`, `create_shorts_plan`,
  `set_background_settings`, `trigger_render`, and many more (the native app exposes the
  full 120-tool catalog; the desktop web build exposes the same tools over its SSE port).

Every mutation can accept `expectedRevision` (to avoid overwriting a newer user change) and
`requestId` (for idempotent retries). Long-running work returns a `jobId`; follow it with
`get_job`, `list_jobs`, or `cancel_job`.

### Security notes

- Auth is a **Bearer token** sent in the `Authorization` header (the same token the embedded
  chat uses). The server also accepts an `x-vaniscript-mcp-token` header.
- The server binds to loopback only and rejects non-loopback `Origin` headers, so localhost
  clients work without any CORS change.
- Token handling follows the QWEN_MCP invariants: no silent MCP→API fallback, isolated
  project-scope MCP config, and the token lives only in the client environment / config — never
  inlined into a command line you paste publicly.

