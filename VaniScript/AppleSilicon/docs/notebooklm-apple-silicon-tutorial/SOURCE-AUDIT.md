# Source Audit - VaniScript Apple Silicon

This audit summarizes the native Apple Silicon code paths inspected for this NotebookLM package. It is included so the tutorial can be grounded in the actual app structure, not only in screenshots.

## Product Scope

Inspected project:

- `VaniScript/AppleSilicon`

## Build And Package Definition

Inspected:

- `Package.swift`
- `README.md`
- `docs/universal-port-map.md`

Findings:

- The native app is a Swift Package Manager macOS app.
- The package contains executable target `VaniScript` and library target `VaniScriptCore`.
- The app targets macOS and is positioned as the native Apple Silicon implementation.
- Dependencies include MLX Swift language-model tooling, WhisperKit-related transcription tooling, Hugging Face utilities, and Swift Transformers-related support.
- The package defines the Apple Silicon macOS app identity and runtime direction.

## App Entry And Shell

Inspected:

- `Sources/VaniScript/VaniScriptApp.swift`
- `Sources/VaniScript/Views/ContentView.swift`
- `Sources/VaniScript/Views/DetailRouterView.swift`
- `Sources/VaniScript/Models/WorkspacePane.swift`

Findings:

- The app creates a shared `WorkflowStore`.
- `ContentView` owns the high-level app shell, background, top actions, project sidebar overlay, onboarding overlay, and routing.
- `DetailRouterView` maps workflow state to `Upload`, `Config`, `Processing`, `Review`, `Export`, and `Visual Editor`.

## Workflow And State

Inspected:

- `Sources/VaniScript/Stores/WorkflowStore.swift`
- `Sources/VaniScriptCore/WorkflowState.swift`
- `Sources/VaniScriptCore/UniversalWorkflow.swift`
- `Sources/VaniScriptCore/SessionModels.swift`
- `Sources/VaniScriptCore/ProjectArchive.swift`

Findings:

- Workflow state drives the entire user journey.
- Sessions store source media, metadata, chunks, translations, cues, approvals, Shorts/Reels plans, and visual editor data.
- The app saves project state and can reopen sessions through the sidebar.
- Review navigation avoids unnecessary glossary reprocessing when opening existing completed chunks.

## Upload, Import, And Recording

Inspected:

- `Sources/VaniScript/Views/UploadWorkspaceView.swift`
- `Sources/VaniScript/Services/DirectMediaImporter.swift`
- `Sources/VaniScript/Services/MediaDownloader.swift`
- `Sources/VaniScript/Services/SystemAudioRecorder.swift`
- `Sources/VaniScript/Services/MicrophoneAudioRecorder.swift`
- `Sources/VaniScript/Services/SourceMediaInspector.swift`
- `Sources/VaniScriptCore/MediaSource.swift`

Findings:

- Users can upload local media, record audio, or import from a link.
- Local media is inspected through native media APIs.
- Recording paths depend on macOS microphone and screen-recording permissions.
- Link import is a media workflow inside the VaniScript app.

## Configuration And Provider Readiness

Inspected:

- `Sources/VaniScript/Views/ConfigWorkspaceView.swift`
- `Sources/VaniScriptCore/AppSettings.swift`
- `Sources/VaniScriptCore/ProviderRegistry.swift`
- `Sources/VaniScriptCore/NativeProcessingReadiness.swift`
- `Sources/VaniScriptCore/NativeModelCatalog.swift`

Findings:

- Configuration includes metadata, target language, transcription provider, translation provider, formats, and chunking.
- Provider readiness checks block processing when the selected model/provider is not usable.
- Local transcription and translation are modeled separately.
- The model catalog tracks local WhisperKit/Core ML and MLX model availability.

## Processing Pipeline

Inspected:

- `Sources/VaniScript/Services/NativeProcessingPipeline.swift`
- `Sources/VaniScript/Services/MLXTextGenerationEngine.swift`
- `Sources/VaniScript/Services/CloudTextTranslationEngine.swift`
- `Sources/VaniScript/Services/AudioChunkExporter.swift`
- `Sources/VaniScriptCore/ChunkPlanner.swift`
- `Sources/VaniScriptCore/SmartSlicePlanner.swift`

Findings:

- Current chunk processing runs through provider readiness, chunk media resolution, local/cloud transcription, cue construction, translation, and session update.
- WhisperKit is used for local ASR when selected.
- MLX Swift is used for local text generation and translation when selected.
- Audio is sliced into chunk media for segment review.
- Chunk planning supports fixed and smarter audio-aware slicing.

## Review Workspace

Inspected:

- `Sources/VaniScript/Views/ReviewWorkspaceView.swift`
- `Sources/VaniScript/Views/KaraokeCueTextView.swift`
- `Sources/VaniScriptCore/TextRevision.swift`
- `Sources/VaniScriptCore/TranscriptExportBuilder.swift`

Findings:

- Review supports source, translated, and dual view.
- The UI exposes audio playback, timed cues, editing, retry transcription, retry translation, regenerate timings, add translation, previous segment, and approve/complete actions.
- The review workflow is built for human correction before export.

## Settings And Glossary

Inspected:

- `Sources/VaniScript/Views/SettingsView.swift`
- `Sources/VaniScriptCore/StarterGlossary.swift`
- `Sources/VaniScriptCore/DefaultPrompts.swift`
- `Sources/VaniScriptCore/AppSettings.swift`

Findings:

- Settings include API & Usage, Models, Appearance, Glossary, Chunking, Transcription, and Prompts.
- The glossary stores terms, translations, variants, categories, and target-language adaptation.
- Prompt presets cover transcription, translation, editing, Shorts/Reels, and export.

## Export And Shorts/Reels

Inspected:

- `Sources/VaniScript/Views/ExportWorkspaceView.swift`
- `Sources/VaniScriptCore/ShortsPlanner.swift`
- `Sources/VaniScriptCore/ShortsTranscriptExtractor.swift`
- `Sources/VaniScriptCore/ShortsIdeasExporter.swift`
- `Sources/VaniScriptCore/ShortsExportSelection.swift`

Findings:

- Export supports reviewed transcript documents and Shorts/Reels workflows.
- Shorts/Reels planning supports source, target, and bilingual language modes.
- Clip cards can be selected, detailed, replaced, deleted, edited, or exported.

## Visual Editor And Native Rendering

Inspected:

- `Sources/VaniScript/Views/VisualClipEditorView.swift`
- `Sources/VaniScript/Views/NativeMetalClipPreviewView.swift`
- `Sources/VaniScriptCore/ShortsVisualEditorState.swift`
- `Sources/VaniScriptCore/ShortsNativeRenderPlan.swift`
- `Sources/VaniScript/Services/NativeShortsVideoRenderer.swift`
- `Sources/VaniScript/Services/NativeMetalVideoCompositor.swift`

Findings:

- The visual editor includes crop framing, subtitle blocks, waveform/timeline, caption editing, style inspector, frame animation, layer controls, sync, save/reset, and source/target modes.
- Visual edits are saved into clip state and converted into native render plans.
- Final video export uses AVFoundation and Metal-backed rendering paths.

## Project Import/Export

Inspected:

- `Sources/VaniScriptCore/ProjectBundleExporter.swift`
- `Sources/VaniScriptCore/ProjectBundleImporter.swift`
- `Sources/VaniScriptCore/ProjectLibraryBundle.swift`

Findings:

- `.vaniscript` is the native VaniScript project exchange format.
- Project bundles preserve session state and associated assets.
- Import normalizes older or alternate session structures into the current model.

## Onboarding

Inspected:

- `Sources/VaniScript/Models/OnboardingTourState.swift`

Findings:

- The app contains built-in onboarding steps in English and Russian.
- The documented video path mirrors and expands the built-in tour: upload, config, review, export, settings, and visual editor.

## Russian Summary / Русское резюме

Разобран `VaniScript/AppleSilicon`: app shell, workflow state, upload/record/import, configuration, provider readiness, local model management, processing pipeline, review workspace, settings/glossary/prompts, export, Shorts/Reels, visual editor, native rendering and project bundle import/export.

Главный вывод: Apple Silicon-версия VaniScript - это нативный macOS workflow для source media -> configuration -> chunk processing -> human review -> transcript export -> Shorts/Reels planning -> visual clip editing -> native video export.
