# FEEDBACK — Blaboom 1.0.4 (ASR Core ML)

> Workers fill sections on handoff. Orchestrator reads this every «статус».

---

## Meta

| Field | Value |
|-------|--------|
| Step | S1 |
| Actor | reviewer |
| Timestamp | 2026-08-03 |
| RESULT | `approved` |

---

## §1 — Build / commands (Coder)

Commands run and outcomes:

```bash
cd "/Users/pavan/Documents/AI Projects/Blaboom"

# 1) Graphify queries
graphify query "OnboardingView primary additional uiLanguage speechLanguages" --graph graphify-out/graph.json
graphify path "OnboardingView" "GeneralSettingsStore" --graph graphify-out/graph.json

# 2) Full unit test suite
swift test
#   ✔ Test run with 471 tests in 4 suites passed after 0.046 seconds
```

No `git commit` / `git push`.

---

## §2 — Step compliance (Coder)

- [x] Three distinct onboarding language screens configured: Step 0 (Interface language), Step 1 (Main dictation language / primary), Step 2 (Additional working language / additional).
- [x] Clear EN titles, hints, and notes added to AppText for screens 0–2.
- [x] Clear hint on screens 0–2: "You can change this later in Settings" (Settings → General for UI, Settings → Hotkey → Your Languages for Primary/Additional).
- [x] Primary+additional speech languages persisted via `GeneralSettingsStore.speechLanguages` (single source of truth).
- [x] Speech pickers use `LanguagePickerOrder.speechLanguages`; UI picker uses `LanguagePickerOrder.uiLanguages`.
- [x] Additional screen provides "Same as primary" toggle and updates speech languages via `.settingAdditional(...)`.
- [x] Copy strictly avoids forbidden terminology ("target always output" / "always force output").
- [x] All 471 unit tests green (`swift test`).
- [x] Step indices and footer Back / Next / Skip / Get Started buttons consistent.
- [x] No `git commit` / `git push`.

---

## §3 — Invariants (Coder)

- Primary/additional terminology strictly preserved — NEVER "target always output".
- Code modified ONLY in target files allowed for S1.
- No Canary/GigaAM/model ranking (S1b/S1c out of scope).
- 471 unit tests green.
- No `git commit` / `git push`.

---

## §4 — Comments / structure (Coder)

- `Sources/NativeBlaboom/Views/OnboardingView.swift`: updated `additionalLanguageStep` picker action to use `.settingAdditional(...)`.
- `Sources/NativeBlaboomCore/Services/AppText.swift`: updated English strings for `.onboardingChooseLanguageTitle`, `.onboardingChooseLanguageHint`, `.onboardingLanguageNote`, `.onboardingPrimaryLanguageTitle`, `.onboardingPrimaryLanguageHint`, `.onboardingPrimaryLanguageBody`, `.onboardingAdditionalLanguageTitle`, `.onboardingAdditionalLanguageHint`, `.onboardingAdditionalLanguageBody` to clearly separate UI language from primary and additional speech languages and include settings hints.

---

## §5 — Reviewer decision

[APPROVED]

### Step S1 Review Checklist:
- [x] **1. UI language vs primary vs additional**: Three distinct concepts and screens in onboarding (Step 0: Interface language, Step 1: Main dictation language, Step 2: Additional working language).
- [x] **2. EN copy + Settings path hints**: English strings provide clear distinctions and hints directing users to Settings → General for UI, and Settings → Hotkey → Your Languages for speech languages.
- [x] **3. Additional ≠ "target always output"**: Terminology is strictly compliant; no "target always output" wording.
- [x] **4. speechLanguages SoT & Same as primary**: Speech languages utilize `GeneralSettingsStore.speechLanguages` single source of truth and update properly via `.settingAdditional(...)`.
- [x] **5. LanguagePickerOrder**: Appropriate ordering lists applied (`uiLanguages` vs `speechLanguages`).
- [x] **6. No scope creep**: No changes made to Canary/GigaAM, S1b/S1c ranking, or engines.
- [x] **7. swift test green**: `swift test` passed cleanly with 471 tests passing across 4 test suites.
- [x] **8. Target files only**: Diff is strictly constrained to `Sources/NativeBlaboom/Views/OnboardingView.swift` and `Sources/NativeBlaboomCore/Services/AppText.swift`.

Verdict: Step S1 changes fully approved.

---

## §6 — Tester QA

| Field | Value |
|-------|--------|
| Actor | tester |
| Timestamp | 2026-08-03 |
| RESULT | `qa_green` |

Commands run:

```bash
cd "/Users/pavan/Documents/AI Projects/Blaboom"
swift test          # ✔ 473 tests in 4 suites passed (471 → +2 Tester gap tests)
./script/qa/run_all.sh  # ✔ Passed: 18   Failed: 0
```

Must-verify: EN onboarding keys resolve (no raw-key) ✅ · no "target always output" / "always force output" in new onboarding speech copy ✅ · diff scoped to OnboardingView + AppText EN, no engines ✅ · `settingAdditional` covered ✅.

New tests added (`Tests/NativeBlaboomCoreTests/OnboardingLocalizationTests.swift`):
- `onboardingSpeechLanguageBodiesPointToRealSettingsSections` — primary/additional bodies + UI-note carry "change this later in Settings" and path segments match real Settings section labels (Hotkey / Your Languages / General).
- `onboardingChooseLanguageStepSeparatesUiFromDictation` — Step-0 title = interface, hint UI-only + dictation unaffected.
- Extended `onboardingSpeechLanguageCopyAvoidsTargetAlwaysOutputTerminology` — scan now includes "force output" / "always force" across all 15 locales.

No gaps left: settingAdditional persistence and same-as-primary already guarded (`UserSpeechLanguagesTests`, `onboardingAndSettingsSameAsPrimaryCopyMatch`). No bugs opened. `bugs_open: 0`. Full details in `AI_Workflow_Kit/docs/AI/REPORT.md` § S1.

---

## Handoff line (all)

> Готово. Вернись к оркестратору и скажи статус.
