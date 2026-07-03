# SmartScribe

Effortless dictation and note polishing. SmartScribe is an Electron app that records your speech, transcribes it locally (Whisper.cpp via CPU/GPU), and optionally polishes the text with cloud or local LLMs. It’s fast, privacy-friendly, and works offline once models are installed.

## Features

- Local speech-to-text (offline) using Whisper.cpp
  - CPU and GPU backends (Vulkan on Windows/Linux, Metal on macOS)
  - Curated model list with quick install/remove
- Polishing pipeline
  - Cloud: Google Gemini, OpenAI, Anthropic, or any OpenAI-compatible API
  - Local: Ollama JSON-mode integration for deterministic outputs
- Two polishing variants (Variant 1 and Variant 2) with customizable prompts
- Translation modal with many target languages
- Global hotkey for quick dictation from anywhere
- Full i18n UI with manual language selection
- Clear usage stats, logging controls, and a setup wizard

## Installation

1. Download and install SmartScribe for your platform (Windows installer provided under `build/`).
2. Launch the app. The setup wizard will check your mic and providers.
3. Optional: open Settings → Local Models to install a Whisper model for offline use.

## Quick Start

- Click Record to capture audio. Stop to transcribe.
- Use the three tabs to view Raw, Variant 1, and Variant 2 notes.
- Copy the polished text with the copy button.

## Offline Transcription

- Go to Settings → Local Models
- Choose and install a model (e.g., Whisper Small EN or Medium EN)
- Click the installed model to set it Active
- In the top-left selector, choose “Local” as the transcription provider

GPU badge (CPU / GPU: Vulkan/Metal) appears after the first successful local transcription for a model.

## Polishing Models

- Cloud providers (Settings → API Providers):
  - Google Gemini: set API key (or `API_KEY` env var) and pick a model
  - OpenAI / Anthropic: set API key and model
  - Custom: use any OpenAI-compatible API (Base URL + API key + model)
- Local LLMs (Settings → Local LLM):
  - Connect to an Ollama server (local or remote)
  - Use JSON-mode chat with strict system prompt for clean, single-language outputs

## Custom Prompts

- Settings → Custom Prompt
- Define Variant 1 (clean/concise) and Variant 2 (more enhanced) prompts
- Click Default to restore built-ins

## Translation

- Select text in the editor and click the Translate button
- Choose a target language (or add from the Custom Language list)
- You can also record in the modal to transcribe and translate in one step

## Global Hotkey

- Settings → Hotkey
- Enable the Global Hotkey, pick target (Raw/V1/V2), and choose action (Clipboard/Typing)
- Click in the shortcut input and press your desired key combo

## Localization

- Settings → General → Interface Language
- Select “System language” or a manual language from the list

## Logs and Troubleshooting

- Settings → General → Log Level to adjust verbosity
- “Open Log File” button opens the current log to help diagnose issues
- If local models show “Failed,” hover the badge for a reason

## Building From Source

Requirements: Node.js 18+, Python 3.x (for native modules), and platform build tools.

- Install dependencies: `npm install`
- Rebuild native module (postinstall runs this automatically): `npm run rebuild`
- Start in dev: `npm start`
- Build installers: `npm run build` (or platform-specific scripts in `package.json`)

## Privacy

- Local transcription runs on your device. No audio leaves your machine when using Local provider
- Polishing via cloud providers sends text to the selected API; configure according to your privacy requirements
- Local LLMs with Ollama keep polishing on-device

## FAQ

- “Why don’t I see GPU badges?”
  - They appear after the first local transcription result per model, once the backend is detected
- “My local model failed to load.”
  - Hover the Failed badge for a reason; try reinstalling the model, or use CPU temporarily
- “Polishing mixes languages.”
  - Use Local LLMs with JSON mode (built-in). Cloud providers should honor prompts, but local JSON mode is most deterministic

---

If you have issues, open the log file from Settings → General or share details when reporting a bug.
