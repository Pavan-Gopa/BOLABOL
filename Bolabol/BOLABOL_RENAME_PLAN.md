# Внеочередной план: переименование Blaboom → Bolabol

| | |
|--|--|
| **Тип** | Out-of-band / pre-S1b gate |
| **Цель** | Полный ребрендинг продукта **Blaboom / BLABOOM / blaboom / NativeBlaboom** → **Bolabol / BOLABOL / bolabol / NativeBolabol** |
| **После** | Продолжение train 1.0.4 ASR Core ML с шага **S1b** (ranking) |
| **Код пишут** | Только внешние агенты (Coder → Reviewer → Tester) |
| **Оркестратор** | Kicks, STATE, checkpoints — **не** product-rename сам |

> **Важно:** в предыдущей сессии мог быть **частичный** rename (папка `Bolabol/`, модули `NativeBolabol*`).  
> Coder **обязан** сначала inventory: что уже переименовано, что осталось, что сломано (build).  
> Не дублировать работу вслепую; довести до **полного** green состояния.

---

## 0. Канонические замены

| Было | Стало |
|------|--------|
| `Blaboom` | `Bolabol` |
| `BLABOOM` | `BOLABOL` |
| `blaboom` | `bolabol` |
| `NativeBlaboom` | `NativeBolabol` |
| `NativeBlaboomCore` | `NativeBolabolCore` |
| `NativeBlaboomPolishWorker` | `NativeBolabolPolishWorker` |
| `NativeBlaboomCoreTests` | `NativeBolabolCoreTests` |
| `NativeBlaboomLog` | `NativeBolabolLog` |
| `BlaboomNote` | `BolabolNote` |
| `BlaboomLogo*` / `BlaboomButton*` / … | `BolabolLogo*` / … |
| `com.blaboom.app` | `com.bolabol.app` |
| `Blaboom.app` / `Blaboom.dmg` | `Bolabol.app` / `Bolabol.dmg` |
| git tags prefix `blaboom/` | **новые** tags `bolabol/` (старые tags можно оставить как history) |
| plan files `BLABOOM_*.md` | `BOLABOL_*.md` |

**Не трогать без отдельного ADR (если не product brand):**

- Имена чужих пакетов (FluidAudio, WhisperKit, mlx-swift, …)
- Remote git URL / GitHub repo name — **только если Human явно попросит** (по умолчанию: rename local product, remote optional)
- User data legacy paths (`NativeSmartScribe`, старые glossary JSON) — **migrate или alias** см. §3

---

## 1. Шаги workflow (R0–R4)

| Step | Actor | Goal |
|------|--------|------|
| **R0** | Coder | Inventory + complete rename (files, modules, strings, scripts, docs) |
| **R1** | Reviewer | Diff scope + brand consistency + no leftover Blaboom in product surface |
| **R2** | Tester | `swift test` + `run_all` + smoke identity (app name, bundle id) |
| **R3** | Orchestrator | POST tag `bolabol/R0-done` (or `bolabol/rename-done`), update STATE → resume **S1b** |
| **R4** | Coder (next) | Kick **S1b** as planned (ranking) — after R3 |

Orchestrator after Human «статус»:

```
R0 Coder → Reviewer → Tester green → POST rename → Kick S1b Coder
```

---

## 2. R0 — Coder scope (полный rename)

### 2.1. Inventory (обязательный первый шаг)

```bash
cd "/Users/pavan/Documents/AI Projects"
# project root may already be Bolabol/ or still Blaboom/
ls -la | grep -iE 'blab|bolab'
find . -maxdepth 3 -iname '*blaboom*' 2>/dev/null | head -50
# inside product tree:
grep -riIn 'blaboom\|NativeBlaboom\|BLABOOM' --exclude-dir=.build --exclude-dir=dist --exclude-dir=graphify-out --exclude-dir=scratch | head -100
```

Записать в FEEDBACK: current root path, partial-done list, remaining hits.

### 2.2. Package / targets

- `Package.swift`: package name, products, targets → `NativeBolabol*`
- Test target `NativeBolabolCoreTests`
- All `@testable import` / imports

### 2.3. Source tree renames

| Path pattern | Action |
|--------------|--------|
| `Sources/NativeBlaboom/` | → `Sources/NativeBolabol/` |
| `Sources/NativeBlaboomCore/` | → `Sources/NativeBolabolCore/` |
| `Sources/NativeBlaboomPolishWorker/` | → `Sources/NativeBolabolPolishWorker/` |
| `Tests/NativeBlaboomCoreTests/` | → `Tests/NativeBolabolCoreTests/` |
| `*Blaboom*.swift`, logos `BLABOOM_*.svg` | rename files + types inside |
| Parent folder `…/Blaboom` | → `…/Bolabol` (if still old name) |

Use `git mv` where possible.

### 2.4. Identity & scripts

- `Info.plist`: CFBundleName/DisplayName/Executable/Identifier → Bolabol / `com.bolabol.app`
- `script/build_and_run.sh`, `build_release_dmg.sh`, `install.sh`, `notarize_dmg.sh`, qa scripts
- `APP_NAME`, `DISPLAY_NAME`, `BUNDLE_ID`, product binary names
- Codesign identity strings that embed product name (local dev cert name if present — document if Human must recreate cert)
- `AI_Workflow_Kit/**` docs & `checkpoint.sh` tag prefix → `bolabol/` for **new** tags
- Plan/docs: `BLABOOM_*.md` → `BOLABOL_*.md`; all narrative strings

### 2.5. App text / UX strings

- Any user-visible «Blaboom» in `AppText` maps (all locales if present)
- Help / onboarding / about strings

### 2.6. Runtime paths (careful)

| Item | Policy |
|------|--------|
| Application Support folder name | Prefer `Bolabol`; if old `Blaboom`/`NativeSmartScribe` data exists — **one-release migration** or documented dual-read |
| SharedModelsRoot | Align with new brand if branded |
| Log subsystem names | `NativeBolabolLog` etc. |

### 2.7. Out of scope for R0

- S1b ranking / S1c model cards / Canary / GigaAM engines
- Force-push / rewrite old git tags history
- Notarize / release DMG (unless needed to prove identity)
- Renaming GitHub remote without Human OK

### 2.8. Done criteria (Coder)

- [ ] No product-surface hits for `Blaboom`/`blaboom`/`NativeBlaboom`/`BLABOOM` in Sources, Tests, script, Package.swift, Info.plist, AI_Workflow_Kit docs (except historical ADR quotes if intentional — prefer rewrite)
- [ ] Folder + module names use Bolabol
- [ ] `swift test` green
- [ ] `APP_VERSION` build verify produces `Bolabol.app` with display name Bolabol
- [ ] FEEDBACK RESULT `waiting_review`

### 2.9. Verify commands

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"   # or actual root after rename
swift test
./script/qa/run_all.sh
# optional:
APP_VERSION=1.0.3 ./script/build_and_run.sh verify
plutil -p dist/Bolabol.app/Contents/Info.plist | grep -E 'Name|Identifier|ShortVersion'
grep -riIn 'blaboom\|NativeBlaboom' Sources Tests Package.swift script --exclude-dir=.build || echo CLEAN
```

---

## 3. Data migration note (Tester + Coder)

If users already have:

`~/Library/Application Support/…Blaboom…` or legacy SmartScribe paths

Coder should either:

1. **Migrate** prefs/notes on first launch to Bolabol paths, or  
2. **Document** breaking change (dev-only OK) in FEEDBACK + RELEASE notes draft.

Tester: verify no crash on missing old path; if migration code added, test both fresh install and legacy folder present (if feasible).

---

## 4. Reviewer checklist (R1)

1. Diff is rename-only (no silent feature work).  
2. Bundle id + display name + executable consistent.  
3. Package products/targets match folder names.  
4. Scripts install/launch **Bolabol.app**.  
5. No leftover Blaboom in Sources/Tests/script (spot + grep).  
6. Logos/resources paths resolve.  
7. `swift test` green.  
8. Workflow kit / plan filenames updated; STATE still points to valid plan paths (`BOLABOL_ASR_COREML_INTEGRATION_PLAN.md`).

---

## 5. Tester checklist (R2)

1. `swift test` full green.  
2. `./script/qa/run_all.sh` green (fix any hardcoded Blaboom paths in qa).  
3. Grep CLEAN for blaboom in product surfaces.  
4. Optional: launch `dist/Bolabol.app` — window title / about if any.  
5. Gap-hunt: qa scripts, RESTRUCTURE docs, README badges.  
6. REPORT: rename verification; FEEDBACK §6 `qa_green`.

---

## 6. Orchestrator after green

1. Commit message style: `chore(bolabol): full product rename Blaboom → Bolabol`  
2. Tag: `bolabol/rename-done`  
3. STATE:

```yaml
current_step: S1b
completed_steps: [S0, S1, RENAME]
# plan_files:
#   - BOLABOL_ASR_COREML_INTEGRATION_PLAN.md
#   - AI_Workflow_Kit/docs/ASR_COREML_STEPS.md
#   - BOLABOL_RENAME_PLAN.md  # this file, archive
next_actor: coder
```

4. Kick **S1b** (OnboardingModelRecommendation) — path project root = **Bolabol**.

---

## 7. Риски

| Risk | Mitigation |
|------|------------|
| Partial rename leaves half tree | Inventory first; one Coder pass to completion |
| TCC / codesign breaks (new bundle id) | Expected; document re-grant mic/accessibility |
| Shell/tools still cwd `…/Blaboom` | Symlink or reopen sessions on Bolabol path |
| qa scripts embed old names | Tester gap-hunt |
| Graphify paths stale | Rebuild after rename |

---

## 8. Definition of Done (rename)

- [ ] Product brand Bolabol everywhere user/developer-facing in-repo  
- [ ] Modules NativeBolabol*  
- [ ] Bundle `com.bolabol.app`  
- [ ] Tests + QA green  
- [ ] Review approved  
- [ ] Tag + STATE resume **S1b**

---

## 9. Kick order (Human)

1. **Coder R0** — full rename (kick below in orchestrator message)  
2. «статус» → Reviewer  
3. «статус» → Tester  
4. «статус» → Orchestrator POST → **Coder S1b**

---

*Конец внеочередного плана. Код rename выполняют только внешние агенты.*
