<p align="center">
  <img src="Bolabol/for%20GITHUB/BOLABOL_LOGO_WHITE.png#gh-dark-mode-only" width="180" alt="BOLABOL logo">
  <img src="Bolabol/for%20GITHUB/BOLABOL_LOGO_BLACK.png#gh-light-mode-only" width="180" alt="BOLABOL logo">
</p>

<h1 align="center">BOLABOL</h1>

<p align="center">
  <strong>Speak. Polish. Translate. Anywhere on your Mac.</strong><br>
  <em>Your voice. Your words. Ready to use.</em>
</p>

<p align="center">
  Native AI voice input for Apple Silicon Macs.<br>
  Dictate into any app, keep the raw transcript, polish it your way, translate it, and insert the result without breaking your workflow.
</p>

<p align="center">
  <a href="https://github.com/Pavan-Gopa/BOLABOL/releases/latest/download/BOLABOL.dmg"><img src="https://img.shields.io/badge/Download-BOLABOL-111111?style=for-the-badge&logo=apple&logoColor=white" alt="Download BOLABOL"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-111111?style=flat-square&logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Apple%20Silicon-M1%20or%20later-111111?style=flat-square" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift / SwiftUI">
  <img src="https://img.shields.io/badge/local--first-privacy-2ea44f?style=flat-square" alt="Local-first">
</p>

<p align="center">
  <a href="#interactive-hud">HUD</a> ·
  <a href="#what-bolabol-does">Features</a> ·
  <a href="#local--cloud-ai">AI engines</a> ·
  <a href="#translation">Translation</a> ·
  <a href="#install">Install</a>
</p>

---

## Interactive HUD

<p align="center">
  <img src="Bolabol/for%20GITHUB/Hud-demo.gif" width="600" alt="BOLABOL interactive HUD demo">
</p>

### One HUD. No trips to Settings.

BOLABOL's floating HUD is more than a recording indicator — it is a compact control surface that stays available while you work in another app.

From the HUD you can:

- switch between **Raw** transcription and **Polishing** on the fly;
- choose polishing profiles **D / 1 / 2 / 3 / 4** without opening the main window;
- adjust the **Humor** level when the active polishing profile supports it;
- switch the active **AI provider and model** while dictating;
- choose **primary and additional languages** from the language popover;
- change the current workflow without stealing keyboard focus from the app you are typing into.

The idea is simple: configure the current voice workflow where you are using it, not several windows away in Settings.

---

## What BOLABOL does

| | In practice |
|---|---|
| **Dictate anywhere** | Press the global hotkey and speak while working in your browser, messenger, IDE, Notes, or another macOS app. |
| **Keep the Raw transcript** | Speech recognition and rewriting are separate stages. Your original transcription remains available even after polishing. |
| **Polish your way** | Light cleanup, stronger rewriting, custom prompt profiles, Markdown output, and adjustable humor. |
| **Translate quickly** | Use dedicated full and quick translation workflows, including post-ASR translation for transcription engines that do not translate speech natively. |
| **Stay local when you want** | Run transcription and text polishing on-device with Core ML / ANE and MLX models. |
| **Use cloud models when useful** | Connect your own API keys for stronger or specialized cloud models. |
| **Insert the result anywhere** | Copy to the clipboard or type directly into the active application with Accessibility permission. |
| **Build a reusable workspace** | Notes history, Raw / polished variants, glossary, prompt templates, translation tools, statistics, and in-app Help. |

### Core workflow

**Speak → Transcribe → Keep Raw → Polish → Translate if needed → Insert**

BOLABOL deliberately separates transcription from rewriting. Questions, commands, or instructions inside a transcript are treated as text to transform — not as commands for the polishing model to execute.

---

## Local + cloud AI

### Local speech recognition

| Engine | Runtime | Best fit |
|---|---|---|
| **WhisperKit** | Core ML | Strong multilingual transcription; Whisper models can also use native speech-to-English translation where supported. |
| **Parakeet TDT 0.6B v3** | FluidAudio · Core ML / ANE | Fast local transcription for supported languages. |
| **Canary Core ML** | Core ML / ANE | Local multilingual ASR. Canary 1B requires macOS 15+. |
| **GigaAM v3** | Core ML / ANE | Local Russian ASR; translation can be applied after transcription. |

Canary and GigaAM are used as **ASR engines**. When translation is requested, BOLABOL can translate the resulting text afterward through the selected local or cloud text model.

### Local text polishing

BOLABOL can run polishing locally through **MLX Swift**, including:

- Qwen 3.5 family;
- NVIDIA Nemotron-3 Nano;
- compatible custom/scanned MLX models from local folders or model caches.

### Optional cloud providers

Use your own API keys with:

**Google Gemini · OpenAI · Qwen · OpenRouter · custom OpenAI-compatible endpoints**

Cloud use is optional. Local transcription and local MLX polishing can stay entirely on your Mac.

---

## HUD in action

### System-wide dictation

<p align="center">
  <img src="Bolabol/for%20GITHUB/%D0%BA%D0%B0%D0%BA%20%D1%8D%D1%82%D0%BE%20%D0%B2%D1%8B%D0%B3%D0%BB%D1%8F%D0%B4%D0%B8%D1%82%20%D0%BD%D0%B0%20%D1%84%D0%BE%D0%BD%D0%B5%20%D0%B4%D1%80%D1%83%D0%B3%D0%BE%D0%B3%D0%BE%20%D0%BF%D1%80%D0%B8%D0%BB%D0%BE%D0%B6%D0%B5%D0%BD%D0%B8%D1%8F.png" width="760" alt="BOLABOL HUD over another application">
</p>

### Provider & model switching

<p align="center">
  <img src="Bolabol/for%20GITHUB/%D0%B2%D1%8B%D0%B1%D0%BE%D1%80%20%D0%BF%D1%80%D0%BE%D0%B2%D0%B0%D0%B9%D0%B4%D0%B5%D1%80%D0%B0%20%D0%B8%20%D0%BC%D0%BE%D0%B4%D0%B5%D0%BB%D0%B8%20%D1%87%D0%B5%D1%80%D0%B5%D0%B7%20HUD.png" width="560" alt="BOLABOL HUD provider and model switcher">
</p>

The HUD remains non-activating, so the keyboard focus stays in the application you are dictating into.

---

## Main workspace

<p align="center">
  <img src="Bolabol/for%20GITHUB/%D0%93%D0%BB%D0%B0%D0%B2%D0%BD%D1%8B%D0%B9%20%D1%8D%D0%BA%D1%80%D0%B0%D0%BD.png" width="900" alt="BOLABOL main workspace">
</p>

The main workspace keeps your notes and audio together with transcription and polishing controls. Each note can preserve **Raw** text alongside polished variants so the original speech-to-text result is never lost.

---

## Translation

BOLABOL includes both a full translation workspace and a lightweight quick-translation window.

| Full translation | Quick translation |
|:---:|:---:|
| <img src="Bolabol/for%20GITHUB/%D0%BE%D0%BA%D0%BD%D0%BE%20%D0%BF%D0%BE%D0%BB%D0%BD%D0%BE%D0%B3%D0%BE%20%D1%8D%D0%BA%D1%80%D0%B0%D0%BD%D0%B0%20%D0%BF%D0%B5%D1%80%D0%B5%D0%B2%D0%BE%D0%B4%D0%B0.png" width="440" alt="Full translation window"> | <img src="Bolabol/for%20GITHUB/%D0%BE%D0%BA%D0%BD%D0%BE%20%D0%B1%D1%8B%D1%81%D1%82%D1%80%D0%BE%D0%B3%D0%BE%20%D0%BF%D0%B5%D1%80%D0%B5%D0%B2%D0%BE%D0%B4%D0%B0%20.png" width="440" alt="Quick translation window"> |

Default global shortcuts:

| Shortcut | Action |
|---|---|
| **⌥S** | Start / stop dictation |
| **⌥1** | Full translation window |
| **⌥2** | Quick translation |
| **⌥~** | Settings |

---

## Privacy

BOLABOL is **local-first**, not local-only.

- Local ASR and local MLX models run on your Mac.
- Nothing is sent to a cloud provider unless you choose a cloud-backed feature.
- Cloud dictation sends audio to the selected cloud transcription service.
- Cloud polishing and translation send the relevant text and prompts to the provider you selected.
- API keys are supplied by the user; release builds do not include personal API keys.

---

## Install

### Requirements

- **Apple Silicon Mac** — M1 or later
- **macOS 14 Sonoma** or later
- **macOS 15+** for Canary 1B
- Microphone permission for recording
- Accessibility permission only when you want BOLABOL to type directly into other apps or work with selected text

### Download

1. Download **[BOLABOL.dmg](https://github.com/Pavan-Gopa/BOLABOL/releases/latest/download/BOLABOL.dmg)**.
2. Open the disk image.
3. Drag **BOLABOL** into **Applications**.
4. Launch the app and complete the first-run setup.

The distributed macOS build is Developer ID signed and notarized.

---

<details>
<summary><strong>Build from source</strong></summary>

The application source is in [`Bolabol/`](Bolabol/).

```bash
git clone https://github.com/Pavan-Gopa/BOLABOL.git
cd BOLABOL/Bolabol
./script/build_and_run.sh
```

Release tooling is available in [`Bolabol/script/`](Bolabol/script/).

</details>

<details>
<summary><strong>Project structure</strong></summary>

The native application is split into:

- `NativeBolabol` — SwiftUI/AppKit application layer;
- `NativeBolabolCore` — shared models, stores, and services;
- `NativeBolabolPolishWorker` — out-of-process local MLX polishing worker.

</details>

---

## License

BOLABOL is distributed under the **PolyForm Noncommercial License**. See [`Bolabol/LICENSE`](Bolabol/LICENSE) for the license text and [`Bolabol/COMMERCIAL.md`](Bolabol/COMMERCIAL.md) for commercial licensing information.

<sub>BOLABOL was previously released under the name <strong>SmartScribe</strong>. Current product documentation uses the BOLABOL name.</sub>
