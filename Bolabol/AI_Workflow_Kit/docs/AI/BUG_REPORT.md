# BUG REPORT — Bolabol 1.0.4

> Tester fills when **functional** suite is red or product behavior is wrong.
> For **security** findings use `SECURITY_REPORT.md` (SEC-*).
> Orchestrator opens fix/retry for Coder from either file.
> Tester never patches product `Sources/**`.

## HUD-HUMOR-PROMPTS Exhaustive Application QA

### Meta

| Field | Value |
|-------|-------|
| Step | HUD-HUMOR-PROMPTS |
| Date | 2026-08-07 |
| Result | `bugs` |
| bugs_open | **8** |
| Safe continuation | Yes. Unit/static/build/runtime checks continued independently; no production data or credentials were used. |

### BUG-HHP-001 - Reapplying humor runtime controls duplicates the request block

| Field | Value |
|-------|-------|
| Severity | major |
| Subsystem | Variant 2 polishing prompt composition |
| Exact repro | `swift test --filter HumorStyleControlTests` |
| Expected | Applying the same runtime control repeatedly leaves exactly one `RUNTIME CONTROL:` and one `HUMOR_LEVEL:` block. |
| Actual | `configuredTwice.body` contains **2** of each marker. |
| Frequency | 20/20 focused stress iterations plus all full/sanitizer runs. |
| Logs | `markerCount("RUNTIME CONTROL:") -> 2`; `markerCount("HUMOR_LEVEL:") -> 2`. |
| Suspect files | `Sources/NativeBolabolCore/Models/HumorStyleControl.swift:323-341` |
| Regression test | `runtimeControlsRemainIdempotentWhenAppliedRepeatedly` |
| Workaround | Ensure callers apply controls only to a pristine stored template. This does not protect future retry/composition callers. |
| Additional testing | Safe; all other humor matrix cases continued. |

### BUG-HHP-002 - Settings humor changes during listening do not update the frozen request

| Field | Value |
|-------|-------|
| Severity | major |
| Subsystem | HUD humor session lifecycle / persistence |
| Exact repro | Start a Variant 2 recording; change humor level through Settings rather than the HUD; finish processing. Automated repro: `swift test --filter ApplicationWideRegressionContractTests` or `bash script/qa/check_hud_humor_prompt_contract.sh`. |
| Expected | While recording, every live preference change updates `pendingHotkeyHumorSession`; freeze captures the visible/current level. |
| Actual | The `humorLevel` observer updates only overlay presentation. Unlike enabled/mode observers, it never calls `updatePendingHotkeyHumorSession(level:)`; freeze can enqueue the old level. |
| Frequency | 100%; source-contract test and QA guard fail every run. |
| Logs | `guardsRecording == false`; `updatesPendingLevel == false`; `FAIL: Settings humor-level changes during listening do not update the pending snapshot`. |
| Suspect files | `Sources/NativeBolabol/Views/ContentView.swift:164-168`, compare `:155-173`, `:1708-1711`, `:1749-1759` |
| Regression test | `contentViewSettingsHumorLevelChangeUpdatesThePendingListeningSnapshot`; `check_hud_humor_prompt_contract.sh` |
| Workaround | Adjust humor from the HUD itself during listening; `handleOverlayHumorLevelChange` updates pending state. |
| Additional testing | Safe; local/cloud frozen snapshot and prompt mutation paths continued. |

### BUG-HHP-003 - Non-finite HUD scroll corrupts or changes provider selection

| Field | Value |
|-------|-------|
| Severity | moderate |
| Subsystem | HUD provider quick switcher |
| Exact repro | `swift test --filter HUDProviderSwitcherFeatureTests` |
| Expected | NaN and positive/negative infinity are ignored; the next finite threshold delta still selects deterministically. |
| Actual | NaN poisons the accumulator so later finite input returns nil. Infinity immediately changes provider and the next finite input changes it again. |
| Frequency | 20/20 stress iterations; 7 deterministic assertions per run. |
| Logs | NaN then `-threshold` returns nil; infinity returns provider `two` instead of nil and changes active provider. |
| Suspect files | `Sources/NativeBolabolCore/Services/ProviderQuickSwitcherModel.swift:70-81` |
| Regression test | `hudProviderSwitcherIgnoresNonFiniteScrollWithoutPoisoningLaterInput` |
| Workaround | Normal AppKit deltas are generally finite; hide/recreate the quick switcher if an integration emits a non-finite delta. |
| Additional testing | Safe; ordinary precise/non-precise/reversal/boundary tests remain green. |

### BUG-HHP-004 - Audio retention deletes text-only notes and can remove the retained audio note

| Field | Value |
|-------|-------|
| Severity | critical |
| Subsystem | Notes / audio archive retention |
| Exact repro | `swift test --filter audioRetentionLimitCountsOnlyAudioNotesAndPreservesTextNotes` |
| Expected | `maxRecordings: 1` counts only notes with audio. One audio note plus any number of text-only notes remains intact. |
| Actual | Retention compares `notes.count`, deletes the oldest `notes.suffix`, removes a text-only note and the only audio note, and leaves audio count 0. |
| Frequency | 100% in focused, full, ThreadSanitizer, and AddressSanitizer runs. |
| Logs | Expected 3 notes / audio count 1; actual only `Newest text` / audio count 0. |
| Suspect files | `Sources/NativeBolabolCore/Stores/NoteStore.swift:144-154` |
| Regression test | `audioRetentionLimitCountsOnlyAudioNotesAndPreservesTextNotes` |
| Workaround | Disable automatic archive cleanup until fixed. |
| Additional testing | Safe in isolated temporary fixtures; no user notes were touched. |

### BUG-HHP-005 - Deleting an imported-audio note can delete the user's source file

| Field | Value |
|-------|-------|
| Severity | critical |
| Subsystem | Notes / imported audio ownership |
| Exact repro | `swift test --filter deletingImportedAudioNoteNeverDeletesTheUsersSourceFile` |
| Expected | A recording with `source == .importedFile` is never deleted when its note is deleted, regardless of path. |
| Actual | Ownership checks only path-under-support-root and ignore `source`; the imported file is removed. |
| Frequency | 100% in isolated focused/full/sanitizer runs. |
| Logs | `fileExists(atPath: .../Imports/user-source.wav) -> false` after `deleteNote`. |
| Suspect files | `Sources/NativeBolabolCore/Stores/NoteStore.swift:88-98`, `:359-370` |
| Regression test | `deletingImportedAudioNoteNeverDeletesTheUsersSourceFile` |
| Workaround | Keep imported audio outside Bolabol's Application Support root and retain an external backup. |
| Additional testing | Safe; fixture was created under `FileManager.temporaryDirectory` and removed with `defer`. |

### BUG-HHP-006 - Onboarding Try Record entry point has no production consumer

| Field | Value |
|-------|-------|
| Severity | major |
| Subsystem | Onboarding / recording entry point |
| Exact repro | Open onboarding Modes step and activate Try Record. Automated source repro: `swift test --filter ApplicationWideRegressionContractTests`. |
| Expected | `.nativeBolabolHotkeyTriggered` has a production observer that starts/toggles recording. |
| Actual | Onboarding posts the notification, but no `ContentView`/app publisher or observer consumes it. Global hotkey code also posts it, so that legacy trigger path is disconnected. |
| Frequency | 100% source-contract failure. Interactive click was not executed because no safe UI automation harness exists. |
| Logs | `hasConsumer == false`. Graph/source grep finds only definitions/posts, no subscriber. |
| Suspect files | `Sources/NativeBolabol/Views/OnboardingView.swift:622-633`; `Sources/NativeBolabol/Views/ContentView.swift:129-145`; `Sources/NativeBolabol/Services/GlobalHotkeyManager.swift:7,331` |
| Regression test | `onboardingTryRecordNotificationHasAProductionConsumer` |
| Workaround | Complete onboarding and use the configured key-down/key-up hotkey path or main record control. |
| Additional testing | Safe; remaining onboarding localization/recommendation tests continued. |

### BUG-HHP-007 - Product runtime violates accepted ADR-021 Canary ASR-only boundary

| Field | Value |
|-------|-------|
| Severity | major |
| Subsystem | Translation / Canary routing / architecture contract |
| Exact repro | `swift test --filter ApplicationWideRegressionContractTests`; `bash script/qa/check_s1b_scope.sh`; inspect Translation provider list after installing Canary 1B. |
| Expected | Accepted ADR-021: Canary remains audio transcription only; text translation uses a separate `TextTranslationEngine`. |
| Actual | `CanarySpeechTranslationRuntime` exists, Translation exposes `localCanaryPrefix` and `onCanaryTranslation`, and current AST-oriented tests exercise speech translation. Catalog/S11 tests simultaneously claim Canary speech translation is unavailable. |
| Frequency | 100% static/runtime-contract contradiction. |
| Logs | ADR regression test reports runtime file exists and both Translation Canary markers are present; S1b emits 15 forbidden runtime references; S9 expects obsolete ASR-only test names while AST tests replaced them. |
| Suspect files | `Sources/NativeBolabol/Services/CanarySpeechTranslationRuntime.swift`; `Sources/NativeBolabol/Views/TranslationModalView.swift:19-54,88-103,530-539`; `Sources/NativeBolabolCore/Services/EngineProtocols.swift:66-110`; `Tests/NativeBolabolCoreTests/S9EngineEdgeCaseTests.swift:91-157`; `Tests/NativeBolabolCoreTests/TranslationRuntimeContractTests.swift` |
| Regression test | `acceptedADR021KeepsCanaryOutOfTheTranslationRuntime`; existing `s11CanarySpeechTranslationOperationIsUnavailable` exposes the contradictory contract. |
| Workaround | Do not select Canary in Translation; use an approved text/cloud provider. |
| Additional testing | Safe; no paid API call was made. Real Canary ASR smokes remained green. |

### BUG-HHP-008 - Translation user feedback bypasses the 15-locale AppText surface

| Field | Value |
|-------|-------|
| Severity | minor |
| Subsystem | Translation localization/accessibility |
| Exact repro | `swift test --filter translationUserFeedbackAndGlossaryActionsUseLocalizedCopy` |
| Expected | Clipboard feedback and glossary action labels resolve via `AppText` in all 15 locales. |
| Actual | `Pasted from clipboard`, `Copied to clipboard!`, and `Add to Glossary` are hard-coded English. |
| Frequency | 3/3 assertions, every run. |
| Logs | `isLocalized == false` for all three literals. |
| Suspect files | `Sources/NativeBolabol/Views/TranslationModalView.swift:471,608,619` |
| Regression test | `translationUserFeedbackAndGlossaryActionsUseLocalizedCopy` |
| Workaround | None for non-English UI users. |
| Additional testing | Safe; full AppText locale matrix otherwise remains green. |

### Current summary for Orchestrator

- Open critical: BUG-HHP-004, BUG-HHP-005.
- Open major: BUG-HHP-001, BUG-HHP-002, BUG-HHP-006, BUG-HHP-007.
- Open moderate: BUG-HHP-003.
- Open minor: BUG-HHP-008.
- Final result is `bugs`; `qa_green` is not permitted.

## Meta

| Field | Value |
|-------|--------|
| Step | S9 |
| Date | 2026-08-05 |
| bugs_open | 0 |

## Bugs

### BUG-001 — Canary 1B package size does not trigger the disk warning

| | |
|--|--|
| Severity | major |
| Repro | `swift test` or `swift test --filter s8` |
| Expected | The S4b/ADR-017 1B package is approximately 1.8 GB and its descriptor must exceed the `>1_000_000_000` Settings threshold so the confirmation alert appears before download. |
| Actual | `canary-1b-v2-coreml` reports `approxDownloadBytes == 573000000` and `downloadSize == "~573 MB"`; `s8CanaryOneBAdvertisesPackageSizeAboveDiskWarningThreshold` fails both assertions. The Settings warning condition therefore does not run for this model. |
| Suspect files | `Sources/NativeBolabolCore/Models/TranscriptionModelDescriptor.swift:432-450`; `Sources/NativeBolabol/Views/Settings/LocalModelsSettingsView.swift:251-271` |
| Logs | `Expectation failed: 573000000 > 1000000000`; `Expectation failed: "~573 MB".localizedCaseInsensitiveContains("GB")` |

### BUG-002 — GO presence accepts incomplete model folders

| | |
|--|--|
| Severity | major |
| Repro | `./script/qa/check_s8_download_contract.sh` |
| Expected | `isCompleteGOModelFolder` must require every bundle in each approved package layout: 1B `canary_encoder.mlmodelc`, `canary_cross_kv.mlmodelc`, `canary_decoder_kv.mlmodelc`, and `canary_spe.model`; Flash `CanaryEncoder.mlmodelc`, `CanaryPrefill.mlmodelc`, `CanaryDecoder.mlmodelc`, `config.json`, and `vocab.json`; GigaAM `Encoder.mlmodelc`, `Predictor.mlmodelc`, `JointDecision.mlmodelc`, and `vocab.txt`. The 1B preprocessor remains excluded. |
| Actual | The implementation only checks for any one visible `.mlmodelc` directory and any one alternate vocabulary/tokenizer asset. The S8 guard reports all nine required bundle names missing from the presence contract, so incomplete downloads can be treated as present/Ready. |
| Suspect files | `Sources/NativeBolabol/Stores/TranscriptionModelStore.swift:395-436` |
| Logs | `FAIL: GO presence check must require the complete bundle canary_encoder.mlmodelc` plus corresponding failures for `canary_cross_kv`, `canary_decoder_kv`, `CanaryEncoder`, `CanaryPrefill`, `CanaryDecoder`, `Encoder`, `Predictor`, and `JointDecision`. |

### BUG-003 — Canary 1B Path B passes a rank-2 `pos` input to a rank-1 Core ML feature

| | |
|--|--|
| Status | **CLOSED** |
| Severity | major |
| Repro | `BOLABOL_S9_RUNTIME_SMOKE=1 swift test --filter canary1BOfflineDictationProducesTextWhenScratchIsEnabled` |
| Expected | The GO Canary 1B package performs offline English dictation and returns non-empty text, as demonstrated by the S4b package/runtime evidence. |
| Actual | Product engine loads the real package and fails on the first Path B decoder prediction: `Error Domain=com.apple.CoreML Code=1 "According to model description, feature 'pos' must be of rank 1, instead got a multi-array value of rank 2."` No transcription text is produced. |
| Suspect files | `Sources/NativeBolabol/Engines/CanaryCoreMLEngine.swift:735-751`; `Sources/NativeBolabol/Engines/CanaryCoreMLEngine.swift:746` constructs `pos` through `makeI32([position])`, whose shape is `[1, 1]`. |
| Evidence | Real scratch package `scratch/canary-1b-fix/package/bolabol-canary-1b-v2-coreml-r1/` and real `scratch/canary-flash-spike/audio/en_short.wav` were used. Canary Flash passed with `The quick brown fox jumps over the lazy dog.`; GigaAM passed with `Сегодня мы проверяем точность русской диктовки на компьютере Apple`; Canary 1B failed consistently with the rank mismatch. |

### S9 BUG-003 Closure

Independent Tester QA rerun on 2026-08-05 verified the fix without changing product code:

- `scratch/canary-flash-spike/models/CanaryFlash/` and `scratch/canary-flash-spike/audio/en_short.wav` present.
- `scratch/canary-1b-fix/package/bolabol-canary-1b-v2-coreml-r1/` and the shared `en_short.wav` present; package contains the three Path B `.mlmodelc` bundles and `canary_spe.model`.
- `scratch/gigaam-spike/models/` and `scratch/gigaam-spike/audio/ru_short.wav` present.
- `swift test --filter canary1BDecoderPositionUsesRankOneProductInput`: **PASS**, 1 test. The real product seam returned int32 rank-1 shape `[1]` with the expected position value.
- `BOLABOL_S9_RUNTIME_SMOKE=1 swift test --filter canary1BOfflineDictationProducesTextWhenScratchIsEnabled`: **PASS**, real Path B runtime returned `The quick brown fox jumps over the lazy dog.`
- `BOLABOL_S9_RUNTIME_SMOKE=1 swift test --filter S9RuntimeSmokeTests`: **PASS**, 4 tests. Flash, 1B, and GigaAM each returned non-empty text; the position regression also passed.
- `swift test`: **PASS**, 555 tests in 15 suites.
- `./script/qa/run_all.sh`: **PASS**, 29/29 checks.

The independent runtime confirmation closes BUG-003. No other open S9 product defect was found; BUG-001 and BUG-002 remain closed under the S8 closure record.

---

## S8 Re-run Closure

The initial S8 run reported BUG-001 and BUG-002. After fix round 1, the Tester reran the complete gate:

- `swift test`: **PASS** - 513 tests in 4 suites.
- `./script/qa/run_all.sh`: **PASS** - 28 passed / 0 failed.
- `check_s8_download_contract.sh`: **PASS**, including the 1 GB threshold, complete GO layouts, empty/incomplete presence, integrity/resume, progress, and regression contracts.

- **BUG-001:** **CLOSED**. The 1B descriptor is `1_884_267_035` bytes / `~1.88 GB`, above the Settings disk-warning threshold.
- **BUG-002:** **CLOSED**. The GO presence check requires the complete 1B, Flash, and GigaAM layouts and rejects missing assets; the 1B preprocessor remains excluded.
- **New bugs:** none found in the post-fix gate.

## Summary for Orchestrator

- Historical initial run: 2 major S8 product defects; the feature gate was red.
- S8 post-fix closure snapshot: both S8 defects were closed; `bugs_open: 0` for that step.
- Current S9 run: BUG-003 was independently reverified and **CLOSED**; Canary 1B offline dictate returns non-empty text through the product Path B decoder.
- Current S9 `bugs_open`: **0**.
- Suggested fix target_files from the initial run are retained above for traceability only.
