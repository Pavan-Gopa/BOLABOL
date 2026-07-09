# VaniScript

VaniScript is the native Apple Silicon macOS application. It is not the
Electron application and it does not modify SmartScribe.

## Direction

1. Build only for Apple Silicon (`arm64`).
2. Use SwiftUI and AppKit for the desktop shell.
3. Use WhisperKit/Core ML for native transcription.
4. Use MLX Swift for local text polishing.
5. Keep Electron, Node, and browser runtimes out of the native app.

## Local Run

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
```
