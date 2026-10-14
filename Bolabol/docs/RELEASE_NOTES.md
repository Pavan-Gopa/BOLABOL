# Bolabol 1.0.8

Native Apple Silicon release for local and cloud dictation, polishing,
translation, and signed Sparkle updates.

**Version:** 1.0.8

## What's new

- **English output no longer gets Russian words.** Model output cleanup used
  to replace some English words (for example "really") with Russian ones and
  could delete ordinary sentences starting with "I will", "I can", "Let me" or
  "Okay", which made **E** fall back to the source language. Cleanup now only
  removes explicit model wrappers and never rewrites dictated text.
- **Reliable HUD target language.** The capsule language (for example **E**)
  is captured when recording starts and checked before insertion. If the result
  is still in the wrong language, Bolabol retries, then uses the translation
  provider, and only then inserts the source-language text with a distinct
  sound, an amber HUD flash and a "Not translated" badge on the note.
- **Cloud key failover.** Timeouts, network errors, rate limits and empty
  replies move to the next enabled API key immediately, for every cloud
  provider including OpenRouter, within bounded time limits.
- **Several named custom providers.** Add any number of OpenAI-compatible
  custom providers in Settings, each with its own name, base URL, keys, model
  and favourites. They appear by name in polishing, translation, the HUD
  provider switcher and note detail. An existing Custom provider, its keys and
  saved selections carry over unchanged.
- **Recording archive.** The configured FIFO limit keeps working: when a new
  recording exceeds it, the oldest one moves to Trash and new recordings keep
  being transcribed. A recording that is still being processed is never
  removed.
- A private rotating session log records recording lifecycle metadata (no
  transcript text, no API keys) to diagnose any future recording loss.

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
