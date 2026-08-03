# AI Team Contract — Bolabol 1.0.3

## Source of truth (priority)

1. `BOLABOL_1.0.3_IMPLEMENTATION_PLAN.md` — authoritative product plan
2. `AI_Workflow_Kit/docs/AI/STATE.yaml` — what to do right now
3. `AI_Workflow_Kit/docs/BOLABOL_STEPS.md` — condensed step cards B0–B12
4. `AI_Workflow_Kit/docs/DECISIONS.md` — ADR log
5. `AI_Workflow_Kit/docs/PROJECT_CONTEXT.md` — repo map + build commands

## Roles

| Role | Actor | Writes code? | Updates |
|------|-------|--------------|---------|
| **Orchestrator** | This session (hub) | no product code | STATE, DECISIONS, checkpoints, kick prompts, graphify |
| **Implementation Engineer** | Coder (fresh terminal) | **yes** product | `target_files` only; FEEDBACK §1–4 |
| **Verification Engineer** | Reviewer (fresh terminal) | no | `FEEDBACK.md` review verdict |
| **Test Engineer** | Tester (fresh terminal) | **test / QA scripts only** (no product) | new/gap tests, `script/qa`, `REPORT.md`, `BUG_REPORT.md` |
| **Architect** *(on demand)* | Orchestrator or dedicated | no product features | ADR → DECISIONS |
| **Human** | Pavel | — | paste kicks, say «статус», approve product decisions |

## Workflow (hub = Orchestrator)

Каждая роль открывается в **новом терминальном окне** (пустой контекст).
**Каждый** kick-промпт пишет **Orchestrator**; Human только копирует.

```
Human ↔ Orchestrator only (control plane)
  Orchestrator: PRE tag + STATE update
  → Orchestrator выдаёт kick Coder (full prompt)
  → Human: новое окно → Coder
  → Coder: code + FEEDBACK waiting_review → «вернись к оркестратору»
  → Human → Orchestrator «статус»
  → Orchestrator: graphify rebuild по последнему Coder diff
  → Orchestrator выдаёт kick Reviewer
  → Human: новое окно → Reviewer
  → Reviewer: APPROVED | CHANGES_REQUESTED → «вернись к оркестратору»
  → Human → Orchestrator
  → if approved: Orchestrator выдаёт kick Tester
  → Tester: REPORT/BUG_REPORT → «вернись к оркестратору»
  → Orchestrator: green → POST + graphify + PRE next + kick Coder; red → fix + kick Coder
```

### Test Engineer after every coding step (mandatory)

After Reviewer **APPROVED**, Tester does **not** only re-run what Coder already wrote.

| Duty | Detail |
|------|--------|
| **1. Run full gate** | `swift test` + `./script/qa/run_all.sh` (or STATE-scoped suite) |
| **2. Gap-hunt** | Compare step Done / plan §12 / coder_brief vs existing tests |
| **3. Add tests** | Write missing unit/integration/qa scripts for **this step’s feature** |
| **4. Report** | Green → `REPORT.md` (what ran + **what new tests added**); red product bug → `BUG_REPORT.md` (no product fix) |

**Split with Coder:**

- **Coder** ships feature + **minimum** tests so the change is not blind (happy path / invariants they own).
- **Tester** is the coverage owner for the step: finds holes, edge cases, regression guards, surface QA scripts; may add many tests.
- **Tester never** edits `Sources/**` product code (only `Tests/**`, `script/qa/**`).

If gap-hunt finds **product** defects → BUG_REPORT → Orchestrator kicks Coder.  
If only coverage is thin → Tester **adds tests in the same turn**, re-runs, then REPORT green.

### Who does what when Tester finds a product bug

| Actor | Action |
|-------|--------|
| **Tester** | Detects failure, writes `BUG_REPORT.md`, «вернись к оркестратору» |
| **Orchestrator** | Reads bugs, opens fix/retry, **issues full Coder kick** |
| **Coder** | **Only one who fixes product code** |
| **Reviewer** | Re-reviews after Orchestrator issues Reviewer kick |
| **Tester** | Re-runs suite + re-checks coverage after Orchestrator issues Tester kick |

**Do not:** send bugs to Reviewer to "fix".  
**Do not:** skip Orchestrator.  
**Do not:** let workers open the next role without Orchestrator.

## Hard rules

1. **Graphify first.** Before large exploration: `graphify query` on `graphify-out/graph.json`.
2. **Graphify update.** A new Orchestrator rebuilds before starting work. Orchestrator
   then runs `graphify_rebuild.sh` after every Coder handoff (including fix/retry)
   before Reviewer, and again after each POST green cycle.
3. Keep project **testable** every step: `swift test` (and QA scripts when on B11 or when STATE requires).
4. **One step at a time** (B0…B12). No skipping stop-gates.
5. Diff **only** in `STATE.yaml` → `target_files`.
6. Communication between agents **via files only**.
7. **Коммитит только Orchestrator.** Workers leave working tree dirty; Orchestrator commits + tags (+ push if allowed).
8. No silent architecture redesign by Coder.
9. No fake data / fake states in production code.
10. **Never** `git add -A` on monorepo root without Bolabol path scope.
11. Product scope = `Bolabol/`. Tags: `bolabol/pre-<step>`, `bolabol/<step>-done`.
12. **Readable, well-commented code** — see § Comments.
13. Human communicates **only with Orchestrator** for workflow.
14. **No Python** in Bolabol runtime / Sources.
15. Terminology: **primary** + **additional** speech languages — not «target always output».
16. Canary = Core ML only; polish = MLX/cloud after ASR text.
17. Parakeet/Whisper auto (HUD **A**) remains default for non-Canary.
18. Version string **1.0.3** (not «1.3»).
19. English for code comments.

## Comments (mandatory quality bar)

| Where | What to document |
|-------|------------------|
| File / module header | Role in system (1–5 lines): layer, ownership, must-not |
| Non-obvious logic | **Why**, not a restate of the code |
| Public API | Brief intent + types/invariants |
| Speech language | primary vs additional; Canary source/target matrix |
| Core ML / download | Paths, presence rules, no Python note |
| TODOs | `// TODO(B9): …` tied to a step ID |

### Forbidden

- Comment every line of trivial getters/setters
- Outdated comments that contradict code
- Secrets, keys, credentials in comments

## Build bar (default)

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"
swift test
# when STATE requires surface QA:
./script/qa/run_all.sh
```

## Handoff phrase (all workers)

> **Готово. Вернись к оркестратору** и скажи «статус» или «приступай».
