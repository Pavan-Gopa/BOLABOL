# REPORT — Blaboom 1.0.3 QA

| Field | Value |
|-------|--------|
| Step | B2 — Onboarding primary + additional |
| Date | 2026-08-02 |
| Status | **GREEN** |
| RESULT | `qa_green` |

---

## Commands run

```bash
cd "/Users/pavan/Documents/AI Projects/Blaboom"

# 1) Full suite
swift test
#   ✔ Test run with 455 tests in 4 suites passed

# 2) Full QA gate (unit tests + structural contract scripts)
./script/qa/run_all.sh
#   Passed: 14   Failed: 0
#   (swift test + 13 check_*.sh contracts, incl. no-secrets, localization
#    surface 542 AppText keys, stores wiring, release identity)
```

## Pass counts

- **455 tests in 4 suites** — green.
- QA gate: **14/14 steps passed** — no pre-existing failures.

## B2 coverage table

| File | Cases | Covers |
|------|-------|--------|
| `OnboardingLocalizationTests.swift` | 7 tests | Every onboarding key localized in every language; newly added keys actually translated (ru/zh/ar/hi); all tour-used keys exist with EN translation; **B2 speech-language keys resolve in EN** (no raw-key fallback); **no "target always" / "target output" / "always output" in onboarding copy** across all 15 locales; glossary explanation avoids internal terms |
| `UserSpeechLanguagesTests.swift` | 17 tests | Defaults map known system locales; fallback en for unknown; additional may equal primary (same-as-primary policy); **settingPrimary keeps same-as-primary mirror** (B2 §6.2); **settingPrimary keeps explicit additional**; **settingPrimary normalizes input**; sameAsPrimary helper mirrors; normalizes codes; migration from legacy codes/names/endonyms; never duplicates target into primary; ignores unknown legacy; Codable round-trip; legacy payload without keys |
| `LanguagePickerOrderTests.swift` | 9 tests | en first (excl. System); ru not second (index 1 == fr); Europe before Asia (ru < zh); System sentinel placement; **speech codes == UI codes minus System** (B2 picker sync); exact canonical sequence; endonym display names; code/name resolution |
| `AppTextFullCoverageTests.swift` | 8 tests | Every key non-empty in EN/RU/all 15 locales; key count ≥ 400; tab labels; note workspace labels; HUD help keys; system locale fallback |

Total B2 delta: +6 new tests (3 in UserSpeechLanguages, 2 in OnboardingLocalization, 1 in LanguagePickerOrder) on top of B1's 449 → 455 total.

## B2 Must-verify checklist

1. ✅ **`swift test` full suite GREEN** — 455/455, all 4 suites passed.
2. ✅ **Onboarding EN keys for primary/additional resolve** — 7 new keys (`onboardingPrimaryLanguageTitle/Hint/Body`, `onboardingAdditionalLanguageTitle/Hint/Body`, `onboardingAdditionalSameAsPrimary`) all have real EN strings ("Primary language", "The language you usually dictate in.", etc.); test `onboardingSpeechLanguageKeysResolveInEnglish()` passes — no raw-key fallback.
3. ✅ **No "target always" / "always output" terminology in onboarding strings** — test `onboardingSpeechLanguageCopyAvoidsTargetAlwaysOutputTerminology()` passes across all 15 locales. Code-comment mentions ("Copy never calls this…") are developer-only prohibitions, not user-facing. `helpLangOtherNote` uses "target always" as natural English ("non-English target always needs an LLM") — this is Help scope (B4), not onboarding, and "target" is a technical forced-language-target concept, not the prohibited "target always output" compound.
4. ✅ **LanguagePickerOrder still green** — en first, ru not #1 (fr is #1 after en), Europe before Asia (ru index < zh index); all 9 order tests pass.
5. ✅ **UserSpeechLanguages settingPrimary / same-as-primary tests green** — 3 new B2 tests (`settingPrimaryKeepsSameAsPrimaryMirror`, `settingPrimaryKeepsExplicitAdditional`, `settingPrimaryNormalizesInput`) plus the existing `sameAsPrimaryHelper` test all pass.
6. ✅ **Diff is B2-scoped** — unstaged changes are exactly the 6 B2 target files + workflow artifacts (FEEDBACK.md, STATE.yaml) + graphify cache stamp. No Settings UI (`SettingsView.swift`, `GeneralSettingsView.swift`), no Help (`HelpSettingsView.swift`), no Canary/HUD (`HUDView.swift`, `CanaryCoreMLEngine.swift`) touched.
7. ✅ **`./script/qa/run_all.sh`** — 14/14 green. No failures (pre-existing or B2-introduced). Localization surface counts 542 AppText keys (up from 535 at B1, reflecting the 7 new onboarding keys).

## Notes

- `graphify-out/cache/last_query_stamp` change is non-target; Coder noted it was reverted (tooling artifact).
- No bugs opened. `bugs_open: 0`.

**RESULT: qa_green**
