# Blaboom 1.0.3

Native Apple Silicon release — local dictation, transcription, polishing, translation, and hotkey insertion into any app.

**Version:** 1.0.3 (build 1)  
**Codename track:** Canary ASR/AST integration (development / testing)

---

## What's planned / in progress in 1.0.3

### Languages + Canary (in progress)

- **Primary + additional** languages (second language you often use — not “always output on that language”).
- Onboarding asks both; Settings + Help; **15 UI locales**.
- **Canary Core ML** ASR/AST — native only (Core ML + MLX polish; **no Python**):  
  [`alexwengg/canary-1b-v2-coreml`](https://huggingface.co/alexwengg/canary-1b-v2-coreml).
- Canary HUD: letter of **primary** (e.g. **R**), tap → **additional** (e.g. **E**); **A** inactive.
- Parakeet / Whisper keep **auto language** by default.
- Master plan: [`BLABOOM_1.0.3_IMPLEMENTATION_PLAN.md`](../BLABOOM_1.0.3_IMPLEMENTATION_PLAN.md).

### Status

- Version **1.0.3**. Early builds may be internal/test before full notarized release.

---

## Carried from 1.0.2

### Crash fix (Turkish / ja / ko / hi)

- Selecting Turkish (and Japanese, Korean, Hindi) no longer crashes on archive stats formatting.
- Positional `String(format:)` args for archive label/tooltip in every locale.

### Polishing reliability (anti-chat contract)

- Immutable editor system instruction; transcription fenced as data.
- Provider-aware generation settings (Gemini 3, o-series, Qwen, OpenRouter).

### From 1.0.1

- HUD provider & model quick switcher (scroll / right-click).
- Onboarding expandable HUD help; Local.AI + cloud without duplicate Qwen rows.
- Parakeet audio normalization; Google polish retries.

---

## Highlights (full product baseline)

- **Local transcription:** Parakeet TDT 0.6B v3 · WhisperKit · *(1.0.3) Canary Core ML — WIP*
- **Local polishing:** MLX Swift (Qwen 3.5 family, Nemotron-3 Nano)
- **Cloud optional:** Gemini, OpenAI, Anthropic, Qwen, OpenRouter, custom OpenAI-compatible
- **Hotkeys / HUD:** dictate, translate, provider switcher
- **Workspace:** notes, Raw / V1 / V2, glossary, translation, multi-language UI

---

## Requirements

- Apple Silicon Mac (M1 or later)
- macOS 14+
- Accessibility for “Type into Active App”

---

## Install (when a release DMG is published)

1. Download **`Blaboom.dmg`**.
2. Open → drag **Blaboom** into **Applications**.
3. Launch from Applications.
