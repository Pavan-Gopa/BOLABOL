# BUG REPORT — Bolabol 1.0.4

> Tester fills when **functional** suite is red or product behavior is wrong.
> For **security** findings use `SECURITY_REPORT.md` (SEC-*).
> Orchestrator opens fix/retry for Coder from either file.
> Tester never patches product `Sources/**`.

## Meta

| Field | Value |
|-------|--------|
| Step | S8 |
| Date | 2026-08-04 |
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
- Current post-fix run: both defects are closed; `bugs_open: 0`; feature gate is green.
- Suggested fix target_files from the initial run are retained above for traceability only.
