# Bolabol ASR Core ML — step cards (S0–S15)

Authoritative plan: `BOLABOL_ASR_COREML_INTEGRATION_PLAN.md`.

## S0 — Train bootstrap

Kit + plan SoT; `APP_VERSION` narrative 1.0.4; STATE at S1.

## S1 — Onboarding language steps

### Goal

Three distinct screens: UI language → primary dictation → additional working language. Clear copy; «change later in Settings». No model cards yet (S1c).

### Requirements

1. Split language UX so UI language is not mixed with speech languages.
2. Primary = main dictation language; additional = second working language (not «always output target»).
3. Same-as-primary control for additional.
4. Footer/hint: change later (General / Hotkey → Your Languages).
5. EN AppText keys (full 15 locales in S3).
6. Persist via existing `UserSpeechLanguages` / GeneralSettingsStore.
7. Pickers: `LanguagePickerOrder`.

### target_files

```yaml
- Sources/NativeBolabol/Views/OnboardingView.swift
- Sources/NativeBolabol/Stores/GeneralSettingsStore.swift
- Sources/NativeBolabolCore/Services/AppText.swift
- Sources/NativeBolabolCore/Models/UserSpeechLanguages.swift
- Sources/NativeBolabolCore/Models/LanguagePickerOrder.swift
- Tests/NativeBolabolCoreTests/OnboardingLocalizationTests.swift
- Tests/NativeBolabolCoreTests/UserSpeechLanguagesTests.swift
```

### Out of scope

- Dynamic 3 model cards (S1b/S1c)
- Canary/GigaAM engines
- Full 15-locale maps (S3) — EN required

### Done

- [ ] Three clear steps; store writes primary+additional
- [ ] swift test green
- [ ] FEEDBACK waiting_review

### Verify

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"
swift test
```

## S1b — Ranking pure function

`OnboardingModelRecommendation.topThree` + unit tests R1/R2/R3 matrix (plan §3.5.3).

## S1c — Onboarding 3 dynamic model cards

### Goal

Replace the hard-coded onboarding model list with a dedicated `localModels`
screen bound directly to `OnboardingModelRecommendation.topThree`.

### Requirements

1. Keep the fixed order: UI language → primary dictation → additional working
   language → local models → existing permissions / modes / glossary / theme.
2. Compute up to three cards from the current primary/additional values and
   `transcriptionModelStore.models`; do not duplicate ranking rules in the view.
3. Returning Back, changing either speech language, and advancing again must
   recalculate the cards automatically.
4. Missing / NO-GO catalog entries disappear and remaining cards shift up.
5. Show `Recommended` only on slot 1 and the localized slot-1 subtitle
   `Best match for your languages`.
6. Preserve existing download/use/progress/error actions for shipped models.
   Downloading is optional; Next and Skip must preserve the current/default
   engine when no model is selected.
7. Add EN source copy for title, hint, recommended subtitle, and the
   Settings → Local Models change-later footer. Full 15-locale copy is S3.
8. Keep accessibility labels and the existing light/dark appearance behavior.

### target_files

```yaml
- Sources/NativeBolabol/Views/OnboardingView.swift
- Sources/NativeBolabolCore/Services/AppText.swift
- Tests/NativeBolabolCoreTests/OnboardingLocalizationTests.swift
```

### Out of scope

- Settings recommended strip (S2)
- Full 15-locale maps (S3)
- Canary/GigaAM catalog, download, or runtime integration (S4+ / GO-gated)
- New ranking logic or changes to the S1b ranking table
- Cloud provider redesign

### Done

- [ ] Screen 3 renders up to three current ranked cards
- [ ] Back → language change → Forward reorders without stale state
- [ ] Slot 1 alone is recommended; thin catalog collapses cleanly
- [ ] Next/Skip works without downloading or changing the engine
- [ ] `swift test` and scoped QA green
- [ ] Fresh `APP_VERSION=1.0.4` build opened
- [ ] FEEDBACK status `waiting_review`

### Verify

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"
swift test
./script/qa/run_all.sh
APP_VERSION=1.0.4 ./script/build_and_run.sh --verify
```

## S2 — Settings model labels + recommendations

### Goal

Make Settings → Local Models use the same language-aware recommendation helper
as onboarding without duplicating models or changing manual selection.

### Requirements

1. Keep the existing backend picker, cloud status, active-model state, download,
   retry, use, delete, progress, and full-catalog behavior.
2. For the local backend, compute recommendations only through
   `OnboardingModelRecommendation.topThree`, using the current canonical
   primary/additional pair from `GeneralSettingsStore` and the shipped catalog.
3. Present recommendations first and the remaining full catalog afterward.
   Each descriptor must appear exactly once across both groups.
4. Language changes in Settings must recalculate the groups without cached or
   duplicated ranking logic.
5. Add clear EN Settings labels/hints explaining that recommendations follow
   main + additional languages. Full locale coverage is S3.
6. Preserve arbitrary manual model selection; recommendations are display order
   only and must not auto-activate, download, or change backend.
7. Preserve accessibility and current light/dark layout.

### target_files

```yaml
- Sources/NativeBolabol/Views/Settings/LocalModelsSettingsView.swift
- Sources/NativeBolabolCore/Services/AppText.swift
- Tests/NativeBolabolCoreTests/SettingsLocalizationTests.swift
```

### Out of scope

- Onboarding changes
- S3 full 15-locale maps
- S4–S10 model spikes, catalog entries, engines, downloads, and OS gates
- S12 default-selection hints for future GO models
- Ranking-table changes or a second ranking helper
- Cloud provider redesign

### Done

- [ ] Recommended group equals current `topThree(primary, additional, catalog)`
- [ ] Recommended + remaining groups contain the full catalog exactly once
- [ ] Speech-pair changes recalculate without stale state
- [ ] No recommendation automatically mutates model/backend/download state
- [ ] EN Settings copy and focused tests green
- [ ] `swift test` and full QA green
- [ ] Fresh `APP_VERSION=1.0.4` build opened
- [ ] FEEDBACK status `waiting_review`

### Verify

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"
swift test
./script/qa/run_all.sh
APP_VERSION=1.0.4 ./script/build_and_run.sh --verify
```

## S3+ (Track B closed)

Spikes S4–S6 + S4b closed. Human GO list **ADR-018** (Flash + GigaAM + 1B Path B).  
Track C: S7→S15.

## S7 — Catalog + backends + capabilities (data layer only)

### Goal

Add product **data layer** for ADR-018 GO models so they appear in catalogs /
ranking IDs without yet implementing download UI or engines (S8/S9).

### GO models (ADR-018)

| id | displayName | backend | languages / notes |
|----|-------------|---------|-------------------|
| `canary-180m-flash-coreml` | Canary Flash (EN/DE/FR/ES) | `canaryCoreML` | en,de,fr,es; S5 package |
| `canary-1b-v2-coreml` | Canary 1B v2 (Path B) | `canaryCoreML` | verified EN (+ EN→FR AST claim); **Bolabol package** `bolabol-canary-1b-v2-coreml-r1`, **not** HF FI/alexwengg |
| `gigaam-v3-rnnt-coreml` | GigaAM v3 (Russian) | `gigaAMCoreML` | **ru only** |

Existing WhisperKit / FluidAudio (Parakeet) unchanged.

### Requirements

1. Extend `TranscriptionModelDescriptor.Backend` with `canaryCoreML` and `gigaAMCoreML` (names per plan §2.1).
2. Add `ASRModelCapabilities` (or equivalent) with honest flags: no auto-detect for Canary/GigaAM; language lists; maxChunkSeconds (Flash ~10s, 1B ~15s, GigaAM ~30s); minOS (1B Path B macOS 15+ if MLState); download size estimates; recommend flags for RU / EN-DE-FR-ES.
3. Catalog entries for the three GO ids; folder/package names align with plan §2.3 / S4b package layout (document CDN base later in S8 — placeholders OK).
4. Ranking helper already references GO ids (S1b) — ensure catalog `id` strings match `OnboardingModelRecommendation` exactly.
5. Unit tests: catalog contains exactly the GO trio + existing models; **no** FluidInference/alexwengg product download URLs; capabilities honesty; backend badges.
6. Update `script/qa/check_no_canary_product.sh` (or successor): **allow** GO catalog/backend/capability surface; still **forbid** engine types, Package canary targets, and NO-GO HF as install source until S8/S9 policy is explicit.
7. **No** download manager changes, **no** Core ML engine classes, **no** Settings card redesign beyond what catalog feeds automatically (S8–S10).

### target_files (expected — adjust via graphify if needed)

```yaml
- Sources/NativeBolabolCore/Models/TranscriptionModelDescriptor.swift
- Sources/NativeBolabolCore/Models/ (capabilities + catalog files as they exist)
- Sources/NativeBolabolCore/Models/OnboardingModelRecommendation.swift  # only if id mismatch
- Tests/NativeBolabolCoreTests/ (catalog/capability tests)
- script/qa/check_no_canary_product.sh  # or check_go_catalog_surface.sh
- AI_Workflow_Kit/docs/AI/FEEDBACK.md
```

### Out of scope

- S8 download/presence UI
- S9 CanaryCoreMLEngine / GigaAMCoreMLEngine
- S10 Settings cards polish / OS banners (beyond data needed for later)
- S11 HUD matrix
- Product wiring of NO-GO HF 1B packages

### Done

- [ ] Backend cases exist
- [ ] Three GO descriptors in catalog with honest capabilities
- [ ] Ranking IDs resolve to catalog entries when present
- [ ] Tests green; QA allows GO surface, blocks engines/NO-GO sources
- [ ] FEEDBACK waiting_review

### Verify

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"
swift test
./script/qa/run_all.sh
```

## S8 — Download + presence + storage paths + progress UI

### Goal

Make the three ADR-018 GO models actually installable: download (with resume),
storage roots, complete-folder presence check, and download progress UI in
Settings → Local Models. No engines yet (S9), no card redesign / banners (S10).

Gate: **install complete-folder works** for all three GO models.

### Install sources (ADR-018 — authoritative)

| id | Source | Notes |
|----|--------|-------|
| `canary-180m-flash-coreml` | HF `aufklarer/Canary-180M-Flash-CoreML` | NOT `nvidia/canary-180m-flash` (NeMo origin, non-Core ML) |
| `gigaam-v3-rnnt-coreml` | HF `huggingfinger0/gigaam-v3-coreml` | NOT `salute-developers/gigaam-v3` (NeMo origin) |
| `canary-1b-v2-coreml` | Bolabol CDN package `bolabol-canary-1b-v2-coreml-r1` | Path B (S4b, ADR-017); MANIFEST.json + SHA-256; CDN base URL placeholder OK, must be explicit/configurable — no fake download |

Reviewer NB-1 (S7): `modelRepositoryID` for Flash/GigaAM currently points at
NeMo origin repos — S8 must NOT use it verbatim as install source. Introduce an
explicit install-source field/mapping per backend.

### Requirements

1. Storage roots (plan §2.3): SharedModelsRoot → `canary/1b-v2/`,
   `canary/180m-flash/`, `gigaam/v3-rnnt/`. Move the S7 temporary
   `parakeetModelsDirectory` placeholders for the new backends to real roots.
2. Complete-folder presence check per model (all required `.mlmodelc` +
   vocab/`canary_spe.model` per package layout; 1B = S4b package layout minus
   the excluded preprocessor).
3. Download with resume reusing the existing model-install path where possible;
   1B via CDN package manifest (`docs/asr/canary-1b/fix/package_manifest.sh`,
   `MANIFEST.json` SHA-256 contract); verify integrity after download.
4. Disk warning for 1B (~1.8 GB package) before download starts.
5. Progress UI: Settings → Local Models rows show Downloading (progress),
   Ready, Failed (retry), Not installed — same pattern as Whisper/Parakeet.
6. Replace the S7 placeholder `download()` throw for the new backends
   (NB-3: user-facing text must not leak internal step ids).
7. Honest states only — no fake progress / fake downloaded states.

### target_files (expected — adjust via graphify if needed)

```yaml
- Sources/NativeBolabol/Stores/TranscriptionModelStore.swift
- Sources/NativeBolabolCore/Models/TranscriptionModelDescriptor.swift  # install-source mapping only
- Sources/NativeBolabol/Views/Settings/LocalModelsSettingsView.swift   # progress states only
- Tests/NativeBolabolCoreTests/
- script/qa/ (guard install sources != NO-GO HF / NeMo origins)
- AI_Workflow_Kit/docs/AI/FEEDBACK.md
```

### Out of scope

- S9 engines (CanaryCoreMLEngine / GigaAMCoreMLEngine)
- S10 card redesign, OS banners, clamp banners
- S11 HUD matrix
- Any use of FluidInference/alexwengg/smdesai trees as install sources

### Done

- [ ] Explicit install-source mapping: Flash→aufklarer, GigaAM→huggingfinger0, 1B→Bolabol CDN package
- [ ] Storage roots per plan §2.3; presence = complete-folder check
- [ ] Resume works; 1B SHA-256 manifest verified after download
- [ ] Disk warning for 1B; progress/ready/failed/retry states in Settings
- [ ] No fake states; placeholder S8 throw removed; no step-id leak in copy
- [ ] swift test + run_all green; FEEDBACK waiting_review

### Verify

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"
swift test
./script/qa/run_all.sh
```

## S4b — Canary 1B Core ML fix + Bolabol-hosted package

### Goal

Produce a **fixed** Canary 1B v2 Core ML artifact that passes ASR preflight (unlike
FluidInference / alexwengg NO-GO exports), package it for **Bolabol cloud download**
(not Hugging Face), re-spike to **GO**, and leave a cloud-ready layout + manifest
for later S7+ product wiring.

Authoritative detail: `docs/asr/canary-1b/FIX_PLAN.md`.

### Why (S4 residual)

S4 NO-GO (ADR-013) is **export failure**, not “no large Canary ever”:

| ID | Defect | Fix ownership |
|----|--------|----------------|
| F1 | Core ML Preprocessor mel broken (no freq discrimination; envelope corr ≈0.009) | **Exporter / frontend** |
| F2 | Encoder embeddings content-free (cos(diff EN)≈0.97) | Usually follows F1; re-validate after F1 |
| F3 | Decoder loops, never EOS | Re-validate after F1; decoder re-export only if still broken |
| F4 | README WER/RTFx unreproducible | Auto-clears if F1–F3 pass |
| F5 | Same class as alexwengg B6 | Do not reuse those HF packages |
| F6 | FluidAudio 0.15.5 has no matching Canary API | Ship **Bolabol adapter/engine** later (S7–S9), not FluidAudio canary branch |

App Settings/UI **cannot** fix F1–F3. Host may be custom CDN; **bytes must be a new GO package**.

### Two allowed fix paths (pick one; document choice)

**Path A — Preferred for cloud package completeness**  
Re-export / fix **Preprocessor.mlmodelc** (and re-export Encoder/Decoder/Projection if mel contract changes) via mobius/coremltools from `nvidia/canary-1b-v2`, so the hosted folder is a self-contained Core ML set.

**Path B — Flash-style hybrid (acceptable if A blocked)**  
Verified **native Swift/Accelerate NeMo-aligned mel** in harness/engine + Core ML Encoder/Decoder/Projection only. Host package then includes mel contract docs + non-preprocessor models; product engine must implement the same mel. Prefer A if both work.

Do **not** ship FluidInference preprocessor as-is.

### Requirements

1. Baseline: read S4 `docs/asr/canary-1b/COREML_SPIKE.md` rev.2 + ADR-012/013 (do not reopen broken HF as primary).
2. Implement Path A or B; work under `docs/asr/canary-1b/fix/`, harness under `docs/canary/harness/` or `docs/asr/canary-1b/`, artifacts under `scratch/canary-1b-fix/` (gitignored).
3. Preflight **all must PASS** before GO:
   - Mel: 1 kHz vs 4 kHz narrow-band discrimination; pearson(mel, envelope) **> 0.5**
   - ASR EN short: non-empty sensible transcript, **EOS true**, no infinite loop
   - ≥1 second language or AST attempt documented (honest scope)
   - True **valid-length** (never padded buffer size as valid)
   - Load on CPU and ANE (or document OS gate, e.g. int4 → macOS 15+)
   - No Python in inference path
4. Cloud package under `scratch/canary-1b-fix/package/` (or documented path):
   - frozen layout + `MANIFEST.json` (version id, sizes, **SHA-256** per file, license, min OS)
   - upload notes for Human CDN (URL placeholders OK; real secrets not in repo)
5. Write `docs/asr/canary-1b/BOLABOL_COREML_SPIKE.md` with explicit **GO** or **NO-GO** and evidence.
6. Optional ADR draft if GO (Orchestrator finalizes).
7. Product Sources remain free of Canary production wiring (S7+ after GO + Human list).

### target_files

```yaml
- docs/asr/canary-1b/FIX_PLAN.md
- docs/asr/canary-1b/BOLABOL_COREML_SPIKE.md
- docs/asr/canary-1b/fix/
- docs/canary/harness/
- scratch/canary-1b-fix/
- script/qa/
- AI_Workflow_Kit/docs/DECISIONS.md
```

### Out of scope

- Product catalog / download UI / CanaryCoreMLEngine production (S7–S10)
- Reopening FluidInference/alexwengg packages as GO without re-export
- FluidAudio unmerged `canary` branch as product dependency
- Canary Flash / GigaAM product wiring (separate GO list)
- git commit / push (Orchestrator)

### Done

- [ ] Path A or B chosen and documented
- [ ] F1 preflight green (mel)
- [ ] F3 preflight green (EOS + sensible EN transcript)
- [ ] Cloud package layout + MANIFEST.json with SHA-256
- [ ] `BOLABOL_COREML_SPIKE.md` Status GO or NO-GO with evidence
- [ ] Product Sources still Canary-production-free
- [ ] `swift test` green; QA dual-checks still green
- [ ] FEEDBACK `waiting_review`

### Verify

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"
# harness build + preflight runs per FIX_PLAN.md
swift test
./script/qa/run_all.sh
script/qa/check_no_canary_product.sh
```
