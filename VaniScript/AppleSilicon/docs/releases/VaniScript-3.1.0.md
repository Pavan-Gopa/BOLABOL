# VaniScript 3.1.0

VaniScript 3.1.0 introduces the **Batch Transcription Workspace**, adding automated, unattended multi-file processing while maintaining full compatibility with all established editorial workflows.

## What's new: Batch Transcription Workspace

- **Watched Folders**: Configure directories to monitor and ingest audio and video files automatically.
- **Sequential Start/Stop Queue**: Predictable single-file sequential queue execution with dedicated Start and Stop controls.
- **Exact Provider & Model Binding**: Files bind to the active local (WhisperKit, Parakeet) or cloud provider and model configuration at queue start, with automatic language detection and fail-closed readiness checks.
- **Automatic Chunking & Resume**: Silence-aware chunking matching single-project processing with configurable duration and threshold settings; interrupted jobs resume safely from completed checkpoints.
- **Truthful Per-File Progress**: Honest real-time status reporting across planning, model loading, audio conversion, inference, and finalizing phases with audio duration coverage.
- **Canonical-Name Toggle**: Optional strict filename convention enforcement; disabling the toggle admits arbitrary valid media files immediately without false naming rejections.
- **Atomic Exact-Stem Timed TXT**: Transcriptions write atomically alongside source media as `<stem>.txt` with timed cue segments, cleanly replacing existing companion files without collision stops.
- **Completed-Checkpoint Recovery**: Normalizes cue timelines and recovers multi-chunk transcripts directly from persisted checkpoints without duplicate cloud provider inference.

## From 3.0.0

VaniScript 3.0.0 established the **Editorial Workspace** foundation—unifying media import, multi-language transcription, synchronized subtitle translation, dual-mode review, glossary management, and multi-format video/transcript export.

VaniScript 3.1.0 adds the Batch Transcription Workspace without removing or altering any single-project editor, review, prompt, or export workflows.

## Update & Installation

- **Existing Users**: Open VaniScript, go to **Settings** (or the application menu), and select **Check for Updates...**. Sparkle verifies the cryptographic signature and securely installs the update.
- **New Users**: Download the signed, notarized, and stapled `VaniScript.dmg` (or `VaniScript-3.1.0.dmg`) from GitHub Releases and drag VaniScript to `/Applications`.
- **System Requirements**: macOS 14.0 or later on Apple Silicon (M1, M2, M3, M4).
