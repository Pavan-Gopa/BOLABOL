# VaniScript Local MCP Server Integration

When the VaniScript application is running, it exposes a local Model Context Protocol (MCP) server utilizing the HTTP/SSE transport standard.

This allows external AI agents, coding assistants, and IDEs to connect directly to VaniScript to view project state, update timed subtitle transcriptions, align translations, and manage shorts rendering.

## Server Endpoints

Depending on the workspace version you are running:
* **Apple Silicon (Native Swift) version**: `http://127.0.0.1:19790/sse`
* **Electron version**: `http://127.0.0.1:19789/sse`

---

## 1. Claude Code
Claude Code supports direct HTTP/SSE connections. In your terminal, run:

### Swift/Apple Silicon Version:
```bash
claude mcp add --transport sse vaniscript http://127.0.0.1:19790/sse
```

### Electron Version:
```bash
claude mcp add --transport sse vaniscript http://127.0.0.1:19789/sse
```

---

## 2. Codex
Codex can connect directly to the running SSE server:

### Swift/Apple Silicon Version:
```bash
codex mcp add vaniscript --url http://127.0.0.1:19790/sse
```

### Electron Version:
```bash
codex mcp add vaniscript --url http://127.0.0.1:19789/sse
```

---

## 3. Cursor IDE
Cursor supports native HTTP/SSE servers:
1. Go to **Cursor Settings** -> **Features** -> **MCP**.
2. Click **+ Add New MCP Server**.
3. Configure as follows:
   * **Name**: `VaniScript`
   * **Type**: `SSE`
   * **URL**: `http://127.0.0.1:19790/sse` *(Use `19789` for Electron version)*
4. Click **Save**.

---

## 4. Claude Desktop
Since Claude Desktop currently only supports `stdio` subprocess commands, you can use the lightweight Python bridge included in this directory to route communications:

Edit your Claude Desktop configuration file (`~/Library/Application Support/Claude/claude_desktop_config.json`) and append:

### For Swift/Apple Silicon:
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

### For Electron:
```json
{
  "mcpServers": {
    "vaniscript": {
      "command": "python3",
      "args": [
        "/Users/pavan/Documents/AI Projects/VaniScript/Electron/mcp_bridge.py"
      ]
    }
  }
}
```

---

## 5. Google Antigravity & AI Developer Platforms
To register the server globally inside the Antigravity developer environment:
1. Edit the global config: `~/.gemini/config/mcp_config.json`
2. Add the server entry pointing to the bridge script:
   ```json
   "vaniscript": {
     "command": "python3",
     "args": [
       "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon/mcp_bridge.py"
     ]
   }
   ```
