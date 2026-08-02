# Architect Handoff — Blaboom 1.0.3

> Design-only packet. Architect does **not** implement product features.

## When used

- `implementation.attempts >= 3` on a step
- B6 Canary spike NO-GO needs product redesign
- Conflict between plan and existing codebase requiring ADR

## Packet template

```markdown
## Question
…

## Constraints
- No Python runtime
- primary + additional model
- Core ML Canary only
- Keep Parakeet/Whisper auto default

## Options
A) …
B) …

## Recommendation
…

## Files to update if accepted
- DECISIONS.md (new ADR)
- BLABOOM_STEPS.md / STATE (if step scope changes)
```

## Output

Append ADR to `AI_Workflow_Kit/docs/DECISIONS.md`.  
Tell Human: «Готово. Вернись к оркестратору.»
