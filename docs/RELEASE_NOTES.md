# SmartScribe 1.0.1

Private draft release for closed testing.

Native Apple Silicon app for local dictation, transcription, polishing, translation, and hotkey insertion.

## What’s new in 1.0.1

### HUD provider & model quick switcher

While the floating **HUD capsule** is visible (Option+S session) and you have **two or more** polishing providers configured:

- **Scroll** over the HUD capsule → opens the translucent **provider list** next to the HUD and steps through providers (live switch of the active polishing engine).
- **Left-click** a provider in the list → selects that provider.
- **Right-click** a provider in the list → opens a **context menu of models** for that provider (favorites + available models). Choosing a model updates the provider configuration and activates that provider.

The panel is non-activating: it does not steal keyboard focus from the app you are dictating into.

## Included product surface

- **Local transcription:** Parakeet TDT 0.6B v3 (FluidAudio / ANE) and WhisperKit Core ML models (Small → Large v3)
- **Local polishing:** MLX Swift models (Qwen 3.5 family, Nemotron-3 Nano); scan custom MLX trees from your disk / HF cache
- **Cloud optional:** Gemini, OpenAI, Anthropic, Qwen, OpenRouter, custom OpenAI-compatible endpoints
- **Hotkeys:** ⌥S dictate, ⇧⌥S dictate + auto-translate; floating red/green HUD; clipboard or type-into-active-app
- **Workspace:** notes sidebar, Raw / Variant 1 / Variant 2, Markdown, audio import, drag-and-drop
- **Glossary:** deterministic post-processing dictionary (JSON/CSV import-export)
- **UI languages:** EN, RU, ES, DE, FR, IT, PT, ZH, JA, KO, AR, HI + system
- **Onboarding, Help, Statistics, log export**

## Requirements

- Apple Silicon Mac (M1+)
- macOS 14+
- Accessibility permission for “Type into Active App”

## Install

**DMG:** open `SmartScribe.dmg` → drag **SmartScribe** to Applications.

**CLI:**

```bash
./install.sh SmartScribe.dmg
# or, with GitHub CLI access to this private repo:
./install.sh --from-github
```

Notarized Developer ID build. If Gatekeeper still prompts on first open: right-click → Open.

## Integrity

See `SHA256SUMS.txt` next to the DMG.

## Notes for testers

- This is a **draft / pre-release** for friends-only testing. It is not a public launch build.
- The app ships **without** API keys. Configure providers under Settings → API Providers.
- Local models download on demand from Settings → Local Models / Polishing.
- To try the new HUD switcher: enable at least two polishing providers, start Option+S, then scroll over the capsule; right-click a provider row for models.
