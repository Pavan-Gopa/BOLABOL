# SmartScribe 1.0.1

**Status:** private draft / pre-release for closed testing (not a public launch).

Native Apple Silicon app for local dictation, transcription, polishing, translation, and hotkey insertion.

---

## What's new in 1.0.1

### 1. HUD provider & model quick switcher (main feature)

While the floating **HUD capsule** is visible (Option+S session) and you have **two or more polishing providers** configured:

| Gesture | Behavior |
|---------|----------|
| **Scroll** over the HUD capsule | Opens a translucent **provider list** next to the HUD and steps through providers. The active polishing engine switches **live**. |
| **Left-click** a provider in the list | Selects that polishing provider. |
| **Right-click** a provider in the list | Opens a **model context menu** for that provider (favorites + available models). Choosing a model updates the provider configuration and activates that provider. |

**Details**

- Panel is **non-activating** — keyboard focus stays in the app you are dictating into.  
- Requires at least **two** available polishing providers (cloud and/or local engines exposed as polishers).  
- Documented in in-app Help / onboarding (expandable HUD section).

### 2. Onboarding & product clarity

- Full HUD explanation moved into an **expandable onboarding panel** (less clutter on first launch).  
- Model ordering cleaned up so recommended options are easier to find.  
- Repository docs and release packaging no longer advertise removed / incorrect models (e.g. Bonsai).

### 3. Packaging

- Marketing version **1.0.1**, build **2**.  
- Developer ID signed + **Apple notarized** DMG (`SmartScribe.dmg`).  
- Draft GitHub release ships the **DMG only** (no separate install script / checksum assets).

### 4. Stability carried from the 1.0.0 line

- Parakeet audio input normalization.  
- Retries when Google polishing requests stall.  
- Broad code-review hardening pass.

---

## Full product surface (unchanged high-level set)

- **Local transcription:** Parakeet TDT 0.6B v3 (FluidAudio / ANE) and WhisperKit Core ML (Small → Large v3)  
- **Local polishing:** MLX Swift (Qwen 3.5 family, Nemotron-3 Nano); scan custom MLX trees  
- **Cloud optional:** Gemini, OpenAI, Anthropic, Qwen, OpenRouter, custom OpenAI-compatible  
- **Hotkeys:** ⌥S dictate, ⇧⌥S dictate + auto-translate; floating red/green HUD; clipboard or type-into-active-app  
- **Workspace:** notes sidebar, Raw / Variant 1 / Variant 2, Markdown, audio import, drag-and-drop  
- **Glossary:** deterministic post-processing dictionary (JSON/CSV import-export)  
- **UI languages:** EN, RU, ES, DE, FR, IT, PT, ZH, JA, KO, AR, HI + system  
- **Onboarding, Help, Statistics, log export**

---

## Requirements

- Apple Silicon Mac (M1+)  
- macOS 14+  
- Accessibility permission for “Type into Active App”  

---

## Install

1. Download **`SmartScribe.dmg`**.  
2. Open → drag **SmartScribe** into **Applications**.  
3. Launch from Applications. If Gatekeeper prompts: right-click → Open.  

The app ships **without** API keys. Configure providers under Settings → API Providers. Local models download on demand.

### How to try the new HUD switcher

1. Configure **at least two** polishing providers (e.g. Local MLX + Google).  
2. Press **Option+S** over any app so the HUD appears.  
3. **Scroll** over the capsule → provider list.  
4. **Right-click** a provider → model menu.  

---

## Notes for testers

- This is a **draft / pre-release** for friends-only testing.  
- Repo remains **private**.  
- Please report: HUD switcher focus issues, wrong model applied, crash after provider switch, Gatekeeper/notarization problems on clean Macs.  
