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
