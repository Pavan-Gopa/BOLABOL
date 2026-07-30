# SmartScribe 1.0.0

Native Apple Silicon release of SmartScribe — local dictation, transcription, polishing, translation, and hotkey insertion.

## Highlights

- **Local transcription:** Parakeet TDT 0.6B v3 (FluidAudio / ANE) and WhisperKit Core ML models (Small → Large v3)
- **Local polishing:** MLX Swift models (Qwen 3.5 family, Nemotron-3 Nano); scan custom MLX trees (including Prism 1-bit Bonsai)
- **Cloud optional:** Gemini, OpenAI, Anthropic, Qwen, OpenRouter, custom OpenAI-compatible
- **Hotkeys:** ⌥S dictate, ⇧⌥S dictate + auto-translate; floating red/green HUD; clipboard or type-into-active-app
- **Workspace:** notes sidebar, Raw / Variant 1 / Variant 2, Markdown, audio import, drag-and-drop
- **Glossary:** deterministic post-processing dictionary (JSON/CSV import-export)
- **UI languages:** EN, RU, ES, DE, FR, IT, PT, ZH, JA, KO, AR, HI + system
- **Onboarding, Help, Statistics, log export**

## Fixes in this release line

- Code review hardening (force-unwrap / safety pass: 5549 → 141 open items)
- Google polishing stall retries
- Parakeet audio input normalization
- MLX Bonsai / Parakeet runtime repairs

## Requirements

- Apple Silicon Mac (M1+)
- macOS 14+
- Accessibility permission for “Type into Active App”

## Install

**DMG:** open `SmartScribe.dmg` → drag to Applications.

**CLI:**

```bash
./install.sh SmartScribe.dmg
# or, with GitHub CLI access to this private repo:
./install.sh --from-github
```

## Integrity

See `SHA256SUMS.txt` next to the DMG.
