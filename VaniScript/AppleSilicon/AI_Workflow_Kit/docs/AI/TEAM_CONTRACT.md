# AI Team Contract — VaniScript

## Source of truth (priority)

1. `AI_Workflow_Kit/docs/AI/STATE.yaml` — **what to do right now**
2. `AI_Workflow_Kit/docs/QWEN_MCP_STEPS.md` / `GROK_MCP_STEPS.md` / `UI_AS_STEPS.md` — step card for `current_step`
3. `AI_Workflow_Kit/docs/QWEN_ARCHITECTURE.md` — architectural spec (Qwen track)
4. `AI_Workflow_Kit/docs/PROJECT_CONTEXT.md` — repo map
5. `AI_Workflow_Kit/docs/DECISIONS.md` — ADR log / escalations / narrowed scope

## Roles

| Role | Model | Writes code? | Updates |
|------|-------|--------------|---------|
| **Architect** *(on demand)* | Qwen 3.8 Max / Claude | no product features | ADR → `DECISIONS.md`, `*_ARCHITECTURE.md`, `*_STEPS.md`; role doc: `ARCHITECT.md` |
| **Planner** *(on demand)* | Qwen 3.8 Max / Claude | no product features | `*_STEPS.md` |
| **Orchestrator** | Grok / Claude | only if attempts ≥ 3 | `STATE.yaml`, `DECISIONS.md`, checkpoints; triages bugs |
| **Implementation Engineer** | **Hy3 / Hi3 / Coder** | **yes** product | code in `target_files`, then `implementation.status` |
| **Verification Engineer** | **Gemini 3.5 Flash** | no | `FEEDBACK.md`, `review.status` |
| **QA Script Engineer** | Qwen 3.8 Max | **QA scripts only** under `QA/` | `QA/scripts`, `manifest.json`, `BUG_REPORT.md`, `REPORT.md` |
| **Human** | you | — | switches models; short commands; dogfood |

No role redesigns architecture unless Orchestrator explicitly allows (Architect packet).

## Workflow — hub = Orchestrator (обязательно)

**Все роли общаются только через файлы + Orchestrator.** Human открывает
**новое окно** для Coder / Reviewer / QA и вставляет **Kick, который выдал
Orchestrator**. Агенты **не** зовут друг друга («зови Gemini», «зови QA» — **запрещено**).

```
Human → Orchestrator: «статус» / «приступай»
        ↓
Orchestrator читает STATE + FEEDBACK + QA reports
        → обновляет STATE / checkpoints
        → выдаёт готовый Kick (copy-paste) + «На очереди: <роль>»
        ↓
Human открывает НОВОЕ окно нужного агента → вставляет Kick
        ↓
Agent работает → пишет файлы (код / FEEDBACK / QA report)
        → STATE: next_actor = orchestrator
        → Human: «Готово. Скажи оркестратору: статус»
        ↓
Human → Orchestrator: «статус»  →  (loop)
```

Типичный круг одного coding-шага:

```
Orchestrator PRE-tag + Kick Coder
  → Coder → waiting_review + next_actor=orchestrator
Orchestrator Kick Reviewer (Gemini)
  → Reviewer → approved|changes_requested + next_actor=orchestrator
Orchestrator Kick QA   (если coding + QA gate)
  → QA → REPORT/BUG_REPORT + next_actor=orchestrator
Orchestrator: green → POST-tag → open next → PRE next → Kick Coder
```

### Handoff phrase (все агенты → Human)

| Кто закончил | Что сказать Human |
|--------------|-------------------|
| **Любой** (Coder / Reviewer / QA) | **«Готово. Скажи оркестратору: статус»** |
| **Запрещено** | «зови Gemini», «зови ревью», «зови QA», «зови Hy3», «зови кодера» |

`next_actor` после сдачи агента **всегда** `orchestrator`. Кого звать дальше
решает только Orchestrator (и выдаёт Kick).

### Кто что делает, когда QA нашёл баг

| Actor | Action |
|-------|--------|
| **QA** | Детектит, пишет `QA/BUG_REPORT.md`, Human: «скажи оркестратору: статус» |
| **Orchestrator** | Читает баги, открывает fix/retry шаг (scope, `target_files`, PRE-tag), Kick Coder |
| **Coder** | **Единственный, кто чинит product-код** → снова «статус» оркестратору |
| **Verifier** | Ре-ревьюит фикс **после Kick от Orchestrator** |
| **QA** | Ре-ранит suite **после Kick от Orchestrator** |

**Не:** отправлять QA-баги Verifier'у «починить» (Verifier не пишет product-код).
**Не:** пропускать Orchestrator (потеряются STATE/checkpoints + нет Kick).
**OK для minor/flaky:** Orchestrator может открыть крошечный fix-шаг с Coder в один прыжок.

## Hard rules

1. Keep project **buildable/testable** every step (`swift test` / `swift build`; Electron `npm run compile`).
2. **One step at a time** (G1…G6 / U0…U3 / Q1…Q7).
3. Diff **only** in `STATE.yaml` → `target_files`.
4. **Git checkpoint before every step and after every approved step** — commit + annotated tag + push when remote allows. See `GIT_CHECKPOINTS.md`. Script: `AI_Workflow_Kit/script/checkpoint.sh`.
5. Communication between agents is **via files only** — human switches models.
6. Do **not** force-update (`-f`) tags; preserve rollback points.
7. GROK_MCP: no UI density redesign. UI_AS: Apple Silicon only. QWEN_MCP: parity с Codex/Grok, no UI redesign.
8. **No silent MCP→API chat fallback** (Codex/Grok/Qwen parity).
9. **Readable, well-commented code** — see § Comments below.
10. **Graphify first (token savings — mandatory for orientation):** before bulk greps / multi-file dumps, query the knowledge graph. Prefer Cline MCP tools (server `graphify`); else CLI `graphify query|explain|path --graph "$GRAPH"`. Skill: `VaniScript/.agents/skills/graphify/SKILL.md`. Rebuild: `./AI_Workflow_Kit/script/graphify_rebuild.sh`. Dev-tool, not product code.
11. **QA прогоняет ВСЕ suite'ы при каждом QA-шаге** (`swift test`/`swift build` + Electron `npm run compile` + MCP black-box smoke). Любой suite красный → RED. Тестер отвечает за всё приложение, не только за свой шаг.
12. **Никогда** `git add -A` вне VaniScript-скопа (монорепо `AI Projects`).

## Comments (mandatory quality bar)

Цель: человек или другой агент через месяцы понимает **what / why / constraints** без восстановления плана.

**Required:**

| Where | What to document |
|-------|------------------|
| File / module header | Role in system (1–5 lines): layer, what it owns, what it must not do |
| Non-obvious logic | **Why**, not a restate of the code |
| Public API | Brief intent + types/invariants |
| Async / concurrency | Ownership, cancel/termination rules, "no blocking here" |
| IPC / protocol | Message format, who sends/receives, error handling |
| Safety / permissions | Token handling, MCP isolation, no-fallback |
| TODOs | `// TODO(Q3): …` tied to a step ID when deferral is intentional |

**Forbidden:** комментировать тривиальные getter/setter; устаревшие комменты; фейковые пояснения для stub; секреты/ключи в комментах.

**Language:** English preferred in code comments; Russian OK in plan docs и Human communication.

**Verifier:** отсутствие essential comments на новом нетривиальном коде (типы, схемы, provider/MCP логика) = **changes_requested**.

## Graphify (development of this repo)

| Item | Path / command |
|------|----------------|
| Graph output | `VaniScript/graphify-out/graph.json` |
| Skill | `VaniScript/.agents/skills/graphify/SKILL.md` (+ `.cline/skills/graphify/`) |
| Cline MCP | `~/.cline/mcp.json` + `~/.cline/data/settings/cline_mcp_settings.json` — `./AI_Workflow_Kit/script/cline_graphify_mcp.sh` |
| Rebuild | `./AI_Workflow_Kit/script/graphify_rebuild.sh` (`--force` after big deletes) |
| Prefer | MCP tools **or** `graphify query/explain/path` over dumping trees |
| When | Coder, Verifier, QA, Orchestrator — anytime navigating code beyond `target_files` |
| Not | Substitute for `STATE.yaml` / `target_files` / step cards — still follow scope |

## Human short commands

**Основной (и почти единственный) цикл:**

| Phrase | Кто | Что происходит |
|--------|-----|----------------|
| **`статус`** / `приступай` / `зови оркестратора` | **Orchestrator** | Читает файлы, двигает STATE, выдаёт **Kick** следующего |
| *(вставить Kick в новое окно)* | Coder / Reviewer / QA | Работает по Kick; сдаёт с `next_actor: orchestrator` |

Legacy-фразы (`зови Hy3`, `зови Gemini`, `зови QA`) **не нужны** — Kick всегда
из ответа Orchestrator. Если агент сам сказал «зови Gemini» — **игнор**; скажи
оркестратору `статус`.
