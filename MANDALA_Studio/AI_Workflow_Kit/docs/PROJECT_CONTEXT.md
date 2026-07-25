# Project Context — MANDALA Studio

## What this is
Creative mandala drawing app (**mandala-pro-studio**): React 19 + TypeScript + Vite + Canvas 2D + WebGL2 (smudge/blur).

## Workspace layout
- App code: `mandala-pro-studio/` (work only here for MVP perf)
- Older prototype: `mandala-studio/` (do not touch unless asked)
- AI workflow: `AI_Workflow_Kit/docs/`
- Performance plan (scope): root `implementation_plan.md`
- Agent step cards: `docs/MVP_STEPS.md` (this kit: `AI_Workflow_Kit/docs/MVP_STEPS.md`)

## Current track: MVP_PERF
Goal: no lag with many strokes, brushes, smudge/blur/stretch, semi-transparent effects.

| Step | Name |
|------|------|
| M0 | Perf baseline HUD |
| M1 | Hot-path React & input |
| M2 | EffectLayer rasterization |
| M3 | ROI / session WebGL |
| M4 | World / tiled bake |

Post-MVP backlog (B1–B5) is **out of scope** until MVP is accepted.

## Rules
1. Keep the project **buildable** after every step (`cd mandala-pro-studio && npm run build`).
2. Prefer **incremental** changes; only files in `STATE.yaml` → `target_files`.
3. Do **not** redesign architecture beyond the current step in `MVP_STEPS.md` / `implementation_plan.md`.
4. Do not implement later MVP steps early.
5. Communication between agents is via files: `STATE.yaml`, `FEEDBACK.md` — human switches models.

## Roles
- **Orchestrator** (Grok): prepares STATE, advances steps, resolves deadlocks after 3 failed attempts
- **Implementation (Hy3 / Hi3)**: writes code
- **Verification (Gemini 3.5 Flash)**: reviews code, writes FEEDBACK

## Paths note
From repo root `MANDALA_Studio/`:
- Plan: `implementation_plan.md`
- Steps: `AI_Workflow_Kit/docs/MVP_STEPS.md`
- State: `AI_Workflow_Kit/docs/AI/STATE.yaml`
- Feedback: `AI_Workflow_Kit/docs/AI/FEEDBACK.md`
