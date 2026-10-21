# Bolabol 1.0.9

Native Apple Silicon release for local and cloud dictation, polishing,
translation, and signed Sparkle updates.

**Version:** 1.0.9

## What's new

- **No more crash when the microphone changes.** If the default input device
  changed or reconnected between recordings (for example a USB audio interface,
  dock or headset re-appearing under a new device ID), the next hotkey
  recording crashed Bolabol. Each recording now binds to the current input
  device and its real hardware format; an input that reports no usable format
  shows "no input device" instead of crashing.

Includes everything from 1.0.8: English output cleanup fix, reliable HUD
target language, cloud key failover, named custom providers, FIFO recording
archive, and the private session log.

## Existing product surface

- Local ASR includes WhisperKit, Parakeet/FluidAudio, Canary Core ML, and
  GigaAM Core ML.
- Canary and GigaAM are ASR-only and require an explicit source language.
- Multilingual Whisper retains native source-to-English translation where
  supported; other translation uses local MLX or the selected cloud provider.
- Google cloud dictation sends audio to Google; local model paths remain local.
- Default hotkeys are Option+S for dictation, Option+1 for the full translation
  window, Option+2 for quick translation, and Option+~ for Settings.
- The visible provider order is Google, OpenAI, Qwen, OpenRouter, then each
  custom provider by its name. Anthropic remains migration-compatible for
  stored settings but is hidden.

## Release checks

- Microphone permission is required for recording.
- Accessibility is required for typing into another app and capturing selected
  text for translation.
- The release bundle uses identity `com.bolabol.app` and is signed with
  Developer ID Application: Stichting Kadamba Foundation (438UQRF7JV).
- Updates require a signed Sparkle appcast and an immutable release URL; the
  release checklist remains the source of truth for packaging steps.
