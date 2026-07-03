# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

SmartScribe is a desktop application built with Electron, React, and TypeScript. It functions as a voice notes and transcription tool, offering both local and cloud-based transcription services.

**Key Technologies:**
- **Electron** - Desktop application framework
- **React 19** with **TypeScript** - Frontend UI
- **Vite** - Frontend build tooling
- **Whisper.cpp** via `@kutalia/whisper-node-addon` - Local AI transcription
- **Google Gemini API** - Cloud transcription and text polishing
- **electron-builder** - Application packaging and distribution

## Architecture

The application uses a **multi-process architecture**:

1. **Main Process** (`main.js`) - Electron main process managing windows, IPC, and system integration
2. **Renderer Process** (`index.tsx`) - React-based UI running in Chromium
3. **Transcription Worker** (`transcription.fork.js`) - Forked Node.js process handling CPU-intensive Whisper.cpp operations
4. **Preload Script** (`preload.js`) - Secure IPC bridge between main and renderer

This architecture ensures the UI remains responsive during transcription by offloading heavy computation to a separate process.

## Development Commands

```bash
# Development workflow
npm run compile          # Compile TypeScript
npm run vite-build      # Build React frontend with Vite
npm start               # Full development build + run Electron

# Building distributables
npm run build           # Windows installer (.exe)
npm run build:x64       # Windows x64 installer
npm run build:arm64     # Windows ARM64 installer  
npm run build:mac       # macOS installer (.dmg)
npm run build:linux     # Linux installers (AppImage, .deb)

# Development utilities
npm run pack            # Package without creating installer
npm run rebuild         # Rebuild native dependencies (whisper addon)
```

**Note:** The `postinstall` script automatically runs `electron-rebuild` to ensure native addons are properly compiled.

## Key Configuration

- **TypeScript Config**: `tsconfig.json` targets ES2022 with React JSX
- **Vite Config**: `vite.config.ts` handles environment variables and build output to `dist/`
- **Electron Builder**: Configured in `package.json` under `build` section for multi-platform packaging
- **Environment Variables**: `.env.local` file manages API keys (GEMINI_API_KEY)

## Critical Architecture Details

### Frontend Application Class (`VoiceNotesApp`)
The main React application is structured as a single large class with:
- **State Management**: Local storage for API settings, usage stats, model states
- **Multi-Provider Support**: Google Gemini, OpenAI, Anthropic, Custom APIs, Local Ollama
- **Real-time Audio**: Web Audio API with live waveform visualization
- **Custom UI Components**: Custom select dropdowns, modal system, tabbed interface

### IPC Communication Pattern
The app uses a sophisticated IPC system for transcription:
- Renderer sends audio data via `ipcRenderer.invoke('whisper:transcribePcm', ...)`
- Main process forwards to transcription worker via `child_process.fork()`
- Results flow back through IPC with request ID tracking for async operations

### Audio Processing Pipeline
1. Audio capture in renderer (Web Audio API) with `MediaRecorder`
2. WAV format validation and PCM Float32 data conversion  
3. Transmission to transcription worker via IPC
4. Whisper.cpp processing with model auto-detection
5. Result streaming back to UI with token usage tracking

### Model Management
**Local Whisper Models** (Q8 quantized):
- Downloaded to `userData/Models/` directory from Hugging Face
- Models: small-en, small-multilingual, medium-en, large-v3-turbo, large-v3
- Installation/removal handled through IPC with progress tracking

**Ollama Integration**:
- Local LLM server support for text polishing
- Models: llama3.2:3b, gemma3:270m, qwen2.5:7b, mistral:7b, phi3.5:3.8b
- Server status monitoring and model management

### Text Processing Pipeline
1. **Raw Transcription** - Direct output from Whisper/cloud providers
2. **Polished Note** - AI-enhanced with grammar/clarity improvements  
3. **Polished X2** - Context-aware enhancement (technical/spiritual/casual)
4. **Translation** - Multi-language support with customizable prompts

**Text Sanitization**: The `sanitizeModelOutput()` method handles:
- Extraction of content between `<<<BEGIN>>>` and `<<<END>>>` markers
- Removal of model preambles and common AI response patterns
- Code fence unwrapping and input marker cleanup
- Fallback handling for various LLM output formats

## Important Development Notes

- **Native Dependencies**: The `@kutalia/whisper-node-addon` requires platform-specific rebuilding
- **Security**: Context isolation enabled, with secure preload bridge pattern
- **Error Handling**: Comprehensive logging via `electron-log` with file output
- **Single Instance**: App prevents multiple instances with focus restoration
- **Tray Integration**: System tray with context menu and global hotkey support

## File Structure Highlights

- `main.js` - Main Electron process with IPC handlers, tray management, overlay windows
- **`index.tsx` - React application entry point with `VoiceNotesApp` class (4,026 lines)**
- `transcription.fork.js` - Whisper worker process handling model downloads and inference  
- `preload.js` - Secure IPC bridge with contextBridge API exposure
- `dist/` - Vite build output (auto-generated)
- `build/` - electron-builder output directory

## Critical File Reading Notes

**`index.tsx` Structure** (4,026 lines total):
- Lines 1-500: Constants, interfaces, custom components (`CustomSelect`)
- Lines 500-1000: `UniversalApiClient` with multi-provider API handling
- Lines 1000-1500: `VoiceNotesApp` constructor and DOM element binding
- Lines 1500-3000: Core functionality (recording, transcription, processing)
- Lines 3000-4000: Model management, UI helpers, setup wizard
- Lines 4000-4026: DOMContentLoaded initialization and placeholder handling

**When reading this file**: Use offset/limit parameters due to 25k token limit. Key sections are spread throughout, especially model management and setup logic near the end.

## Key Implementation Details

### State Management Pattern
- All app state stored in localStorage with specific keys
- Usage statistics tracked per model with token counts
- Settings persisted across sessions (API keys, preferences, model states)

### Custom UI Components
- `CustomSelect` class replaces native dropdowns with styled alternatives
- Modal system for settings, translations, confirmations
- Tab system with active indicator animations
- Real-time waveform visualization during recording

### Error Handling & Logging
- Centralized `logger` with configurable levels (error, warn, info, debug)
- IPC error forwarding from renderer to main process
- Comprehensive error modals with user-friendly messages
- Electron-log integration for file-based logging

### Multi-Provider Architecture
- `UniversalApiClient` class handles all external API integrations
- Fallback mechanisms between providers (local → cloud)
- Token usage tracking and quota error handling
- Provider-specific error handling and retry logic

### Setup Wizard & First-Run Experience
- Setup wizard overlay for first-time users (`setupWizardOverlay`)
- API provider configuration validation
- Microphone permission checking with fallback handling
- Setup completion stored in localStorage

### Model Management System
**Local Whisper Models**:
- State tracking: `not_downloaded` → `downloading` → `downloaded` → `failed`
- Progress tracking during downloads with IPC events
- Provider detection (CPU/Vulkan/Metal) with fallback reasons
- Interactive model selection with activation/deactivation

**Ollama Local LLM Integration**:
- Server status monitoring (`http://localhost:11434`)
- Model discovery and download management
- Blocklist for unsuitable models (`OLLAMA_MODEL_BLOCKLIST`)
- State persistence across app sessions

### Key Implementation Patterns
- **Tab System**: Active indicator animations with smooth transitions
- **Custom UI Components**: Styled dropdowns replacing native selects
- **Error Handling**: Multiple modal types (confirmation, error, translation)
- **Responsive Design**: Adaptive tab widths and mobile-friendly layouts
- **Web Preview Mode**: Feature detection for Electron vs web environment