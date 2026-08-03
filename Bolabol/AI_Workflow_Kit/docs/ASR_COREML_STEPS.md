# Bolabol ASR Core ML — step cards (S0–S15)

Authoritative plan: `BOLABOL_ASR_COREML_INTEGRATION_PLAN.md`.

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
- Sources/NativeBolabol/Views/OnboardingView.swift
- Sources/NativeBolabol/Stores/GeneralSettingsStore.swift
- Sources/NativeBolabolCore/Services/AppText.swift
- Sources/NativeBolabolCore/Models/UserSpeechLanguages.swift
- Sources/NativeBolabolCore/Models/LanguagePickerOrder.swift
- Tests/NativeBolabolCoreTests/OnboardingLocalizationTests.swift
- Tests/NativeBolabolCoreTests/UserSpeechLanguagesTests.swift
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
cd "/Users/pavan/Documents/AI Projects/Bolabol"
swift test
```

## S1b — Ranking pure function

`OnboardingModelRecommendation.topThree` + unit tests R1/R2/R3 matrix (plan §3.5.3).

## S1c — Onboarding 3 dynamic model cards

### Goal

Replace the hard-coded onboarding model list with a dedicated `localModels`
screen bound directly to `OnboardingModelRecommendation.topThree`.

### Requirements

1. Keep the fixed order: UI language → primary dictation → additional working
   language → local models → existing permissions / modes / glossary / theme.
2. Compute up to three cards from the current primary/additional values and
   `transcriptionModelStore.models`; do not duplicate ranking rules in the view.
3. Returning Back, changing either speech language, and advancing again must
   recalculate the cards automatically.
4. Missing / NO-GO catalog entries disappear and remaining cards shift up.
5. Show `Recommended` only on slot 1 and the localized slot-1 subtitle
   `Best match for your languages`.
6. Preserve existing download/use/progress/error actions for shipped models.
   Downloading is optional; Next and Skip must preserve the current/default
   engine when no model is selected.
7. Add EN source copy for title, hint, recommended subtitle, and the
   Settings → Local Models change-later footer. Full 15-locale copy is S3.
8. Keep accessibility labels and the existing light/dark appearance behavior.

### target_files

```yaml
- Sources/NativeBolabol/Views/OnboardingView.swift
- Sources/NativeBolabolCore/Services/AppText.swift
- Tests/NativeBolabolCoreTests/OnboardingLocalizationTests.swift
```

### Out of scope

- Settings recommended strip (S2)
- Full 15-locale maps (S3)
- Canary/GigaAM catalog, download, or runtime integration (S4+ / GO-gated)
- New ranking logic or changes to the S1b ranking table
- Cloud provider redesign

### Done

- [ ] Screen 3 renders up to three current ranked cards
- [ ] Back → language change → Forward reorders without stale state
- [ ] Slot 1 alone is recommended; thin catalog collapses cleanly
- [ ] Next/Skip works without downloading or changing the engine
- [ ] `swift test` and scoped QA green
- [ ] Fresh `APP_VERSION=1.0.4` build opened
- [ ] FEEDBACK status `waiting_review`

### Verify

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"
swift test
./script/qa/run_all.sh
APP_VERSION=1.0.4 ./script/build_and_run.sh --verify
```

## S2 — Settings model labels + recommendations

### Goal

Make Settings → Local Models use the same language-aware recommendation helper
as onboarding without duplicating models or changing manual selection.

### Requirements

1. Keep the existing backend picker, cloud status, active-model state, download,
   retry, use, delete, progress, and full-catalog behavior.
2. For the local backend, compute recommendations only through
   `OnboardingModelRecommendation.topThree`, using the current canonical
   primary/additional pair from `GeneralSettingsStore` and the shipped catalog.
3. Present recommendations first and the remaining full catalog afterward.
   Each descriptor must appear exactly once across both groups.
4. Language changes in Settings must recalculate the groups without cached or
   duplicated ranking logic.
5. Add clear EN Settings labels/hints explaining that recommendations follow
   main + additional languages. Full locale coverage is S3.
6. Preserve arbitrary manual model selection; recommendations are display order
   only and must not auto-activate, download, or change backend.
7. Preserve accessibility and current light/dark layout.

### target_files

```yaml
- Sources/NativeBolabol/Views/Settings/LocalModelsSettingsView.swift
- Sources/NativeBolabolCore/Services/AppText.swift
- Tests/NativeBolabolCoreTests/SettingsLocalizationTests.swift
```

### Out of scope

- Onboarding changes
- S3 full 15-locale maps
- S4–S10 model spikes, catalog entries, engines, downloads, and OS gates
- S12 default-selection hints for future GO models
- Ranking-table changes or a second ranking helper
- Cloud provider redesign

### Done

- [ ] Recommended group equals current `topThree(primary, additional, catalog)`
- [ ] Recommended + remaining groups contain the full catalog exactly once
- [ ] Speech-pair changes recalculate without stale state
- [ ] No recommendation automatically mutates model/backend/download state
- [ ] EN Settings copy and focused tests green
- [ ] `swift test` and full QA green
- [ ] Fresh `APP_VERSION=1.0.4` build opened
- [ ] FEEDBACK status `waiting_review`

### Verify

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"
swift test
./script/qa/run_all.sh
APP_VERSION=1.0.4 ./script/build_and_run.sh --verify
```

## S3+

See master plan §4.
