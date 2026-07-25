# AI Team Contract

## Source of truth (priority)

1. `docs/AI/STATE.yaml` — **что делать прямо сейчас**
2. `docs/MVP_STEPS.md` — карточка шага
3. `implementation_plan.md` — полный MVP design / budgets
4. `docs/PROJECT_CONTEXT.md` — контекст репо

Старый `ARCHITECTURE_PLAN.md` — история Фазы 1–2 (уже в коде). Не использовать как текущий backlog.

## Roles

| Role | Model | Writes code? | Updates |
|------|-------|--------------|---------|
| **Orchestrator** | Grok | only if attempts ≥ 3 | `STATE.yaml`, occasionally `DECISIONS.md` |
| **Implementation Engineer** | **Hy3 / Hi3** | **yes** | code in `target_files`, then `implementation.status` |
| **Verification Engineer** | **Gemini 3.5 Flash** | no | `FEEDBACK.md`, `review.status` |

No role redesigns architecture unless Orchestrator explicitly allows.

## Workflow (shared filesystem)

```
Orchestrator prepares STATE (step + target_files)
        ↓
Human → Hy3: implement
        ↓
Hy3 codes → build → implementation.status = waiting_review
        ↓
Human → Gemini: review
        ↓
Gemini → FEEDBACK.md → review.status = approved | changes_requested
        ↓
Human → Orchestrator: advance or retry
        ↓
(loop)
```

1. Orchestrator готовит `STATE.yaml` для шага.
2. Человек даёт команду **Hy3**.
3. Hy3 читает STATE, пишет код **только** в `target_files`, `npm run build`, ставит `implementation.status = waiting_review`, `next_actor: verification`.
4. Человек даёт команду **Gemini 3.5 Flash**.
5. Gemini ревьюит по `REVIEW_TEMPLATE.md`, пишет `FEEDBACK.md`, ставит `review.status`, `next_actor: orchestrator`.
6. Человек даёт команду **Orchestrator (Grok)**.
7. Orchestrator: next step **или** retry с `attempts++`.

## Hard rules

- Keep `mandala-pro-studio` buildable every step.
- One MVP step at a time (M0…M4).
- No Post-MVP until MVP accepted.
- Smudge multi-brush single-pass **forbidden** (see implementation_plan M3).
