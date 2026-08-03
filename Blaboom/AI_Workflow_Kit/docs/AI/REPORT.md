# REPORT — Blaboom 1.0.3 QA

| Field | Value |
|-------|-------|
| Step | B3 — Settings UI (primary + additional) |
| Date | 2026-08-02 |
| Status | **GREEN** |
| RESULT | `qa_green` |

---

## Commands run

```bash
cd "/Users/pavan/Documents/AI Projects/Blaboom"

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

---

# Step B4 — Help EN Bilingual (Plan §8.1)

| Field | Value |
|-------|-------|
| Step | B4 — Help EN bilingual |
| Date | 2026-08-02 |
| Status | **GREEN** |
| RESULT | `qa_green` |

## Commands run

```bash
cd "/Users/pavan/Documents/AI Projects/Blaboom"

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
cd "/Users/pavan/Documents/AI Projects/Blaboom"

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

# Step B6 — Canary Core ML spike (Meta Step)

| Field | Value |
|-------|-------|
| Step | B6 — Canary spike NO-GO (review approved) |
| Date | 2026-08-03 |
| Status | **GREEN** |
| RESULT | `qa_green` |

## Commands run

```bash
cd "/Users/pavan/Documents/AI Projects/Blaboom"

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
cd "/Users/pavan/Documents/AI Projects/Blaboom"

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
cd "/Users/pavan/Documents/AI Projects/Blaboom"

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

