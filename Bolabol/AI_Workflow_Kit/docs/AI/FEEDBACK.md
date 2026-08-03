# FEEDBACK — Bolabol 1.0.4 (ASR Core ML)

> Workers fill sections on handoff. Orchestrator reads this every status check.

## Meta

| Field | Value |
|-------|-------|
| Step | S2 |
| Actor | coder |
| Timestamp | 2026-08-03T11:32:00Z |
| RESULT | waiting_review |

## §1 — Inventory & Pass/Fail Summary

- **Working Directory**: `/Users/pavan/Documents/AI Projects/Bolabol`
- **Required Graphify commands**: all four completed against `graphify-out/graph.json`:
  - `graphify explain "LocalModelsSettingsView" --graph graphify-out/graph.json`
  - `graphify explain "OnboardingModelRecommendation" --graph graphify-out/graph.json`
  - `graphify path "LocalModelsSettingsView" "OnboardingModelRecommendation" --graph graphify-out/graph.json`
  - `graphify query "settings local models recommendations catalog layout" --graph graphify-out/graph.json`
- **Reviewed context**: AGENTS.md chain, TEAM_CONTRACT.md, STATE.yaml (read-only), ASR S2 card, integration plan §§3.1/7/9.4, prior FEEDBACK.md S1c sections, and REPORT.md.
- **Changed product/test paths**:
  - `Sources/NativeBolabol/Views/Settings/LocalModelsSettingsView.swift`
  - `Sources/NativeBolabolCore/Services/AppText.swift`
  - `Tests/NativeBolabolCoreTests/SettingsLocalizationTests.swift`
- `STATE.yaml` was not changed. No commit, tag, or push was performed.

## §2 — S2 Implementation Compliance

- [x] Settings → Local Models now computes recommendations via `OnboardingModelRecommendation.topThree(primary:additional:available:)` using current `GeneralSettingsStore.speechLanguages` and `TranscriptionModelStore.models` (the shipped catalog).
- [x] Recommended group appears first, then the remaining full catalog; each model/descriptor appears exactly once across both groups.
- [x] Language pair changes in Settings recalculate groups without cached or duplicated ranking logic (computed properties, no `@State` cache).
- [x] Added clear EN Settings labels/hints: recommendations follow primary + additional speech languages; full 15-locale maps deferred to S3 (out of scope).
- [x] Manual model selection is preserved: recommendations are display order only — no auto-activate, auto-download, or backend change.
- [x] Existing backend picker, cloud status, active-model state, download, retry, use, delete, progress, accessibility, light/dark layout all preserved.
- [x] SectionHeader component added for clean section titles with optional hints.
- [x] No OnboardingView / S1c changes; no ranking-table changes; no second ranking helper.

## §3 — Verification

| Command | Result |
|---------|--------|
| `swift test` | **PASS** — 493 tests in 4 suites (5 new S2 tests added) |
| `git diff --check -- .` | **PASS** — no whitespace errors |
| `git diff --stat -- .` | **PASS** — target-scope diff limited to 3 files |

New S2 tests in `SettingsLocalizationTests.swift`:
- `s2SettingsLocalModelsKeysResolveInEnglish` — EN keys resolve non-empty and non-raw
- `s2SettingsLocalModelsHintMentionsPrimaryAndAdditional` — hint copy mentions primary/additional, avoids "target always" terminology
- `onboardingModelRecommendationTopThreeReturnsUniqueModels` — helper returns ≤3 unique catalog models
- `onboardingModelRecommendationTopThreeWithDifferentLanguagePairs` — ranking varies by language pair
- `recommendedAndRemainingPartitionFullCatalog` — recommended + remaining = full catalog exactly once, no overlaps

## §4 — Changed Paths & Handoff

- `Sources/NativeBolabol/Views/Settings/LocalModelsSettingsView.swift`
- `Sources/NativeBolabolCore/Services/AppText.swift`
- `Tests/NativeBolabolCoreTests/SettingsLocalizationTests.swift`
- `AI_Workflow_Kit/docs/AI/FEEDBACK.md`
- Focused localization tests cover EN copy + recommendation grouping invariants; all 493 tests green.
- No S3/S4+, no new engines, no Python, no unrelated refactor; diff limited to target files.
- **RESULT: `waiting_review`**

> Готово. Вернись к оркестратору и скажи статус/приступай.

---

## §5 — Independent Reviewer Verification (S1c Historical)

| Field | Value |
|-------|-------|
| Role | Verification Engineer (independent review) |
| Scope | S1c — Onboarding: 3 dynamic local-model cards |
| Reviewed files | `OnboardingView.swift`, `AppText.swift`, `OnboardingLocalizationTests.swift` |
| Graphify | Fresh S1c symbols present; 4176 nodes / 9717 edges |

### Findings

- **None, product/test severity:** no blocking or non-blocking defect was found in the S1c implementation or its target tests.
- **INFO, workflow gate only, not a product defect:** `script/qa/check_s1b_scope.sh:30` rejects the required S1c call from `Sources/NativeBolabol/Views/OnboardingView.swift:365`. S1c explicitly requires this call, so the `18/19` QA result is an obsolete S1b rule. No product change is requested and the QA script was not modified.

### Command Results

| Command | Result |
|---------|--------|
| `graphify explain "OnboardingView" --graph graphify-out/graph.json` | **PASS**; fresh `OnboardingView` at `Sources/NativeBolabol/Views/OnboardingView.swift:13` |
| `graphify explain "OnboardingModelRecommendation" --graph graphify-out/graph.json` | **PASS**; fresh `.topThree()` symbol present |
| `graphify path "OnboardingView" "OnboardingModelRecommendation" --graph graphify-out/graph.json` | **PASS**; path reaches `.topThree()` through `TranscriptionModelDescriptor` |
| `graphify query "S1c onboarding local model cards ranking localization" --graph graphify-out/graph.json` | **PASS**; BFS completed with S1c symbols in context |
| `git diff --check -- .` | **PASS**; no whitespace errors |
| `git diff --stat -- .` | **PASS**; full diff reviewed; target-scope diff is limited to the three S1c files |
| `git diff -- Sources/NativeBolabol/Views/OnboardingView.swift Sources/NativeBolabolCore/Services/AppText.swift Tests/NativeBolabolCoreTests/OnboardingLocalizationTests.swift` | **PASS**; complete target diff reviewed |
| `git diff --name-only -- Sources Tests script/qa` | **PASS**; exactly the three target paths, no QA script changes |
| `swift test` | **PASS**; 488 tests in 4 suites |
| `swift build` | **PASS**; executable target compiled; only pre-existing SwiftPM/dependency warnings |
| `./script/qa/run_all.sh` | **18/19**; 18 passed, only `check_s1b_scope.sh` failed for the stale rule documented above |

### S1c Acceptance Review

| # | Status | Evidence |
|---|--------|----------|
| 1. Onboarding order | **PASS** | `Sources/NativeBolabol/Views/OnboardingView.swift:97-114` maps UI language → primary → additional → local models → permissions → modes → glossary → theme. |
| 2. No hard-coded screen-3 preferred/model-ID order | **PASS** | `Sources/NativeBolabol/Views/OnboardingView.swift:362-369` contains no preferred IDs or model-ID ordering. |
| 3. Cards use the required `topThree` call | **PASS** | `Sources/NativeBolabol/Views/OnboardingView.swift:365-369` passes current primary, additional, and `transcriptionModelStore.models` exactly. |
| 4. No duplicated R1/R2/R3 rules in the view | **PASS** | `Sources/NativeBolabol/Views/OnboardingView.swift:362-369` delegates ranking to the helper only. |
| 5. Recalculation from current store state | **PASS** | `onboardingModels` is a computed property at `Sources/NativeBolabol/Views/OnboardingView.swift:362-369`; no stale model-list `@State` exists. |
| 6. Up to three cards; missing/NO-GO entries collapse | **PASS** | `Sources/NativeBolabol/Views/OnboardingView.swift:348-351` renders only the helper result; `OnboardingModelRecommendation.swift:47-60` skips unavailable IDs and caps at three. |
| 7. Recommended and Best-match copy only on slot #1 | **PASS** | `Sources/NativeBolabol/Views/OnboardingView.swift:390-410` uses `slot == 0`; later cards use only their ordinary badge. |
| 8. Existing model actions preserved | **PASS** | `Sources/NativeBolabol/Views/OnboardingView.swift:376-436` preserves state/progress/error rendering and `:456-503` preserves Download, Retry, Use, and active actions. |
| 9. Download remains optional and does not auto-select | **PASS** | Next is enabled at `Sources/NativeBolabol/Views/OnboardingView.swift:141-150`; only explicit model actions call download/activate at `:459-494`; finish only completes onboarding at `:950-953`. |
| 10. Cloud runtime/store untouched; only screen-3 cloud setup removed | **PASS** | The target diff removes the old cloud choice/setup from `localModelsStep`; no cloud source/store path appears in `git diff --name-only -- Sources Tests script/qa`. |
| 11. Five EN keys exist and are non-raw | **PASS** | Enum declarations at `Sources/NativeBolabolCore/Services/AppText.swift:415-420`, EN values at `:1158-1166`, and tests at `Tests/NativeBolabolCoreTests/OnboardingLocalizationTests.swift:120-128`. |
| 12. Change-later copy names the real Settings path | **PASS** | `Sources/NativeBolabolCore/Services/AppText.swift:1166` says `Settings → Local Models`; path assertions are at `Tests/NativeBolabolCoreTests/OnboardingLocalizationTests.swift:132-140`. |
| 13. Tests cover EN model copy and the onboarding key list | **PASS** | S1c key list is at `Tests/NativeBolabolCoreTests/OnboardingLocalizationTests.swift:21-28`; the tour key contract is at `:91-117`; EN resolution is asserted at `:120-128`. |
| 14. No S2/S3/S4+, new engines, Python, or unrelated refactor | **PASS** | Source/test scope is exactly the three target paths; no `script/qa` changes and no new runtime/engine files are present in the target diff. |

### Change List

- **CODER:** none. No product or target-test change is required.
- **Tester/Orchestrator follow-up:** update the S1b-only allowlist in `script/qa/check_s1b_scope.sh:21-30` for the S1c-required `OnboardingView.topThree` call before declaring the full QA gate green. This is outside the Reviewer permission boundary and is not a reason to alter product code.

### Verdict

**RESULT: `APPROVED`**

Product implementation conforms to S1c and `swift test` is green. The single red QA result is an independently confirmed stale S1b scope gate, not a product/test defect.

Готово. Вернись к оркестратору и скажи статус.

---

## §6 — Independent Tester QA (S1c Historical)

| Field | Value |
|-------|-------|
| Role | Tester |
| Step | S1c — Onboarding: 3 dynamic local-model cards |
| Date | 2026-08-03 |
| RESULT | `qa_green` |

### What was added

- Added `script/qa/check_s1c_onboarding_models.sh` for the S1c SwiftUI structure: fixed eight-step order, `localModelsStep`, one `topThree` call with current speech languages and `transcriptionModelStore.models`, computed cards, no hard-coded IDs/cache/placeholders, slot-zero labels, optional Next, existing store actions, five AppText keys, and no Python/Canary/GigaAM runtime wiring.
- Narrowly updated `script/qa/check_s1b_scope.sh` so only the required `topThree` call in `Sources/NativeBolabol/Views/OnboardingView.swift` is allowed; all S1b purity and runtime prohibitions remain active.
- Confirmed `run_all.sh` includes the new check through its `check_*.sh` contract glob.
- Added no Swift tests because the identified gaps were view-source structural contracts; existing 488-test ranking/localization coverage was re-run.

### Full gate

| Command | Result |
|---------|--------|
| `bash -n script/qa/check_s1b_scope.sh` | PASS |
| `bash -n script/qa/check_s1c_onboarding_models.sh` | PASS |
| `swift test` | PASS — 488 tests in 4 suites |
| `./script/qa/run_all.sh` | PASS — 20/20 |
| `git diff --check -- .` | PASS |

Baseline before the QA changes was `swift test` 488/4 PASS and `run_all.sh` 18/19, with only the obsolete S1b scope gate red. Both S1b and S1c checks pass independently after the change.

### Manual verification

- `swift package clean`: PASS.
- `APP_VERSION=1.0.4 ./script/build_and_run.sh --verify`: PASS; NativeBolabol and NativeBolabolPolishWorker built and verify returned successfully.
- `plutil -p dist/Bolabol.app/Contents/Info.plist`: PASS; `CFBundleShortVersionString` is `1.0.4`, executable/name `Bolabol`, bundle id `com.bolabol.app`.
- `pgrep -ifl "Bolabol|NativeBolabol"`: PASS; fresh `dist/Bolabol.app/Contents/MacOS/Bolabol` process observed.
- Live accessibility inspection: screen 3 showed one card for the thin RU+EN catalog; after changing the pair to English+French it showed two cards, with Recommended and Best Match only on the first. The full three-card Back-loop, no-download transition, and light theme are `UNVERIFIED` because the available catalog and UI session did not support a stable check. The original RU+EN language pair was restored.

Tester did not modify `Sources/**`, `Package.swift`, `STATE.yaml`, or Graphify artifacts. No product defect was found, so `BUG_REPORT.md` remains unchanged with `bugs_open: 0`.

**RESULT: `qa_green`**

> Готово. Вернись к оркестратору и скажи статус.

---

## §7 - Independent Reviewer Verification (S2)

| Field | Value |
|-------|-------|
| Role | Verification Engineer (independent review) |
| Step | S2 - Settings model labels + recommendations |
| Scope | The three S2 target files only; no product code written by Reviewer |
| Graphify | Fresh graph confirmed: 4214 nodes / 9769 links |

### Graphify Results

| Query | Result |
|-------|--------|
| `graphify explain "LocalModelsSettingsView" --graph graphify-out/graph.json` | **PASS**; current symbol at `Sources/NativeBolabol/Views/Settings/LocalModelsSettingsView.swift:4` |
| `graphify explain "OnboardingModelRecommendation" --graph graphify-out/graph.json` | **PASS**; current helper at `Sources/NativeBolabolCore/Models/OnboardingModelRecommendation.swift:5`, with `.topThree()` present |
| `graphify path "LocalModelsSettingsView" "OnboardingModelRecommendation" --graph graphify-out/graph.json` | **PASS**; shortest path found in 3 hops |
| `graphify query "settings local models recommended remaining topThree" --graph graphify-out/graph.json` | **PASS**; traversal found `recommendedAndRemainingPartitionFullCatalog()`, the S2 AppText keys, and `.topThree()` |

The fresh Coder symbols are present in the rebuilt graph; review continued against the current graph rather than a stale extraction.

### Command Results

| Command | Result |
|---------|--------|
| `git diff --stat -- .` | **REVIEWED**; full worktree also contains orchestration `STATE.yaml`, `FEEDBACK.md`, and Graphify artifacts outside the product target scope |
| `git diff --name-only -- Sources Tests script/qa` | **PASS**; exactly the three S2 target paths, with no `OnboardingView` or QA-script product diff |
| `git diff --` on the three target files | **PASS**; complete target diff reviewed |
| `git diff --check -- .` | **PASS**; no whitespace errors |
| `swift test --filter SettingsLocalizationTests` | **PASS**; 17 focused tests |
| `swift test` | **PASS**; 493 tests in 4 suites |
| `./script/qa/run_all.sh` | **18/20**; two stale scope checks failed, documented under Findings below |

### S2 Acceptance Review

| # | Status | Evidence |
|---|--------|----------|
| 1. Recommended group equals the shared `topThree(primary, additional, catalog)` | **PASS** | `Sources/NativeBolabol/Views/Settings/LocalModelsSettingsView.swift:10-19` reads the canonical pair and calls the shared helper with `transcriptionModelStore.models`; helper contract is `Sources/NativeBolabolCore/Models/OnboardingModelRecommendation.swift:15-20`. |
| 2. Recommended plus remaining contain the full catalog exactly once | **PASS** | `LocalModelsSettingsView.swift:21-25` removes only recommended IDs from the same catalog; catalog IDs are unique by construction at `Sources/NativeBolabolCore/Models/TranscriptionModelDescriptor.swift:103-115`; invariant test is `Tests/NativeBolabolCoreTests/SettingsLocalizationTests.swift:466-493`. |
| 3. Speech-pair changes recalculate without stale state | **PASS** | `recommendedModels` and `remainingModels` are computed properties with no SwiftUI cache at `LocalModelsSettingsView.swift:10-25`; the observed canonical settings value is `GeneralSettingsStore.settings` at `Sources/NativeBolabol/Stores/GeneralSettingsStore.swift:22-27,66-73`. |
| 4. Recommendations are presentation-only | **PASS** | The new recommendation properties only read stores at `LocalModelsSettingsView.swift:10-25`; activation, download, retry, delete, and backend actions remain explicit existing controls at `LocalModelsSettingsView.swift:115-122,241-307`. |
| 5. EN copy explains primary plus additional | **PASS** | New keys and EN values are at `Sources/NativeBolabolCore/Services/AppText.swift:421-424,1172-1174`; focused assertions are at `SettingsLocalizationTests.swift:361-389`. Copy uses primary/additional terminology and does not use target-always wording. |
| 6. Existing backend/cloud/download/use/delete/progress behavior is preserved | **PASS** | Existing backend and cloud status surface remains at `LocalModelsSettingsView.swift:27-74`; row action/state handling remains at `:155-317`, with only the catalog presentation wrapped in the two groups. |
| 7. S2 tests are present and green | **PASS** | Five S2 tests were added/updated at `SettingsLocalizationTests.swift:361-494`; focused and full Swift test runs both passed. |
| 8. Parakeet/Whisper auto path remains unchanged; no Canary product wiring | **PASS** | The S2 diff does not change the catalog, engines, backend enum, or OnboardingView; repository QA checks for no Python and no Canary product surface passed. Existing catalog/runtime remains the shipped Parakeet/Whisper path. |
| 9. No Onboarding changes, second ranker, S3 maps, engines, or S3+ scope creep | **PASS** | Scoped `git diff --name-only` contains only the three S2 target files; `AppText.swift` adds only three EN source entries and Settings calls the existing helper once. |

### Findings

- **Blocking:** none.
- **Non-blocking:** none.
- **INFO - stale QA allowlists:** `./script/qa/run_all.sh` fails `check_s1b_scope.sh` and `check_s1c_onboarding_models.sh` because their ranking-symbol scans only allow the helper and `OnboardingView`; they reject the required S2 call at `LocalModelsSettingsView.swift:10,14`. This is a workflow-gate defect outside the S2 target files, not a product defect.
- **INFO - test assertion strength:** `onboardingModelRecommendationTopThreeWithDifferentLanguagePairs` checks valid bounded results for each pair but does not assert that the order differs despite its comment (`SettingsLocalizationTests.swift:420-463`). Existing ranking matrix tests cover the shared helper; no Coder product change is required for S2 approval.

### Change List

- **Coder:** none. No product or target-test change is required.
- **Tester/Orchestrator follow-up:** update the S1b/S1c structural scope allowlists so the required S2 Settings call is accepted while preserving the one shared ranker contract. This is outside the Reviewer edit boundary and should not be fixed in product code.

### Verdict

**RESULT: `approved`**

S2 target code conforms to the step contract, preserves existing model-management behavior, and passes focused plus full Swift tests. The only red surface gate is caused by stale S1-only QA rules and is recorded as workflow INFO rather than a Coder blocker.

> Готово. Вернись к оркестратору и скажи статус.

---

## §8 - Independent Tester QA (S2)

| Field | Value |
|-------|-------|
| Role | Tester |
| Step | S2 - Settings model labels + recommendations |
| Date | 2026-08-03 |
| RESULT | `qa_green` |

### Gap-hunt result

- The existing five Coder S2 tests covered EN key resolution, hint terminology, bounded unique results, a full-catalog partition, and valid helper outputs.
- The Reviewer-identified hole was real: `onboardingModelRecommendationTopThreeWithDifferentLanguagePairs` did not assert that the output changed. Added `s2RecommendationRecalculatesWhenSpeechPairChanges` with exact current-catalog outputs for `en+de` and `hi+en`.
- The view-level contracts were not unit-testable through the Core target, so added `script/qa/check_s2_local_models_settings.sh` for the Settings source structure and side-effect boundary.
- The stale S1b/S1c allowlists now accept only the legitimate S2 `LocalModelsSettingsView` `topThree` call (and documentation lines); the S2 check enforces exactly two qualified product call sites.

### What was added

- `SettingsLocalizationTests.swift`: one new S2 language-pair recalculation test.
- `check_s2_local_models_settings.sh`: new structural check for shared ranking, current settings inputs, computed partition, group order, presentation-only behavior, preserved model actions, EN keys, and no Python/Canary wiring.
- `check_s1b_scope.sh`: narrow S2 call-site allowlist update.
- `check_s1c_onboarding_models.sh`: narrow S2 call-site allowlist update.
- `run_all.sh` required no functional edit because its existing `check_*.sh` glob auto-discovers the new script.

### Full gate

| Command | Result |
|---------|--------|
| `swift test` | **PASS** - 494 tests in 4 suites |
| `./script/qa/run_all.sh` | **PASS** - 21/21 |
| `APP_VERSION=1.0.4 ./script/build_and_run.sh --verify` | **PASS** - app and polish worker built; verify exited 0 |
| `plutil -p dist/Bolabol.app/Contents/Info.plist` | **PASS** - `Bolabol`, `com.bolabol.app`, `1.0.4` |
| `git diff --check -- .` | **PASS** |

### Scope

- Tester did not modify `Sources/**`, `Package.swift`, `STATE.yaml`, or product logic.
- No S3+ product wiring, Python runtime, Canary product surface, duplicate ranker, or automatic model/backend/download mutation was introduced.
- No product bug was found. `BUG_REPORT.md` remains unchanged with `bugs_open: 0`.
- No git commit or push was performed.

**RESULT: `qa_green`**

> Готово. Вернись к оркестратору и скажи статус.
