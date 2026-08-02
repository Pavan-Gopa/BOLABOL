# FEEDBACK — Blaboom 1.0.3

> Workers fill sections on handoff. Orchestrator reads this every «статус».

---

## Meta

| Field | Value |
|-------|--------|
| Step | B3 |
| Actor | coder + reviewer |
| Timestamp | 2026-08-02 |
| RESULT | `approved` |

---

## §1 — Build / commands (Coder)

Commands run and outcomes:

```
cd "/Users/pavan/Documents/AI Projects/Blaboom"
graphify query "GeneralSettingsView HotkeySettingsView speechLanguages primary additional" --graph graphify-out/graph.json
graphify path "HotkeySettingsView" "GeneralSettingsStore" --graph graphify-out/graph.json
graphify explain "UserSpeechLanguages" --graph graphify-out/graph.json
swift build   # ✔ Build complete (45s; mlx-swift identity warning pre-existing, unrelated)
swift test    # ✔ 461 tests in 4 suites passed (455 at B2 + 6 new B3 tests)
bash script/qa/run_all.sh  # ✔ Passed: 14, Failed: 0
```

Graphify cache stamp reverted (non-target artifact).

---

## §2 — Step compliance (Coder)

- [x] Only `target_files` touched (6 modified; graphify cache stamp reverted)
- [x] **Path chosen: Settings → Hotkey tab** (plan §7.1 allows Hotkey and/or General). New «Your Languages» section sits directly above the legacy engine-level «Recognition Language & Output» block — co-located near existing language controls; General-only would have mixed speech languages with the Interface Language picker. Documented here per brief.
- [x] Explicit Primary picker + hint, Additional picker + hint, «Same as primary» toggle (plan §7.1); both pickers use `LanguagePickerOrder.speechLanguages` (canonical en → Europe → Asia order, not en-ru top-2 allCases)
- [x] Read/write ONLY `GeneralSettingsStore.speechLanguages` — the same blob onboarding writes (single source of truth, plan §3.3); no second store invented; `HotkeySettingsStore` read-only mirror untouched
- [x] Values after a Settings edit match what onboarding wrote/read: primary writes via `settingPrimary(_:)` (keeps same-as-primary mirror intact, §6.2), additional via new `settingAdditional(_:)`, toggle-off fallback identical to onboarding (en, or fr when primary is en)
- [x] Legacy Parakeet/Whisper auto/force control kept and clearly separated: distinct Form section below the pair; `TranscriptionModelStore.languageSelectionTag` / custom code / hotkey target untouched — auto-detect preserved (plan §4.1)
- [x] EN-only new AppText keys (7: `languagePairSectionTitle`, `primaryLanguage`, `primaryLanguageHint`, `additionalLanguage`, `additionalLanguageHint`, `additionalSameAsPrimary`, `languagePairEngineNote`); other locales EN-fallback until B5. New keys added to the all-locale resolve list (EN fallback satisfies non-empty/non-raw contract) but deliberately NOT to the «must differ from EN» list
- [x] Terminology: primary + additional; automated test asserts no «target always» / «target output» / «always output» in any new Settings string across all 15 locales (EN fallback included)
- [x] No Python / forbidden runtime; no future-step work (no B4 Help, no B5 15-locale bulk, no Canary/HUD B6+, no onboarding redesign)
- [x] No git commit / push

Notes: `GeneralSettingsStore.swift` already exposes the `speechLanguages` get/set accessor (B1) — no change needed. `HotkeySettingsStore.swift` / `SettingsView.swift` / `LanguagePickerOrder.swift` / `GeneralSettingsView.swift` inspected; no edits required. `OnboardingView.swift` untouched (not in target list); its inline additional-picker construction remains valid.

---

## §3 — Invariants (Coder)

What must stay true (engines, HUD A for non-Canary, version, etc.):

- Auto-detect untouched: `TranscriptionModelSettings.languagePreference` / `TranscriptionLanguageRouter` / `TranscriptionModelStore` language tags unchanged; legacy «Recognition Language» control intact (plan §4.1).
- `LanguagePickerOrder` invariants intact (en first; ru not index 1; Europe before Asia; System sentinel first in `uiLanguages`) — order tests still green.
- `UserSpeechLanguages` semantics intact (may be equal; same-as-primary policy; normalization; legacy-payload decode) + new `settingAdditional(_:)` — all B1/B2 tests still green.
- New EN keys resolve without raw-key fallback in English; every `AppTextKey` still resolves non-empty/non-raw across all 15 locales (EN fallback per B5 deferral) — full-coverage test green.
- Version line stays 1.0.3; no version-train changes.
- Additional ≠ «always output»: wording + automated test.

---

## §4 — Comments / structure (Coder)

New modules headers, non-obvious why-comments:

- `HotkeySettingsView.swift` — new «Your Languages» Section (plan §7) with why-comment: reads/writes `GeneralSettingsStore.speechLanguages` (same blob onboarding writes, §3.3); separate preference from the engine-level Recognition Language control below (§4.1); copy never calls additional a «target» / «always output» language. Three bindings: `primaryLanguageSelection` (via `settingPrimary` so the same-as-primary mirror stays intact, §6.2), `additionalLanguageSelection` (via new `settingAdditional`; picking primary restores same-as-primary automatically), `sameAsPrimaryBinding` (mirror on; toggle-off picks en, or the first Europe-group language when primary is already en — identical to onboarding fallback, §6.2). Section placed above the legacy block and NOT gated on hotkey enabled: the pair is a general preference (also the future HUD/Canary base), while the engine auto/force control stays gated as before.
- `AppText.swift` — 7 new keys grouped under the onboarding speech-language block, matching plan §9.4 Settings draft: `languagePairSectionTitle`, `primaryLanguage`, `primaryLanguageHint`, `additionalLanguage`, `additionalLanguageHint`, `additionalSameAsPrimary`, `languagePairEngineNote`; EN map entries with why-comment (never «target always output»; full 15-locale maps land in B5). `languagePairEngineNote` keeps engine behavior honest: Parakeet/Whisper still auto-detect by default; the pair is defaults + base for HUD language switching — it does not promise Canary or change engine behavior.
- `UserSpeechLanguages.swift` — new `settingAdditional(_:)` (plan §7.1): primary untouched, same-as-primary expressed by additional == primary (plan §3.4); unit-tested (3 tests). Mirrors the existing `settingPrimary(_:)` API.
- Why no store unit test for «updating speechLanguages via store API»: `NativeBlaboomCoreTests` depends on Core only (`Package.swift`); `GeneralSettingsStore` lives in the app executable target. Store glue is thin UI-layer (`speechLanguages` setter → `update { $0.speechLanguages = newValue }` → persist); the semantics it exercises (`settingPrimary` / `settingAdditional`, same-as-primary, Codable round-trip, migration) are fully covered at Core level.
- Tests added: `SettingsLocalizationTests` +3 (`settingsSpeechLanguageKeysResolveInEnglish`, `settingsSpeechLanguageCopyAvoidsTargetAlwaysOutputTerminology`, plus 7 new keys appended to the all-locale resolve list), `OnboardingLocalizationTests` +1 (`onboardingAndSettingsSameAsPrimaryCopyMatch` — Settings and onboarding «Same as primary» share wording), `UserSpeechLanguagesTests` +3 (`settingAdditional` keeps primary / normalizes input / restores same-as-primary).
- No other target files changed: `GeneralSettingsStore.swift` (accessor from B1), `HotkeySettingsStore.swift` (read-only mirror from B1), `SettingsView.swift` (Hotkey tab already present), `LanguagePickerOrder.swift` (speech list already canonical), `GeneralSettingsView.swift` (inspected; Interface Language untouched — speech pair lives in Hotkey per the chosen path).

---

## §5 — Reviewer findings (Reviewer)

**Verdict:** [APPROVED]

### Must fix

None.

### Nice to have

— (Optional polish, not blocking: the «Your Languages» Section has no header title, so it renders unlabeled between the hotkeys rows and the Recognition Language block; adding a `Section("Your Languages")`-style header would aid scanability. The `languagePairEngineNote` caption is honest and fine.)

### Notes (what was verified)

1. **Diff scope** — only B3 target files modified: `HotkeySettingsView.swift` (+104), `AppText.swift` (+21), `UserSpeechLanguages.swift` (+10), `SettingsLocalizationTests.swift` (+48), `OnboardingLocalizationTests.swift` (+12), `UserSpeechLanguagesTests.swift` (+39), plus orchestration files (FEEDBACK/STATE). No B4 Help bulk, no B5 15-locale bulk, no Canary, no onboarding redesign. `git diff` confirms GeneralSettingsView/SettingsView/GeneralSettingsStore/HotkeySettingsStore/LanguagePickerOrder untouched.
2. **Primary + additional + same-as-primary** — all three controls present in Settings with labels, hints and toggle (§7.1).
3. **Path** — Settings → Hotkey per plan §7.1; new «Your Languages» Section placed directly above the legacy engine-level «Recognition Language & Output» block, co-located near language controls. Not gated on hotkey `enabled` — acceptable as a general preference (documented rationale).
4. **SoT** — all three bindings read/write `GeneralSettingsStore.speechLanguages` only (verified accessor at GeneralSettingsStore.swift:69-72 → `update { $0.speechLanguages = newValue }`); same blob onboarding writes (`OnboardingView.settingsStore` is `GeneralSettingsStore`); no second store; `HotkeySettingsStore` read-only mirror untouched.
5. **Picker order** — both pickers iterate `LanguagePickerOrder.speechLanguages` (en → Europe → Asia, canonical).
6. **Terminology** — no «target always output» anywhere; `settingsSpeechLanguageCopyAvoidsTargetAlwaysOutputTerminology` asserts it across all 15 locales (EN fallback included); `settingsSpeechLanguageKeysResolveInEnglish` + `onboardingAndSettingsSameAsPrimaryCopyMatch` guard EN resolution and shared wording.
7. **Legacy separation** — auto/force Recognition Language remains in its own Section below, still gated on hotkey enabled; `tag("auto")` and `TranscriptionModelStore` language path untouched (plan §4.1 preserved).
8. **Tests** — `swift test` green: 461/461 passed; all B3 tests (UserSpeechLanguages +3, SettingsLocalization +3, OnboardingLocalization +1) pass.
9. **Comments** — non-obvious bindings documented (`settingPrimary` mirror semantics, toggle-off fallback identical to onboarding, picker-to-same-as-primary restore).

Graphify confirmed: `HotkeySettingsView --references--> GeneralSettingsStore` (1 hop); `UserSpeechLanguages`/`LanguagePickerOrder`/`speechLanguages` reachable from the view's language controls.

---

## §6 — QA summary (Tester)

**RESULT: `qa_green`**

- **Suite:** `swift test` — 461/461 in 4 suites passed (B2 455 → B3 +6).
- **QA gate:** `./script/qa/run_all.sh` — 14/14 passed; no pre-existing failures.
- **B3 focus:** Settings EN keys for the language pair resolve with real strings (no raw-key fallback); no "target always"/"always output" in new Settings copy across all 15 locales; `settingAdditional` semantics (keep primary / normalize / restore same-as-primary) green; LanguagePickerOrder (9 tests) and settingPrimary mirrors green; diff B3-scoped — no Help/Canary/onboarding rewrite.
- **Report:** `AI_Workflow_Kit/docs/AI/REPORT.md` — B3 GREEN, `qa_green`.
- **Bugs opened:** 0.

---

## Handoff line (all)

> Готово. Вернись к оркестратору и скажи «статус».
