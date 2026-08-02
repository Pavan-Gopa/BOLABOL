# REPORT — Blaboom 1.0.3 QA

| Field | Value |
|-------|--------|
| Step | B1 — Language pair store + picker order |
| Date | 2026-08-02 |
| Status | **GREEN** |
| RESULT | `qa_green` |

---

## Commands run

```bash
cd "/Users/pavan/Documents/AI Projects/Blaboom"

# 1) Full suite (run twice to confirm determinism)
swift test
#   ✔ Test run with 449 tests in 4 suites passed

# 2) Full QA gate (unit tests + structural contract scripts)
./script/qa/run_all.sh
#   Passed: 14   Failed: 0
#   (swift test + 13 check_*.sh contracts, incl. no-secrets, localization
#    surface 535 AppText keys, stores wiring, release identity)
```

## Pass counts

- **449 tests in 4 suites** — green (both runs).
- QA gate: **14/14 steps passed** — no pre-existing failures to document.

## B1 test files / cases that cover order + migration

| File | Cases | Covers |
|------|-------|--------|
| `Tests/NativeBlaboomCoreTests/LanguagePickerOrderTests.swift` | 7 tests | Order invariants: `en` first excluding System sentinel; `ru` not index 1 (index 1 == `fr`); Europe before Asia (`ru` index < `zh` index); System sentinel first in `uiLanguages` and never between `en`/`fr`; exact canonical sequence `en → fr…uk → ar…zh…ko`; endonym display names; code/name/endonym resolution |
| `Tests/NativeBlaboomCoreTests/UserSpeechLanguagesTests.swift` | 14 tests | Pair store + migration: defaults map known system locales, fallback `en` for unknown; additional may equal primary (same-as-primary policy); migration seeds primary from legacy transcription code and additional from legacy force-target name/code/endonym; never duplicates target into primary; ignores unknown legacy values; Codable round-trip; legacy payload without keys decodes to defaults |
| `Tests/NativeBlaboomCoreTests/GeneralSettingsTests.swift` | +5 additions | Pair carried in blob; Codable round-trip; legacy payload without `speechLanguages` key still decodes → fresh-install defaults (store then runs best-effort migration once); `normalize()` preserves the pair |
| `Tests/NativeBlaboomCoreTests/TranscriptionLanguageModeTests.swift` | +1 addition | `CaseIterable` stable order `[.auto, .target]` |

Total B1 delta: **21 new tests** (14 + 7) + **6 additions** in GeneralSettings/TranscriptionLanguageMode — matches Coder/Reviewer claims.

## B1 Must-verify checklist

1. ✅ `swift test` full suite GREEN (449/449, run twice).
2. ✅ Order invariants covered by dedicated tests (see table) — all pass.
3. ✅ Migration / pair tests present and pass (`UserSpeechLanguages` 14, `GeneralSettings` +5, legacy decode + migration path verified; store glue thin as documented).
4. ✅ additional may equal primary — `userSpeechLanguagesAdditionalMayEqualPrimary`, same-as-primary helper, en-primary default policy all green.
5. ✅ No Python / forbidden runtime in B1 Sources — new files import only `Foundation`; grep for `python|Python` in the 5 B1 source files: no matches.
6. ✅ `./script/qa/run_all.sh` — 14/14 green, no failures (pre-existing or otherwise).

## Notes

- Diff scope check: `git status` shows exactly the B1 `target_files` (6 modified + 4 new); `HotkeySettings.swift` model untouched as documented; no onboarding/settings/UI/AppText bulk.
- No bugs opened. `bugs_open: 0`.

**RESULT: qa_green**
