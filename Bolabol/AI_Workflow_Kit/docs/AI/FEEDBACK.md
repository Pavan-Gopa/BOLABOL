# FEEDBACK — Bolabol 1.0.4 (ASR Core ML)

> Workers fill sections on handoff. Orchestrator reads this every status check.

## Meta

| Field | Value |
|-------|-------|
| Step | S3 |
| Actor | coder |
| Timestamp | 2026-08-03T18:40:00Z |
| RESULT | waiting_review |

## §1 — Inventory & Pass/Fail Summary

- **Working Directory**: `/Users/pavan/Documents/AI Projects/Bolabol`
- **Required Graphify commands**: completed against `graphify-out/graph.json` (not stale):
  - `graphify explain "AppText" --graph graphify-out/graph.json` — node at `Sources/NativeBolabolCore/Services/AppText.swift L593`
  - `graphify query "AppText locale maps onboarding models settings local models" --graph graphify-out/graph.json` — 275 nodes, AppTextKey/OnboardingView/Settings families present
  - `graphify path "AppText" "OnboardingLocalizationTests" --graph graphify-out/graph.json` — 3-hop path via `.localized()`
- **Reviewed context**: AGENTS.md chain, TEAM_CONTRACT.md, STATE.yaml (read-only), S3 card, integration plan §§3.1/3.5.6/9.4, prior FEEDBACK.md S1c/S2 sections.
- **Inventory result**: of 569 EN keys, exactly **8 keys** lacked non-EN maps — all in scope (S1c onboarding model screen + S2 Settings local-models recommendation copy). All audited S1 language-step keys (`onboardingPrimaryLanguage*`, `onboardingAdditionalLanguage*`, `onboardingAdditionalSameAsPrimary`, `onboardingLanguageNote`) and B3 speech-pair keys were already 15/15; no new keys invented.
- **Locales filled** (14 non-EN maps, matching the existing 15-locale table `en, ru, es, de, fr, it, pt, zh, ja, ko, ar, hi, uk, tr, pl`): `ru, es, de, fr, it, pt, zh, ja, ko, ar, hi, uk, tr, pl`.
- **Keys touched**: `onboardingModelsTitle`, `onboardingModelsHint`, `onboardingModelsRecommended`, `onboardingModelsBestMatch`, `onboardingModelsChangeLater`, `settingsLocalModelsRecommendedTitle`, `settingsLocalModelsRecommendedHint`, `settingsLocalModelsAllTitle`.
- `STATE.yaml` was not changed. No commit, tag, or push was performed.

## §2 — S3 Implementation Compliance

- [x] All 8 in-scope keys now present in EN + 14 non-EN maps (15 total, verified by full-map scan).
- [x] Honest translations preserve meaning: recommendations follow the **primary + additional** speech-language pair; recommendations are optional display order only.
- [x] Non-EN "change later" copy names the real Settings → Local Models path using each locale's own localized section labels (`Настройки → Локальные модели`, `Ajustes → Modelos locales`, `设置 → 本地模型`, …).
- [x] No "target always" / "target output" / "always output" / "force output" framing anywhere in the new strings (terminology scan clean; only pre-existing negated EN helpBilingual references remain).
- [x] No change to ranking, Views, Stores, QA scripts, engines, catalog, or EN source strings (EN remains source of truth).
- [x] Test expansion: S1c keys resolve non-empty/non-raw in all 15 locales, differ from EN in all 14 non-EN locales, avoid forbidden terminology in every locale, and the change-later copy names the real Settings path in every locale; same set of guarantees added for the S2 keys.

## §3 — Verification

| Command | Result |
|---------|--------|
| `swift test` | **PASS** — 506 tests in 4 suites (7 new S3 tests) |
| `./script/qa/run_all.sh` | **PASS** — 21/21 |
| `git diff --check -- .` | **PASS** — no whitespace errors |
| `git diff --name-only -- Sources Tests script/qa` | **PASS** — diff limited to the 3 target files |

New S3 tests in `OnboardingLocalizationTests.swift`:
- `onboardingModelKeysResolveInEveryLanguage` — S1c keys non-empty/non-raw across all 15 locales
- `onboardingModelKeysDifferFromEnglishInEveryNonEnglishLocale` — no silent EN fallback in the 14 non-EN maps
- `onboardingModelKeysAvoidTargetAlwaysOutputTerminology` — terminology guard across all locales
- `onboardingModelsChangeLaterPointsToRealSettingsPathInEveryLocale` — localized Settings + Local Models path named in every locale

New S3 tests in `SettingsLocalizationTests.swift`:
- `s2SettingsLocalModelsKeysResolveInEveryLanguage` — S2 keys non-empty/non-raw across all 15 locales
- `s2SettingsLocalModelsKeysDifferFromEnglishInEveryNonEnglishLocale` — no silent EN fallback
- `s2SettingsLocalModelsCopyAvoidsTargetAlwaysOutputTerminology` — terminology guard across all locales

`AppTextFullCoverageTests` needed no edits: its existing `everyAppTextKeyResolvesInEveryConcreteLanguage` cartesian suite now covers the new maps automatically.

## §4 — Changed Paths & Handoff

- `Sources/NativeBolabolCore/Services/AppText.swift`
- `Tests/NativeBolabolCoreTests/OnboardingLocalizationTests.swift`
- `Tests/NativeBolabolCoreTests/SettingsLocalizationTests.swift`
- `AI_Workflow_Kit/docs/AI/FEEDBACK.md`
- S3 is strings + tests only: no ranking/View/Store/engine/catalog change, no new product features or keys, no Python, no S4+ spikes.
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

---

## §9 - Independent Reviewer Verification (S3)

| Field | Value |
|-------|-------|
| Role | Verification Engineer (independent review) |
| Step | S3 - AppText i18n × 15 |
| Scope | The four S3 target files; no product code written by Reviewer |
| Graphify | Current graph accepted; AppText and OnboardingLocalizationTests symbols are present |

### Graphify Results

| Query | Result |
|-------|--------|
| `graphify explain "AppText" --graph graphify-out/graph.json` | **PASS**; `AppText` at `Sources/NativeBolabolCore/Services/AppText.swift:593` |
| `graphify query "AppText locale maps onboarding models settings local models" --graph graphify-out/graph.json` | **PASS**; current BFS completed with 282 nodes, including AppText, locale-map and localization-test symbols |
| `graphify path "AppText" "OnboardingLocalizationTests" --graph graphify-out/graph.json` | **PASS**; 3-hop path through `.localized()` and `onboardingAndSettingsSameAsPrimaryCopyMatch()` |

The graph was not stale for the reviewed symbols, so review continued against the current extraction.

### Command Results

| Command | Result |
|---------|--------|
| `git diff --stat -- .` | **REVIEWED**; full Bolabol diff also contains orchestrator `STATE.yaml`/`FEEDBACK.md` and Graphify artifacts outside the S3 product scope |
| `git diff --name-only -- Sources Tests script/qa` | **PASS**; exactly the three changed S3 target paths; `AppTextFullCoverageTests.swift` is unchanged |
| `git diff --` on the four target files | **PASS**; AppText adds only the S3 locale strings, tests add the S3 localization assertions, and no Views/Stores/engines are touched |
| `git diff --check -- .` | **PASS**; no whitespace errors |
| `swift test` | **PASS**; 501 tests in 4 suites |

SwiftPM emitted existing dependency/resource warnings during the test build, but the build and all tests passed.

### S3 Acceptance Review

| # | Status | Evidence |
|---|--------|----------|
| 1. S1c/S2 keys have complete 15-locale maps | **PASS** | The eight-key blocks are present in EN at `AppText.swift:1166-1174` and in `ru/es/de/fr/it/pt/zh/ja/ko/ar/hi/uk/tr/pl` at `:1728-1735`, `:2302-2309`, `:2876-2883`, `:3450-3457`, `:4024-4031`, `:4598-4605`, `:5172-5179`, `:5746-5753`, `:6320-6327`, `:6894-6901`, `:7468-7475`, `:8045-8052`, `:8622-8629`, `:9199-9206`. Sentinel scans return 15 entries for both `.onboardingModelsTitle` and `.settingsLocalModelsRecommendedTitle`. |
| 2. Existing S1 language-step maps remain complete | **PASS** | `onboardingLanguageNote`, the six primary/additional title/hint/body keys, and `onboardingAdditionalSameAsPrimary` each have 15 map entries; representative entries are at `AppText.swift:1150-1164` and `:1721-1743`, with the same blocks through the remaining locale maps. |
| 3. Honest primary/additional meaning | **PASS** | New hints explicitly describe ordering/recommendations from the user's language pair; S3 assertions cover all concrete locales at `OnboardingLocalizationTests.swift:144-156` and `SettingsLocalizationTests.swift:392-404`. |
| 4. No target-always/target-output framing | **PASS** | No such framing appears in the 15-locale S3 strings; all new-locale terminology assertions pass at `OnboardingLocalizationTests.swift:179-193` and `SettingsLocalizationTests.swift:427-441`. |
| 5. EN remains source of truth | **PASS** | EN source values remain at `AppText.swift:1166-1174`; the target diff has no EN-value hunk. Existing `AppTextFullCoverageTests.swift:35-53` cartesian coverage remains unchanged. |
| 6. Change-later path is real in every locale | **PASS** | `onboardingModelsChangeLaterPointsToRealSettingsPathInEveryLocale()` checks the localized Settings and Local Models labels for all 15 locales at `OnboardingLocalizationTests.swift:197-214`; the test passed. |
| 7. No silent EN fallback | **PASS** | Full 14-locale non-EN comparisons for S1c and S2 are asserted at `OnboardingLocalizationTests.swift:160-175` and `SettingsLocalizationTests.swift:408-423`; both passed. |
| 8. Scope and prohibited work | **PASS** | The scoped name-only diff is limited to `AppText.swift`, `OnboardingLocalizationTests.swift`, and `SettingsLocalizationTests.swift`; no Python, S4+ spike, ranking, UI, View, Store, engine, catalog, or QA-script change appears in the target diff. |
| 9. Verification gate | **PASS** | `git diff --check -- .` and full `swift test` passed; `AppTextFullCoverageTests.swift` was correctly left unchanged because its existing cartesian suite covers the new maps. |

### Findings

- **Blocking:** none.
- **Non-blocking:** none.
- **INFO:** the target diff also escapes apostrophes in two pre-existing French/Turkish `helpCloudTranscriptionBody` strings (`AppText.swift:3448` and `:8620`). This is a Swift string-value no-op inside an allowed target file and does not affect the S3 verdict.

### Change List

- **Coder:** none. No product or target-test change is required.
- **Reviewer:** appended this S3 review section only; no product code, `STATE.yaml`, commit, or push was changed.

### Verdict

**RESULT: `approved`**

S3 meets the 15-locale map, terminology, fallback, Settings-path, scope, and test requirements.

> Готово. Вернись к оркестратору и скажи статус.

---

## §10 - Independent Tester QA (S3)

| Field | Value |
|-------|-------|
| Role | Tester |
| Step | S3 - AppText i18n × 15 |
| Date | 2026-08-03 |
| RESULT | `qa_green` |

### Gap-hunt result

- Coder's seven S3 localization tests covered runtime resolution, non-EN fallback detection, terminology, and the localized Settings → Local Models path for the 8 S3 keys.
- The pre-existing `check_i18n_b2_b4_families.sh` did not include the S3 family and counted entries globally rather than per locale map.
- The broad cartesian coverage did not explicitly lock the complete S1 language-step set, including `onboardingLanguageNote` and the interface-language keys.
- No product defect was found.

### What was added

- `OnboardingLocalizationTests.swift`: `s1LanguageStepKeysRemainCompleteInEveryLanguage` checks all 10 S1 language-step keys across all 15 locales for non-empty/non-raw resolution.
- `OnboardingLocalizationTests.swift`: `s1LanguageStepKeysRemainTranslatedInEveryNonEnglishLocale` checks all 14 non-EN locales for silent EN fallback.
- `script/qa/check_s3_i18n_locales.sh`: new map-aware structural check requiring exactly one entry per locale map for all 8 S3 keys and the 10 S1 regression keys, with an S3 target/output terminology guard.
- The new script is automatically wired by the existing `run_all.sh` `check_*.sh` glob; `run_all.sh` required no edit.

### Full gate

| Command | Result |
|---------|--------|
| `swift test` | **PASS** - 503 tests in 4 suites |
| `./script/qa/run_all.sh` | **PASS** - 22/22 |
| `APP_VERSION=1.0.4 ./script/build_and_run.sh --verify` | **PASS** - app and polish worker built; verify exited 0 |
| `bash -n script/qa/check_s3_i18n_locales.sh` | **PASS** |
| `bash script/qa/check_s3_i18n_locales.sh` | **PASS** - 8 S3 + 10 S1 keys in all 15 maps |
| `git diff --check -- .` | **PASS** |

### Scope and result

- Tester did not modify `Sources/**`, `Package.swift`, `STATE.yaml`, or product logic. The existing `AppText.swift` source diff is Coder-owned.
- Tester changed only the existing localization test file, the new S3 QA script, this report, and this S3 FEEDBACK section.
- `BUG_REPORT.md` remains unchanged with `bugs_open: 0`.
- No git commit or push was performed.

**RESULT: `qa_green`**

> Готово. Вернись к оркестратору и скажи статус.
