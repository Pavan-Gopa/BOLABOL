# FEEDBACK — Bolabol 1.0.4 (ASR Core ML)

> Workers fill sections on handoff. Orchestrator reads this every status check.

## Meta

| Field | Value |
|-------|-------|
| Step | S1c |
| Actor | coder |
| Timestamp | 2026-08-03T10:47:52Z |
| RESULT | waiting_review |

## §1 — Inventory & Pass/Fail Summary

- **Working Directory**: `/Users/pavan/Documents/AI Projects/Bolabol`
- **Required Graphify commands**: all four completed against `graphify-out/graph.json`:
  - `graphify explain "OnboardingView" --graph graphify-out/graph.json`
  - `graphify explain "OnboardingModelRecommendation" --graph graphify-out/graph.json`
  - `graphify path "OnboardingView" "TranscriptionModelStore" --graph graphify-out/graph.json`
  - `graphify query "onboarding local model cards and localization" --graph graphify-out/graph.json`
- **Reviewed context**: AGENTS.md chain, TEAM_CONTRACT.md, STATE.yaml (read-only), ASR S1c card, integration plan §§3.1/3.5/4/6–7, prior FEEDBACK.md, and REPORT.md.
- **Changed product/test paths**:
  - `Sources/NativeBolabol/Views/OnboardingView.swift`
  - `Sources/NativeBolabolCore/Services/AppText.swift`
  - `Tests/NativeBolabolCoreTests/OnboardingLocalizationTests.swift`
- `STATE.yaml` was not changed. No commit, tag, or push was performed.

## §2 — S1c Implementation Compliance

- [x] Step order is UI language → primary → additional → local models → permissions → modes → glossary → theme.
- [x] Local model cards come only from `OnboardingModelRecommendation.topThree(primary:additional:available:)` using current settings and `transcriptionModelStore.models`.
- [x] The former hard-coded preferred-ID order, active-model injection, and duplicated R1/R2/R3 logic were removed from `OnboardingView`.
- [x] The computed card list has no `@State` or cache, so Back → language changes → Forward recomputes ranking.
- [x] Missing/NO-GO descriptors collapse naturally to the available result, capped at three; no placeholders are inserted.
- [x] Only slot #1 receives the localized Recommended badge and Best match subtitle.
- [x] Existing Download, progress, retry, Use, and active-state actions remain on the existing `TranscriptionModelStore` pipeline; successful download still activates through that store.
- [x] Next and Skip do not require a download and do not change backend/activeModelID when no card action is taken.
- [x] Cloud runtime/store support was not changed; this step only removes the old cloud choice/setup from the dedicated local-model onboarding screen.
- [x] Added EN source keys for title, hint, recommendation, best-match subtitle, and Settings → Local Models footer.

## §3 — Verification

| Command | Result |
|---------|--------|
| `swift test` | **PASS** — 488 tests in 4 suites |
| `./script/qa/run_all.sh` | **18/19** — 18 passed; `check_s1b_scope.sh` failed because its S1b-era rule rejects the S1c-required `topThree` call from `OnboardingView`. No QA script was changed because it is outside the permitted files. |
| `swift package clean` | **PASS** |
| `APP_VERSION=1.0.4 ./script/build_and_run.sh --verify` | **PASS** — NativeBolabol and NativeBolabolPolishWorker built, app launched, verify returned successfully |
| `plutil -p dist/Bolabol.app/Contents/Info.plist` | **PASS** — `CFBundleShortVersionString => "1.0.4"` |
| `pgrep -x Bolabol` | **PASS** after fresh build/run; process observed |

- Manual UI verification was attempted after the successful build. The current automation session exposed no accessible Bolabol window to System Events/CGWindow, so the four visual checks (ranked screen, Back/reorder, no-download Next, slot #1 badge only) are **not claimed as completed**.
- Build-time warnings were pre-existing dependency/deprecation warnings (`AudioPlaybackModalView` duration, SwiftPM dependency identity, FluidAudio benchmark resource); they did not fail the build.

## §4 — Changed Paths & Handoff

- `Sources/NativeBolabol/Views/OnboardingView.swift`
- `Sources/NativeBolabolCore/Services/AppText.swift`
- `Tests/NativeBolabolCoreTests/OnboardingLocalizationTests.swift`
- `AI_Workflow_Kit/docs/AI/FEEDBACK.md`
- Focused localization tests cover EN non-empty/non-raw keys, the real Settings → Local Models path, and the tour key list used by the updated view.
- Known follow-up for Orchestrator: refresh the S1b-only scope gate for S1c before treating the full QA gate as green; do not change the product implementation to evade that guard.
- **RESULT: `waiting_review`**

> Готово. Вернись к оркестратору и скажи статус.

---

## §5 — Independent Reviewer Verification

| Field | Value |
|-------|-------|
| Role | Verification Engineer (independent review) |
| Scope | S1c — Onboarding: 3 dynamic local-model cards |
| Reviewed files | `OnboardingView.swift`, `AppText.swift`, `OnboardingLocalizationTests.swift` |
| Graphify | Fresh S1c symbols present; 4176 nodes / 9717 edges |

### Findings

- **None, product/test severity:** no blocking or non-blocking defect was found in the S1c implementation or its target tests.
- **INFO, workflow gate only, not a product defect:** `script/qa/check_s1b_scope.sh:30` rejects the required S1c call from `Sources/NativeBolabol/Views/OnboardingView.swift:365`. S1c explicitly requires this call, so the `18/19` QA result is an obsolete S1b rule. No product change is requested and the QA script was not modified.

### Command Results

| Command | Result |
|---------|--------|
| `graphify explain "OnboardingView" --graph graphify-out/graph.json` | **PASS**; fresh `OnboardingView` at `Sources/NativeBolabol/Views/OnboardingView.swift:13` |
| `graphify explain "OnboardingModelRecommendation" --graph graphify-out/graph.json` | **PASS**; fresh `.topThree()` symbol present |
| `graphify path "OnboardingView" "OnboardingModelRecommendation" --graph graphify-out/graph.json` | **PASS**; path reaches `.topThree()` through `TranscriptionModelDescriptor` |
| `graphify query "S1c onboarding local model cards ranking localization" --graph graphify-out/graph.json` | **PASS**; BFS completed with S1c symbols in context |
| `git diff --check -- .` | **PASS**; no whitespace errors |
| `git diff --stat -- .` | **PASS**; full diff reviewed; target-scope diff is limited to the three S1c files |
| `git diff -- Sources/NativeBolabol/Views/OnboardingView.swift Sources/NativeBolabolCore/Services/AppText.swift Tests/NativeBolabolCoreTests/OnboardingLocalizationTests.swift` | **PASS**; complete target diff reviewed |
| `git diff --name-only -- Sources Tests script/qa` | **PASS**; exactly the three target paths, no QA script changes |
| `swift test` | **PASS**; 488 tests in 4 suites |
| `swift build` | **PASS**; executable target compiled; only pre-existing SwiftPM/dependency warnings |
| `./script/qa/run_all.sh` | **18/19**; 18 passed, only `check_s1b_scope.sh` failed for the stale rule documented above |

### S1c Acceptance Review

| # | Status | Evidence |
|---|--------|----------|
| 1. Onboarding order | **PASS** | `Sources/NativeBolabol/Views/OnboardingView.swift:97-114` maps UI language → primary → additional → local models → permissions → modes → glossary → theme. |
| 2. No hard-coded screen-3 preferred/model-ID order | **PASS** | `Sources/NativeBolabol/Views/OnboardingView.swift:362-369` contains no preferred IDs or model-ID ordering. |
| 3. Cards use the required `topThree` call | **PASS** | `Sources/NativeBolabol/Views/OnboardingView.swift:365-369` passes current primary, additional, and `transcriptionModelStore.models` exactly. |
| 4. No duplicated R1/R2/R3 rules in the view | **PASS** | `Sources/NativeBolabol/Views/OnboardingView.swift:362-369` delegates ranking to the helper only. |
| 5. Recalculation from current store state | **PASS** | `onboardingModels` is a computed property at `Sources/NativeBolabol/Views/OnboardingView.swift:362-369`; no stale model-list `@State` exists. |
| 6. Up to three cards; missing/NO-GO entries collapse | **PASS** | `Sources/NativeBolabol/Views/OnboardingView.swift:348-351` renders only the helper result; `OnboardingModelRecommendation.swift:47-60` skips unavailable IDs and caps at three. |
| 7. Recommended and Best-match copy only on slot #1 | **PASS** | `Sources/NativeBolabol/Views/OnboardingView.swift:390-410` uses `slot == 0`; later cards use only their ordinary badge. |
| 8. Existing model actions preserved | **PASS** | `Sources/NativeBolabol/Views/OnboardingView.swift:376-436` preserves state/progress/error rendering and `:456-503` preserves Download, Retry, Use, and active actions. |
| 9. Download remains optional and does not auto-select | **PASS** | Next is enabled at `Sources/NativeBolabol/Views/OnboardingView.swift:141-150`; only explicit model actions call download/activate at `:459-494`; finish only completes onboarding at `:950-953`. |
| 10. Cloud runtime/store untouched; only screen-3 cloud setup removed | **PASS** | The target diff removes the old cloud choice/setup from `localModelsStep`; no cloud source/store path appears in `git diff --name-only -- Sources Tests script/qa`. |
| 11. Five EN keys exist and are non-raw | **PASS** | Enum declarations at `Sources/NativeBolabolCore/Services/AppText.swift:415-420`, EN values at `:1158-1166`, and tests at `Tests/NativeBolabolCoreTests/OnboardingLocalizationTests.swift:120-128`. |
| 12. Change-later copy names the real Settings path | **PASS** | `Sources/NativeBolabolCore/Services/AppText.swift:1166` says `Settings → Local Models`; path assertions are at `Tests/NativeBolabolCoreTests/OnboardingLocalizationTests.swift:132-140`. |
| 13. Tests cover EN model copy and the onboarding key list | **PASS** | S1c key list is at `Tests/NativeBolabolCoreTests/OnboardingLocalizationTests.swift:21-28`; the tour key contract is at `:91-117`; EN resolution is asserted at `:120-128`. |
| 14. No S2/S3/S4+, new engines, Python, or unrelated refactor | **PASS** | Source/test scope is exactly the three target paths; no `script/qa` changes and no new runtime/engine files are present in the target diff. |

### Change List

- **CODER:** none. No product or target-test change is required.
- **Tester/Orchestrator follow-up:** update the S1b-only allowlist in `script/qa/check_s1b_scope.sh:21-30` for the S1c-required `OnboardingView.topThree` call before declaring the full QA gate green. This is outside the Reviewer permission boundary and is not a reason to alter product code.

### Verdict

**RESULT: `APPROVED`**

Product implementation conforms to S1c and `swift test` is green. The single red QA result is an independently confirmed stale S1b scope gate, not a product/test defect.

Готово. Вернись к оркестратору и скажи статус.

---

## §6 — Independent Tester QA

| Field | Value |
|-------|-------|
| Role | Tester |
| Step | S1c — Onboarding: 3 dynamic local-model cards |
| Date | 2026-08-03 |
| RESULT | `qa_green` |

### What was added

- Added `script/qa/check_s1c_onboarding_models.sh` for the S1c SwiftUI structure: fixed eight-step order, `localModelsStep`, one `topThree` call with current speech languages and `transcriptionModelStore.models`, computed cards, no hard-coded IDs/cache/placeholders, slot-zero labels, optional Next, existing store actions, five AppText keys, and no Python/Canary/GigaAM runtime wiring.
- Narrowly updated `script/qa/check_s1b_scope.sh` so only the required `topThree` call in `Sources/NativeBolabol/Views/OnboardingView.swift` is allowed; all S1b purity and runtime prohibitions remain active.
- Confirmed `run_all.sh` includes the new check through its `check_*.sh` contract glob.
- Added no Swift tests because the identified gaps were view-source structural contracts; existing 488-test ranking/localization coverage was re-run.

### Full gate

| Command | Result |
|---------|--------|
| `bash -n script/qa/check_s1b_scope.sh` | PASS |
| `bash -n script/qa/check_s1c_onboarding_models.sh` | PASS |
| `swift test` | PASS — 488 tests in 4 suites |
| `./script/qa/run_all.sh` | PASS — 20/20 |
| `git diff --check -- .` | PASS |

Baseline before the QA changes was `swift test` 488/4 PASS and `run_all.sh` 18/19, with only the obsolete S1b scope gate red. Both S1b and S1c checks pass independently after the change.

### Manual verification

- `swift package clean`: PASS.
- `APP_VERSION=1.0.4 ./script/build_and_run.sh --verify`: PASS; NativeBolabol and NativeBolabolPolishWorker built and verify returned successfully.
- `plutil -p dist/Bolabol.app/Contents/Info.plist`: PASS; `CFBundleShortVersionString` is `1.0.4`, executable/name `Bolabol`, bundle id `com.bolabol.app`.
- `pgrep -ifl "Bolabol|NativeBolabol"`: PASS; fresh `dist/Bolabol.app/Contents/MacOS/Bolabol` process observed.
- Live accessibility inspection: screen 3 showed one card for the thin RU+EN catalog; after changing the pair to English+French it showed two cards, with Recommended and Best Match only on the first. The full three-card Back-loop, no-download transition, and light theme are `UNVERIFIED` because the available catalog and UI session did not support a stable check. The original RU+EN language pair was restored.

Tester did not modify `Sources/**`, `Package.swift`, `STATE.yaml`, or Graphify artifacts. No product defect was found, so `BUG_REPORT.md` remains unchanged with `bugs_open: 0`.

**RESULT: `qa_green`**

> Готово. Вернись к оркестратору и скажи статус.
