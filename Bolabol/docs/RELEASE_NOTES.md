# Bolabol 1.0.7

Native Apple Silicon release for local and cloud dictation, polishing,
translation, and signed Sparkle updates.

**Version:** 1.0.7

## What's new

- HUD target language (the capsule letter, for example **E** for English) is
  now a hard contract for polishing. With Parakeet or another ASR-only engine,
  Variant 1/2 inserts text in the selected target language instead of leaving
  the spoken-language transcript.
- The polishing prompt keeps the translation instruction in the system task
  and rewrites conflicting "never translate" template rules, so cloud and
  local models cannot ignore the HUD target.
- If the first polish pass still returns the source script (for example
  Russian when the HUD shows **E**), Bolabol retries once with a stricter
  translation instruction.

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
