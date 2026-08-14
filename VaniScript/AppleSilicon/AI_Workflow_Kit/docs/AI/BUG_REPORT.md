# BUG REPORT

> Main Orchestrator writes this after verifying a Tester's structured
> functional failure evidence. For security findings use `SECURITY_REPORT.md`.
> Main routes accepted fixes to a fresh Coder. Tester never patches product
> source or writes workflow reports directly.

## Meta

| Field | Value |
|-------|--------|
| Step | S3 |
| Date | 2026-08-11 |
| bugs_open | 2 |

## Bugs

### BUG-001 — SmartAudioAnalyzer end-frame overflow crashes native processing

| | |
|--|--|
| Severity | critical |
| Status | open |
| Repro | In build `20260811133359`, select Canary 1B and start native re-transcription for chunk 1 of the existing project. |
| Expected | Audio analysis completes or safely falls back to fixed-duration chunking. |
| Actual | `SIGTRAP` before ASR execution while converting an infinite `Double` to `AVAudioFramePosition`. |
| Suspect files | `Sources/VaniScript/Services/SmartAudioAnalyzer.swift:48-67` |
| Logs / evidence | Crash incident `B03A6D52-4873-4BE1-A51C-E4178E24E8D7`; app log `2026-08-11 19:14:37.243`; Main exact conversion reproduction exits 133 with the same libswiftCore assertion. |


### BUG-002 — Native readiness rejects non-Whisper Core ML ASR

| | |
|--|--|
| Severity | critical |
| Status | open |
| Repro | In fresh candidate 7, select the active Canary Flash 180M provider and click `Initialize Engine`. |
| Expected | Readiness resolves the selected descriptor through `activeLocalASRModel`; supported local ASR is accepted, while OS, source-language, missing-source, and integrity failures are specific. |
| Actual | Initialization fails with `Core ML transcription requires a downloaded or located WhisperKit model.` |
| Suspect files | `Sources/VaniScriptCore/NativeProcessingReadiness.swift:17-54`; processing callsites in `NativeProcessingPipeline.swift`. |
| Logs / evidence | Human screenshot; persisted `settings.json` has `transcriptionProvider: canary-180m-flash-coreml`; source still calls `activeWhisperKitModel`. |
---

_(add BUG-002, … as needed)_
