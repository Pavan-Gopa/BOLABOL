<p align="center">
  <img src="for GITHUB/BOLABOL_LOGO_WHITE.png#gh-dark-mode-only" width="160" alt="Bolabol logo">
  <img src="for GITHUB/BOLABOL_LOGO_BLACK.png#gh-light-mode-only" width="160" alt="Bolabol logo">
</p>

<h1 align="center">Bolabol</h1>

<p align="center">
  <strong>Your voice. Your words. Ready to use.</strong>
</p>

<p align="center">
  AI-powered voice input for your Mac.<br>
  Dictate, rewrite, translate, format, and insert polished text into any app — with local and cloud AI models.
</p>

<p align="center">
  <a href="https://github.com/Pavan-Gopa/BOLABOL/releases/latest"><img src="https://img.shields.io/github/v/release/Pavan-Gopa/BOLABOL?style=flat-square&label=release&color=2ea44f" alt="Release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B%20Apple%20Silicon-111111?style=flat-square" alt="macOS 14+ Apple Silicon">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?style=flat-square" alt="Swift / SwiftUI">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-PolyForm%20Noncommercial-6f42c1?style=flat-square" alt="PolyForm Noncommercial"></a>
</p>

---

## Overview

**Bolabol** is a native Apple Silicon macOS application designed for effortless voice dictation, translation, and text polishing.

<p align="center">
  <img src="for GITHUB/Hud-demo.gif" width="600" alt="Bolabol HUD Demo">
</p>

### Key Features

- **Local & Offline Speech Recognition (ASR)**: Native support for WhisperKit, Parakeet/FluidAudio, Canary Core ML, and GigaAM Core ML on Apple Neural Engine.
- **Two-Stage Pipeline**: Keeps your exact raw transcript while generating polished variants.
- **Polishing & Translation**: Polish and translate dictated text into any target language using cloud LLMs (GigaChat, Gemini, OpenAI, OpenRouter) or local MLX models.
- **Floating HUD Overlay**: Dictate over any app using global hotkeys (`Option+S` for dictation, `Option+1` / `Option+2` for polishing and translation).
- **System-Wide Insertion**: Insert polished text directly into active text fields across macOS.
- **Privacy First**: Choose local models to keep audio and text completely on-device.

---

## Screenshots

### Main Interface
![Main Screen](<for GITHUB/Главный экран.png>)

### Floating HUD & Recording
| HUD over applications | Recording state | Processing state |
|:---:|:---:|:---:|
| ![HUD background](<for GITHUB/как это выглядит на фоне другого приложения.png>) | ![HUD recording](<for GITHUB/один из тех скинов HUD -запись.png>) | ![HUD processing](<for GITHUB/Ожидание - processing.png>) |

### Provider & Model Quick Switcher
![Provider switcher](<for GITHUB/выбор провайдера и модели через HUD.png>)

### Translation Windows
| Full Translation Window | Quick Translation |
|:---:|:---:|
| ![Full translation](<for GITHUB/окно полного экрана перевода.png>) | ![Quick translation](<for GITHUB/окно быстрого перевода .png>) |

---

## Installation

1. Download **`BOLABOL.dmg`** from the [Latest Release](https://github.com/Pavan-Gopa/BOLABOL/releases/latest).
2. Open the disk image and drag **Bolabol.app** to your **Applications** folder.
3. Launch Bolabol from Applications.

---

## Requirements

- **Mac with Apple Silicon** (M1/M2/M3/M4)
- **macOS 14.0** (Sonoma) or later

---

## Building from Source

```bash
git clone https://github.com/Pavan-Gopa/BOLABOL.git
cd BOLABOL
./script/build_and_run.sh
```

To build a notarized release DMG:
```bash
./script/build_release_dmg.sh --notarize
```

---

## License

Distributed under the PolyForm Noncommercial License. See [LICENSE](LICENSE) for details.
