# S9 BUG-003 Fix Feature QA Report

**Date:** 2026-08-05
**Tester:** Test Engineer (independent feature QA; full security audit out of scope)
**Scope:** S9 BUG-003 fix rerun, Path B decoder input contract, and ADR-018 runtime coverage
**Status:** **qa_green**

---

## 1. Graphify gate

The required query ran before source study:

```text
graphify query "S9 BUG-003 Canary 1B Path B decoder pos rank one runtime smoke TranscriptionEngineStore" --graph graphify-out/graph.json
```

Result: **PASS**, 361 related nodes found. The traversal resolved the real `CanaryCoreMLEngine` Path B decoder, `TranscriptionEngineStore`, `S9RuntimeSmokeTests`, the product position seam, and the BUG-003 handoff.

## 2. Scratch assets

All documented assets required by the opt-in smokes were present:

- Flash: `scratch/canary-flash-spike/models/CanaryFlash/` and `scratch/canary-flash-spike/audio/en_short.wav`.
- Canary 1B Path B: `scratch/canary-1b-fix/package/bolabol-canary-1b-v2-coreml-r1/` and `scratch/canary-flash-spike/audio/en_short.wav`. The package contains `canary_encoder.mlmodelc`, `canary_cross_kv.mlmodelc`, `canary_decoder_kv.mlmodelc`, and `canary_spe.model`; no preprocessor is required.
- GigaAM: `scratch/gigaam-spike/models/` and `scratch/gigaam-spike/audio/ru_short.wav`.

No fake fixture or duplicated product parser/builder was created.

## 3. Feature gate results

| Command | Result |
|---|---|
| `swift test --filter canary1BDecoderPositionUsesRankOneProductInput` | **PASS** - 1 test; real product seam returned int32 rank-1 `[1]` and the expected position value |
| `swift test` | **PASS** - 555 tests in 15 suites |
| `./script/qa/run_all.sh` | **PASS** - 29/29 checks |
| `BOLABOL_S9_RUNTIME_SMOKE=1 swift test --filter canary1BOfflineDictationProducesTextWhenScratchIsEnabled` | **PASS** - real Path B returned `The quick brown fox jumps over the lazy dog.` |
| `BOLABOL_S9_RUNTIME_SMOKE=1 swift test --filter S9RuntimeSmokeTests` | **PASS** - 4 tests; Flash, 1B, and GigaAM returned non-empty text and the position regression passed |
| `bash script/qa/check_s9_engine_contract.sh` | **PASS** - S9 constraints, product regression mapping, and token-shape guard |

SwiftPM emitted existing dependency identity/resource warnings during Swift test planning; they did not affect the result. The default `swift test` run printed the expected opt-in smoke availability messages; the two explicit opt-in commands above executed the real assets.

## 4. Independent gap-hunt mapping

| S9 / BUG-003 requirement | Existing coverage and independent result |
|---|---|
| Product `pos` regression | `S9RuntimeSmokeTests.canary1BDecoderPositionUsesRankOneProductInput` calls `CanaryCoreMLEngine.pathBDecoderPositionArray(position:)` and asserts dtype, rank/shape `[1]`, and value. **PASS**. |
| Preserve token contract `[1, 1]` | New `check_s9_engine_contract.sh` guard checks the product decoder call `makeI32([token])` and the real `makeI32` int32 builder shape `[1, values.count]`, which is `[1, 1]` for one token. **PASS**. |
| BUG-003 real Path B behavior | Dedicated opt-in smoke loads the real package and returns non-empty English text. **PASS**; this is the independent closure evidence. |
| All three runtime smokes | `S9RuntimeSmokeTests` covers Flash, Canary 1B, GigaAM, and the position regression. **PASS**, 4/4. |
| Flash constraints | Product uses `.cpuAndNeuralEngine`, true encoder `length`, capability max chunk 10 seconds, and product chunk tests cover the 160,000-sample boundary. Source guard and tests **PASS**. |
| Canary 1B constraints | Product has the macOS 15+/`MLState` gate, native Path B frontend, true `mel_length`/`encoder_length`, 15-second chunking, fresh state per segment, and native `SentencePieceModel` from `canary_spe.model`. Source guard, edge tests, regression, and runtime **PASS**. |
| GigaAM constraints | Product uses RU-only capability validation, HTK frontend at 16 kHz, 30-second chunking, fresh RNNT decode per chunk, valid encoder frames, and blank ID 1024. Source guard, language/chunk tests, and runtime **PASS**. |
| Explicit language through capabilities | Canary and GigaAM product language seams reject nil/unsupported requests; capability tests disable auto-detect for all three GO models. **PASS**. |
| Native-only runtime | `check_no_python_in_sources.sh`, `check_no_canary_product.sh`, S4b/S6 guards, and `check_sec_no_download_code.sh` all passed through `run_all.sh`. No Python runtime was introduced. **PASS**. |
| No S10+ expansion | S9 changes remain in engine/store/test/QA surfaces; existing S8 download, security allowlist, HUD, and product-boundary guards passed. No S10/S11 UI/HUD/catalog/download implementation was added by this QA rerun. **PASS**. |

## 5. New tests and QA

- Added QA-only assertions to `script/qa/check_s9_engine_contract.sh` for the real BUG-003 product seam, the preserved product token call, and the int32 array builder contract.
- No Swift test-side token builder was added: the product token builder is private, and duplicating it would not test product behavior. The existing regression remains a direct call to the real product seam.
- Existing S9 tests provide the remaining construction, store wiring, missing/incomplete folder, language, OS, dtype, chunk, and runtime coverage. This is a no-fake, minimal gap closure.

## 6. BUG-003 closure

The former failure was reproduced in the prior QA run with the real package and the rank-2 `pos` error. This independent rerun now passes the real product regression and the real Canary 1B Path B runtime smoke, with the expected non-empty transcript. BUG-003 is therefore **CLOSED**. No other open S9 product defect was found; `bugs_open` is **0**.

---

# S4b Feature QA Report

**Date:** 2026-08-04
**Tester:** Test Engineer (feature QA only; full vuln-hunt out of scope)
**Scope:** S4b (bolabol-canary-1b-v2-coreml-r1) feature gate verification
**Status:** **qa_green** — all checks executed and verified on local machine

---

## 1. Feature gate results

### 1.1 BOLABOL_COREML_SPIKE.md Status GO + package id ✅
- File: `docs/asr/canary-1b/BOLABOL_COREML_SPIKE.md`
- Verdict: **GO — `bolabol-canary-1b-v2-coreml-r1`**
- Package ID confirmed in report.

### 1.2 check_s4b_canary_fix.sh ✅ (with caveat)
- `docs/asr/canary-1b/BOLABOL_COREML_SPIKE.md` contains GO + package ID: **PASS**
- `docs/canary/harness/CanarySmdesaiSpike.swift` exists and contains required markers (`import Accelerate`, `CoreML`, `Foundation`, `NativeMelFrontend`, `MLState`, `makeState()`, `audio_length`, `mel_length`, `encoder_length`, `ASR_PREFLIGHT`): **PASS**
- Package at `scratch/canary-1b-fix/package/bolabol-canary-1b-v2-coreml-r1/` exists with 8 elements (3 `.mlmodelc` dirs + 5 files): **PASS**
- `canary_preprocessor.mlmodelc` absent from package: **PASS**
- MANIFEST SHA integrity (text files): **PASS** (FRONTEND.md, LICENSE.txt, metadata.json, MANIFEST.json SHA-256 match MANIFEST; large binary sizes match)
- Product boundary (no canary in product Sources except allowed locations): **PASS**

**Caveat:** `VERIFY_S4B_PACKAGE=1` (full SHA verification for all files including binaries) is **OFF by default** in the script. This is a feature gap, not a bug — SHA is not automatically verified in `run_all.sh`. Recommendation: enable by default or add separate `check_sec_s4b_package_integrity.sh`.

### 1.3 Preprocessor absent from package ✅
- Package contains: `canary_encoder.mlmodelc`, `canary_decoder_kv.mlmodelc`, `canary_cross_kv.mlmodelc`, `canary_spe.model`, `FRONTEND.md`, `LICENSE.txt`, `MANIFEST.json`, `metadata.json`.
- **No** `canary_preprocessor.mlmodelc` in package root or subdirectories.

### 1.4 MANIFEST SHA integrity ✅
- Text files verified via SHA-256:
  - `FRONTEND.md`: `fcf748399547af47872f48d2436b988e72664673419a9c8d38c2db11687f513a` ✅
  - `LICENSE.txt`: `944212da165ee581a024c9d51bd21ef7badbf72ad4d00b23a731706ae1ce3c98` ✅
  - `metadata.json`: `1d98e1cceaf4ab9fc69e9178b1a3dedf46e11d835e006f9e88b00f77cc722be7` ✅
  - `MANIFEST.json`: `3a258e36b6a71b95e538656569c455a76c302cd7ca69724b3a7075f0f20202a5` ✅
- Binary weights: sizes match MANIFEST (encoder 1,579,377,472 B, decoder_kv 270,864,448 B, cross_kv 33,589,312 B, tokenizer 503,803 B).

### 1.5 Product boundary check_no_canary_product ✅
- `Package.swift`: no "canary" occurrences.
- `Sources/` and `Tests/`: "canary" found only in:
  - `Sources/NativeBolabolCore/Models/OnboardingModelRecommendation.swift` — ModelSpec IDs (`canary-1b-v2-coreml-r1`, `canary180mFlashCoreML`). Allowed: spec definitions only, no product integration.
  - `Sources/NativeBolabolCore/Services/AppText.swift` — `helpBilingualCanary` key for help guide. Allowed: helpBilingual* keys only.
- No canary-specific code in production paths (Engines, Services, TranscriptionModels, etc.).

### 1.6 S4 NO-GO + S5 GO + S6 dual-checks still green via run_all ✅
- `check_b6_canary_spike.sh` confirms:
  - `docs/canary/COREML_SPIKE.md` (B6): NO-GO + D1-D5 + Recommendation ✅
  - `docs/canary/harness/CanarySpike.swift`: exists, no Python ✅
  - `docs/asr/canary-1b/COREML_SPIKE.md` (S4): NO-GO + F1-F6 + checklist sections ✅
  - `docs/canary/harness/CanaryFluidSpike.swift`: exists, no Python ✅
  - `docs/asr/canary-flash/COREML_SPIKE.md` (S5): GO + F1-F4 + checklist sections ✅
  - `docs/canary/harness/CanaryFlashSpike.swift`: exists, no Python ✅
- All spike reports and harnesses present with correct verdicts.

### 1.7 Runtime EN short — executed ✅
- Fresh harness build: `swiftc -O -parse-as-library docs/canary/harness/CanarySmdesaiSpike.swift -framework CoreML -framework Accelerate` → builds clean, `--help` works.
- Path B EN ASR run (documented command, `modelRoot=scratch/canary-1b-fix/smdesai`, `frontend=native`, CPU):
  - `MEL_PREFLIGHT: PASS` (pearson_mel_energy_envelope=0.701, valid_region_exact_zero_fraction=0.000)
  - transcript: `The quick brown fox jumps over the lazy dog.` — `EOS=true`, no repetition tail, `ASR_PREFLIGHT: PASS` (8.4 s wall).
- Evidence reproduces the spike report claims.

### 1.8 Harness builds ✅
- Full compilation verified locally (`swiftc -O -parse-as-library`, see 1.7). Pre-built binary `scratch/canary-1b-fix/bin/CanarySmdesaiSpike` also functional.

---

## 2. Local execution — completed 2026-08-04 (verified)

| Command | Result |
|---|---|
| `swift test` | ✅ 503 tests, 4 suites, all passed |
| `bash script/qa/check_s4b_canary_fix.sh` | ✅ OK (report GO, harness contracts, package boundary, no-product) |
| `VERIFY_S4B_PACKAGE=1 bash script/qa/check_s4b_canary_fix.sh` | ✅ OK — full SHA-256 + size verification of all 19 manifest files |
| `script/qa/check_no_canary_product.sh` | ✅ zero Canary product/module surface (ADR-012) |
| `./script/qa/run_all.sh` | ✅ 27 passed / 0 failed (incl. dual-checks + `check_sec_s4b_package_integrity.sh` 19/19) |
| `git check-ignore -v scratch/canary-1b-fix` | ✅ ignored via `.gitignore:6`; no tracked package artifacts |
| Runtime EN ASR (see §1.7) | ✅ MEL_PREFLIGHT PASS, ASR_PREFLIGHT PASS |

**QA-script fix applied this pass (script/qa only, no product Sources touched):**
`check_sec_no_download_code.sh` (new, untracked) Pattern 4 false-positived on the
pre-existing sanctioned cloud surface
`Sources/NativeBolabol/Services/CloudProviderModelCatalog.swift` (`fetchModels(`
= GET /models LLM catalog listing, not ASR/CoreML weight download; file present
since the rename commit, unchanged since the S4b checkpoint, presence enforced
by `check_cloud_providers.sh`). Fixed by allowlisting that one file for Pattern
4 only. Defense in depth verified preserved: Patterns 1-3 unchanged; Pattern 1
still catches any future `downloadTask/dataTask` introduced in that file; a
negative test confirms `downloadModelPackage`/`fetchCoreMLWeights` helpers are
still detected.

---

## 3. Feature gaps (non-blocking)

| # | Gap | Impact | Status |
|---|---|---|---|
| FG1 | `VERIFY_S4B_PACKAGE=1` off by default in `check_s4b_canary_fix.sh` | SHA integrity not automatically verified by that script | **Mitigated:** `check_sec_s4b_package_integrity.sh` now runs in `run_all.sh` (19/19 SHA-256 + size) |
| FG2 | `check_no_secrets.sh` does not scan `docs/`, `scratch/`, `AI_Workflow_Kit/docs/` | Potential secret in those dirs may be missed | **Mitigated:** `check_sec_no_secrets_extended.sh` now runs in `run_all.sh` |
| FG3 | No `check_sec_no_download_code.sh` for CDN residual risk | Download code could appear without guard | **Resolved:** script added to `run_all.sh`; Pattern 4 false positive on the sanctioned cloud catalog fixed this pass |
| FG4 | Harness `Models.load` loads `canary_preprocessor.mlmodelc` unconditionally, but the GO package intentionally excludes the preprocessor | Harness cannot use the package dir directly as `modelRoot` (fails at load even with `frontend=native`) | **Non-blocking observation:** documented runtime evidence uses `modelRoot=scratch/canary-1b-fix/smdesai` (extraction dir incl. preprocessor), exactly as recorded in the spike doc. S7+ integrator must not assume harness ⇄ package drop-in; product adapter loads encoder/cross/decoder + native mel only |

These are **low/medium severity**, all non-blocking.

---

## 4. Verdict

**qa_green — verified, not expected.** All feature checks for the S4b contract executed green on the local machine: `swift test` (503), `run_all.sh` (27/27), S4b contract script with and without `VERIFY_S4B_PACKAGE=1`, package SHA integrity 19/19, preprocessor absent, product Canary-free, gitignore boundary holds, harness builds, runtime EN ASR reproduces spike evidence.

No product functional bugs found → **no BUG_REPORT**. The single `run_all.sh` red was a QA-script false positive (new `check_sec_no_download_code.sh` vs. pre-existing sanctioned cloud catalog), fixed in `script/qa/` only.

Out of scope this pass (per role): product `Sources/**` changes, full security/vuln audit (Security Engineer), git commit/push.

---

## S7 Feature QA Report

**Date:** 2026-08-04
**Tester:** Test Engineer (feature QA; full vulnerability hunt out of scope)
**Scope:** S7 Catalog + backends + capabilities, data layer only
**Status:** **qa_green**

### 1. Feature gate

| Command | Result |
|---|---|
| `swift test` | **PASS** — 507 tests in 4 suites |
| `./script/qa/run_all.sh` | **PASS** — 27 passed / 0 failed |
| `check_no_secrets.sh` via `run_all.sh` | **PASS** |
| `check_sec_no_secrets_extended.sh` via `run_all.sh` | **PASS** |

### 2. Gap-hunt mapping

| S7 requirement | Evidence |
|---|---|
| Backend cases exist | Existing catalog coverage plus new exact runtime-badge test for WhisperKit, FluidAudio, Canary, and GigaAM. |
| Three GO descriptors and honest capabilities | Existing GO trio/order test; new exact 10/15/30 second chunk limits, language lists, download sizes, and macOS 15 capability assertions. |
| Ranking IDs resolve to catalog entries | Existing `OnboardingModelRecommendation` matrix and S2 ranking tests pass against the current catalog IDs. |
| QA permits GO surface and blocks engines/NO-GO sources | `check_no_canary_product.sh`, dependent scope checks, and all 27 contract scripts pass. New backends remain unavailable-engine stubs by existing product contract. |
| Reviewer NB-2 runtime badges and chunk values | Covered by `nativeTranscriptionBackendsExposeStableRuntimeBadges` and `nativeTranscriptionCatalogUsesAdr018ChunkAndDownloadCapabilities`. |
| FI/alexwengg install-source guard in catalog | Covered by `nativeTranscriptionCatalogKeepsNoGoCanarySourcesOutOfGoEntries` for all three GO entries; the sanctioned existing Parakeet FluidInference descriptor is excluded from this GO-only guard. |
| Existing WhisperKit/FluidAudio regression | `nativeTranscriptionCatalogPreservesExistingWhisperKitAndFluidAudioDescriptors` snapshots the seven pre-S7 descriptors, including repository IDs, globs, badges, descriptions, ratings, and backend metadata. |

### 3. New tests added

Added to `Tests/NativeBolabolCoreTests/TranscriptionModelCatalogTests.swift`:

- `nativeTranscriptionBackendsExposeStableRuntimeBadges`
- `nativeTranscriptionCatalogUsesAdr018ChunkAndDownloadCapabilities`
- `nativeTranscriptionCatalogKeepsNoGoCanarySourcesOutOfGoEntries`
- `nativeTranscriptionCatalogPreservesExistingWhisperKitAndFluidAudioDescriptors`

### 4. Scope and verdict

- Tester changed only the test file, this report, and the Tester section in `FEEDBACK.md`.
- No `Sources/**`, `Package.swift`, `STATE.yaml`, or product code was changed.
- `BUG_REPORT.md` remains unchanged with `bugs_open: 0`; no product defect was found.
- Security coverage was limited to the existing lightweight secret checks in the gate, as required for Tester.

**RESULT: `qa_green`**

---

## S8 re-run

**Date:** 2026-08-04
**Tester:** Test Engineer (post-fix feature gate; full vulnerability hunt out of scope)
**Scope:** S8 Download + presence + storage paths + progress UI, fix round 1
**Status:** **qa_green**

### Gate results

Graphify was queried first against `graphify-out/graph.json` for the S8 download, presence, package-size, storage, and regression-contract relationships. The query resolved the S8 tests, `TranscriptionModelStore`, `TranscriptionModelDescriptor`, and the QA guard.

| Command | Result |
|---|---|
| `swift test` | **PASS** - 513 tests in 4 suites |
| `./script/qa/run_all.sh` | **PASS** - 28 passed / 0 failed |
| `check_s8_download_contract.sh` via `run_all.sh` | **PASS** |

### Bug closure

- **BUG-001 CLOSED:** `canary-1b-v2-coreml` advertises `approxDownloadBytes == 1_884_267_035` and `~1.88 GB`; the `>1_000_000_000` Settings warning condition therefore triggers. `s8CanaryOneBAdvertisesPackageSizeAboveDiskWarningThreshold` is green.
- **BUG-002 CLOSED:** `isCompleteGOModelFolder` uses `requiredItems.isSubset(of: visible)` with the complete layouts for 1B, Flash, and GigaAM. Missing any bundle or vocabulary/metadata item, including an empty folder, is rejected; the 1B layout does not require `canary_preprocessor.mlmodelc`. `s8PresenceFixturesRejectEmptyFoldersAndIncompleteModelAssets` and the executable-target S8 contract are green.

### Regression and gap-hunt

- Install-source mapping, `SharedModelsRoot` storage paths, resume/SHA-256 hooks, and Settings progress states remain green.
- Existing WhisperKit/FluidAudio catalog coverage, engine routing, and HUD-A markers remain green.
- The gap-hunt strengthened `check_s8_download_contract.sh` with an explicit subset-semantics assertion covering missing-any-required-asset rejection across all three GO layouts. No new product bug was found.
- Security verification remained limited to the lightweight checks already included in the gate.

### Verdict

**RESULT: `qa_green`** - BUG-001 and BUG-002 are closed; current `BUG_REPORT.md` has `bugs_open: 0`.
