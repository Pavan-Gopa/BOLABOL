# Bolabol 1.0.4

Native Apple Silicon release for local and cloud dictation, polishing,
translation, and hotkey insertion into other apps.

**Version:** 1.0.4 (build 1)

## Renaming

The project previously known as **Smart Sky / SmartScribe** is now **Bolabol**.
The app bundle, bundle identifier (`com.bolabol.app`), repository, and download
asset (`Bolabol.dmg`) carry the new name. Signed and notarized with Developer ID
Application: Stichting Kadamba Foundation (438UQRF7JV).

## Current product surface

- Local ASR includes WhisperKit, Parakeet/FluidAudio, Canary Core ML, and GigaAM Core ML.
- Canary and GigaAM are ASR-only and require an explicit source language. Canary 1B requires macOS 15+.
- Multilingual Whisper retains native source-to-English translation where supported.
- Other translation is post-ASR text processing through local MLX or the selected cloud provider.
- Google cloud dictation sends audio to Google. Cloud polishing and translation send text and prompts to the selected provider; local model paths remain local.
- Default hotkeys are Option+S for dictation, Option+1 for the full translation window, Option+2 for quick translation, and Option+~ for Settings.
- The visible provider order is Google, OpenAI, Qwen, OpenRouter, and Custom. Anthropic remains migration-compatible for stored settings but is hidden from the order.

## Release checks

- Microphone permission is required for recording.
- Accessibility is required for typing into another app and capturing selected text for translation.
- Release verification must confirm the Bolabol bundle identity, version 1.0.4,
  and a clean active staging directory before publication.

Historical 1.0.3 planning and spike evidence is retained in the versioned plan
and workflow records; this file describes the active 1.0.4 release surface.
