# VaniScript Apple Silicon - Deep Dive

This document explains the native Apple Silicon VaniScript app from the inside out. It is written for NotebookLM so it can produce a detailed tutorial, onboarding sequence, or technical video script.

## 1. Product Boundary

VaniScript Apple Silicon is the macOS implementation of VaniScript for Apple Silicon.

The native app is defined by these boundaries:

- Swift Package Manager project in `VaniScript/AppleSilicon`.
- SwiftUI/AppKit desktop app.
- macOS 14+ target.
- Apple Silicon-oriented runtime.
- Native app bundle ID: `com.vaniscript.apple-silicon`.
- Local transcription through WhisperKit/Core ML model assets.
- Local text generation and translation through MLX Swift models.
- Native media operations through AVFoundation and related macOS APIs.
- Native visual rendering/export through AVFoundation and Metal-backed composition.

The app can use optional cloud providers such as Gemini or OpenAI when configured, while the main workflow remains the VaniScript Apple Silicon app.

## 2. Runtime Philosophy

The Apple Silicon version is designed as a local-first professional workflow.

Local-first means:

- project data is stored on the user's Mac;
- recordings and imported media are stored in app-controlled local directories;
- local models can be discovered and used directly on the Mac;
- glossary and settings are stored locally;
- exports are created locally;
- logs are written locally.

Hybrid capability means:

- cloud transcription or translation can be used when the user configures a provider key;
- cloud usage and provider settings are visible in Settings;
- the app checks provider readiness before processing.

The correct explanation is not "everything is always local." The accurate explanation is "the native Apple Silicon app supports a local-first model path and optional cloud providers, while remaining a native macOS application."

## 3. Main Workflow State

The user-facing workflow is controlled by a small set of screens:

- `upload`
- `config`
- `processing`
- `review`
- `export`
- `visualEditor`

The normal sequence is:

1. `upload`: choose file, recording, or link.
2. `config`: choose metadata, target language, providers, formats, chunking.
3. `processing`: run current chunk processing and show progress.
4. `review`: review source and translation.
5. `export`: export documents and plan Shorts/Reels.
6. `visualEditor`: edit a selected clip.

The app is not a collection of unrelated tools. It is a staged workflow where state moves forward but remains reopenable through saved sessions.

## 4. App Shell And Navigation

The app shell uses SwiftUI scenes with a shared `WorkflowStore`. The store owns the current workflow, session, settings, project list, processing pipeline, playback state, import/export state, visual editor draft, onboarding state, and status messages.

The main content router decides which workspace to show:

- Upload workspace for new source selection.
- Configuration workspace after a source is selected.
- Processing workspace during model work.
- Review workspace for editorial review.
- Export workspace for transcript and Shorts/Reels output.
- Visual editor workspace for clip-level editing.

The shell also provides top-level access to:

- help/onboarding;
- project sidebar;
- settings;
- new session;
- search and review tools where applicable.

## 5. Source Input Paths

The native app has three source paths.

### Local File Upload

The file picker imports existing audio/video media. The app inspects media metadata and stores session information such as duration, codecs, resolution, frame rate, bitrate, sample rate, channel count, and file path.

### Recording

The recording path can capture microphone or system audio depending on permissions and implementation path. Microphone capture uses macOS capture permissions. System audio capture relies on Screen Recording-style permission because macOS protects system audio capture.

Recordings are saved locally and can become the source file for a session.

### Link Import

The link importer resolves and downloads media. The app may use bundled media utilities for this path. The user should treat it as a convenience path and use local files for the most reliable first tutorial.

## 6. Configuration And Readiness

Configuration is where the user chooses:

- source metadata;
- target language;
- transcription provider;
- translation provider;
- output formats;
- chunk duration;
- fixed or smart slicing behavior.

Readiness checks are important. The app should not start processing if the selected provider cannot run. Examples:

- selected local WhisperKit model is missing;
- selected local MLX model is missing;
- cloud provider key is missing;
- provider is disabled or unavailable.

This is especially important for Apple Silicon onboarding because new users often assume the app will automatically download or select models. The better explanation is: the app can discover, download, or locate models depending on settings, but the chosen provider must be ready before processing.

## 7. Chunk Planning

Long media is split into chunks. Chunking makes the workflow practical.

Benefits:

- the user can review one segment at a time;
- failed segments can be retried without redoing the whole lecture;
- the app can save progress after each chunk;
- export can build from approved chunks;
- visual clip planning can reference timed text.

The app supports fixed chunking and smarter audio-aware slicing. Smart slicing can use audio energy and silence windows to find better cut points.

## 8. Transcription Pipeline

The native transcription path is built around WhisperKit/Core ML for local ASR when a local provider is selected.

The pipeline:

1. Ensures the selected transcription provider is ready.
2. Resolves the current chunk audio.
3. Creates or reuses chunk media if needed.
4. Runs transcription.
5. Requests timestamp and word/cue output where available.
6. Stores original text and timed cues.
7. Marks the chunk status.

The app caches local model runtime state so repeated processing does not reload everything unnecessarily.

## 9. Translation And Text Generation

The native local text path uses MLX Swift. Translation, polishing, transcript formatting, Shorts/Reels planning, and clip metadata work can use local MLX models when selected.

Cloud providers can also be used if configured.

The app keeps translation output structured:

- active target language;
- available translation languages;
- translation archive by language;
- translated text;
- translated cues;
- output formats.

This matters because a session may have more than one translation language. The review UI and export builder must know which language is active.

## 10. Glossary System

The glossary stabilizes terminology.

A glossary entry can include:

- source term;
- translation;
- variants;
- category;
- target-language adaptation.

The glossary is especially important for devotional and philosophical content, where terms can be transliterated many ways and where generic translation models may flatten proper nouns or doctrinal vocabulary.

Good onboarding should tell users: prepare your glossary before processing a long project, then add terms during review when new recurring variants appear.

## 11. Review Workspace

The Review workspace is the editorial center.

It provides:

- audio playback for the current segment;
- source-only, translated-only, and dual view;
- timed source cues;
- timed translated cues;
- cue-level highlighting;
- source text editing;
- translated text editing;
- glossary insertion;
- retry transcription;
- retry translation;
- regenerate timing;
- add translation language;
- approve and advance;
- final complete/export action.

The Review screen is designed for repeated careful work. A user can listen, compare, correct, approve, and continue.

## 12. Project Storage

The app stores local application data under the user's Application Support area. Important categories include:

- settings JSON;
- project list JSON;
- project asset folders;
- recordings;
- imported media;
- downloaded helper binaries for media workflows;
- logs.

The project list stores session state. A project session includes media metadata, chunks, cues, translations, approvals, Shorts/Reels plans, and visual editor information.

This is why the Sessions sidebar can reopen a project and jump directly to a chunk or export state.

## 13. Project Bundles

Project export/import uses VaniScript bundle formats. A project bundle preserves session data and associated assets so it can be moved, archived, or shared.

A `.vaniscript` bundle should be described as the VaniScript project exchange format for moving, archiving, or sharing reviewed work.

Bundle import normalizes session data after reading. This matters for compatibility because older bundle fields or alternate cue structures may need to be converted into the current session model.

## 14. Settings Deep Dive

### API & Usage

Controls cloud provider keys, usage state, provider configuration, custom providers, logs, and diagnostics.

### Models

Controls local model discovery, download/locate/delete actions, WhisperKit local ASR state, and MLX local text model state.

### Appearance

Controls theme, font scale, and app presentation preferences.

### Glossary

Controls source terms, translations, variants, categories, import/export, filtering, sorting, and target-language adaptation.

### Chunking

Controls chunk length and slicing behavior.

### Transcription

Controls ASR provider defaults and transcription-specific behavior.

### Prompts

Controls prompt presets for transcription cleanup, translation, editing, Shorts/Reels planning, and export.

## 15. Export Workspace

The Export workspace has two major outputs.

### Transcript Documents

The user can export source and target transcripts in text/subtitle/Markdown-oriented formats. These outputs are based on reviewed chunks and selected language state.

### Shorts/Reels

The user can:

- choose clip count;
- set min/max duration;
- generate ideas in source, target, or bilingual mode;
- inspect clip cards;
- replace timing;
- delete plans;
- open a clip in the visual editor;
- export ideas as JSON/TXT;
- export selected videos.

The export screen is the bridge between long-form editorial work and short-form publishing.

## 16. Visual Clip Editor

The Visual Clip Editor is not just a preview window. It is a native editing workspace.

It includes:

- source/target language toggle;
- sync behavior between source and target edits;
- vertical crop preview;
- dimmed outside frame;
- subtitle overlay;
- logo/overlay support;
- playback;
- cut range;
- looping;
- video/audio/subtitle timeline;
- waveform display;
- subtitle block list;
- caption text editor;
- word chips;
- split/merge/delete actions;
- text overlay tracks;
- background and frame behavior;
- style inspector;
- frame keyframes;
- layer controls;
- save/reset/undo/redo.

The editor writes visual settings back into the Shorts/Reels plan. Export uses those settings to build the final video.

## 17. Native Rendering

The video export path uses native macOS media APIs. Render plans describe:

- clip timing;
- crop/frame state;
- subtitles;
- text overlays;
- background;
- logo;
- audio tracks;
- intro/outro;
- output size;
- frame rate.

AVFoundation composes and exports the media. Metal-backed composition/rendering is used for visual overlay work.

The key onboarding phrase: visual edits are not just cosmetic UI state; they become part of the native render plan.

## 18. Onboarding System

The app contains a built-in guided tour with steps for upload, configuration, review, export, settings, and the visual editor. The tutorial video can mirror that structure while going deeper than the in-app tour.

A good video should use the same mental model:

1. Choose source.
2. Configure.
3. Review.
4. Export.
5. Edit clips.
6. Return to sessions any time.

## 19. What Makes This Apple Silicon-Specific

The Apple Silicon version should be presented through these points:

- native SwiftUI desktop UI;
- native app bundle;
- local Core ML/WhisperKit transcription path;
- local MLX Swift text-generation path;
- native AVFoundation media inspection, slicing, playback, and export;
- native recording/capture permissions;
- local project storage;
- Apple Silicon model management and runtime readiness.

The app may bundle or use media helper utilities for link and video workflows, while the product surface and workflow remain the VaniScript Apple Silicon macOS app.

## 20. Practical Teaching Summary

Teach VaniScript as a professional native workflow:

1. Import or record source media.
2. Confirm models and providers.
3. Configure metadata and target language.
4. Process in chunks.
5. Review source and translation with timed cues.
6. Use glossary and retry tools for consistency.
7. Approve all chunks.
8. Export transcripts.
9. Generate Shorts/Reels plans.
10. Edit clips visually.
11. Export final videos.
12. Reopen or share projects through Sessions and project bundles.
