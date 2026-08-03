# Bolabol 1.0.3 — Step cards (B0–B12)

Authoritative product plan: `BOLABOL_1.0.3_IMPLEMENTATION_PLAN.md`.  
This file: **executable step cards** for `STATE.yaml` and Orchestrator kicks.

## Tracks

| Track | Steps | Theme |
|-------|-------|--------|
| **FOUNDATION** | B0 → B1 | Version train, language-pair store, picker order |
| **UX** | B2 → B5 | Onboarding, Settings, Help EN, i18n × 15 |
| **CANARY** | B6 → B10 | Core ML spike, catalog, engine, HUD, local models UI |
| **RELEASE** | B11 → B12 | QA suite, 1.0.3 test build |

## Global quality (every coding step)

- Diff **only** in `STATE.yaml` → `target_files`.
- Keep package buildable: `swift test` green (or scoped tests if STATE says so).
- **No Python** in Sources / runtime path.
- English in code comments; role headers on new modules.
- Terminology: **primary** + **additional** (never «target always output»).
- Graphify first before large exploration.
- Workers do **not** commit; Orchestrator runs `checkpoint.sh` + graphify after green cycles.

---

## B0 — Version train + workflow kit ready

### Goal

1.0.3 branch identity, version string defaults, AI_Workflow_Kit live for Bolabol (not Torrentino). Master plan is the only plan file.

### Requirements

1. Docs/scripts reference **1.0.3** where version is set for this train.
2. `AI_Workflow_Kit` fully Bolabol-scoped (STATE B0/B1…, no TORRENTINO remnants).
3. `BOLABOL_1.0.3_IMPLEMENTATION_PLAN.md` present and authoritative.
4. Checkpoint + graphify scripts work from Bolabol product dir.

### target_files (typical)

```yaml
target_files:
  - AI_Workflow_Kit/**
  - BOLABOL_1.0.3_IMPLEMENTATION_PLAN.md
  - docs/RELEASE.md
  - docs/RELEASE_NOTES.md
  - script/build_and_run.sh
  - script/build_release_dmg.sh
  - Sources/NativeBolabol/Resources/Info.plist
```

### Out of scope

- Product bilingual UI / Canary engine code (B1+)

### Done

- [ ] Kit consistent; STATE points at next product step after B0 close
- [ ] Version narrative 1.0.3
- [ ] No Torrentino strings in kit docs

### Rollback

Tag `bolabol/pre-B0`

---

## B1 — Language pair store + picker order

### Goal

Canonical `UserSpeechLanguages` (primary + additional), migration from legacy prefs, `LanguagePickerOrder` (English → Europe incl. ru/uk → Asia/other).

### Requirements

1. Codable store fields: `primaryLanguageCode`, `additionalLanguageCode` (may be equal).
2. Migration best-effort from old transcription / force-target prefs.
3. `LanguagePickerOrder` for UI + speech pickers; unit tests:
   - `en` first among speech/UI lists (excluding System sentinel)
   - `ru` not index 1
   - Europe before Asia (`ru` before `zh`)
4. No UI copy calling additional «target always».

### target_files (example — refine in STATE)

```yaml
target_files:
  - Sources/NativeBolabolCore/Models/**  # UserSpeechLanguages, LanguagePickerOrder
  - Sources/NativeBolabol/Stores/GeneralSettingsStore.swift
  - Sources/NativeBolabol/Stores/HotkeySettingsStore.swift
  - Tests/NativeBolabolCoreTests/**      # order + migration tests
```

### Out of scope

- Onboarding steps (B2), Settings chrome (B3), Canary (B6+)

### Done

- [ ] Unit tests green for store + order invariants
- [ ] Migration path documented in DECISIONS if non-obvious

### Rollback

`bolabol/pre-B1`

---

## B2 — Onboarding primary + additional

### Goal

After UI language: ask **primary** then **additional** (or one screen, two blocks); persist to same store as Settings; option «same as primary».

### Requirements

1. Steps order per plan §6.1.
2. EN AppText keys for new copy (full 15 langs in B5).
3. Fresh tour writes both fields.
4. Picker uses `LanguagePickerOrder`.

### Out of scope

- Full i18n (B5), Help (B4), Canary

### Done

- [ ] Onboarding writes primary + additional
- [ ] No en-ru as forced top-2 ordering

### Rollback

`bolabol/pre-B2`

---

## B3 — Settings UI (primary + additional)

### Goal

Explicit Settings controls for primary + additional; sync with store; honest hints (not «target always»).

### Requirements

1. Path: Settings → Hotkey and/or General (plan §7).
2. «Same as primary» behavior.
3. Values match onboarding after change either side.

### Done

- [ ] Settings == store; copy guidelines met

### Rollback

`bolabol/pre-B3`

---

## B4 — Help (EN structure)

### Goal

Help section «Your languages» / bilingual model per plan §8; update helpLang / HUD keys in EN.

### Requirements

1. Explains primary vs additional, onboarding, Settings path, auto engines, Canary HUD, polish note.
2. Insert section in HelpSettingsView logically (after HUD / language).

### Done

- [ ] EN Help complete in app Help surface

### Rollback

`bolabol/pre-B4`

---

## B5 — i18n × 15 UI languages

### Goal

All new/updated onboarding, Settings, Help, error strings in:  
en, ru, es, de, fr, it, pt, zh, ja, ko, ar, hi, uk, tr, pl.

### Requirements

1. No raw-key fallback in localization tests.
2. Positional format args (`%1$@`) for multi-arg strings.
3. RTL spot-check note for ar.

### Done

- [ ] Localization tests green

### Rollback

`bolabol/pre-B5`

---

## B6 — Canary Core ML spike (GO / NO-GO)

### Goal

Load HF Core ML package, ASR smoke (EN), AST pair if possible, lang-token audit, metrics → `docs/canary/COREML_SPIKE.md`. **No Python.**

### Requirements

1. Artifact: https://huggingface.co/alexwengg/canary-1b-v2-coreml  
2. Write GO or NO-GO with evidence.
3. Document real supported languages (do not invent 25).

### Out of scope

- Product catalog integration (B7) unless needed for spike harness

### Done

- [ ] `docs/canary/COREML_SPIKE.md` with GO/NO-GO
- [ ] No Python runtime path introduced

### Rollback

`bolabol/pre-B6`

**Gate:** NO-GO → Orchestrator opens DECISIONS + may skip/narrow B7–B10.

---

## B7 — Catalog, presence, download

### Status (1.0.3)

**SKIPPED** — ADR-012. alexwengg Canary Core ML is **NO-GO** (B6). No catalog/download for that artifact in this train.

### Rollback

`bolabol/pre-B7` (not opened)

---

## B8 — CanaryCoreMLEngine

### Status (1.0.3)

**SKIPPED** — ADR-012. No product Canary engine.

### Rollback

`bolabol/pre-B8` (not opened)

---

## B9 — Dictation wiring + HUD Canary logic

### Status (1.0.3)

**SKIPPED** — ADR-012. Non-Canary HUD A / auto path unchanged (B1–B5 already ship primary+additional store + Help copy that mentions Canary “when available” as future).

### Rollback

`bolabol/pre-B9` (not opened)

---

## B10 — Local Models UI + banners

### Status (1.0.3)

**SKIPPED** — ADR-012. No Canary card / auto-unavailable banner for unshipped engine.

### Rollback

`bolabol/pre-B10` (not opened)

---

## B11 — QA suite + scripts

### Goal

Unit coverage for plan §12.1 + `script/qa` checks: native-only, bilingual keys, catalog, no Python.

### Requirements

1. `swift test` green  
2. `./script/qa/run_all.sh` green  

### Done

- [ ] Both green; REPORT.md written by Tester/QA

### Rollback

`bolabol/pre-B11`

---

## B12 — Test build 1.0.3

### Goal

`APP_VERSION=1.0.3` build + smoke; release notes bullets. Notarize when product-ready (not hard gate for first internal).

### Done

- [ ] Smoke list pass; version string 1.0.3  
- [ ] Plan DoD §14 checklist satisfied or residual risks in DECISIONS  

### Rollback

`bolabol/pre-B12`

---

## Cycle per step (Orchestrator)

```
PRE tag → Kick Coder → Kick Reviewer → Kick Tester/QA
  → green: POST tag → graphify rebuild → open next → PRE next → Kick Coder
  → red: fix retry Coder (not advance)
```
