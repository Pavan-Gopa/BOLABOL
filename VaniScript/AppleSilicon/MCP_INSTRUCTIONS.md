# VaniScript Local MCP Integration

VaniScript can expose a local Model Context Protocol server for trusted AI tools on the same Mac.

The server is disabled by default. Enable it in **VaniScript Settings -> Agents -> Local MCP Server**.

## Security Model

- Endpoint: `http://127.0.0.1:19790/sse`
- Transport: HTTP/SSE
- Bind policy: loopback only
- Authentication: required access token
- Default tool policy: read-only
- Write tools: available only when **Allow Write Tools** is enabled
- Secret handling: project state never returns API keys, provider keys, media resolver tokens, or MCP access tokens

## Tools

Read-only tools:

- `get_project_state`
- `get_subtitle_style`
- `get_shorts_plans`

Optional write tools:

- `update_chunk_text`
- `approve_chunk`
- `update_subtitle_style`
- `update_cue_timestamps`
- `align_translation_timings`
- `reprocess_chunk`

## Setup

1. Open VaniScript.
2. Open **Settings -> Agents -> Local MCP Server**.
3. Turn on **Enable MCP**.
4. Copy the access token.
5. Keep **Allow Write Tools** off for read-only inspection. Turn it on only when the external agent should be allowed to edit the active project.
6. Use **Settings -> Agents -> Agent Profiles** to copy the setup command or config for the MCP client you want to use.

## Switching Agents

VaniScript does not force external apps to connect or disconnect. The **Active Target** selector marks the profile you are currently setting up, and the green status dot appears only when that client has an active MCP session.

To move from one agent to another:

1. Stop or close the current MCP client if you do not want it to keep the session.
2. Select the next profile in **Active Target**.
3. Click **Copy Setup** for that profile.
4. Apply the command or config in that client.
5. Open or restart the client. When it connects, its status changes to **Connected**.

## Codex

Direct SSE connection with a bearer token:

```bash
export VANISCRIPT_MCP_TOKEN="<paste token from VaniScript Settings>"
codex mcp add --bearer-token-env-var VANISCRIPT_MCP_TOKEN vaniscript --url http://127.0.0.1:19790/sse
```

Stdio bridge alternative:

```bash
codex mcp add vaniscript -- python3 "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon/mcp_bridge.py"
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
