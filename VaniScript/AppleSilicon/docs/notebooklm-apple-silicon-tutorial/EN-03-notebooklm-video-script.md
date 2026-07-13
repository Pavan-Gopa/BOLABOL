# NotebookLM Video Script - VaniScript Apple Silicon

Use this as the primary English script for NotebookLM video generation. The tone should be calm, practical, and tutorial-like. The audience is a new user who needs to understand the complete native Apple Silicon workflow.

## Video Title

VaniScript Apple Silicon: From Lecture Recording To Reviewed Transcript, Translation, And Shorts

## Target Length

10 to 14 minutes.

## Style Direction

Use a clean desktop tutorial style. Show one screen at a time. Do not make it feel like a marketing landing page. The video should feel like a guided product walkthrough for real users.

## Chapter 1 - What This App Is

Visual: `screenshots/01-upload-workspace.png`

Narration:

Welcome to VaniScript Apple Silicon. This is VaniScript running as a macOS app for Apple Silicon. The app is designed for long-form audio and video transcription, translation, careful review, and final export into documents or short vertical clips.

The main idea is simple: bring in a lecture, class, interview, or devotional recording, let VaniScript process it in chunks, review the source and translated text segment by segment, then export polished transcripts or create Shorts and Reels from the best moments.

On-screen emphasis:

- Native Apple Silicon app.
- Local-first workflow.
- Transcription, translation, review, export, clips.

## Chapter 2 - Start With Source Media

Visual: `screenshots/02-upload-workspace-clean.png`

Narration:

The first workspace is Upload. A beginner starts here. There are three ways to bring material into the app.

Upload Audio or Video is for files already on the Mac. This is the most reliable first path. Record Audio Source is for capturing a new recording directly. Import Link is for bringing in online media when the link resolver can access it.

For a first project, use a local audio or video file. This keeps the tutorial focused on the main VaniScript workflow instead of network or platform issues.

On-screen emphasis:

- Upload Audio / Video.
- Record Audio Source.
- Import Link.

## Chapter 3 - Configure Providers Before Processing

Visual: `screenshots/03-settings-api-usage.png`

Narration:

Before processing a serious project, open Settings. The API and Usage area shows cloud provider configuration, usage tracking, and logs. VaniScript can use local Apple Silicon models, cloud providers, or a hybrid setup depending on what the user configures.

This distinction matters. The native app remains the Apple Silicon version even when a cloud provider is configured. The app surface, project storage, media workflow, and editor are native macOS.

On-screen emphasis:

- Provider configuration.
- Logs and diagnostics.
- Cloud can supplement the VaniScript workflow when configured.

## Chapter 4 - Confirm Local Models

Visual: `screenshots/04-settings-models.png`

Narration:

The Models tab is where the Apple Silicon workflow becomes concrete. Local transcription uses WhisperKit and Core ML model assets. Local translation and text generation use MLX Swift models.

If a selected model is missing, processing should not begin blindly. VaniScript checks whether the selected provider is ready. A user can scan for local models, locate them, download where supported, or switch providers.

For the most native workflow, make sure a WhisperKit transcription model and an MLX text model are installed and selected.

On-screen emphasis:

- WhisperKit/Core ML for local transcription.
- MLX Swift for local text generation.
- Model readiness before processing.

## Chapter 5 - Prepare The Glossary

Visual: `screenshots/05-settings-glossary.png`

Narration:

The glossary is one of the most important parts of VaniScript. For devotional and philosophical material, names, Sanskrit terms, places, titles, and traditional vocabulary must remain consistent.

The glossary stores source terms, translations, variants, and categories. A user can add terms before processing and continue adding terms during review. This helps stabilize both transcription cleanup and translation.

On-screen emphasis:

- Terms and variants.
- Categories.
- Target-language consistency.

## Chapter 6 - Prompt Presets

Visual: `screenshots/06-settings-prompts.png`

Narration:

The Prompts tab shows that VaniScript is configurable. There are prompt presets for transcription, translation, editing, Shorts and Reels, and export. New users do not need to change these immediately, but advanced users can adapt the app to their vocabulary and content style.

For a devotional workflow, this is where the app can be tuned to preserve proper names, theological precision, and the expected tone of the final text.

On-screen emphasis:

- Prompt presets.
- Editing behavior.
- Shorts/Reels planning behavior.

## Chapter 7 - Sessions And Project Continuity

Visual: `screenshots/08-sessions-sidebar-real-project.png`

Narration:

Every serious job becomes a saved session. The Sessions sidebar shows the current project, source media, chunk list, progress, target language, and export action.

This is important for long recordings. The user can stop, reopen the project, jump to a chunk, export a bundle, or continue review later. VaniScript is not a single-pass transcript generator. It is a project-based review environment.

On-screen emphasis:

- Saved sessions.
- Chunks.
- Project export.
- Source media information.

## Chapter 8 - Review In Dual View

Visual: `screenshots/10-review-dual-mode.png`

Narration:

The Review workspace is where the real work happens. In Dual View, the original transcription appears on the left and the translated Russian text appears on the right. Both sides are organized into timed cues.

The user should listen to the current segment, compare the source and translation, correct any mistakes, and approve the segment only when it is ready. If needed, the user can retry transcription, regenerate timings, retry translation, add another translation language, or add glossary terms.

This is the heart of the app: careful segment-by-segment review instead of blindly trusting raw model output.

On-screen emphasis:

- Current segment audio.
- Source transcript.
- Translated Russian.
- Timed cues.
- Approve workflow.

## Chapter 9 - Export Reviewed Documents

Visual: `screenshots/12-export-workspace.png`

Narration:

After review, the session moves to Export. The top section exports reviewed transcript documents. The user can export original or translated material as plain text, subtitles, WebVTT, or Markdown.

The key point is that export uses the reviewed session. Every correction, glossary decision, and approved cue matters here.

On-screen emphasis:

- Original TXT, SRT, VTT, Markdown.
- Target TXT, SRT, VTT, Markdown.
- Export is based on reviewed chunks.

## Chapter 10 - Plan Shorts And Reels

Visual: `screenshots/12-export-workspace.png`

Narration:

The same Export workspace also plans Shorts and Reels. The user chooses how many clips to find, how long they should be, and whether planning should use the source language, target language, or both.

VaniScript then creates clip cards with titles, timing, summaries, categories, and actions. The user can inspect details, replace timing, delete a plan, or open a clip in the visual editor.

This turns a long lecture into a set of candidate short-form clips without leaving the native app.

On-screen emphasis:

- Find short moments.
- Choose clips.
- Edit Clip.
- Export selected videos.

## Chapter 11 - Visual Clip Editor

Visual: `screenshots/13-visual-editor.png`

Narration:

The visual clip editor is where a selected moment becomes a polished vertical video. In this NotebookLM-safe screenshot, the source video area is represented by a neutral graphic preview, while the interface still shows the vertical crop frame, caption overlay area, audio waveform, subtitle timeline, and inspector.

The right inspector controls style and frame behavior. The user can adjust font, size, outline, shadow, subtitle box, crop zoom, pan, and keyframes. Caption blocks can be split, merged, edited, and aligned.

When the user saves edits, these settings become part of the clip's render plan. The final video export uses those native settings.

On-screen emphasis:

- Vertical crop frame.
- Captions.
- Timeline and waveform.
- Inspector.
- Save edits.

## Chapter 12 - Final Export

Visual: `screenshots/12-export-workspace.png`

Narration:

Back in Export, the user chooses video format, resolution, and frame rate. The app can export selected clips as MP4 or MOV, using source-based settings or vertical output presets.

At the end of the workflow, one long source file has become reviewed text, translated subtitles, and optional vertical clips.

This is the complete VaniScript Apple Silicon path: ingest, configure, process, review, export, and edit clips, all inside the native macOS app.

On-screen emphasis:

- MP4 or MOV.
- Resolution.
- Frame rate.
- Export selected videos.

## Closing Narration

VaniScript Apple Silicon is best understood as a native review studio, not just a transcription button. Its strength is the complete path: source media, model configuration, glossary consistency, timed review, document export, Shorts/Reels planning, and visual clip editing.

For new users, the safest first workflow is: upload a local file, confirm models, process in chunks, review in Dual View, export transcripts, then create clips only after the text is approved.

End card text:

VaniScript Apple Silicon
Native transcription, translation, review, and clip export for macOS.
