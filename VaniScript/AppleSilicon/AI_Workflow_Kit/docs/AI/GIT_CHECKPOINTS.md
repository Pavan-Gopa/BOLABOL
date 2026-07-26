# Git checkpoints — GROK_MCP + UI_AS + QWEN_MCP

**Обязательно:** перед **каждым** этапом и после **закрытия** этапа — git commit + annotated tag + **push на GitHub** (когда remote доступен). Цель: всегда можно откатиться.

## Naming — GROK_MCP

| Moment | Tag | Commit message (пример) |
|--------|-----|-------------------------|
| **До** старта шага `Gn` | `grok/pre-Gn` | `chore(grok): checkpoint before Gn` |
| **После** approve `Gn` | `grok/Gn-done` | `feat(grok): Gn — <кратко>` |
| Bootstrap kit | `grok/G0-done` | `chore(grok): G0 AI_Workflow_Kit bootstrap` |

## Naming — UI_AS

| Moment | Tag | Commit message (пример) |
|--------|-----|-------------------------|
| **До** старта `Un` | `ui/pre-Un` | `chore(ui): checkpoint before Un` |
| **После** approve + visual PASS | `ui/Un-done` | `feat(ui): Un — <кратко>` |

**UI_AS close rule:** Gemini APPROVED is not enough for visual steps. Orchestrator should **build & visually accept** when applicable, then `post` + push.

## Naming — QWEN_MCP

| Moment | Tag | Commit message (пример) |
|--------|-----|-------------------------|
| **До** старта `Qn` | `qwen/pre-Qn` | `chore(qwen): checkpoint before Qn` |
| **После** approve `Qn` (+ QA green для coding-шагов) | `qwen/Qn-done` | `feat(qwen): Qn — <кратко>` |

**QWEN_MCP QA gate:** для coding-шагов (Q2–Q6) `post` ставится после approve **и** QA green. Doc-only (Q1, Q7) — сразу после approve.

## Naming — API_USAGE

| Moment | Tag | Commit message (пример) |
|--------|-----|-------------------------|
| **До** старта `An` | `apiusage/pre-An` | `chore(apiusage): checkpoint before An` |
| **После** approve `An` (+ QA green для coding-шагов) | `apiusage/An-done` | `feat(apiusage): An — <кратко>` |

**API_USAGE QA gate:** для coding-шагов (A1–A7) `post` ставится после approve **и** QA green. Doc-only (A8) — сразу после approve.

Теги **не** перезаписывать (`-f` запрещён).

## Script

```bash
cd "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon"

./AI_Workflow_Kit/script/checkpoint.sh pre G1
./AI_Workflow_Kit/script/checkpoint.sh post G1 "external Grok MCP profile"

./AI_Workflow_Kit/script/checkpoint.sh pre U0
./AI_Workflow_Kit/script/checkpoint.sh post U0 "theme density tokens"

./AI_Workflow_Kit/script/checkpoint.sh pre Q1
./AI_Workflow_Kit/script/checkpoint.sh post Q1 "qwen discovery ADR"

./AI_Workflow_Kit/script/checkpoint.sh list
```

### Scope (важно)

Workspace `AI Projects` — multi-project monorepo. Checkpoint script:

- **не** делает `git add -A` по всему workspace;
- stage только `VaniScript/AppleSilicon/**` (и `VaniScript/Electron/**` когда `STATE.working_roots` includes electron);
- commit message + tag + `git push` если remote pushable.

## Who does what

| Actor | When | Action |
|-------|------|--------|
| **Orchestrator (Grok)** | Opening step | Ensure `pre` tag exists **before** Hy3 codes |
| **Orchestrator** | After Gemini **APPROVED** (coding + QA gate) | STATE → `next_actor: qa` (no post yet); Kick QA. After **QA green**: `post` → advance → `pre` next |
| **Orchestrator** | After Gemini **APPROVED** (doc-only) | `post` step; advance STATE; immediately `pre` next |
| **Hy3** | End of implement | Does **not** post-tag; leave dirty tree OK |
| **Human** | If agents cannot push | Run same script / `git push && git push --tags` |

**Policy:**

1. `pre Gn` — clean checkpoint of relevant tree before implementation  
2. Hy3 implements (working tree dirty OK)  
3. Gemini reviews  
4. On approve (coding + QA gate: Q2–Q6, A1–A7) → STATE `next_actor: qa` (no post yet) → QA suite  
5. On QA green → `post Gn` → advance → `pre G(n+1)`  
6. On approve (doc-only: Q1/Q7/G6/A8) → `post` → advance → `pre` next immediately  

On **changes_requested**: no new post-tag until approve. No second pre-tag.

## Rollback

```bash
git tag -l 'grok/*' 'ui/*' 'qwen/*'
git log --oneline --decorate -15

# hard reset (destructive):
git reset --hard grok/pre-G1
git reset --hard qwen/pre-Q1

# safer recover branch:
git switch -c recover/pre-G1 grok/pre-G1
```

## STATE fields

```yaml
checkpoint:
  last_pre_tag: grok/pre-G1
  last_post_tag: grok/G0-done
  last_commit: <short sha>
```

## Remote note

If `git remote` has push DISABLED (e.g. `DISABLED` URL), local commit+tag still **must** happen. Orchestrator reports push blocked and asks human to enable remote / push manually. **Do not skip local checkpoints.**
