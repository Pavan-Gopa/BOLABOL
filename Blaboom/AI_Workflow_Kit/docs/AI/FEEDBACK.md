# FEEDBACK — Blaboom 1.0.3

> Workers fill sections on handoff. Orchestrator reads this every «статус».

---

## Meta

| Field | Value |
|-------|--------|
| Step | B5 |
| Actor | coder + reviewer |
| Timestamp | 2026-08-03 |
| RESULT | `approved` |

---

## §1 — Build / commands (Coder)

Commands run and outcomes:

```bash
cd "/Users/pavan/Documents/AI Projects/Blaboom"
graphify query "AppText locale maps primary additional helpBilingual" --graph graphify-out/graph.json
swift build      # ✔ Build complete
swift test       # ✔ 467 tests in 4 suites passed
./script/qa/run_all.sh           # ✔ 14/14
./script/qa/check_localization_surface.sh   # ✔ OK (561 AppText keys)
```

No `git commit` / `git push`.

---

## §2 — Step compliance (Coder)

- [x] Only `target_files` touched / inspected:
  - `Sources/NativeBlaboomCore/Services/AppText.swift` (large pre-existing unstaged diff completed)
  - `Tests/NativeBlaboomCoreTests/AppTextFullCoverageTests.swift`
  - `Tests/NativeBlaboomCoreTests/SettingsLocalizationTests.swift`
  - `Tests/NativeBlaboomCoreTests/OnboardingLocalizationTests.swift`
  - `Tests/NativeBlaboomCoreTests/ArchiveStatsLocalizationTests.swift`
  - `script/qa/check_localization_surface.sh` (inspected — already green, no change needed)
  - `AI_Workflow_Kit/docs/AI/FEEDBACK.md` (handoff only)
- [x] All **15 locales** (en, ru, es, de, fr, it, pt, zh, ja, ko, ar, hi, uk, tr, pl) carry real maps for every B2–B4 key family (verified key-by-key per locale, zero missing/empty):
  - B2 onboarding primary/additional: 7 keys (`onboardingPrimaryLanguageTitle` … `onboardingAdditionalSameAsPrimary`)
  - B3 Settings language pair: 7 keys (`languagePairSectionTitle` … `languagePairEngineNote`)
  - B4 Help bilingual: 12 keys (`helpBilingualTitle` … `helpBilingualPolishNote`)
  - helpLang*/helpHUD* non-EN alignment: `helpLangIntro/Auto/Forced/EnglishNote/OtherNote/Where` + `helpHUDLeftA/LeftLetter/LeftTap/ControlLanguage` rewritten in all 14 non-EN locales to the EN primary+additional model (old single-"target" product-promise wording removed).
- [x] No raw-key fallback: full `keys × languages` cartesian check green (`everyAppTextKeyResolvesInEveryConcreteLanguage`), plus per-family no-raw-key tests for B2/B3/B4.
- [x] No silent EN fallback: B2/B3/B4 families + updated helpLang/helpHUD differ from EN in every non-EN locale (verified: 0 identical-to-EN values in zh/ja/ko/ar/hi/uk/tr; guarded by `newlyAddedOnboardingKeysAreActuallyTranslated` / `settingsKeysAreActuallyTranslatedBeyondEnglish` for ru/zh/ar/hi).
- [x] Format args: `%@`/`%d`/positional usage consistent across locales for every format-bearing key in AppText (no cross-locale arg-count mismatch).
- [x] Terminology: primary + additional framing everywhere; no unnegated "target always output" / "always output" / "target output" in any of the 15 locales (grep + per-locale scan clean; tests `settingsSpeechLanguageCopyAvoidsTargetAlwaysOutputTerminology`, `onboardingSpeechLanguageCopyAvoidsTargetAlwaysOutputTerminology`, `helpBilingualCopyAvoidsUnnegatedTargetAlwaysOutputTerminology` all green).
- [x] Archive stats localization regressions green: `ArchiveStatsLocalizationTests` (tr/ja/ko/hi format-arg crash guards) pass unchanged.
- [x] `swift test` GREEN — 467/467.
- [x] `./script/qa/run_all.sh` GREEN — 14/14; `check_localization_surface.sh` green without edits.
- [x] No Python runtime, no out-of-scope work (no B6 Canary engine, no product UX redesign).
- [x] No `git commit` / `git push`.

---

## §3 — Invariants (Coder)

- Every AppTextKey resolves non-empty and never to its raw key in all 15 concrete UI languages.
- B2–B4 key families + updated helpLang*/helpHUD* are real translations in all 15 locales — none falls back to the EN source outside EN.
- Terminology invariant intact: additional language is framed as a second language for quick switching, NEVER as an unnegated "target always output" promise.
- Format specifiers consistent across locales (no tr/ja/ko/hi-style `%d`/`%@` ordering crashes).
- Version stays `1.0.3`; full suite 467/467; QA 14/14.

---

## §4 — Comments / structure (Coder)

- `AppText.swift`: B2–B4 key families inserted per locale after `.helpCloudTranscriptionBody` (marked `// B2–B4 — primary + additional speech languages (plan §6.1–§8.1, §9). Full 15-locale maps (B5).`); helpLang*/helpHUD* blocks rewritten in every non-EN locale to the EN primary+additional model (HUD letter defaults to additional language, Hotkey → Your Languages path, Canary no-A / primary↔additional letter cycle, glossary fallback chain preserved).
- `SettingsLocalizationTests.swift`: B3 (`b3SettingsSpeechLanguageKeys`) and B4 (`b4HelpBilingualKeys`) families added to `settingsKeys` (all-locale no-raw-key guard) and to `settingsKeysAreActuallyTranslatedBeyondEnglish`; B5 comments updated (full 15-locale maps landed).
- `OnboardingLocalizationTests.swift`: B2 keys added to `newlyAddedOnboardingKeysAreActuallyTranslated` (must differ from EN in ru/zh/ar/hi); 12 → 15 locale doc comments updated.
- `AppTextFullCoverageTests.swift`: full keys × 15 locales coverage (no edits needed in B5).
- `ArchiveStatsLocalizationTests.swift`: unchanged — format-arg guards (incl. tr positional `%1$@`/`%2$d`) still green.
- `script/qa/check_localization_surface.sh`: unchanged — passes (561 keys, 15 languages, onboarding/help families ≥ 10).

---

## §5 — Reviewer findings (Reviewer)

**Verdict: [APPROVED]**

Independent verification (B5, i18n × 15):

1. **Scope** — Diff touches exactly 3 B5 target files: `AppText.swift` (+549/−157), `SettingsLocalizationTests.swift`, `OnboardingLocalizationTests.swift`. No Canary engine, no UX redesign, no out-of-scope product copy. `AppTextFullCoverageTests`, `ArchiveStatsLocalizationTests`, `check_localization_surface.sh` untouched.
2. **15-locale cartesian check (independent script)** — all B2 (7), B3 (7), B4 (12), helpLang (6), helpHUD (4) keys × 15 locales: 0 missing, 0 empty, 0 raw-key, **0 identical-to-EN** (checked all 14 non-EN locales, not only ru/zh/ar/hi). 561 AppText keys total.
3. **helpLang*/helpHUD* alignment** — ru/zh/ar/tr/hi/uk samples all rewritten to the EN primary+additional model: HUD letter defaults to additional language, A = spoken language (primary default), Hotkey → Your Languages path, Canary no-A primary↔additional cycle.
4. **No unnegated "target always output" promise** — grep across all locales: every "always" match is negated ("not a target always output" / «не «всегда выводить»" / "не является") or pre-existing always-on-top float-window copy unrelated to B2–B4.
5. **Tests** — `swift test` GREEN 467/467; guards verified in source: B2 in `newlyAddedOnboardingKeysAreActuallyTranslated`, B3/B4 in `settingsKeysAreActuallyTranslatedBeyondEnglish` (non-EN differ for ru/zh/ar/hi), full no-raw-key guards over all 15 concrete languages.
6. **Archive format regressions** — `ArchiveStatsLocalizationTests` (tr positional `%1$@`/`%2$d`) untouched and green in the 467.
7. **Format args** — independent scan of every format-bearing key × 15 locales: 0 arg-count/positional mismatches.
8. **Terminology** — primary/additional framing consistent across all 15 locales ("Same as primary" / "Как основной" / "与主要语言相同" / "مثل اللغة الأساسية" / "Taki sam jak główny"…).
9. **QA** — `./script/qa/run_all.sh` GREEN 14/14; `check_localization_surface.sh` OK (561 keys).

**Spot-check notes (non-blocking):**
- Two stale comments in the EN block (`AppText.swift:1146-1147`, `:1157`): "Full 15-locale maps land in B5; other locales fall back to English until then" — outdated now that B5 landed. Cosmetic; safe to clean in a future chore.
- Non-EN differ guards iterate only ru/zh/ar/hi (4 locales); my independent cartesian scan confirmed 0 same-as-EN across all 14 non-EN locales, so coverage is adequate.
- pl block is the last entry and closes `]` without trailing comma (valid Swift); locale-splitting parsers must tolerate this.

**Meta RESULT: approved**

---

## §6 — QA summary (Tester)

**RESULT: qa_green**

### Commands

```bash
swift test            # ✔ 470 tests in 4 suites passed (+3)
./script/qa/run_all.sh # ✔ Passed: 15  Failed: 0 (incl. NEW check_i18n_b2_b4_families.sh)
```

### Gap-hunt → new coverage

- **Reviewer 4-locale hole closed** — `newlyAddedOnboardingKeysAreActuallyTranslated` and `settingsKeysAreActuallyTranslatedBeyondEnglish` now iterate ALL 14 non-EN locales (were ru/zh/ar/hi). Independent pre-verification: 0 identical-to-EN / 0 raw-key / 0 empty across all 14 × B2/B3/B4.
- **NEW tests (3)** — `helpLangHelpHUDDifferFromEnglishInEveryNonEnglishLocale`, `helpLangHelpHUDCopyAvoidsUnnegatedTargetAlwaysOutputInEveryLocale`, `primaryAdditionalTerminologyDistinctInSampleLocales` (ru/zh/ar/tr).
- **NEW script (1)** — `script/qa/check_i18n_b2_b4_families.sh`: 36 B2–B4/helpLang/helpHUD keys present in all 15 locale maps.
- Archive format regressions (tr/ja/ko/hi) green unchanged; full cartesian no-raw-key green.
- No product changes (`Sources/**` untouched). `bugs_open: 0`.

**RESULT: qa_green**

---

## Handoff line (all)

> Готово. Вернись к оркестратору и скажи «статус».
