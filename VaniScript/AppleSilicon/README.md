# VaniScript

VaniScript is the native Apple Silicon macOS application. It is not the
Electron application and it does not modify SmartScribe.

## Direction

1. Build only for Apple Silicon (`arm64`).
2. Use SwiftUI and AppKit for the desktop shell.
3. Use WhisperKit/Core ML for native transcription.
4. Use MLX Swift for local text polishing.
5. Keep Electron, Node, and browser runtimes out of the native app.

## AI Providers

VaniScript integrates external AI providers as CLI subprocesses (no bundled
runtimes). Each provider follows the same isolation model: the MCP access token
is passed only in the child process environment, and there is no silent
MCP-chat → API fallback.

- **Codex** — CLI subprocess.
- **Grok** — CLI subprocess.
- **Qwen** — CLI subprocess, model `qwen3.8-max-preview`.

Provider access surfaces:

- **Embedded chat** — inside the app on Apple Silicon (`ChatSidebarView` route
  selector) and in the Electron desktop build.
- **External MCP access** — a manually launched CLI connects to the local MCP
  server over SSE (AS `:19790`, Electron `:19789`); see `MCP_INSTRUCTIONS.md`.
- **In-app API** — `QwenStreamingProvider` in `VaniScriptCore` (streaming,
  cancel, typed errors) usable programmatically without UI.

## Local Run

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
```
