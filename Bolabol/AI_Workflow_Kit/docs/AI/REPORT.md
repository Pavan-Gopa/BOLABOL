# REPORT — Bolabol 1.0.3 QA

| Field | Value |
|-------|-------|
| Step | B3 — Settings UI (primary + additional) |
| Date | 2026-08-02 |
| Status | **GREEN** |
| RESULT | `qa_green` |

---

## Commands run

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"

# 1) Full suite
swift test
#   ✔ Test run with 461 tests in 4 suites passed

# 2) Full QA gate (unit tests + structural contract scripts)
./script/qa/run_all.sh
#   Passed: 14   Failed: 0
#   (swift test + 13 check_*.sh contracts, incl. no-secrets, localization
#    surface 549 AppText keys, stores wiring, release identity)
```

## Pass counts

- **461 tests in 4 suites** — green (455 at B2 → +6 B3 tests).
- QA gate: **14/14 steps passed** — no failures (pre-existing or B3-introduced).

## B3 coverage table

| File | Cases | Covers |
|------|-------|--------|
| `SettingsLocalizationTests.swift` | 4 tests | **B3 keys added to `settingsKeys`** (resolve in every locale via EN fallback until B5 maps); `settingsSpeechLanguageKeysResolveInEnglish` — all 7 new keys have real EN strings, no raw-key fallback; **`settingsSpeechLanguageCopyAvoidsTargetAlwaysOutputTerminology`** — no "target always" / "target output" / "always output" in any of the 7 new strings across all 15 locales (EN fallback included); every Settings key localized in every language |
| `OnboardingLocalizationTests.swift` | 7 tests | **`onboardingAndSettingsSameAsPrimaryCopyMatch`** — Settings "Same as primary" shares exact wording with onboarding (plan §6.2 / §7.1, never a forced-output frame); onboarding keys resolve in EN; onboarding copy avoids target/always-output terminology |
| `UserSpeechLanguagesTests.swift` | 20 tests | **+3 B3 tests: `settingAdditionalKeepsPrimary`** (primary untouched), **`settingAdditionalNormalizesInput`** (" FR " → fr), **`settingAdditionalToPrimaryRestoresSameAsPrimary`** (additional == primary ⇒ same-as-primary state); plus existing settingPrimary/migration/defaults/Codable coverage |
| `LanguagePickerOrderTests.swift` | 9 tests | Still green: en first, ru not second (fr is), Europe before Asia, exact canonical 15-code sequence, speech codes == UI codes (minus System), endonym display names, code/name resolution |
| `AppTextFullCoverageTests.swift` | 8 tests | Every key non-empty in EN/RU/all 15 locales; key count ≥ 400; tab labels; HUD help keys; system locale fallback |

Total B3 delta: +6 tests (UserSpeechLanguages +3, SettingsLocalization +2, OnboardingLocalization +1) on top of B2's 455 → 461 total. B3 added 7 AppText keys (542 → 549).

## B3 Must-verify checklist

1. ✅ **`swift test` full suite GREEN** — 461/461, all 4 suites passed.
2. ✅ **Settings EN keys for language pair resolve (no raw-key fallback EN)** — 7 new keys (`languagePairSectionTitle`, `primaryLanguage`, `primaryLanguageHint`, `additionalLanguage`, `additionalLanguageHint`, `additionalSameAsPrimary`, `languagePairEngineNote`) all have real EN strings ("Your Languages", "Primary language", "The language you usually dictate in.", "Additional language", "A second language you often use.", "Same as primary", engine auto-detect note); test `settingsSpeechLanguageKeysResolveInEnglish()` passes. Path Settings → Hotkey → "Your Languages" Section above the legacy engine-level block, per plan §7.1.
3. ✅ **No "target always" / "always output" in new Settings strings** — `settingsSpeechLanguageCopyAvoidsTargetAlwaysOutputTerminology()` passes across all 15 locales (EN fallback included). Actual copy is "A second language you often use." — no target/always-output compound anywhere. `onboardingAndSettingsSameAsPrimaryCopyMatch` additionally pins shared non-forced wording between onboarding and Settings.
4. ✅ **UserSpeechLanguages settingAdditional / settingPrimary tests green** — 3 new `settingAdditional*` tests pass (keep primary, normalize, restore same-as-primary); existing `settingPrimary*` mirror tests still pass. `settingAdditional` semantics verified in diff: primary untouched, additional == primary ⇒ `usesSameAdditionalAsPrimary`.
5. ✅ **LanguagePickerOrder still green** — all 9 order tests pass (canonical en→fr→de→… sequence, Europe before Asia, UI sync).
6. ✅ **Diff B3-scoped** — unstaged changes are exactly the B3 target files (`HotkeySettingsView.swift`, `UserSpeechLanguages.swift`, `AppText.swift`) + 3 test files + workflow artifacts (FEEDBACK.md, STATE.yaml) + graphify cache stamp. No Help (`HelpSettingsView.swift`), no Canary/HUD, no onboarding-view rewrite (onboarding test is a copy-consistency guard only), no `SettingsView.swift`/`GeneralSettingsView.swift`/store rewrites.
7. ✅ **`./script/qa/run_all.sh`** — 14/14 green. No failures (pre-existing or B3-introduced). Localization surface counts 549 AppText keys (up from 542 at B2, reflecting the 7 new keys). No secrets, package/targets, stores wiring, release identity, pipeline, workspace/HUD surfaces all pass.

## Notes

- `graphify-out/cache/last_query_stamp` change is a tooling artifact, not target code.
- Legacy engine-level "Recognition Language & Output" Section untouched (plan §4.1) — B3 adds the speech-language pair above it, sharing `GeneralSettingsStore.speechLanguages` with onboarding (single source of truth).
- No bugs opened. `bugs_open: 0`.

**RESULT: qa_green**

# RENAME — Tester Verification (R2)

| Field | Value |
|-------|-------|
| Step | RENAME |
| Date | 2026-08-03 |
| Status | **GREEN** |
| RESULT | `qa_green` |

## Commands run

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"

# 1) Full Swift suite
swift test
#   Test run with 473 tests in 4 suites passed

# 2) Full QA gate
./script/qa/run_all.sh
#   Passed: 18  Failed: 0

# 3) Product-surface legacy-brand gate
legacy_pattern="$(printf '\142\154\141\142\157\157\155')"
grep -riIn "$legacy_pattern" \
  Sources Tests Package.swift script AI_Workflow_Kit/docs --exclude-dir=.build || echo CLEAN
#   CLEAN

# 4) Source identity
plutil -p Sources/NativeBolabol/Resources/Info.plist | grep -E 'Name|Identifier|Executable'
#   Bolabol / com.bolabol.app / Bolabol

# 5) Optional app build verification
APP_VERSION=1.0.3 ./script/build_and_run.sh verify
plutil -p dist/Bolabol.app/Contents/Info.plist | grep -E 'Name|Identifier'
#   Bolabol / com.bolabol.app
```

## Gap-hunt

- `script/qa`: no stale brand paths or literals.
- `Tests/NativeBolabolCoreTests/ReleaseIdentityTests.swift`: no stale identity expectations; all release checks use `Bolabol` and `com.bolabol.app`.
- `script/build_and_run.sh` and `script/build_release_dmg.sh`: `APP_NAME="Bolabol"`, `BUNDLE_ID="com.bolabol.app"`, and `Bolabol.app`/`Bolabol.dmg` outputs.
- `scratch/test_persistence.swift`: fixed one stale `NativeBolabolCore` import.
- No new unit tests were required; the existing release identity tests and 473-test suite cover the rename contracts.

## Result

- Product surfaces are clean.
- Source and built app identities are consistent.
- QA suite is green: 18/18.
- No product feature changes, git commit, or push performed.

**RESULT: `qa_green`**

---

# Step S1c — Tester QA: Onboarding 3 dynamic local-model cards

| Field | Value |
|-------|-------|
| Step | S1c — Onboarding local models |
| Date | 2026-08-03 |
| Status | **GREEN** |
| RESULT | `qa_green` |
| bugs_open | 0 |

## Graphify and baseline

The supplied Graphify graph was queried read-only; no Graphify rebuild was performed.

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"

graphify explain "OnboardingView" --graph graphify-out/graph.json
# PASS — OnboardingView at Sources/NativeBolabol/Views/OnboardingView.swift:13

graphify explain "OnboardingModelRecommendation" --graph graphify-out/graph.json
# PASS — .topThree() at Sources/NativeBolabolCore/Models/OnboardingModelRecommendation.swift:16

graphify path "OnboardingView" "OnboardingModelRecommendation" \
  --graph graphify-out/graph.json
# PASS — 3-hop path through TranscriptionModelDescriptor and .topThree()

graphify query "S1c onboarding local models test coverage and regressions" \
  --graph graphify-out/graph.json
# PASS — BFS completed; 289 nodes found in the returned context
```

Graphify context supplied by the Orchestrator: **4176 nodes / 9717 edges**.

```bash
swift test
# BASELINE PASS — 488 tests in 4 suites

./script/qa/run_all.sh
# BASELINE 18/19 — only check_s1b_scope.sh failed because the old S1b
# allowlist rejected the required S1c OnboardingView.topThree call
```

## Commands and results

```bash
bash -n script/qa/check_s1b_scope.sh
# PASS

bash -n script/qa/check_s1c_onboarding_models.sh
# PASS

bash script/qa/check_s1b_scope.sh
# PASS — only the ranking helper and the S1c OnboardingView call are allowed

bash script/qa/check_s1c_onboarding_models.sh
# PASS — dynamic-card, ordering, slot, optional-action, and no-runtime contracts

swift test
# PASS — 488 tests in 4 suites

./script/qa/run_all.sh
# PASS — 20/20

git diff --check -- .
# PASS — no whitespace errors

git diff --name-only -- Sources Tests script/qa
# Sources/NativeBolabol/Views/OnboardingView.swift
# Sources/NativeBolabolCore/Services/AppText.swift
# Tests/NativeBolabolCoreTests/OnboardingLocalizationTests.swift
# script/qa/check_s1b_scope.sh
# script/qa/run_all.sh
# The new check_s1c_onboarding_models.sh is untracked, so it is confirmed by
# git status rather than git diff --name-only.
```

## New and changed QA coverage

| Path | Change | Coverage |
|------|--------|----------|
| `script/qa/check_s1c_onboarding_models.sh` | **NEW** | Fixed eight-screen order; screen 3 `localModelsStep`; exactly one UI `topThree`; current primary/additional/store arguments; computed list; slot-zero labels; optional Next; store actions; five AppText keys; no placeholder/runtime wiring |
| `script/qa/check_s1b_scope.sh` | **UPDATED** | Narrowly permits the required `topThree` call only in `Sources/NativeBolabol/Views/OnboardingView.swift`; retains pure-helper, engine/store/process, Canary/GigaAM, and runtime prohibitions |
| `script/qa/run_all.sh` | **UPDATED** | Documents that the `check_*.sh` glob includes the dedicated S1c contract |
| `Tests/NativeBolabolCoreTests/OnboardingModelRecommendationTests.swift` | Existing coverage re-run | R1/R2/R3 matrix, normalization, missing/NO-GO collapse, empty catalog, fallbacks, duplicate suppression, and three-card cap |
| `Tests/NativeBolabolCoreTests/OnboardingLocalizationTests.swift` | Existing coverage re-run | Five S1c EN keys, tour key set, and real `Settings -> Local Models` path |

No additional Swift tests were needed: the remaining gaps were SwiftUI source-structure invariants, now guarded by the dedicated S1c check. No product source or Package.swift file was modified by Tester.

## Gap-hunt mapping

| S1c acceptance | Test / QA guard |
|----------------|-----------------|
| Fixed order of eight onboarding screens | `check_s1c_onboarding_models.sh`: `totalSteps = 8` and `case 0...6` / `default` mapping |
| Screen 3 uses `localModelsStep` | `check_s1c_onboarding_models.sh` adjacency check |
| Exactly one UI call to `topThree` | `check_s1c_onboarding_models.sh` count = 1; updated `check_s1b_scope.sh` call-site allowlist |
| Arguments use current primary, additional, and store models | `check_s1c_onboarding_models.sh` checks `primaryLanguageCode`, `additionalLanguageCode`, and `transcriptionModelStore.models` in the call block |
| No hard-coded preferred IDs/model-ID ranking | `check_s1c_onboarding_models.sh` rejects preferred-ID/ranking patterns, product IDs, fixed slots, and placeholders |
| Computed list with no stale `@State`/cache | `check_s1c_onboarding_models.sh` requires computed `onboardingModels` and rejects SwiftUI state/cache declarations |
| Recommended and Best Match only on slot #1 | `check_s1c_onboarding_models.sh` requires both keys inside `if slot == 0`; UI accessibility showed both only on the first of two cards |
| Next is not blocked by a missing download | `check_s1c_onboarding_models.sh` rejects a step-3 disable gate; source review confirms the Next button has no download prerequisite |
| Enter/exit without selection preserves backend and `activeModelID` | `check_s1c_onboarding_models.sh` checks the `finish()` block for no backend/activation/download mutation; explicit model actions remain separate |
| Download/Retry/Use continue through the existing store | `check_s1c_onboarding_models.sh` requires store-backed download, retry, activate, progress, and failed-state paths |
| Five EN AppText keys exist | Existing `OnboardingLocalizationTests` plus `check_s1c_onboarding_models.sh` enum/source-map checks |
| Change-later copy names Settings -> Local Models | `onboardingModelsChangeLaterPointsToRealSettingsPath()` |
| Missing/NO-GO entries collapse without placeholders | Existing `OnboardingModelRecommendationTests` collapse/empty/fallback cases plus dynamic `ForEach(onboardingModels.enumerated())` guard |
| No S2/S3/S4+, new engines, Python, or Canary/GigaAM runtime | `check_s1c_onboarding_models.sh`, `check_s1b_scope.sh`, `check_no_python_in_sources.sh`, `check_no_canary_product.sh`, package/target checks, and scoped diff review |

## Clean build and manual UI verification

```bash
swift package clean
# PASS

APP_VERSION=1.0.4 ./script/build_and_run.sh --verify
# PASS — NativeBolabol and NativeBolabolPolishWorker built; --verify returned 0

plutil -p dist/Bolabol.app/Contents/Info.plist
# PASS — CFBundleName/Executable = Bolabol, bundle id = com.bolabol.app,
# CFBundleShortVersionString = 1.0.4

pgrep -ifl "Bolabol|NativeBolabol"
# PASS — fresh dist/Bolabol.app/Contents/MacOS/Bolabol process observed
```

Manual UI result:

| Scenario | Result |
|----------|--------|
| Screen 3 opens with dynamic local-model cards | **PASS** — accessibility inspection showed `Whisper Large v3 Full`; the thin available catalog correctly produced one card for the initial RU + EN pair |
| Change primary/additional and recompute | **PASS, partial** — changing primary to English and additional to French before advancing changed screen 3 to two cards: `Whisper Large v3 Full` and `Whisper Large v3 Turbo` |
| Recommended / Best Match only on first visible card | **PASS** — accessibility values showed both labels for the first card; the second card had neither |
| Full Back -> change -> Forward reorder loop across a three-card catalog | **UNVERIFIED** — the current catalog exposed at most two usable cards and the UI accessibility session became unstable during the return loop |
| Continue without downloading a model | **UNVERIFIED** — the observed card was already active; structural QA confirms no step-3 download gate |
| Dark theme layout | **PASS** — onboarding screen rendered without visible clipping in the available dark appearance |
| Light theme layout | **UNVERIFIED** — not claimed because the UI session did not provide a stable second-theme check |

The app was relaunched only after the successful clean build. The manual language changes were restored to the original Russian primary / English additional pair before handoff. No screenshots are used as acceptance evidence; the UI claims above are based on live accessibility/static-text inspection, with unavailable scenarios explicitly marked `UNVERIFIED`.

## Scope and result

- `Sources/**` was not modified by Tester. The existing S1c product diff remains the Coder's diff.
- `Package.swift`, `STATE.yaml`, and product implementation files were not modified by Tester.
- `graphify-out/**` was not rebuilt or edited as a QA artifact.
- No commit, tag, or push was performed.
- `BUG_REPORT.md` was not changed because no product defect was found; `bugs_open: 0` is accurate.

**RESULT: `qa_green`**

---

# Step S1 — Onboarding language steps (ASR Core ML 1.0.4)

| Field | Value |
|-------|-------|
| Step | S1 — Onboarding language UX |
| Date | 2026-08-03 |
| Status | **GREEN** |
| RESULT | `qa_green` |

## Commands run

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"

# 1) Full unit test suite
swift test
#   ✔ Test run with 473 tests in 4 suites passed after 0.040 seconds
#   (471 at S1 review → +2 Tester gap tests)

# 2) Full QA gate (unit tests + structural contract scripts)
./script/qa/run_all.sh
#   Passed: 18   Failed: 0
```

## Pass counts

- **473 tests in 4 suites** — green (471 at reviewer approval → +2 S1 Tester tests).
- QA gate: **18/18 steps passed** — no failures (pre-existing or S1-introduced).

## S1 Must-verify checklist

1. ✅ **`swift test` GREEN (~471)** — 471/471 at review state re-ran clean; 473/473 after Tester gap tests. All 4 suites passed.
2. ✅ **`./script/qa/run_all.sh`** — 18/18 passed (incl. `check_localization_surface.sh`, `check_no_canary_product.sh`, `check_no_python_in_sources.sh`).
3. ✅ **EN onboarding keys for UI / primary / additional resolve (no raw-key)** — `onboardingSpeechLanguageKeysResolveInEnglish()` + `onboardingKeysUsedByWelcomeTourAllExist()` green; all `onboarding*` keys non-empty and never the raw key across all 15 locales (`everyOnboardingKeyIsLocalizedInEveryLanguage`).
4. ✅ **No "target always output" / "always force output" in new onboarding speech copy** — `onboardingSpeechLanguageCopyAvoidsTargetAlwaysOutputTerminology()` now also asserts **"force output"** and **"always force"** (previously only target/always-output compounds) across all 15 locales. Verified manually: the only "force output" hits in AppText are pre-existing `helpHUDLeftLetter`/`helpHUDLeftTap`/`helpHUDControlLanguage` HUD-letter help copy — a different surface, not the onboarding speech steps.
5. ✅ **Diff scoped to S1** — `git diff --stat -- Sources Tests`: only `OnboardingView.swift` (+7/−4, `.settingAdditional(...)` refactor), `AppText.swift` EN map (+5/−8, UI/primary/additional copy + Settings hints), and Tester's `OnboardingLocalizationTests.swift`. No engines, no Canary/GigaAM, no S1b ranking.

## New tests added (S1 Tester delta)

| File | Test | Covers |
|------|------|--------|
| `OnboardingLocalizationTests.swift` | **NEW `onboardingSpeechLanguageBodiesPointToRealSettingsSections`** | S1 req 4 — EN primary/additional bodies + UI-language note contain the "change this later in Settings" promise, and the path segments match the **real** Settings section labels (`.settingsHotkey` = "Hotkey", `.languagePairSectionTitle` = "Your Languages", `.settingsGeneral` = "General") so copy can never point at a nonexistent settings path. |
| `OnboardingLocalizationTests.swift` | **NEW `onboardingChooseLanguageStepSeparatesUiFromDictation`** | S1 req 1 — EN Step-0 title says "interface"; the hint says UI-only and that dictation is unaffected; hint avoids target / force-output / always-output wording. |
| `OnboardingLocalizationTests.swift` | **EXTENDED `onboardingSpeechLanguageCopyAvoidsTargetAlwaysOutputTerminology`** | Added "force output" + "always force" to the forbidden-compound scan over the 7 B2 keys × 15 locales. |

## Gap-hunt mapping

| Gap-hunt idea | Status |
|---------------|--------|
| Assert EN strings for primary/additional include Settings path hints | **Added** — `onboardingSpeechLanguageBodiesPointToRealSettingsSections` (hint + real section-label match, not just any "Settings" mention). |
| Terminology test re-run; extend if hole | **Extended** — "force output" / "always force" compounds were not covered by the existing test (only target/always-output); added to the 15-locale scan. No hits in any onboarding key; HUD-help hits are pre-existing and out of scope. |
| UI language decoupled from speech languages (S1 req 1) | **Added** — `onboardingChooseLanguageStepSeparatesUiFromDictation` (title = interface; hint = UI-only, dictation unaffected). |
| settingAdditional persistence / same-as-primary | **No-gap** — `settingAdditionalKeepsPrimary` / `settingAdditionalNormalizesInput` / `settingAdditionalToPrimaryRestoresSameAsPrimary` (UserSpeechLanguagesTests) + `onboardingAndSettingsSameAsPrimaryCopyMatch` already cover the S1 picker change (`.settingAdditional(...)` in `OnboardingView`). |

## Notes

- Tester made **no product changes** (`Sources/**` untouched beyond the already-present S1 diff) and **no git commit/push**.
- Diff-scope verified: only the 2 S1 target files + Tester test file are modified in `Sources/`/`Tests/`.
- No bugs opened. `bugs_open: 0`.

**RESULT: qa_green**

---

| Field | Value |
|-------|-------|
| Step | B4 — Help EN bilingual |
| Date | 2026-08-02 |
| Status | **GREEN** |
| RESULT | `qa_green` |

## Commands run

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"

# 1) Full suite
swift test
#   ✔ Test run with 467 tests in 4 suites passed (+6 from B3)

# 2) Full QA gate (unit tests + structural contract scripts)
./script/qa/run_all.sh
#   Passed: 14   Failed: 0
```

## Pass counts

- **467 tests in 4 suites** — green (461 at B3 → +6 B4 tests).
- QA gate: **14/14 steps passed** — no failures.

## B4 coverage table

| File | Cases | Covers |
|------|-------|--------|
| `SettingsLocalizationTests.swift` | +2 tests | **NEW: `helpBilingualSettingsPathMentionsHotkeyAndYourLanguages`** — `helpBilingualSettingsPath` contains "Hotkey" and "Your Languages"; **NEW: `helpLangHelpHUDConsistentWithBilingualModel`** — spot-check that `helpLangForced`, `helpHUDLeftLetter`, `helpHUDControlLanguage`, `helpLangWhere` don't contradict bilingual model (additional = second language, not target-always-output); existing: `helpBilingualKeysResolveInEnglish` (12 keys, no raw-key fallback), `helpBilingualCopyAvoidsUnnegatedTargetAlwaysOutputTerminology` (no unnegated "target always output"), `helpBilingualCopyDescribesPrimaryAndAdditionalModel` (primary + additional described, canary no-A, polish-after-text) |
| `AppTextFullCoverageTests.swift` | 8 tests | Still green: every key non-empty in EN/RU/all 15 locales; `appTextBilingualHelpKeysExistAndDocumentLanguages` validates bilingual help keys |
| `check_localization_surface.sh` | 1 check | `help*` key family ≥ 10 keys (covers 12 helpBilingual* + existing helpLang/helpHUD/helpCloud*) |

Total B4 delta: +2 tests (SettingsLocalization +2) on top of B3's 461 → 467 total. 12 `helpBilingual*` keys already present in AppTextKey (B4 product code claimed).

## B4 Must-verify checklist

1. ✅ **All 12 `helpBilingual*` EN resolve (no raw-key)** — `helpBilingualKeysResolveInEnglish()` passes for all 12 keys: `Title`, `Intro`, `Primary`, `Additional`, `NotAlwaysOutput`, `Where`, `Onboarding`, `SettingsPath`, `Canary`, `HUD`, `AutoEngines`, `PolishNote`. `appTextBilingualHelpKeysExistAndDocumentLanguages` also confirms.
2. ✅ **Unnegated "target always output" forbidden; negation OK** — `helpBilingualCopyAvoidsUnnegatedTargetAlwaysOutputTerminology()` passes across all 15 locales. The phrase appears only in `helpBilingualNotAlwaysOutput` with explicit negation: "not a 'target always output' model".
3. ✅ **Primary + additional model described in helpBilingual copy** — `helpBilingualCopyDescribesPrimaryAndAdditionalModel()`: `Intro` contains "primary language" + "additional language"; `Primary` describes primary = usual dictation language; `Additional` describes additional = second language for HUD letter switching.
4. ✅ **Settings path string includes Hotkey / Your Languages** — NEW test `helpBilingualSettingsPathMentionsHotkeyAndYourLanguages()` passes: `helpBilingualSettingsPath` = "Settings → Hotkey → Your Languages."
5. ✅ **Canary no-A / letter cycle mentioned (copy-level)** — `helpBilingualCopyDescribesPrimaryAndAdditionalModel()` checks `Canary` contains "canary" + ("no a" or "does not have an a"). Actual copy: "Canary (when available) does not have an A mode. The HUD left button cycles directly between your primary and additional language letters (e.g., E ↔ S). No auto-detect fallback."
6. ✅ **Polish-after-text note present** — `helpBilingualCopyDescribesPrimaryAndAdditionalModel()` checks `PolishNote` contains "polishing" + "after transcription". Actual copy: "Polishing (MLX or cloud) runs after transcription, not on Canary. It improves the text in whatever language the transcript is in — it does not change the language."
7. ✅ **helpLang*/helpHUD EN not contradicting bilingual model (spot)** — NEW test `helpLangHelpHUDConsistentWithBilingualModel()` passes: `helpLangForced` mentions "additional language" and avoids "target always output"; `helpHUDLeftLetter` mentions "additional language"; `helpHUDControlLanguage` describes A = auto, letter = force; `helpLangWhere` references "Hotkey" + "Your Languages".
8. ✅ **AppTextFullCoverage / localization surface still green** — `everyAppTextKeyResolvesInEveryConcreteLanguage()` passes (0 gaps); `check_localization_surface.sh` reports 561 AppText keys.
9. ✅ **helpBilingual* keys exist in AppTextKey enum** — verified by test resolution (all 12 keys resolve) and `check_localization_surface.sh` `help*` family ≥ 10 keys.

## Notes

- No product source changes required — all 12 `helpBilingual*` keys and their EN strings already present in `AppText.swift` (B4 product work complete).
- 2 tests added to `SettingsLocalizationTests.swift` to close gap-hunt items 4 and 7.
- No bugs opened. `bugs_open: 0`.

**RESULT: qa_green**

---

# Step B5 — i18n × 15 (Plan §9)

| Field | Value |
|-------|-------|
| Step | B5 — i18n × 15 UI languages |
| Date | 2026-08-03 |
| Status | **GREEN** |
| RESULT | `qa_green` |

## Commands run

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"

# 1) Full suite
swift test
#   ✔ Test run with 470 tests in 4 suites passed (+3 from B4's 467)

# 2) Full QA gate (unit tests + structural contract scripts)
./script/qa/run_all.sh
#   Passed: 15   Failed: 0
#   (swift test + 14 check_*.sh contracts — NEW check_i18n_b2_b4_families.sh)

# 3) New i18n family structural check (standalone re-run)
bash script/qa/check_i18n_b2_b4_families.sh
#   OK: 36 B2–B4/helpLang/helpHUD keys present in all 15 locale maps
```

## Pass counts

- **470 tests in 4 suites** — green (467 at B4 → +3 B5 Tester tests).
- QA gate: **15/15 steps passed** (14 pre-existing + 1 new script) — no failures.

## B5 coverage table

| File | Cases | Covers |
|------|-------|--------|
| `SettingsLocalizationTests.swift` | 10 tests | **NEW `helpLangHelpHUDDifferFromEnglishInEveryNonEnglishLocale`** — all 10 helpLang*/helpHUD* keys differ from EN in **all 14** non-EN locales (was EN spot-check only); **NEW `helpLangHelpHUDCopyAvoidsUnnegatedTargetAlwaysOutputInEveryLocale`** — no unnegated "target always output" / "target output" / "always output" in any of 15 locales; **NEW `primaryAdditionalTerminologyDistinctInSampleLocales`** — ru/zh/ar/tr primary ≠ additional labels, same-as-primary distinct phrase shared verbatim between onboarding and Settings; existing `settingsKeysAreActuallyTranslatedBeyondEnglish` **loop expanded** from ru/zh/ar/hi to all 14 non-EN locales |
| `OnboardingLocalizationTests.swift` | 7 tests | `newlyAddedOnboardingKeysAreActuallyTranslated` **loop expanded** from ru/zh/ar/hi to all 14 non-EN locales (B2 keys + onboarding legacy keys) |
| `AppTextFullCoverageTests.swift` | 8 tests | Still green: every key non-empty in EN/RU/all 15 locales; `everyAppTextKeyResolvesInEveryConcreteLanguage` (full cartesian, 0 gaps) |
| `ArchiveStatsLocalizationTests.swift` | 5 tests | Unchanged, green: tr positional `%1$@`/`%2$d` order guards + tr/ja/ko/hi no-crash format checks |
| `check_i18n_b2_b4_families.sh` | **NEW** script | Structural: all 36 B2/B3/B4/helpLang/helpHUD keys literally present in every one of the 15 locale maps of AppText.swift (runtime resolution already guarded by Swift tests) |

Total B5 Tester delta: **+3 tests, +1 QA script** (467 → 470).

## B5 Must-verify checklist

1. ✅ **Full keys × 15 locales: non-empty, never raw-key** — `everyAppTextKeyResolvesInEveryConcreteLanguage()` green (re-run, no changes needed); `check_localization_surface.sh` reports 561 AppText keys.
2. ✅ **B2/B3/B4 families differ from EN in ALL 14 non-EN locales** — Reviewer-flagged 4-locale hole closed: `newlyAddedOnboardingKeysAreActuallyTranslated` and `settingsKeysAreActuallyTranslatedBeyondEnglish` now iterate every non-EN concrete language (B2 7 keys + B3 7 keys + B4 12 keys). Independent pre-verification (parser over all 15 maps): 0 missing / 0 empty / 0 raw-key / **0 identical-to-EN** across all 14 non-EN locales.
3. ✅ **helpLang*/helpHUD* non-EN: no unnegated "target always output"** — NEW all-locale terminology test + NEW all-14 differ test over the 10 rewritten keys (`helpLangIntro/Auto/Forced/EnglishNote/OtherNote/Where` + `helpHUDLeftA/LeftLetter/LeftTap/ControlLanguage`). Independent scan: 0 hits of the forbidden phrases in any locale; every non-EN locale carries a real translation.
4. ✅ **Terminology primary/additional in sample locales (ru, zh, ar, tr)** — NEW `primaryAdditionalTerminologyDistinctInSampleLocales`: labels distinct per locale ("Основной язык"/"Дополнительный язык", "主要语言"/"附加语言", "اللغة الأساسية"/"اللغة الإضافية", "Birincil dil"/"Ek dil"), same-as-primary is a distinct phrase, onboarding and Settings share it verbatim.
5. ✅ **Archive stats format regressions still green** — `ArchiveStatsLocalizationTests` unchanged and green (tr/ja/ko/hi `%d`/`%@` crash guards incl. tr positional `%1$@`/`%2$d`).
6. ✅ **script/qa structural family check** — NEW `check_i18n_b2_b4_families.sh` proves each of 36 B2–B4/helpLang/helpHUD keys exists in all 15 locale maps (36 × 15 = 540 entries, all present); wired into `run_all.sh` (15/15).
7. ✅ **`./script/qa/run_all.sh`** — 15/15 green. No failures (pre-existing or B5-introduced).

## Notes

- Tester made **no product changes** (`Sources/**` untouched). Test-only edits: 2 loop expansions + 3 new tests + 1 new QA script.
- Reviewer's "non-EN differ guards iterate only ru/zh/ar/hi" note is now a permanent test contract — all 14 non-EN locales are guarded.
- No bugs opened. `bugs_open: 0`.

**RESULT: qa_green**

---

# Step B12 — Tester confirmation (independent re-verify of build 1.0.3)

| Field | Value |
|-------|-------|
| Step | B12 — Test build 1.0.3 (independent Tester confirmation) |
| Date | 2026-08-03 |
| Status | **GREEN** |
| RESULT | `qa_green` |

## Commands run (independent re-run)

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"

# 1) Full unit test suite
swift test
#   ✔ Test run with 471 tests in 4 suites passed

# 2) Full QA gate (unit tests + structural contract scripts)
./script/qa/run_all.sh
#   Passed: 18   Failed: 0

# 3) Version check — dev app bundle
plutil -p dist/Bolabol.app/Contents/Info.plist | grep ShortVersion
#   CFBundleShortVersionString => "1.0.3"   (CFBundleVersion "202608031018")

# 4) Version check — release app bundle
plutil -p dist/release/Bolabol.app/Contents/Info.plist | grep ShortVersion
#   CFBundleShortVersionString => "1.0.3"   (CFBundleVersion "1")

# 5) Artifact presence / recency / size
ls -la dist/Bolabol.dmg dist/Bolabol.app dist/release/Bolabol.app dist/handoff/
#   dist/Bolabol.dmg  26,388,418 bytes  2026-08-03 10:32

# 6) Optional: codesign identity
codesign -dv --verbose=2 dist/release/Bolabol.app 2>&1 | head -8
#   Authority=Developer ID Application: Stichting Kadamba Foundation (438UQRF7JV)

# 7) Optional: SHA256 handoff verification
shasum -a 256 dist/Bolabol.dmg dist/handoff/Bolabol.dmg dist/handoff/install.sh
#   matches dist/handoff/SHA256SUMS.txt entries exactly
```

## Must-verify checklist (Tester re-verify)

1. ✅ **`swift test` GREEN** — 471/471 tests in 4 suites passed (matches ~471 claim).
2. ✅ **`./script/qa/run_all.sh` GREEN** — 18/18 steps passed, 0 failed.
3. ✅ **`dist/Bolabol.app` version** — `CFBundleShortVersionString` = `1.0.3` (plutil verified).
4. ✅ **`dist/release/Bolabol.app` version** — `CFBundleShortVersionString` = `1.0.3` (plutil verified).
5. ✅ **`dist/Bolabol.dmg`** — exists, 26,388,418 bytes (~25 MB, non-trivial), timestamp 2026-08-03 10:32 (recent).
6. ✅ **REPORT B12 section complete** — artifacts table, version confirmation, smoke matrix M1–M3/M7–M10 PASS, M4–M6 N/A (ADR-012 Canary NO-GO), notarization optional skip noted.
7. ✅ **No Canary product ship claim** — `docs/RELEASE_NOTES.md` "Honest Engine Status": Canary 1B Core ML marked NO-GO, "not shipped in 1.0.3".

## Optional verification

- **Codesign:** `dist/release/Bolabol.app` signed with `Developer ID Application: Stichting Kadamba Foundation (438UQRF7JV)`, runtime flag, arm64 Mach-O — matches REPORT claims.
- **SHA256 handoff:** `dist/handoff/SHA256SUMS.txt` present; recomputed hashes match exactly — `Bolabol.dmg` `768c8f55eaac25bf990123fbdb2186961dfa98edf6518f3f9fee0accb547fc4c` (identical in `dist/` and `dist/handoff/`), `install.sh` `09a1a33f247587720ba084a1628d249410db5647a87ef2c5d6e15881f2f40d31`.
- Notarization not re-run (optional skip per step; Developer ID signed and ready).

## Gap-hunt mapping

| Gap-hunt idea | Status |
|---------------|--------|
| Verify handoff SHA256SUMS.txt against actual artifacts | **No-gap** — recomputed `shasum -a 256` for both DMG copies + install.sh matches the handoff file exactly; no new script needed. |
| Extra unit tests for release step | **No-gap** — release step is artifact/plist/checksum verification, already covered by the 471-test suite + 18-check QA gate + the above plutil/shasum/codesign re-verify. Suite + artifacts solid. |

## Notes

- Tester made **no product changes** (`Sources/**`, `Package.swift` untouched) and **no git commit/push**.
- Artifacts verified as-is; **no rebuild performed** (nothing broken).
- No bugs opened. `bugs_open: 0`.

**RESULT: qa_green**


# Step B6 — Canary Core ML spike (Meta Step)

| Field | Value |
|-------|-------|
| Step | B6 — Canary spike NO-GO (review approved) |
| Date | 2026-08-03 |
| Status | **GREEN** |
| RESULT | `qa_green` |

## Commands run

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"

# 1) Full suite
swift test
#   ✔ Test run with 470 tests in 4 suites passed (expectation ~470 met)

# 2) Full QA gate (unit tests + structural contract scripts)
./script/qa/run_all.sh
#   Passed: 16   Failed: 0
#   (swift test + 15 check_*.sh contracts — NEW check_b6_canary_spike.sh)

# 3) Spike contract check (standalone re-run)
bash script/qa/check_b6_canary_spike.sh
#   OK: B6 spike docs-only NO-GO + zero-Python harness contracts hold

# 4) Optional harness rebuild + short ASR run (models present under scratch/)
xcrun swiftc -O -parse-as-library -o scratch/canary-spike/bin/CanarySpike docs/canary/harness/CanarySpike.swift
scratch/canary-spike/bin/CanarySpike scratch/canary-spike/audio/en_short.wav task=asr src=en tgt=en modelRoot=scratch/canary-spike/models
#   transcript: "To the other, to the other, …" (119 tokens, EOS: false) —
#   reproduces spike defect D5 (degenerate loop, no content) exactly as documented.
```

## Pass counts

- **470 tests in 4 suites** — green (470 at B5, no delta; spike is docs-only).
- QA gate: **16/16 steps passed** (15 pre-existing + 1 new B6 script) — no failures.

## B6 coverage table

| File | Cases | Covers |
|------|-------|--------|
| `check_b6_canary_spike.sh` | **NEW** script | Structural contracts: `docs/canary/COREML_SPIKE.md` exists + `/NO-GO/i` verdict + defects D1–D5 + Recommendation section; `docs/canary/harness/CanarySpike.swift` exists + zero Python invocation path (`python3`/`python`/`pip`/`pip3`/`nemo`/`/usr/bin/env`/`Process(`/`executableURL`/`launchPath`), literal "Python" tolerated only in `//` comments |
| Manual verification | — | `swift test` 470 green; harness rebuild + ASR run reproduces D5; `git status -- Sources Tests` clean |

Total B6 Tester delta: **+1 QA script** (no Swift tests needed — spike is a docs-only meta step with no product code surface to unit-test).

## B6 Must-verify checklist

1. ✅ **`swift test` full suite GREEN (~470)** — `✔ Test run with 470 tests in 4 suites passed` (exact 470, matches B5 baseline and the ~470 expectation).
2. ✅ **`./script/qa/run_all.sh` GREEN** — `Passed: 16  Failed: 0` (15 pre-existing + new `check_b6_canary_spike.sh`).
3. ✅ **No Sources/** product Canary integration** — `git status --short -- Sources Tests` empty; `git diff --stat -- Sources` empty; the only "canary" hits in `Sources/**` are pre-existing B4 i18n copy strings (`helpBilingualCanary` in `AppText.swift`, surfaced in `HelpSettingsView.swift`) — UI help text about a future engine, no Core ML/engine code.
4. ✅ **COREML_SPIKE.md present + contents** — exists; contains `Status: NO-GO`; defect table D1–D5 with evidence; zero-Python pipeline (native Swift/CoreML/Accelerate harness, `swiftc -O -parse-as-library`, no Package target); Recommendation section (do not integrate alexwengg/canary-1b-v2-coreml; keep WhisperKit; FluidInference/FluidAudio or mlx as alternatives; disk-budget note).
5. ✅ **CanarySpike.swift has no Python invocations** — grep clean for `python3`/`python`/`pip`/`pip3`/`nemo`/`Process(`/`executableURL`/`launchPath`/`/usr/bin/env`; the single "Python" token is the header comment "pure Swift, no Python"; imports are only Accelerate/CoreML/Foundation.
6. ✅ **Optional harness rebuild + short ASR run** — models present under `scratch/canary-spike/models/` (1.8 GB, gitignored), so the harness was rebuilt and `en_short.wav` (2.50 s < 4.09 s cap) ran: preprocessor 250 mel frames, encoder `encoded_lengths_out=4992` (matches D3), decoder produced the documented 119-token degenerate loop without EOS (matches D5). The NO-GO verdict reproduces on re-run.

## Gap-hunt mapping

| Gap-hunt idea | Status |
|---------------|--------|
| Unit test or qa script: `docs/canary/COREML_SPIKE.md` exists + `/NO-GO/i` | **Added** — part of `check_b6_canary_spike.sh` (+ D1–D5 + Recommendation) |
| qa script: `docs/canary/harness/CanarySpike.swift` exists + greps clean for python\|Python\|pip\|nemo | **Added** — `check_b6_canary_spike.sh` (invocation patterns rejected; comment-only "Python" allowed) |
| No multi-GB model downloads in CI-style runs | Respected — models already local; script only greps files, never downloads |

## Notes

- Tester made **no product changes** (`Sources/**` untouched) and **no git commit/push**.
- Harness rebuild verified the spike's own reproduction command works; behavior confirmed unchanged (D3/D5 as documented).
- `scratch/canary-spike/` remains gitignored per the spike's disk-budget note (delete decision is the orchestrator's, not the tester's).
- No bugs opened. `bugs_open: 0`.

**RESULT: qa_green**

---

# Step B11 — QA suite consolidation (Plan §11 step 11 / §12.1)

| Field | Value |
|-------|-------|
| Step | B11 — QA suite consolidation |
| Date | 2026-08-03 |
| Status | **GREEN** |
| RESULT | `qa_green` |

## Commands run

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"

# 1) Full unit test suite
swift test
#   ✔ Test run with 471 tests in 4 suites passed (+1 B11 test)

# 2) Full QA gate (unit tests + structural contract scripts)
./script/qa/run_all.sh
#   Passed: 17   Failed: 0
#   (swift test + 16 check_*.sh contracts — NEW check_no_python_in_sources.sh)

# 3) New Python contract check
./script/qa/check_no_python_in_sources.sh
#   OK: Sources/ is 100% native Swift with zero Python files or runtime invocations
```

## Pass counts

- **471 tests in 4 suites** — green (+1 new test `nativeTranscriptionCatalogDoesNotContainCanaryProductOrBackend`).
- QA gate: **17/17 steps passed** (16 pre-existing + 1 new script `check_no_python_in_sources.sh`) — 0 failures.

## B11 coverage table

| Area | Status | Test / Script Guard |
|------|--------|---------------------|
| Language pair migration | **GREEN** | `UserSpeechLanguagesTests.swift` (B1) |
| Picker order (en first; ru not #2; europe before asia) | **GREEN** | `LanguagePickerOrderTests.swift` (B1) |
| Onboarding/settings/help keys × 15 locales | **GREEN** | `AppTextFullCoverageTests.swift`, `OnboardingLocalizationTests.swift`, `SettingsLocalizationTests.swift`, `check_i18n_b2_b4_families.sh` (B2–B5) |
| Canary product absence (no false capabilities) | **GREEN** | `check_b6_canary_spike.sh`, `TranscriptionModelCatalogTests.swift` (`nativeTranscriptionCatalogDoesNotContainCanaryProductOrBackend`) |
| HUD cycle primary↔additional | **GREEN** | `HUDProviderSwitcherFeatureTests.swift`, `HUDLayoutAndComposerTests.swift` |
| ASR/AST routing matrix | **GREEN** | `TranscriptionLanguageRoutingTests.swift`, `StarterGlossaryAndLanguageRoutingTests.swift` |
| Archive stats format regression (tr/ja/ko/hi) | **GREEN** | `ArchiveStatsLocalizationTests.swift` |
| No Python in Sources | **GREEN** | `script/qa/check_no_python_in_sources.sh` (**NEW**), `check_b6_canary_spike.sh` |

## B11 Must-verify checklist

1. ✅ **`swift test` full suite GREEN** — 471/471 tests passed across 4 suites.
2. ✅ **`./script/qa/run_all.sh` GREEN** — 17/17 steps passed (16 check_*.sh scripts + swift test).
3. ✅ **No Python in Sources** — `script/qa/check_no_python_in_sources.sh` created, executable, and passing. Zero `.py` files and zero binary/process spawning in `Sources/`.
4. ✅ **Canary product catalog absence asserted** — `nativeTranscriptionCatalogDoesNotContainCanaryProductOrBackend` unit test added to `TranscriptionModelCatalogTests.swift` and passing.
5. ✅ **COVERAGE.md updated** — §12.1 matrix updated for 1.0.3 train status.
6. ✅ **RELEASE_NOTES.md updated** — honest Canary status (NO-GO pending Core ML export improvements) and 1.0.3 bilingual primary/additional feature highlights added.

**RESULT: qa_green**

---

# Step B11 re-verification — QA suite consolidation (Tester re-run, gap-hunt)

| Field | Value |
|-------|-------|
| Step | B11 — QA suite consolidation (independent re-verify) |
| Date | 2026-08-03 |
| Status | **GREEN** |
| RESULT | `qa_green` |

## Commands run (independent re-run)

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"

# 1) Full unit test suite
swift test
#   ✔ Test run with 471 tests in 4 suites passed (matches claim ~471+)

# 2) Full QA gate (unit tests + structural contract scripts)
./script/qa/run_all.sh
#   Passed: 18   Failed: 0
#   (swift test + 17 check_*.sh contracts — NEW check_no_canary_product.sh)

# 3) Python contract check (standalone)
./script/qa/check_no_python_in_sources.sh
#   OK: Sources/ is 100% native Swift with zero Python files or runtime invocations

# 4) Canary catalog test (isolated)
swift test --filter nativeTranscriptionCatalogDoesNotContainCanaryProductOrBackend
#   ✔ passed (1/1)
```

## §12.1 ↔ real guard mapping (verified, no holes)

| Plan §12.1 row | Guard (verified exists + green) |
|----------------|--------------------------------|
| Language pair migration | `UserSpeechLanguagesTests.swift` (B1) |
| Picker order: en first; ru not #2; europe before asia | `LanguagePickerOrderTests.swift` (B1) |
| All new onboarding/settings/help keys × 15 langs | `AppTextFullCoverageTests.swift`, `OnboardingLocalizationTests.swift`, `SettingsLocalizationTests.swift`, `check_i18n_b2_b4_families.sh` (B2–B5) |
| Canary capabilities.supportsAuto == false (ADR-012: no product Canary ⇒ absence) | `nativeTranscriptionCatalogDoesNotContainCanaryProductOrBackend` + `check_b6_canary_spike.sh` + **`check_no_canary_product.sh`** |
| HUD cycle primary↔additional | `HUDProviderSwitcherFeatureTests.swift`, `HUDLayoutAndComposerTests.swift` |
| ASR vs AST routing from primary/additional/active | `TranscriptionLanguageRoutingTests.swift`, `StarterGlossaryAndLanguageRoutingTests.swift` |
| Archive stats format regression (tr/ja/ko/hi) | `ArchiveStatsLocalizationTests.swift` |
| No Python imports in Sources | `script/qa/check_no_python_in_sources.sh` |

## Gap-hunt mapping

| Gap-hunt idea | Status |
|---------------|--------|
| Assert Package.swift / Sources have no canary product module name | **Added** — NEW `script/qa/check_no_canary_product.sh`: zero case-insensitive "canary" in `Package.swift` (products/targets/deps); in `Sources/**` canary allowed ONLY in `AppText.swift` i18n maps or `helpBilingual*` key references (verified all 62 hits are `AppText.swift` help-copy or `HelpSettingsView.swift` rendering `.helpBilingualCanary`). Wired into `run_all.sh` (auto-glob): 17 → 18/18. |
| Expand catalog test if other catalog enums could list canary | **No-gap** — enumerated all catalog types in Sources: `TranscriptionModelCatalog` (guarded by unit test), `PolishingModelCatalog`, `CloudProviderModelCatalog` (providers openAI/qwen/openRouter/custom/anthropic/google — no canary), `GlossaryLanguageCatalog` (language codes). Zero canary case/entry in any non-AppText source. No expansion needed. |
| RELEASE_NOTES honesty spot-read | **No-gap** — `docs/RELEASE_NOTES.md` §"Honest Engine Status": Canary 1B Core ML marked NO-GO (precision loss, audio-length scaling limits, degenerate repetition loops), "not shipped in 1.0.3", WhisperKit/Parakeet remain primary. Honest. |
| COVERAGE.md §12.1 rows match real guards | **No-gap** — all 8 plan rows map to existing files/scripts (table above); COVERAGE.md row "Canary product absence" updated to include the new script. |

## Must-verify checklist (re-run)

1. ✅ `swift test` — 471/471 green.
2. ✅ `./script/qa/run_all.sh` — 18/18 green (17 pre-existing + NEW `check_no_canary_product.sh`).
3. ✅ `check_no_python_in_sources.sh` standalone — OK.
4. ✅ `nativeTranscriptionCatalogDoesNotContainCanaryProductOrBackend` present (`TranscriptionModelCatalogTests.swift:83`) and green in isolation + suite.
5. ✅ COVERAGE.md §12.1 rows ↔ real tests/scripts — all 8 mapped, no orphans.
6. ✅ RELEASE_NOTES Canary NO-GO — honest, spot-read verified.

## Notes

- Tester made **no product changes** (`Sources/**`, `Package.swift` untouched) and **no git commit/push**.
- Delta this re-verify: +1 QA script (`check_no_canary_product.sh`), docs only (COVERAGE.md, REPORT.md, FEEDBACK.md).
- No bugs opened. `bugs_open: 0`.

**RESULT: qa_green**

---

# Step B12 — Test build 1.0.3 (LAST)

| Field | Value |
|-------|-------|
| Step | B12 — Test build 1.0.3 (LAST) |
| Date | 2026-08-03 |
| Status | **GREEN** |
| RESULT | `qa_green` |

## Commands run

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"

# 1) Full unit test suite
swift test
#   ✔ Test run with 471 tests in 4 suites passed after 0.052 seconds

# 2) Full QA gate (unit tests + structural contract scripts)
./script/qa/run_all.sh
#   Passed: 18   Failed: 0

# 3) Build and verify dev app bundle (version 1.0.3)
APP_VERSION=1.0.3 ./script/build_and_run.sh verify
#   Build of product 'NativeBolabol' complete!
#   dist/Bolabol.app created; Info.plist CFBundleShortVersionString = 1.0.3

# 4) Build release DMG package (version 1.0.3, build 1)
APP_VERSION=1.0.3 APP_BUILD=1 ./script/build_release_dmg.sh
#   DMG created at dist/Bolabol.dmg (25 MB)
#   Signed with identity: Developer ID Application: Stichting Kadamba Foundation (438UQRF7JV)

# 5) Optional WhisperKit Tiny smoke script
./script/smoke_whisperkit_tiny.sh
#   Skipped / Blocked: missing fixture /Users/pavan/Documents/AI Projects/jfk.wav (code 2)
```

## Produced Artifacts & Evidence

| Artifact | Path | Size | Timestamp | Identity / Checksum |
|----------|------|------|-----------|--------------------|
| Dev App Bundle | `dist/Bolabol.app` | — | 2026-08-03 10:18 | Ad-hoc / Local (CFBundleShortVersionString 1.0.3) |
| Release App Bundle | `dist/release/Bolabol.app` | — | 2026-08-03 10:32 | Developer ID Application: Stichting Kadamba Foundation (438UQRF7JV) |
| Release DMG | `dist/Bolabol.dmg` | ~25 MB | 2026-08-03 10:32 | Developer ID Application: Stichting Kadamba Foundation (438UQRF7JV) |
| Handoff DMG | `dist/handoff/Bolabol.dmg` | ~25 MB | 2026-08-03 10:32 | SHA256: `768c8f55eaac25bf990123fbdb2186961dfa98edf6518f3f9fee0accb547fc4c` |
| Handoff Script | `dist/handoff/install.sh` | — | 2026-08-03 10:32 | SHA256: `09a1a33f247587720ba084a1628d249410db5647a87ef2c5d6e15881f2f40d31` |
| Checksums File | `dist/handoff/SHA256SUMS.txt` | — | 2026-08-03 10:32 | Verified present |

## Version Confirmation
- `Sources/NativeBolabol/Resources/Info.plist`: `CFBundleShortVersionString` = `1.0.3`
- `script/build_and_run.sh`: `APP_VERSION` default `1.0.3`, outputs `CFBundleShortVersionString` `1.0.3` into `dist/Bolabol.app/Contents/Info.plist`
- `script/build_release_dmg.sh`: `APP_VERSION` default `1.0.3`, outputs `CFBundleShortVersionString` `1.0.3` into `dist/release/Bolabol.app/Contents/Info.plist`
- `docs/RELEASE.md`: release commands specify `APP_VERSION=1.0.3`
- `docs/RELEASE_NOTES.md`: version `1.0.3 (build 1)` documented

## Smoke & Manual Matrix Verification (M1–M10)

- **App Launch & Smoke:** `./script/build_and_run.sh verify` launched `dist/Bolabol.app`, confirmed active process. Bundle version verified as `1.0.3`.
- **Notarization Status:** Skipped as OPTIONAL (Developer ID codesigned, ready for notarization via `script/notarize_dmg.sh` or `NOTARIZE=1` when Apple ID credentials configured on build machine).
- **M1–M3, M7–M10 Manual Matrix:** Confirmed GREEN / PASS.
- **M4–M6 Manual Matrix:** N/A (ADR-012 Canary Core ML marked NO-GO, omitted from product train 1.0.3 per plan).

## Pass counts

- **471 tests in 4 suites** (`swift test`) — green.
- **18/18 QA gate checks** (`./script/qa/run_all.sh`) — green.
- **Zero Python dependency** in `Sources/` (`check_no_python_in_sources.sh`).
- **No Canary product code** (`check_no_canary_product.sh`).
- **No git commit / push**.

**RESULT: qa_green**

---

# Step S1b — Tester QA: OnboardingModelRecommendation ranking

| Field | Value |
|-------|-------|
| Step | S1b — Ranking pure function |
| Date | 2026-08-03 |
| Status | **GREEN** |
| RESULT | `qa_green` |

## Commands run

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"

graphify query "OnboardingModelRecommendation topThree TranscriptionModelDescriptor" --graph graphify-out/graph.json
# PASS — BFS query completed against graphify-out/graph.json

swift test
# Test run with 486 tests in 4 suites passed

./script/qa/run_all.sh
# Passed: 19  Failed: 0

swift package clean
APP_VERSION=1.0.4 ./script/build_and_run.sh --verify
# Build of product 'NativeBolabol' complete; --verify returned successfully

pgrep -x Bolabol
# running Bolabol process observed after the fresh build

plutil -p dist/Bolabol.app/Contents/Info.plist
# CFBundleShortVersionString => "1.0.4"
```

## Pass counts

- **486 tests in 4 suites** — green (481 baseline; +5 new S1b tests).
- QA gate: **19/19 steps passed** — 0 failures.
- Fresh app build and launch verification: **PASS**; `Bolabol.app` opened only after both product builds completed and `--verify` confirmed the process.
- Manual ranking-helper UI verification: **N/A**; S1b has no visible UI state. Fresh application launch was verified instead.

## New tests added

| File | Test | Covers |
|------|------|--------|
| `OnboardingModelRecommendationTests.swift` | `onboardingModelRecommendationUsesCanaryFlashForEveryCompactLanguagePair` | All `en/de/fr/es` primary/additional combinations with Canary Flash, Large v3, Turbo order |
| `OnboardingModelRecommendationTests.swift` | `onboardingModelRecommendationUsesR3OrderForOtherLanguagePairs` | Non-compact `zh+en` R3 order: Large v3, Turbo, Canary 1B |
| `OnboardingModelRecommendationTests.swift` | `onboardingModelRecommendationNormalizesRussianAdditionalLanguageCode` | Case/whitespace normalization when Russian is additional |
| `OnboardingModelRecommendationTests.swift` | `onboardingModelRecommendationCapsResultAtThreeModels` | Explicit maximum-three invariant |
| `OnboardingModelRecommendationTests.swift` | `onboardingModelRecommendationAcceptsOnlySpeechLanguageInputs` | Compile-time API guard: only primary, additional, catalog; no UI language input |

`onboardingModelRecommendationDoesNotReturnDuplicateModels` was strengthened to assert the exact R1 output while the catalog contains a duplicate ID.

## Gap-hunt mapping

| # | Requirement | Guard |
|---|-------------|-------|
| 1 | R1: Russian primary or additional puts GigaAM first | `onboardingModelRecommendationMatchesLanguageMatrix`; `onboardingModelRecommendationAppliesRussianRuleWhenAdditionalIsRussian` |
| 2 | `ru+en` and `ru+ru` matrix | `onboardingModelRecommendationMatchesLanguageMatrix` |
| 3 | R2 `en/de/fr/es`: Canary Flash, Large v3, Turbo | `onboardingModelRecommendationUsesCanaryFlashForEveryCompactLanguagePair` |
| 4 | `en+es`, `en+en`, `de+fr` matrix | `onboardingModelRecommendationMatchesLanguageMatrix` |
| 5 | R3 other pairs: Large v3, Turbo, available fallback | `onboardingModelRecommendationUsesR3OrderForOtherLanguagePairs`; `onboardingModelRecommendationUsesParakeetWhenCanary1BIsUnavailable`; `onboardingModelRecommendationUsesFlashAsFinalR3Fallback` |
| 6 | `hi+en` matrix | `onboardingModelRecommendationMatchesLanguageMatrix`; `onboardingModelRecommendationCapsResultAtThreeModels` |
| 7 | Russian only in additional | `onboardingModelRecommendationAppliesRussianRuleWhenAdditionalIsRussian`; `onboardingModelRecommendationNormalizesRussianAdditionalLanguageCode` |
| 8 | Language-code case and whitespace normalization | `onboardingModelRecommendationNormalizesSpeechLanguageCodes`; `onboardingModelRecommendationNormalizesRussianAdditionalLanguageCode` |
| 9 | Missing GigaAM shifts available models upward | `onboardingModelRecommendationCollapsesMissingGigaAM` |
| 10 | Missing Canary 1B uses next available fallback | `onboardingModelRecommendationUsesParakeetWhenCanary1BIsUnavailable` |
| 11 | Empty catalog returns `[]` | `onboardingModelRecommendationReturnsEmptyForEmptyCatalog` |
| 12 | Duplicate IDs do not duplicate output | `onboardingModelRecommendationDoesNotReturnDuplicateModels` |
| 13 | Result is capped at three | `onboardingModelRecommendationCapsResultAtThreeModels` |
| 14 | Ranking is independent of UI language | `onboardingModelRecommendationAcceptsOnlySpeechLanguageInputs`; `check_s1b_scope.sh` confirms no UI call site |
| 15 | No S1c UI, engine wiring, or Canary/GigaAM runtime integration | `check_s1b_scope.sh`; `check_no_canary_product.sh`; `check_package_and_targets.sh` all passed |

## Scope and notes

- Tester changed only `Tests/**`, `script/qa/**`, this report, and FEEDBACK §6. No `Sources/**` product code was changed by Tester.
- `check_no_canary_product.sh` now permits the S1b ranking helper's model IDs only; `check_s1b_scope.sh` rejects UI/runtime imports, engine/store/process wiring, ranking call sites outside the helper, and ASR candidate references outside the helper or existing help copy.
- No S1c UI, engine wiring, or Canary/GigaAM runtime integration was added.
- `BUG_REPORT.md` was not changed; no product bugs found. `bugs_open: 0`.

**RESULT: `qa_green`**

---

# Step S2 - Tester QA: Settings model labels + recommendations

| Field | Value |
|-------|-------|
| Step | S2 - Settings Local Models |
| Date | 2026-08-03 |
| Status | **GREEN** |
| RESULT | `qa_green` |
| bugs_open | 0 |

## Graphify context

```bash
graphify explain "LocalModelsSettingsView" --graph graphify-out/graph.json
# PASS - current Settings view and store/helper references found

graphify query "settings local models recommended remaining topThree" \
  --graph graphify-out/graph.json
# PASS - Settings call site, recommendation helper, partition test, and S2 keys found
```

## Commands run

```bash
swift test
# PASS - 494 tests in 4 suites

./script/qa/run_all.sh
# PASS - 21/21 (swift test + 20 check_*.sh contracts)

APP_VERSION=1.0.4 ./script/build_and_run.sh --verify
# PASS - NativeBolabol and NativeBolabolPolishWorker built; --verify exited 0

plutil -p dist/Bolabol.app/Contents/Info.plist
# PASS - Bolabol / com.bolabol.app / 1.0.4

git diff --check -- .
# PASS - no whitespace errors
```

## New tests and QA scripts

| Path | Change | Coverage |
|------|--------|----------|
| `Tests/NativeBolabolCoreTests/SettingsLocalizationTests.swift` | **NEW `s2RecommendationRecalculatesWhenSpeechPairChanges`** | Proves the same catalog produces different, pair-specific results for compact `en+de` and broad `hi+en` pairs, closing the Reviewer-noted weak assertion. |
| `script/qa/check_s2_local_models_settings.sh` | **NEW** | One shared Settings `topThree` call with the canonical pair/catalog; computed recommendation and remaining properties; full-catalog partition; recommended-before-remaining order; presentation-only mutation guard; preserved manual model actions; EN keys; exactly two product call sites; Python/Canary guards. |
| `script/qa/check_s1b_scope.sh` | **UPDATED** | Narrowly allows the exact S2 Settings call and comments while retaining pure-helper and runtime prohibitions. |
| `script/qa/check_s1c_onboarding_models.sh` | **UPDATED** | Narrowly allows the exact S2 Settings call while retaining the S1c onboarding contract. |

The new `check_s2_*.sh` script is automatically included by the existing
`run_all.sh` `check_*.sh` glob; `run_all.sh` itself required no functional change.

## Gap-hunt mapping

| S2 requirement | Guard |
|----------------|-------|
| Recommended group equals shared `topThree(primary, additional, catalog)` | `check_s2_local_models_settings.sh` verifies the sole Settings call uses `GeneralSettingsStore.speechLanguages` and `TranscriptionModelStore.models`; existing ranking matrix and `onboardingModelRecommendationTopThreeReturnsUniqueModels` re-run. |
| Recommended plus remaining equals the full catalog exactly once | `recommendedAndRemainingPartitionFullCatalog`; S2 structural check verifies ID removal from the current catalog and group order. |
| Speech-pair changes recalculate without stale state | NEW `s2RecommendationRecalculatesWhenSpeechPairChanges`; S2 check requires computed properties and rejects state/cache declarations. |
| No recommendation auto-activates, downloads, or changes backend | S2 check rejects mutation calls inside recommendation computation and requires explicit existing download/use/delete/progress paths. |
| EN keys are real and the hint mentions primary/additional without target-always wording | `s2SettingsLocalModelsKeysResolveInEnglish`; `s2SettingsLocalModelsHintMentionsPrimaryAndAdditional`; full localization suite remains green. |
| Settings and onboarding call sites are allowlisted with one shared ranker | Updated S1b/S1c checks plus S2 exact two-call-site check; `run_all.sh` green. |
| No Python, Canary product wiring, or S3+ product scope | `check_no_python_in_sources.sh`, `check_no_canary_product.sh`, package/target checks, and scoped diff review; no Tester edits to `Sources/**`, `Package.swift`, or `STATE.yaml`. |
| Reviewer INFO on different language pairs | Closed with the exact-output NEW S2 recalculation test rather than leaving a non-differentiating assertion. |

## Scope and result

- Tester changed only `Tests/NativeBolabolCoreTests/SettingsLocalizationTests.swift`, `script/qa/check_s1b_scope.sh`, `script/qa/check_s1c_onboarding_models.sh`, `script/qa/check_s2_local_models_settings.sh`, this report, and FEEDBACK §8.
- Existing Coder S2 changes in `Sources/NativeBolabol/Views/Settings/LocalModelsSettingsView.swift` and `Sources/NativeBolabolCore/Services/AppText.swift` were not modified by Tester.
- `STATE.yaml`, `BUG_REPORT.md`, `Package.swift`, and Graphify source artifacts were not edited by Tester. No commit or push was performed.
- No product defect was found; `BUG_REPORT.md` remains at `bugs_open: 0`.

**RESULT: `qa_green`**

---

# Step S3 — Tester QA: AppText i18n × 15

| Field | Value |
|-------|-------|
| Step | S3 — AppText localization |
| Date | 2026-08-03 |
| Status | **GREEN** |
| RESULT | `qa_green` |
| bugs_open | 0 |

## Graphify context

The required read-only Graphify queries were run against `graphify-out/graph.json`:

```bash
graphify explain "AppText" --graph graphify-out/graph.json
# PASS — AppText at Sources/NativeBolabolCore/Services/AppText.swift:593

graphify query "AppText locale maps onboarding models settings local models" \
  --graph graphify-out/graph.json
# PASS — AppText, locale maps, onboarding, Settings, and localization tests found
```

## Gap-hunt result

- Existing Coder S3 tests covered runtime resolution, EN-fallback detection, terminology, and the localized Settings → Local Models path for all 8 S3 keys.
- The structural family check still covered only B2–B4/helpLang/helpHUD; it did not include the 8 S3 keys.
- The existing structural check counted entries globally, so it did not prove one entry per specific locale map.
- Existing broad coverage did not provide an explicit S1 language-step regression list including `onboardingLanguageNote` and the interface-language keys.

## Commands and results

```bash
swift test
# PASS — 503 tests in 4 suites

./script/qa/run_all.sh
# PASS — 22/22 (unit tests + 21 check_*.sh contracts)

APP_VERSION=1.0.4 ./script/build_and_run.sh --verify
# PASS — NativeBolabol and NativeBolabolPolishWorker built; --verify exited 0

bash -n script/qa/check_s3_i18n_locales.sh
bash script/qa/check_s3_i18n_locales.sh
# PASS — 8 S3 keys + 10 S1 language-step keys in all 15 locale maps

git diff --check -- .
# PASS — no whitespace errors
```

SwiftPM emitted the existing dependency identity and unhandled-resource warnings; they did not affect the green build or test result.

## New tests and QA scripts

| Path | Change | Coverage |
|------|--------|----------|
| `Tests/NativeBolabolCoreTests/OnboardingLocalizationTests.swift` | **NEW `s1LanguageStepKeysRemainCompleteInEveryLanguage`** | Explicitly checks the 10 S1 interface/primary/additional language-step keys for non-empty, non-raw resolution across all 15 concrete locales. |
| `Tests/NativeBolabolCoreTests/OnboardingLocalizationTests.swift` | **NEW `s1LanguageStepKeysRemainTranslatedInEveryNonEnglishLocale`** | Detects a silent EN fallback for every S1 language-step key in all 14 non-EN locales. |
| `script/qa/check_s3_i18n_locales.sh` | **NEW** | Isolates each concrete locale dictionary and requires exactly one entry per map for all 8 S3 keys and the 10-key S1 regression family; also scans S3 entries for forbidden English target/output framing. Automatically included by the existing `run_all.sh` `check_*.sh` glob. |

`AppTextFullCoverageTests.swift` needed no edit: its existing cartesian key × locale suite continues to cover runtime non-empty/non-raw resolution for every AppText key.

## Gap-hunt mapping

| S3 requirement | Guard |
|----------------|-------|
| Every S3 key appears in every one of the 15 locale maps | NEW `check_s3_i18n_locales.sh`, map-aware `8 × 15` structural check. |
| Runtime values are non-empty and non-raw | Existing `AppTextFullCoverageTests` plus Coder's S3 resolution tests; full suite passed. |
| No silent EN fallback for S3 keys | Existing all-14 non-EN S1c/S2 comparison tests; full suite passed. |
| No target-always/output framing | Existing all-locale S3 Swift terminology tests plus the source-map-scoped S3 script guard. |
| Change-later copy names the real localized Settings → Local Models path | Existing `onboardingModelsChangeLaterPointsToRealSettingsPathInEveryLocale`. |
| S1 language-step maps remain complete | NEW S1 Swift regression tests plus the script's `10 × 15` structural check. |
| Localization surface remains intact | Existing `check_localization_surface.sh`; 569 AppText keys and all 15 UI languages pass. |
| No product scope creep | Existing no-Python/no-Canary/package/surface checks pass; Tester did not modify `Sources/**`, `Package.swift`, or `STATE.yaml`. |

## Scope and result

- Tester added only test coverage in the existing `OnboardingLocalizationTests.swift`, the new `script/qa/check_s3_i18n_locales.sh`, this report, and FEEDBACK §10.
- The only `Sources/**` path remains the pre-existing Coder `AppText.swift` localization diff; no product code was changed by Tester.
- `STATE.yaml`, `BUG_REPORT.md`, `Package.swift`, and product implementation files were not edited by Tester. No commit or push was performed.
- No product defect was found; `BUG_REPORT.md` remains at `bugs_open: 0`.

**RESULT: `qa_green`**
