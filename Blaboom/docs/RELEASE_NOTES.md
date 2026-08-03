# Blaboom 1.0.3

Native Apple Silicon release — local dictation, transcription, polishing, translation, and hotkey insertion into any app.

**Version:** 1.0.3 (build 1)  
**Codename track:** Bilingual Language Pairs & QA Consolidation

---

## What's new in 1.0.3

### Languages & Picker Ordering

- **Primary + Additional** language pair model (second language you often use — not a forced "always output in this target language" setting).
- Onboarding configures both languages upfront; Settings + Help fully updated; **15 UI locales**.
- Canonical language picker ordering: **English first → Europe (incl. ru/uk) → Asia & others**. Russian is no longer listed at #2.

### Honest Engine Status (Canary Spike Evaluation)

- **Canary 1B Core ML spike (ADR-012):** Evaluated and marked **NO-GO** for product integration in 1.0.3 due to precision loss, audio length scaling limits, and degenerate repetition loops in the current Core ML export (`alexwengg/canary-1b-v2-coreml`).
- Canary is **not shipped** in 1.0.3 pending an official or improved Core ML export.
- **WhisperKit (Large v3 / Turbo / Small)** and **Parakeet TDT 0.6B v3** remain the primary production local transcription engines with full auto language detection.

### Quality & QA Consolidation

- Comprehensive automated test suite and QA contract scripts (`script/qa/run_all.sh`).
- Verified zero Python runtime dependencies in application sources (100% native Swift/Core ML/Accelerate).

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

- **Local transcription:** Parakeet TDT 0.6B v3 · WhisperKit (Large v3 / Turbo / Multilingual / Small)
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
