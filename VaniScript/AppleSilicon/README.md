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

## Cloud Providers & the API & Usage tab

Settings → **API & Usage** manages cloud API providers (track `API_USAGE`,
Apple Silicon only). Supported providers, in catalog order
(`CloudProviderCatalog`): **Gemini, OpenAI, Anthropic, Qwen (DashScope),
OpenRouter, Ollama Cloud, Custom**.

The tab has five surfaces:

1. **Provider dropdown** — fixed catalog order, single source of truth.
2. **Provider card** — API key input with live key validation and model list
   (`CloudKeyValidator` / `CloudModelCatalog`), budget slider (Qwen/OpenRouter),
   Base URL (Ollama Cloud). The Transcribing toggle is honestly disabled for
   providers without audio capability.
3. **Usage recording** — token usage is recorded best-effort per
   `provider:model` (`UsageRecorder`); recording failures never break
   transcription or translation.
4. **Usage statistics** — last transaction, active providers summary, and
   per-model cards (tokens, audio minutes, estimated spent/remaining) in
   `UsageStatisticsView`. Costs are estimates; provider billing can differ.
5. **Real balance** — shown only where the provider exposes it
   (`CloudBalanceService`): OpenRouter credits ("$X remaining / $Y limit"),
   Ollama Cloud plan label. All other providers show honest estimates only —
   no fake "$" figures.

Keys live only in settings (never in sources, logs, or git). Old settings
decode without migration. Acceptance checklist:
`AI_Workflow_Kit/docs/API_USAGE_ACCEPTANCE.md`.

## Local Run

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
```
