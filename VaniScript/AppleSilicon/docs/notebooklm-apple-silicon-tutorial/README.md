# VaniScript Apple Silicon NotebookLM Tutorial Package

This folder is a NotebookLM-ready source package for a video onboarding/tutorial about the native Apple Silicon version of VaniScript.

Scope:

- Covered: `VaniScript/AppleSilicon`, the native Swift/SwiftUI macOS app for Apple Silicon.
- Audience-facing framing: this is simply VaniScript running as an Apple Silicon macOS app.
- Language priority: English first, then a full Russian version.
- Screenshot quality: the PNG files in `screenshots/` are direct macOS window captures at native 1920x1050 app-window resolution, not downscaled exports.

Recommended NotebookLM upload order:

1. `EN-01-user-journey.md`
2. `EN-02-apple-silicon-deep-dive.md`
3. `EN-03-notebooklm-video-script.md`
4. `SOURCE-AUDIT.md`
5. `screenshot-map.md`
6. `RU-01-user-journey.md`
7. `RU-02-apple-silicon-deep-dive.md`
8. `RU-03-notebooklm-video-script.md`
9. All PNG files in `screenshots/`

Primary deliverables:

- `EN-01-user-journey.md` - full beginner-friendly user journey from first launch to export.
- `EN-02-apple-silicon-deep-dive.md` - deep architecture and feature breakdown of the native app.
- `EN-03-notebooklm-video-script.md` - production script for a video tutorial.
- `RU-01-user-journey.md` - full Russian user journey.
- `RU-02-apple-silicon-deep-dive.md` - Russian deep dive.
- `RU-03-notebooklm-video-script.md` - Russian video script.
- `screenshot-map.md` - bilingual mapping between screenshots and narration points.
- `SOURCE-AUDIT.md` - source-grounded map of inspected native Apple Silicon code paths.

Important framing for the video:

VaniScript Apple Silicon should be presented as a native macOS workflow for long-form audio/video transcription, translation, review, and Shorts/Reels export. The core story is: source media enters the app, the user configures local/cloud models and glossary behavior, the session is chunked, each segment is reviewed in a dual-language editor, then the finished material becomes transcript documents and optional vertical clips.
