# NativeSmartScribe

NativeSmartScribe is the macOS-only Swift rewrite of SmartScribe.

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
