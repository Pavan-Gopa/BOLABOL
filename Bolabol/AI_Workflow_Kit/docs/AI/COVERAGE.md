# Coverage notes — Bolabol 1.0.3 train

Living checklist of automated vs manual coverage for the bilingual + Canary train.
Full matrices live in `BOLABOL_1.0.3_IMPLEMENTATION_PLAN.md` §12.

## Automated (§12.1 matrix — B11 consolidated)

| Area | Status | Test / Script Guard |
|------|--------|---------------------|
| Language pair migration | **GREEN** | `UserSpeechLanguagesTests.swift` (B1) |
| Picker order invariants (en first; ru not #2; europe before asia) | **GREEN** | `LanguagePickerOrderTests.swift` (B1) |
| Onboarding/settings/help keys × 15 locales | **GREEN** | `AppTextFullCoverageTests.swift`, `OnboardingLocalizationTests.swift`, `SettingsLocalizationTests.swift`, `check_i18n_b2_b4_families.sh` (B2–B5) |
| Canary product absence (no false capabilities) | **GREEN** | `check_b6_canary_spike.sh`, `check_no_canary_product.sh` (**NEW B11 re-verify** — zero canary in Package.swift/Sources outside i18n help copy), `TranscriptionModelCatalogTests.swift` (`nativeTranscriptionCatalogDoesNotContainCanaryProductOrBackend`) (ADR-012 B6 NO-GO, B7–B10 skipped) |
| HUD cycle primary↔additional | **GREEN** | `HUDProviderSwitcherFeatureTests.swift`, `HUDLayoutAndComposerTests.swift` |
| ASR/AST routing matrix | **GREEN** | `TranscriptionLanguageRoutingTests.swift`, `StarterGlossaryAndLanguageRoutingTests.swift` |
| Archive stats format regression (tr/ja/ko/hi) | **GREEN** | `ArchiveStatsLocalizationTests.swift` |
| No Python in Sources | **GREEN** | `script/qa/check_no_python_in_sources.sh`, `check_b6_canary_spike.sh` (B11) |

## Manual (§12.2 matrix — B12 release build verified)

| ID | Scenario | Status |
|----|----------|--------|
| M1 | Onboarding primary + additional | **PASS** (B12 release build verified) |
| M2 | Additional → Settings sync | **PASS** (B12 release build verified) |
| M3 | Parakeet A / auto mode | **PASS** (B12 release build verified) |
| M4 | Canary HUD | **N/A** (ADR-012 Canary NO-GO) |
| M5–M6 | Canary offline dictation/switch | **N/A** (ADR-012 Canary NO-GO) |
| M7 | V1/V2 Polish MLX/cloud | **PASS** (B12 release build verified) |
| M8 | UI Turkish layout & stats | **PASS** (B12 release build verified) |
| M9 | Language list picker order | **PASS** (B12 release build verified) |
| M10 | Help EN/multilingual sections | **PASS** (B12 release build verified) |

## Verification Commands

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"
swift test
./script/qa/run_all.sh
```
