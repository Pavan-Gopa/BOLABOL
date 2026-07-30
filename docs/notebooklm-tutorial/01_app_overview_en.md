# 00. App Overview

## Video Narrative

SmartScribe Native is a macOS app for local dictation, transcription, text polishing, translation, and inserting the result into the active app. The key idea: transcription can run locally with WhisperKit/Core ML, while polishing can run either locally through MLX models or through API providers.

Open the tutorial with this simple architecture:

- The left side is the note history.
- The right side is the current note workspace.
- The bottom bar contains recording, audio import, translation, polishing, and settings.
- Settings contains models, API providers, hotkeys, HUD, prompts, glossary, statistics, and help.

## Key Points

- This is the native Swift/SwiftUI macOS app, not the Electron app.
- The app is designed around Apple Silicon and local models.
- Core workflow: choose a local transcription model, choose a polishing engine, record or import audio, review Raw text, then use Variant 1, Variant 2, or Markdown.

