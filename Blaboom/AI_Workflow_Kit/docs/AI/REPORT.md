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