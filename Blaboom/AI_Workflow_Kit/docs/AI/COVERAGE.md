# Coverage notes — Blaboom 1.0.3 train

Living checklist of automated vs manual coverage for the bilingual + Canary train.
Full matrices live in `BLABOOM_1.0.3_IMPLEMENTATION_PLAN.md` §12.

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

## Manual (§12.2 matrix — B12 target)

| ID | Scenario | Status |
|----|----------|--------|
| M1 | Onboarding primary + additional | Ready for B12 smoke |
| M2 | Additional → Settings sync | Ready for B12 smoke |
| M3 | Parakeet A / auto mode | Ready for B12 smoke |
| M4 | Canary HUD | N/A (ADR-012 Canary skipped) |
| M5–M6 | Canary offline dictation/switch | N/A (ADR-012 Canary skipped) |
| M7 | V1/V2 Polish MLX/cloud | Ready for B12 smoke |
| M8 | UI Turkish layout & stats | Ready for B12 smoke |
| M9 | Language list picker order | Ready for B12 smoke |
| M10 | Help EN/multilingual sections | Ready for B12 smoke |

## Verification Commands

```bash
cd "/Users/pavan/Documents/AI Projects/Blaboom"
swift test
./script/qa/run_all.sh
```
