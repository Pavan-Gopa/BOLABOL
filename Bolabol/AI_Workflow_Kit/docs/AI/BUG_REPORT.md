# BUG REPORT — Bolabol 1.0.4

> Tester fills when **functional** suite is red or product behavior is wrong.
> For **security** findings use `SECURITY_REPORT.md` (SEC-*).
> Orchestrator opens fix/retry for Coder from either file.
> Tester never patches product `Sources/**`.

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
