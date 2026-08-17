# Bolabol 1.0.5

Native Apple Silicon release for local and cloud dictation, polishing,
translation, and hotkey insertion into other apps.

**Version:** 1.0.5

## What's new

The project previously known as **SmartScribe** is now **Bolabol**.
The app bundle, bundle identifier (`com.bolabol.app`), repository, and download
asset (`BOLABOL.dmg`) carry the new name. Signed and notarized with Developer ID
Application: Stichting Kadamba Foundation (438UQRF7JV).

- Signed in-app updates through Sparkle 2.9.4 and the stable GitHub appcast.
- A visible update action in the main window title bar with safe retry and
  relaunch handling.
- Update installation is gated while recording or other app work is active;
  cancellation and failure keep the current installation intact.
- Native click-to-record hotkey controls replace manual shortcut text fields.
- Right Option and Right Command primary hotkey taps are captured directly,
  with keyboard-layout-independent modifier-plus-key recording.
- Recording, rejection, help, and accessibility states remain localized across
  all supported UI languages.

## Existing product surface

- Local ASR includes WhisperKit, Parakeet/FluidAudio, Canary Core ML, and
  GigaAM Core ML.
- Canary and GigaAM are ASR-only and require an explicit source language.
- Multilingual Whisper retains native source-to-English translation where
  supported; other translation uses local MLX or the selected cloud provider.
- Google cloud dictation sends audio to Google; local model paths remain local.
- Default hotkeys are Option+S for dictation, Option+1 for the full translation
  window, Option+2 for quick translation, and Option+~ for Settings.
- The visible provider order is Google, OpenAI, Qwen, OpenRouter, and Custom.
  Anthropic remains migration-compatible for stored settings but is hidden.

## Release checks

- Microphone permission is required for recording.
- Accessibility is required for typing into another app and capturing selected
  text for translation.
- The release bundle uses identity `com.bolabol.app` and is signed with
  Developer ID Application: Stichting Kadamba Foundation (438UQRF7JV).
- Updates require a signed Sparkle appcast and a notarized DMG; no unsigned
  GitHub asset or mutable download URL is trusted.
