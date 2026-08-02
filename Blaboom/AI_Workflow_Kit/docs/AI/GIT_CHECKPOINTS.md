# Git Checkpoints — Blaboom 1.0.3

## Rules

1. **Idempotent** — existing tag is not overwritten.
2. **Scope-guard** — stage **only** `Blaboom/` paths under monorepo root  
   (`AI Projects/`). Never `git add -A` at monorepo root without path filter.
3. **Orchestrator only** commits/tags/pushes.
4. **Commit convention:**
   - PRE: `chore(blaboom): checkpoint before <step>`
   - POST: `feat(blaboom): <step> — <summary>`
5. **Tags:**
   - PRE: `blaboom/pre-<step>` (e.g. `blaboom/pre-B1`)
   - POST: `blaboom/<step>-done` (e.g. `blaboom/B1-done`)
6. **Push** if remote allows; if push DISABLED — keep local and tell Human.

## Usage

```bash
cd "/Users/pavan/Documents/AI Projects/Blaboom"
./AI_Workflow_Kit/script/checkpoint.sh pre B1
./AI_Workflow_Kit/script/checkpoint.sh post B1 "language pair store + picker order"
./AI_Workflow_Kit/script/checkpoint.sh list
```

## When

| Event | Action |
|-------|--------|
| Before Coder starts step | `pre <step>` |
| After review **approved** + QA **green** | `post <step>` then graphify then open next |
| Doc-only bootstrap (B0 kit) | post after Orchestrator closes B0 |

## Rollback (careful)

```bash
# list
./AI_Workflow_Kit/script/checkpoint.sh list
# hard reset only if Human confirms — destructive
git reset --hard blaboom/pre-B1
```
