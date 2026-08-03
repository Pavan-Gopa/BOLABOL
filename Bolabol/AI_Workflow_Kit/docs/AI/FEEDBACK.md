# FEEDBACK — Bolabol 1.0.4 (ASR Core ML)

> Workers fill sections on handoff. Orchestrator reads this every «статус».

---

## Meta

| Field | Value |
|-------|-------|
| Step | S1b |
| Actor | reviewer |
| Timestamp | 2026-08-03 |
| RESULT | approved |

---

## §1 — Inventory & Pass/Fail Summary

- **Working Directory**: `/Users/pavan/Documents/AI Projects/Bolabol`
- **Inventory reviewed**:
  - `Sources/NativeBolabolCore/Models/OnboardingModelRecommendation.swift` — pure R1/R2/R3 ranking.
  - `Sources/NativeBolabolCore/Models/TranscriptionModelDescriptor.swift` — descriptor API and model ID context.
  - `Tests/NativeBolabolCoreTests/OnboardingModelRecommendationTests.swift` — language matrix and availability tests.
  - `BOLABOL_ASR_COREML_INTEGRATION_PLAN.md` §3.5.3 — authoritative ranking rules.
- **Commands executed**:
  - `graphify query "OnboardingModelRecommendation TranscriptionModelDescriptor" --graph graphify-out/graph.json`: **PASS** (query completed).
  - `swift test`: **PASS** (481 tests in 4 suites).

---

## §2 — S1b Implementation Compliance

- [x] R1: `ru` in primary or additional ranks GigaAM first; additional-language tie-break matches the plan.
- [x] R2: `en/de/fr/es` pair ranks Canary Flash, Whisper Large v3, then Turbo.
- [x] R3: ranks Whisper Large v3, Turbo, then Canary 1B, Parakeet, and Flash by availability.
- [x] Uses the required model IDs, collapses unavailable models, prevents duplicate output, and caps results at three.
- [x] Ranking depends only on primary/additional speech languages; no UI language parameter.
- [x] No S1c onboarding cards, ASR engines, or engine wiring was added.
- [x] No git commit or push was performed.

---

## §3 — Unit Matrix Coverage

| Primary | Additional | Expected order |
|---------|------------|----------------|
| ru | en | GigaAM, Canary Flash, Whisper Large v3 |
| ru | ru | GigaAM, Whisper Large v3, Turbo |
| en | es | Canary Flash, Whisper Large v3, Turbo |
| en | en | Canary Flash, Whisper Large v3, Turbo |
| hi | en | Whisper Large v3, Turbo, Canary 1B |
| de | fr | Canary Flash, Whisper Large v3, Turbo |

- Missing GigaAM: output collapses to available Canary Flash and Whisper Large v3.
- Empty catalog: output is `[]`.
- Additional coverage: Russian in `additional`, code case/whitespace normalization, missing Canary 1B, R3 Flash fallback, and duplicate IDs.

---

## §4 — Changed Paths & Handoff

- `Sources/NativeBolabolCore/Models/OnboardingModelRecommendation.swift`
- `Tests/NativeBolabolCoreTests/OnboardingModelRecommendationTests.swift`
- `AI_Workflow_Kit/docs/AI/FEEDBACK.md`
- `TranscriptionModelDescriptor.swift` was reviewed; no change was needed for S1b.
- **RESULT: `approved`**

---

## §5 — Reviewer Verdict

**VERDICT: [APPROVED]** — S1b is a pure ranking helper with the required R1/R2/R3 behavior and green unit coverage.

| # | Checklist item | Result |
|---|----------------|--------|
| 1 | Pure function only; no S1c UI model cards | ✅ Pass — `topThree` only ranks available descriptors; no onboarding view or card code was added |
| 2 | R1/R2/R3 match plan §3.5.3 | ✅ Pass — RU prioritizes GigaAM; EN/DE/FR/ES pairs prioritize Canary Flash; other pairs prioritize Large v3 then Turbo |
| 3 | Required and future model ID mapping | ✅ Pass — Whisper Large v3 full/turbo, Parakeet TDT, GigaAM, Canary Flash, and Canary 1B IDs are explicit and covered by tests |
| 4 | Missing-role collapse, maximum three, no duplicates | ✅ Pass — unavailable roles are skipped, output is capped at three, and duplicate IDs are suppressed |
| 5 | No UI-language input | ✅ Pass — ranking accepts only primary/additional speech language codes and the catalog |
| 6 | Required unit matrix | ✅ Pass — ru+en, ru+ru, en+es, en+en, hi+en, de+fr plus Russian-additional, normalization, collapse, fallback, duplicate, and empty-catalog cases |
| 7 | Full test suite | ✅ Pass — `swift test`: 481 tests in 4 suites passed |
| 8 | Scope and touched product files | ✅ Pass — only the two S1b product/test files are new under `Sources`/`Tests`; `TranscriptionModelDescriptor.swift` was not changed |

### Blocking items

None.

### Non-blocking

None.

> Готово. Вернись к оркестратору и скажи статус.

---

## §6 — Tester QA Result

| Field | Value |
|-------|-------|
| Step | S1b |
| Actor | tester |
| Date | 2026-08-03 |
| Suite | `swift test` + `./script/qa/run_all.sh` + fresh build/run |
| Tests | 486 tests in 4 suites passed |
| QA gate | 19/19 passed |
| Bugs | 0 |

- Added five gap tests in `Tests/NativeBolabolCoreTests/OnboardingModelRecommendationTests.swift` for the complete compact-language matrix, R3 other-language pair, Russian-additional normalization, three-item cap, and speech-only API inputs.
- Strengthened `onboardingModelRecommendationDoesNotReturnDuplicateModels` with an exact expected R1 order.
- Added `script/qa/check_s1b_scope.sh`; updated the existing Canary product guard to allow only the pure S1b ranking helper's model IDs.
- Gap-hunt mapping for all 15 requested items is recorded in the new S1b section of `REPORT.md`.
- Manual UI ranking verification is not applicable because S1b has no visible UI state. `APP_VERSION=1.0.4 ./script/build_and_run.sh --verify` built and opened a fresh `Bolabol.app`; bundle version verified as `1.0.4`.
- `Sources/**` and `STATE.yaml` were not changed by Tester. No S1c UI, engine wiring, or Canary/GigaAM runtime integration was added.

**RESULT: qa_green**
