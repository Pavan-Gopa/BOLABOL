# Blaboom ASR Core ML — step cards (S0–S15)

Authoritative plan: `BLABOOM_ASR_COREML_INTEGRATION_PLAN.md`.

## S0 — Train bootstrap

Kit + plan SoT; `APP_VERSION` narrative 1.0.4; STATE at S1.

## S1 — Onboarding language steps

### Goal

Three distinct screens: UI language → primary dictation → additional working language. Clear copy; «change later in Settings». No model cards yet (S1c).

### Requirements

1. Split language UX so UI language is not mixed with speech languages.
2. Primary = main dictation language; additional = second working language (not «always output target»).
3. Same-as-primary control for additional.
4. Footer/hint: change later (General / Hotkey → Your Languages).
5. EN AppText keys (full 15 locales in S3).
6. Persist via existing `UserSpeechLanguages` / GeneralSettingsStore.
7. Pickers: `LanguagePickerOrder`.

### target_files

```yaml
- Sources/NativeBlaboom/Views/OnboardingView.swift
- Sources/NativeBlaboom/Stores/GeneralSettingsStore.swift
- Sources/NativeBlaboomCore/Services/AppText.swift
- Sources/NativeBlaboomCore/Models/UserSpeechLanguages.swift
- Sources/NativeBlaboomCore/Models/LanguagePickerOrder.swift
- Tests/NativeBlaboomCoreTests/OnboardingLocalizationTests.swift
- Tests/NativeBlaboomCoreTests/UserSpeechLanguagesTests.swift
```

### Out of scope

- Dynamic 3 model cards (S1b/S1c)
- Canary/GigaAM engines
- Full 15-locale maps (S3) — EN required

### Done

- [ ] Three clear steps; store writes primary+additional
- [ ] swift test green
- [ ] FEEDBACK waiting_review

### Verify

```bash
cd "/Users/pavan/Documents/AI Projects/Blaboom"
swift test
```

## S1b — Ranking pure function

`OnboardingModelRecommendation.topThree` + unit tests R1/R2/R3 matrix (plan §3.5.3).

## S1c — Onboarding 3 dynamic model cards

UI bound to ranking; Back recalculates.

## S2+ 

See master plan §4.
