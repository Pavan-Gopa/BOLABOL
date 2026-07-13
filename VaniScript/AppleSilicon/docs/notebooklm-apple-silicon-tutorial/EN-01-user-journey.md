# VaniScript Apple Silicon - Complete User Journey

This guide describes the native Apple Silicon VaniScript workflow as a beginner should experience it. It starts from first launch and ends with document export and vertical video editing.

VaniScript Apple Silicon is the VaniScript macOS app running on Apple Silicon. It is built with SwiftUI/AppKit, native media APIs, WhisperKit/Core ML for local transcription, MLX Swift for local language work, and AVFoundation/Metal for audio/video workflows.

## 1. First Launch: Understand The Starting Screen

![First launch with onboarding overlay](screenshots/01-upload-workspace.png)

The first screen is the Upload workspace. A new user sees the VaniScript identity, the main entry points, and an onboarding overlay that explains what the first step is. The app is designed around a sequential workflow:

1. Add a source.
2. Configure metadata, language, models, and chunking.
3. Process the media into timed segments.
4. Review source and translation.
5. Export documents or clips.

The key beginner message is simple: the user does not start in a file manager or a timeline. They start by choosing where the source material comes from.

## 2. Choose A Source

![Clean Upload workspace](screenshots/02-upload-workspace-clean.png)

The Upload workspace has three main choices.

`Upload Audio / Video` imports an existing local file. This is the normal path for lectures, classes, interviews, recordings, MP3, WAV, M4A, MP4, MOV, and similar media.

`Record Audio Source` records a new source directly. The native app supports microphone-style recording and system-audio capture paths, depending on macOS permissions and selected input. System audio capture relies on ScreenCaptureKit-style permissions, so users may need to grant Screen Recording access in macOS settings.

`Import Link` downloads or resolves media from a direct media link. The app can use bundled media utilities for link workflows while keeping the user's project inside the same VaniScript workspace.

Beginner advice: for a first tutorial, use a local video or audio file. It gives the most predictable result and avoids link-permission or site-resolution issues.

## 3. Configure The App Before Heavy Processing

![API and usage settings](screenshots/03-settings-api-usage.png)

Before a serious project, the user should open Settings and confirm how transcription and translation will run.

The API & Usage tab covers cloud provider configuration, usage display, provider keys, and logs. This matters because VaniScript can run with local Apple Silicon models, cloud models, or a hybrid setup. A user who wants a fully local workflow should make sure local models are installed and selected. A user who wants Gemini or OpenAI should add the relevant key and confirm the provider appears as available.

The Settings area also gives access to app logs. This is important for troubleshooting model discovery, failed downloads, link imports, and processing errors.

## 4. Confirm Local Models

![Model settings](screenshots/04-settings-models.png)

The Models tab is central to the Apple Silicon version.

For transcription, the app expects local WhisperKit/Core ML models when using the local path. These models must be present on disk and discoverable. The app can scan common local model locations and can track installed, missing, downloading, and verified states.

For translation and text generation, the Apple Silicon path uses MLX Swift models. The settings model catalog includes local MLX options and can scan local model directories. The app does not automatically run a random cloud model if the selected local provider is unavailable; readiness checks prevent processing until the configured provider is usable.

Beginner advice: if the user wants the most Apple Silicon-native experience, install or locate a WhisperKit transcription model and an MLX text model before starting the session.

## 5. Prepare The Glossary

![Glossary settings](screenshots/05-settings-glossary.png)

The glossary is a major part of VaniScript's value. It keeps philosophical names, Sanskrit terms, place names, speaker names, and recurring vocabulary consistent.

The Glossary tab lets the user add terms, variants, target-language equivalents, and categories. In a devotional context, this is where terms such as holy names, Sanskrit titles, places, and lineage-specific vocabulary should be normalized.

The glossary is not just a list for display. It affects how source text and translated text are corrected and normalized through the workflow. In practice, this means the user should prepare important terms before processing a long lecture.

## 6. Review Prompt Presets

![Prompt settings](screenshots/06-settings-prompts.png)

The Prompts tab exposes the app's prompt presets for stages such as transcription cleanup, translation, editing, Shorts/Reels planning, and export formatting.

A beginner does not need to edit prompts on day one. But for an onboarding video, this screen is important because it shows that VaniScript is not a black box. Advanced users can adapt behavior for their tradition, vocabulary, formatting preferences, and content style.

## 7. Work With Sessions

![Sessions sidebar with a real project](screenshots/08-sessions-sidebar-real-project.png)

Sessions are saved projects. The sidebar shows the project title, progress, target language, media type, resolution, frame rate, source file, chunks, and project actions.

A session contains:

- the original source media path or copied media asset;
- metadata such as date, location, speaker, and participants;
- chunk boundaries;
- transcription provider and translation provider;
- reviewed source text;
- translations by language;
- timed cues;
- approval state;
- Shorts/Reels plans;
- visual editor settings;
- export-ready state.

The user can reopen a session, jump to a chunk, export a project bundle, import project bundles, and continue reviewing without starting from scratch.

## 8. Configure A New Session

After a source is selected, VaniScript moves to configuration. This screen is not shown in the current screenshot set, but it is a core step in the actual path.

The user confirms metadata:

- date;
- location;
- lecturer or speaker;
- interviewer or participants.

The user chooses:

- source language behavior;
- target language;
- transcription provider;
- translation provider;
- output formats;
- chunk length;
- fixed slicing or smarter slicing behavior.

When the user starts the session, the app plans chunks and creates an autosaved project. This is why long recordings can be reviewed segment by segment instead of forcing the user to wait for a single monolithic transcript.

## 9. Process And Review Segment By Segment

![Review workspace in dual mode](screenshots/10-review-dual-mode.png)

The Review workspace is the main editorial surface.

The top bar shows the app status, editing model, view mode, search, help, project sidebar, settings, and new-session action. The audio strip lets the user play and inspect the current segment.

The central area can show:

- source transcript only;
- translated text only;
- dual view with source and translation side by side.

In dual view, each side has timed cues. This lets the user compare the source and translated meaning at the same point in the audio. For lectures, classes, and devotional recordings, this is essential because the user can preserve meaning while still making the translation readable.

The bottom action bar is where review work happens:

- retry transcription;
- regenerate timings;
- retry translation;
- add another translation language;
- move to the previous segment;
- approve the current segment and advance.

The expected beginner behavior is:

1. Play the current segment.
2. Read the highlighted cue.
3. Correct source text if needed.
4. Correct translation if needed.
5. Add glossary terms when a repeated term should be stabilized.
6. Approve the segment.
7. Continue until all chunks are approved.

## 10. Complete The Review

When the final chunk is approved, the review button changes from `Approve & Next` to `Complete & Export`. That is the bridge from editorial work to deliverables.

The user should not treat export as a separate app. Export is the next workspace inside the same native project. The approved session state is carried forward automatically.

## 11. Export Documents

![Export workspace](screenshots/12-export-workspace.png)

The Export workspace begins with document export.

The app can export the original transcript and translated transcript in common formats such as plain text, subtitles, WebVTT, and Markdown. This is the path for:

- uploading transcripts to a learning system;
- giving editors a reviewed source document;
- giving translators a clean translated text;
- producing subtitles for video tools;
- preparing Markdown notes or publication drafts.

The important concept is that document export is built from the reviewed session, not from raw model output. The better the review step, the better the exported document.

## 12. Create Shorts And Reels Plans

The same Export workspace includes Shorts & Reels planning.

The user chooses how many clips to find, minimum duration, maximum duration, and language mode:

- source language;
- source plus target;
- target language.

When plans exist, the app displays clip cards with title, timing, duration, category, summary, and action buttons. The user can inspect details, replace timing, delete a plan, or open a clip in the visual editor.

This is useful when a long lecture contains several strong moments that should become short vertical clips for YouTube Shorts, Instagram Reels, or TikTok.

## 13. Edit A Vertical Clip

![Visual clip editor](screenshots/13-visual-editor.png)

The visual editor is a full native video-editing workspace for the selected clip.

The top bar shows the clip title, language side, timing, source/target toggle, sync button, undo/redo, help, inspector visibility, reset, save edits, and close.

The preview area shows:

- a NotebookLM-safe neutral preview standing in for source video;
- vertical crop frame;
- dimmed outside area;
- subtitles over the selected crop;
- logo or overlay elements if configured.

The timeline shows:

- video track;
- audio waveform;
- subtitle track;
- playhead;
- cuts and subtitle blocks.

The lower editor lets the user edit caption blocks, split captions, add subtitle blocks, add text blocks, merge blocks, delete blocks, and adjust selected words.

The right inspector changes depending on the selected tab. It includes controls for caption style, frame animation, media/background behavior, and layers. Users can adjust font, size, case, color, outline, shadow, subtitle box, opacity, crop zoom, pan, and frame keyframes.

This is the final step where a long reviewed session becomes a polished social clip.

## 14. Export Selected Videos

Back in the Export workspace, the user chooses:

- format: MP4 or MOV;
- resolution: source-based, Full HD vertical, 2K vertical, or 4K vertical;
- frame rate: source-based or a fixed FPS option;
- selected clip count.

The native renderer uses AVFoundation and the app's render plan to produce the final vertical video. The important user expectation is that caption styling, crop framing, subtitles, and clip timing are saved with the project before export.

## 15. Project Bundles And Portability

VaniScript can export and import project bundles. A project bundle preserves the session data and associated assets so a project can be moved or archived.

This matters for teams:

- one person can prepare a transcript;
- another person can review translation;
- a video editor can work from the Shorts/Reels plans;
- an archive can preserve the reviewed state for later updates.

The Apple Silicon app uses VaniScript project/session storage and a portable bundle format for moving or archiving work.

## 16. Troubleshooting For Beginners

If transcription does not start, check:

- local WhisperKit model is installed and selected;
- cloud key is configured if using a cloud transcription provider;
- the source file is readable;
- the app has permission to access the selected file.

If translation does not start, check:

- local MLX model is installed and selected;
- cloud provider key is present if using Gemini/OpenAI;
- target language is not set to "same";
- the selected provider appears ready in settings.

If recording does not work, check:

- Microphone permission for microphone capture;
- Screen Recording permission for system audio capture;
- selected input device;
- whether another app is holding the device.

If visual export fails, check:

- the source video file still exists;
- enough disk space is available;
- output folder is writable;
- selected resolution and frame rate are reasonable for the Mac;
- the project has saved visual editor edits before exporting.

## 17. Beginner Summary

The user path is:

1. Open VaniScript Apple Silicon.
2. Add source media.
3. Configure metadata, language, models, and chunking.
4. Process the session.
5. Review each chunk in source/translated/dual view.
6. Use glossary and retry tools to improve consistency.
7. Approve all chunks.
8. Export transcript documents.
9. Generate Shorts/Reels plans.
10. Edit selected clips visually.
11. Export final vertical videos.

The app is strongest when the user treats it as one continuous native workflow: ingest, configure, process, review, export, and clip editing all inside the same Apple Silicon app.
