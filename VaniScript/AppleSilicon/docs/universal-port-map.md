# VaniScript Universal -> Apple Silicon Port Map

This app ports `../VaniScript` into a native Apple Silicon macOS application.
`../VaniScript` is reference-only. Do not edit it from this project.
`../NativeSmartScribe` is reference-only. Do not edit it from this project.

## Product Boundary

- Product name: `VaniScript`
- Bundle id: `com.vaniscript.apple-silicon`
- Runtime: macOS native, Apple Silicon only
- Shell: SwiftUI and AppKit
- Transcription: WhisperKit/Core ML only
- Local LLM tasks: MLX Swift only. This covers translation, literary polish,
  audio-aware review, document formatting, and Shorts/Reels planning.
- No Python, Node, Electron, Chromium, ffmpeg-static, yt-dlp, llama.cpp, or
  other external executable runtime in the native app bundle

## Universal Workflow Parity

The native app follows the Universal workflow state order:

1. `upload`: audio/video file import, system/microphone recording, link import, project library
2. `config`: metadata, source/target language, transcription provider, translation provider, chunking
3. `processing`: media conversion, smart slicing, chunk queue, transcription, translation
4. `review`: audio playback, source/translated/dual panes, karaoke timestamps, glossary actions, AI review
5. `export`: TXT/SRT/VTT/Markdown document export and Shorts/Reels planning/rendering

## Module Mapping

| Universal module | Native target | Status |
| --- | --- | --- |
| `src/types.ts` | `Sources/VaniScriptCore/*` | started |
| `src/services/storage.ts` | `VaniScriptCore` settings/project stores | ported |
| `src/services/transcription.ts` | WhisperKit transcription service | ported |
| `src/services/chunk-queue.ts` | native chunk queue service | ported |
| `src/services/local-translation.ts` | MLX Swift translation service | ported |
| `src/services/cloud-translation.ts` | native URLSession cloud providers | planned |
| `src/services/literary-polish.ts` | MLX polishing service | ported |
| `src/services/audio-review.ts` | audio-aware review service | planned |
| `src/services/document-export.ts` | native deterministic + MLX document exporter | ported |
| `src/lib/prompt-presets.ts` | prompt preset store | planned |
| `src/lib/starter-glossary.ts` | starter glossary catalog | ported |
| `src/lib/shorts-reels.ts` | shorts planning models + MLX planner | started |
| `src/render-engine/*` | AVFoundation/Metal render pipeline | planned |
| `src/components/*` | SwiftUI views | started |
| `electron/main.js` IPC | AppKit/AVFoundation/ScreenCaptureKit/file services | started |

## First Implementation Slices

1. Mirror Universal data contracts and default settings in `VaniScriptCore`.
2. Replace the starter shell with Universal workflow navigation.
3. Port storage and project autosave.
4. Port file import, recording, and link import.
5. Port chunk queue and WhisperKit transcription.
6. Port MLX translation/polishing and prompt presets.
7. Port review UX, glossary actions, audio playback, and karaoke navigation.
8. Port document export.
9. Port Shorts/Reels planning and native render pipeline.
