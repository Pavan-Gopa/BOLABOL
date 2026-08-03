# FEEDBACK — Bolabol 1.0.4 (ASR Core ML)

> Workers fill sections on handoff. Orchestrator reads this every «статус».

---

## Meta

| Field  | Value          |
|--------|----------------|
| Step   | RENAME         |
| Actor  | reviewer       |
| Timestamp | 2026-08-03   |
| RESULT | approved       |

---

## §1 — Inventory & Pass/Fail Summary

- **Working Directory**: `/Users/pavan/Documents/AI Projects/Bolabol`
- **Initial Inventory**:
  - Codebase root: `Bolabol/`
  - Modules in `Sources/`: `NativeBolabol`, `NativeBolabolCore`, `NativeBolabolPolishWorker`
  - Test modules in `Tests/`: `NativeBolabolCoreTests`
  - App identity in `Sources/NativeBolabol/Resources/Info.plist`: `Bolabol`, `com.bolabol.app`
  - Product surface hits in `Sources`, `Tests`, `Package.swift`, `script`: **CLEAN** (0 leftover occurrences)
- **Verification Commands Executed**:
  - `swift test`: **PASS** (473/473 tests passed in 4 suites)
  - `./script/qa/run_all.sh`: **PASS** (18/18 QA check scripts green)
  - `APP_VERSION=1.0.3 ./script/build_and_run.sh verify`: **PASS** (produced `dist/Bolabol.app`)
  - Plist check: `CFBundleDisplayName` = `Bolabol`, `CFBundleIdentifier` = `com.bolabol.app`, `CFBundleExecutable` = `Bolabol`

---

## §2 — Rename Checklist

- [x] **Modules & Targets**: `NativeBolabol`, `NativeBolabolCore`, `NativeBolabolPolishWorker`, `NativeBolabolCoreTests`
- [x] **Bundle ID & Identity**: `com.bolabol.app`, Display Name `Bolabol`, Executable `Bolabol`
- [x] **Scripts**: `build_and_run.sh`, `build_release_dmg.sh`, `install.sh`, `notarize_dmg.sh`, all QA scripts targeting `Bolabol.app` and `Bolabol.dmg`
- [x] **Docs & Plans**: `BOLABOL_RENAME_PLAN.md`, `BOLABOL_ASR_COREML_INTEGRATION_PLAN.md`, `BOLABOL_1.0.3_IMPLEMENTATION_PLAN.md`, `README.md`
- [x] **Product Surface Grep**: `CLEAN` across `Sources/`, `Tests/`, `Package.swift`, `script/`

---

## §3 — Migration & TCC Notes

- **Application Support Path**: Stores use `~/Library/Application Support/NativeBolabol/` for note/glossary persistence.
- **TCC / Permissions**: Changing bundle ID to `com.bolabol.app` requires macOS to re-prompt for Microphone and Accessibility permissions upon first launch.

---

## §4 — Key Path & Module Renames

- `Sources/NativeBolabol`
- `Sources/NativeBolabolCore`
- `Sources/NativeBolabolPolishWorker`
- `Tests/NativeBolabolCoreTests`
- `dist/Bolabol.app`
- `dist/Bolabol.dmg`

---

## §5 — Reviewer Verdict (R1)

**VERDICT: [APPROVED]** — product rename is complete, rename-only, and green.

| # | Checklist item | Result |
|---|----------------|--------|
| 1 | Diff is rename/identity only (no silent S1b/Canary/GigaAM) | ✅ Pass — full diff scanned; changes are brand string/module/plist renames only; `gigaam/canary/s1b` hits confined to historical ADR IDs in AI_Workflow_Kit docs |
| 2 | Modules `NativeBolabol` / `Core` / `PolishWorker` / `CoreTests` | ✅ Pass — Package.swift products/targets match folder names |
| 3 | Bundle `com.bolabol.app`, display/executable `Bolabol` | ✅ Pass — plutil: CFBundleName/DisplayName/Executable `Bolabol`, Identifier `com.bolabol.app` |
| 4 | Scripts build/launch `Bolabol.app` | ✅ Pass — APP_NAME=`Bolabol`, BUNDLE_ID=`com.bolabol.app`, APP_BUNDLE=`$DIST_DIR/Bolabol.app`; `dist/Bolabol.app` present |
| 5 | Product surfaces grep CLEAN | ✅ Pass — `Sources/`, `Tests/`, `Package.swift`, `script/` zero hits. STATE.yaml historical references are outside the product surface. |
| 6 | Plan/docs filenames `BOLABOL_*`; STATE plan_files valid | ✅ Pass — BOLABOL_RENAME_PLAN.md, BOLABOL_ASR_COREML_INTEGRATION_PLAN.md, AI_Workflow_Kit/docs/ASR_COREML_STEPS.md all exist |
| 7 | `swift test` green | ✅ Pass — 473 tests / 4 suites green |
| 8 | Residual pre-rename dist artifacts | ✅ OK as residual — scripts now write `Bolabol.app`/`Bolabol.dmg`; old builds can be deleted by Human |

**Notes (non-blocking):**
- `STATE.yaml` `last_post_tag` is a historical tag reference — new tags must use the `bolabol/` prefix (plan §0).
- Tester (R2) completed: `./script/qa/run_all.sh` (18/18) + smoke identity on `dist/Bolabol.app`.
- No git commit performed (out of scope for Reviewer; Orchestrator owns the rename commit).

---

## §6 — Tester Verdict (R2)

| Check | Result |
|---|---|
| Full Swift suite | PASS — 473 tests in 4 suites |
| Full QA gate | PASS — 18/18 steps |
| Product-surface legacy-brand grep | CLEAN |
| Source Info.plist identity | PASS — `Bolabol`, `com.bolabol.app`, executable `Bolabol` |
| Optional app build verify | PASS — `dist/Bolabol.app` produced and launched |

Gap-hunt found no stale references in `script/qa`, release identity tests, or build scripts. The standalone `scratch/test_persistence.swift` helper had one stale module import; it now uses `NativeBolabolCore`. No product feature changes, commit, or push were made.

**RESULT: `qa_green`**

---

## Handoff line (all)

> Готово. Вернись к оркестратору и скажи статус.
