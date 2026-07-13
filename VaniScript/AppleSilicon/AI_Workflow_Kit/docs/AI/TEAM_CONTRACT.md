# AI Team Contract — VaniScript

## Source of truth (priority)

1. `AI_Workflow_Kit/docs/AI/STATE.yaml` — **what to do right now**
2. `AI_Workflow_Kit/docs/GROK_MCP_STEPS.md` or `UI_AS_STEPS.md` — step card for `current_step`
3. `AI_Workflow_Kit/docs/PROJECT_CONTEXT.md` — repo map
4. `AI_Workflow_Kit/docs/DECISIONS.md` — escalations / narrowed scope

## Roles

| Role | Model | Writes code? | Updates |
|------|-------|--------------|---------|
| **Orchestrator** | Grok | only if attempts ≥ 3 | `STATE.yaml`, `DECISIONS.md`, git checkpoints |
| **Implementation Engineer** | **Hy3 / Hi3 / Coder** | **yes** | code in `target_files`, then `implementation.status` |
| **Verification Engineer** | **Gemini 3.5 Flash** | no | `FEEDBACK.md`, `review.status` |
| **Human** | you | — | switches models; short commands |

No role redesigns architecture unless Orchestrator explicitly allows.

## Workflow (shared filesystem)

```
Orchestrator: git checkpoint PRE step (commit + tag grok/pre-Gn or ui/pre-Un + push)
        ↓
Orchestrator prepares STATE (step + target_files)
        ↓
Human → Hy3: implement
        ↓
Hy3 codes → verify → implementation.status = waiting_review
        ↓
Human → Gemini: review
        ↓
Gemini → FEEDBACK.md → review.status = approved | changes_requested
        ↓
Human → Orchestrator: advance or retry
        ↓
If approved: git checkpoint POST step (commit + tag …-done + push)
        ↓
PRE next step → (loop)
```

## Hard rules

- Keep project **buildable/testable** every step (`swift test` / `swift build`; Electron only on G5).
- One step at a time (G1…G6, then U0…).
- **Git checkpoint before every step and after every approved step** — commit + annotated tag + **push to GitHub when remote allows**. See `GIT_CHECKPOINTS.md`. Script: `AI_Workflow_Kit/script/checkpoint.sh`.
- Communication between agents is **via files only** — human switches models.
- Do **not** force-update (`-f`) tags; preserve rollback points.
- GROK_MCP: no UI density redesign. UI_AS: Apple Silicon only, no Electron visual pass.
- No silent MCP→API chat fallback (Codex/Grok parity).

## Human short commands

| Phrase | Actor |
|--------|--------|
| `приступай` / `зови оркестратора` / `статус` | Grok |
| `зови Hy3` / `кодер` | Hy3 |
| `зови Gemini` / `ревью` | Gemini |
| `следующий шаг` | Grok (only if approved) |
| `retry` / `правки` | Grok → same step, attempts++ |
