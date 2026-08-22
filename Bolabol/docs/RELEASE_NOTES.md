# Bolabol 1.0.6

Native Apple Silicon release for local and cloud dictation, polishing,
translation, and signed Sparkle updates.

**Version:** 1.0.6

## What's new

- Compatible local MLX models can be discovered from the shared model pool by
  the app and companion tooling. Model licenses remain separate from Bolabol's
  license; follow each model package's terms before use or redistribution.
- Tech-processing visuals use the accepted deterministic electric particle
  swarm, with the vertical HUD layout and centered glyph rendering.
- Audio archive cleanup fails safe when note metadata cannot load; orphaned
  microphone recordings move to Trash, and files newer than the 15-minute
  minimum age are left alone.
- The reviewed security surface keeps hard-coded network endpoints on an HTTPS
  allowlist and rejects unreviewed hosts or plaintext URLs.
- Sparkle delivery requires a signed appcast and immutable release asset URLs
  before an update can be offered.

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
- Updates require a signed Sparkle appcast and an immutable release URL; the
  release checklist remains the source of truth for packaging steps.
