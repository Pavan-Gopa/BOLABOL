# SmartScribe

SmartScribe is the macOS-only Swift app for transcription, polishing, translation,
and direct hotkey insertion into the active macOS application.

This app is intentionally separate from the existing Electron implementation at
the repository root. The first goal is a native shell with clean architecture:
SwiftUI scenes, AppKit bridges for desktop-only behavior, and protocol-based
audio, transcription, polishing, and model-management services.

## Targets

- Apple Silicon only, starting with M1.
- macOS 14 minimum for the initial scaffold.
- SwiftUI-first UI with AppKit bridges only where macOS requires them.

## Local Run

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
```

## Glossary

NativeSmartScribe includes a local deterministic glossary for correcting
recurring transcription terms after recognition. It stores entries in
`~/Library/Application Support/NativeSmartScribe/glossary.json`, applies exact
Unicode word-boundary replacements from variants to source/translation forms,
and does not bias WhisperKit, Apple Speech, or any LLM provider.

## Local Model Runtimes

- Whisper models use WhisperKit with Core ML.
- Parakeet TDT 0.6B v3 uses FluidAudio 0.15.5 with Core ML and Apple Neural Engine.
  It transcribes 25 European languages but does not translate speech to English.
- The HUD language control is disabled for Parakeet and English-only Whisper models.
- MLX polishing models use the GPU through MLX Swift.
- Bonsai 27B uses the official `prism-ml/Bonsai-27B-mlx-1bit` model and Prism's
  1-bit MLX Swift kernels. No llama.cpp or GGUF runtime is used for polishing.
