# FEEDBACK — Blaboom 1.0.3

> Workers fill sections on handoff. Orchestrator reads this every «статус».

---

## Meta

| Field | Value |
|-------|--------|
| Step | B2 |
| Actor | coder + reviewer |
| Timestamp | 2026-08-02 |
| RESULT | `approved` |

---

## §1 — Build / commands (Coder)

Commands run and outcomes:

```
cd "/Users/pavan/Documents/AI Projects/Blaboom"
graphify query "OnboardingView UI language step GeneralSettingsStore speechLanguages" --graph graphify-out/graph.json
graphify path "OnboardingView" "GeneralSettingsStore" --graph graphify-out/graph.json
graphify explain "LanguagePickerOrder" --graph graphify-out/graph.json
swift build  # ✔ Build complete (40s; mlx-swift identity warning pre-existing, unrelated)
swift test   # ✔ 455 tests in 4 suites passed (449 at B1 + 6 new B2 tests)
```

Graphify cache stamp reverted (non-target artifact).

---

## §2 — Step compliance (Coder)

- [x] Only `target_files` touched (6 modified; graphify cache stamp reverted)
- [x] Onboarding order per plan §6.1: UI lang (step 0) → primary (1) → additional (2) → transcription (3) → permissions (4) → modes (5) → glossary (6) → theme (7); `totalSteps` 6 → 8
- [x] Persisted into the same Settings blob via existing `GeneralSettingsStore.speechLanguages` (single source of truth, plan §3.3); no second store invented
- [x] Speech pickers use `LanguagePickerOrder.speechLanguages`; UI-language picker switched from `UILanguagePreference.allCases` to `LanguagePickerOrder.uiLanguages` (allCases put `ru` at index 1; §5 invariants preserved)
- [x] Same-as-primary option on additional step; primary change keeps the mirror intact when pair is same-as-primary
- [x] Glossary author language prefills from primary (plan §6.1 step 7; small — new `glossaryLanguageName(forSpeechCode:)` helper)
- [x] EN-only new AppText keys (7); other locales fall back to EN until B5 (all existing localization tests green — fallback satisfies non-empty/non-raw-key contract; new keys deliberately NOT added to the "must differ from EN" list)
- [x] Terminology: primary + additional; copy tests assert no "target always"/"target output"/"always output" in any locale
- [x] No Python / forbidden runtime; no future-step work (no Settings UI, no Help, no Canary/HUD)
- [x] No git commit / push

Notes: `GeneralSettingsStore.swift`, `GeneralSettings.swift`, `LanguagePickerOrder.swift`, `UserSpeechLanguages.swift` listed in STATE target_files were inspected; only `UserSpeechLanguages.swift` needed a change (new `settingPrimary(_:)` helper — see §4). Modes/HUD step copy untouched (auto A preserved; no Canary HUD).

---

## §3 — Invariants (Coder)

What must stay true (engines, HUD A for non-Canary, version, etc.):

- Auto-detect untouched: `TranscriptionModelSettings.languagePreference` / `TranscriptionLanguageRouter` unchanged; the pair is persisted and read-only mirrored into `TranscriptionModelStore`/`HotkeySettingsStore` accessors (plan §4.1).
- `LanguagePickerOrder` invariants intact (en first excluding System; ru not index 1; Europe before Asia; System sentinel first in `uiLanguages`) — order tests still green.
- `UserSpeechLanguages` semantics intact (may be equal; same-as-primary policy; normalization; legacy-payload decode) — all B1 tests still green.
- New EN keys resolve without raw-key fallback in English; every onboarding key still resolves non-empty/non-raw across all 15 locales (EN fallback per B5 deferral).
- Version line stays 1.0.3; no version-train changes.
- Additional ≠ "always output": wording + automated test.

---

## §4 — Comments / structure (Coder)

New modules headers, non-obvious why-comments:

- `OnboardingView.swift` — two new steps (`primaryLanguageStep`, `additionalLanguageStep`) with B2 header comments citing plan §6.1/§6.2/§3.3/§5; step renumbering (transcription now step 3; footer gate moved to `step == 3`); UI-language grid uses `LanguagePickerOrder.uiLanguages` (with why-comment re: allCases putting ru second); `LanguageChip` generalized from `UILanguagePreference` to a plain `label` so both UI and speech lists share it; glossary prefill helper `glossaryLanguageName(forSpeechCode:)` (pl/tr/uk fall back to English, matching old behavior since the glossary catalog lacks them). "Same as primary" toggle-off picks English (or French when primary is already English) so the control is meaningful both ways.
- `AppText.swift` — 7 new keys grouped under the existing `onboarding*` block (`onboardingPrimaryLanguageTitle/Hint/Body`, `onboardingAdditionalLanguageTitle/Hint/Body`, `onboardingAdditionalSameAsPrimary`) per plan §9.4; EN map entries with a why-comment: copy never calls additional a "target"/"always output" language, full 15-locale maps land in B5. Hint copy deliberately avoids promising "change in Settings" — Settings surfaces are B3.
- `UserSpeechLanguages.swift` — new `settingPrimary(_:)` (plan §6.2): keeps same-as-primary mirror intact on primary change, preserves explicit additional; unit-tested (3 tests).
- Why no store unit test for "updating speechLanguages via store API": `NativeBlaboomCoreTests` depends on Core only (`Package.swift`), and `GeneralSettingsStore` lives in the app executable target — store glue is thin UI-layer (`speechLanguages` setter → `update { $0.speechLanguages = newValue }` → persist). The semantics it exercises (`settingPrimary`, same-as-primary, Codable round-trip, migration) are fully covered at Core level; view-level persistence is UI-only, documented per brief item 8.
- Tests added: `OnboardingLocalizationTests` +2 (EN keys resolve without raw-key fallback; no target-always-output terminology across all locales), `UserSpeechLanguagesTests` +3 (`settingPrimary` mirror/explicit/normalize), `LanguagePickerOrderTests` +1 (speech codes == UI languages minus System — locks the B2 picker-list sync).
- No other target files changed: `GeneralSettingsStore.swift` already exposes the `speechLanguages` get/set accessor (B1) — onboarding writes through it; `GeneralSettings.swift` / `LanguagePickerOrder.swift` needed no edits.

---

## §5 — Reviewer findings (Reviewer)

**Verdict:** [APPROVED]

### Must fix

None.

### Nice to have

None blocking. (Nits, optional: FEEDBACK §2 says allCases put `ru` at index 1 — actually `UILanguagePreference.allCases` = [system, en, ru, …] so ru sits at index 2; the substantive claim — ru directly after en, breaking §5 — is correct and the fix is right. Also, on the additional step while the same-as-primary toggle is ON the primary chip still renders selected in the chip grid (additional == primary); the toggle communicates the state and clicking any chip disables the mirror, so behaviour is coherent.)

### Notes (what was verified)

Re-reviewed the full B2 diff against plan §5/§6/§3.3/§4.1 + §9.4, ran graphify first (query + path OnboardingView→GeneralSettingsStore: direct references edge), and ran `swift test` myself (455 tests in 4 suites passed).

1. Scope — `git diff --stat` shows exactly the 6 expected files; no B3 Settings UI, no B4 Help, no B5 15-locale bulk, no Canary/HUD copy. `GeneralSettingsStore.swift` / `GeneralSettings.swift` / `LanguagePickerOrder.swift` untouched (inspected-only, as claimed).
2. Order (§6.1) — stepContent: 0 UI lang → 1 primary → 2 additional → 3 transcription → 4 permissions → 5 modes → 6 glossary → 7 theme; `totalSteps` 6→8; footer gate moved to `step == 3`; previous tour steps unchanged apart from renumbering.
3. SoT (§3.3) — onboarding writes `settingsStore.speechLanguages`, which routes to `settings.speechLanguages` in the same `GeneralSettings` blob the Settings surface reads/writes; no second store invented.
4. Picker order (§5) — speech pickers use `LanguagePickerOrder.speechLanguages`; UI-language step switched from `allCases` to `LanguagePickerOrder.uiLanguages` (System sentinel first, then en → Europe alpha → Asia alpha; ru no longer directly after en). New test locks speech codes == UI codes minus System.
5. Same-as-primary (§6.2) — `settingPrimary(_:)` keeps the mirror when pair is same-as-primary, preserves explicit additional otherwise; 3 new unit tests (mirror / explicit / normalize). Toggle-off fallback (en, or fr when primary is en) makes the control meaningful both ways.
6. EN keys / terminology — 7 new keys with real EN strings; tests assert no raw-key fallback in EN and no "target always" / "target output" / "always output" in any locale (EN fallback included). Existing 15-locale non-empty/non-raw-key onboarding contract stays green (EN fallback satisfies it — per B5 deferral).
7. Auto engines (§4.1) — `TranscriptionModelSettings.swift` / `TranscriptionLanguageRouter.swift` / `TranscriptionBackend.swift` byte-identical to B1 (verified with `git diff --quiet`); auto-detect untouched.
8. Tests — `swift test`: 455 tests in 4 suites passed, matching the Coder's claim.
9. Comments — why-comments present on all non-obvious bits (allCases ru-second rationale, mirror semantics, toggle-off fallback choice, glossary prefill pl/tr/uk → EN fallback, LanguageChip label generalization, EN-only deferral note in AppText).

---

## §6 — QA summary (Tester)

**RESULT: `qa_green`**

- `swift test` — 455 tests in 4 suites passed (B1 had 449; +6 B2 tests).
- `./script/qa/run_all.sh` — 14/14 green; 0 failures (pre-existing or new).
- Onboarding EN keys (7 new) resolve with real strings — no raw-key fallback.
- No "target always" / "always output" terminology in any onboarding string across all 15 locales (test `onboardingSpeechLanguageCopyAvoidsTargetAlwaysOutputTerminology` passes).
- LanguagePickerOrder: en first, ru not #1, Europe before Asia — all 9 order tests green.
- UserSpeechLanguages: `settingPrimary` keeps mirror / explicit / normalizes — all 17 tests green.
- Diff B2-scoped: 6 target files + workflow artifacts only; no Settings UI / Help / Canary touched.
- Localization surface: 542 AppText keys (up from 535 at B1 — 7 new onboarding keys).
- Full report: `AI_Workflow_Kit/docs/AI/REPORT.md`.

---

## Handoff line (all)

> Готово. Вернись к оркестратору и скажи «статус» или «приступай».
