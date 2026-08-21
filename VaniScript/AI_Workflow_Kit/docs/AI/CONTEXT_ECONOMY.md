# Context-Economy Experiment v3 — Main Only

This experiment is an **additive OMP extension**. It does not replace the base
workflow dashboard, dashboard parser, dashboard event bridge, agents, role
contracts, or `/workflow` command.

## Session ownership

Context economy belongs only to the top-level interactive Main Orchestrator
session. OMP rebuilds project extensions for task sessions and copies effective
project settings into those sessions, so the experiment applies two independent
protections:

1. project-level OMP automatic compaction is disabled (`compaction.enabled:
   false`, no native threshold, no mid-turn compaction);
2. the extension detects nested/headless task sessions and disables its timer,
   status, `workflow_context` tool, compaction hook, and compaction invocation
   there.

Coder, Reviewer, Tester, Architect, Security, Advisor, and Designer therefore
retain their complete fresh assignment context until their normal session ends.
The experiment never compacts or interrupts a worker.

## Main floating window

- Arm Main at 23% context usage.
- Show a one-time Main warning when the latch arms.
- While a worker or asynchronous job is active, show that Main is waiting and
  leave worker context untouched.
- Compact Main at the first safe idle boundary between 23% and 28%.
- Treat 28% as the upper target reported by the controller; OMP's global native
  automatic threshold is intentionally disabled so it cannot fire in workers.
- Reset the latch at 18% or below.
- Use the configured manual method order `shake -> soft`.
- Keep provider-native remote, speculative, idle, and mid-turn automatic
  compaction disabled.

A Main session can therefore sit at 23–28% while Coder is running. That is
expected: the warning says `waiting-worker`, and the actual Main compaction runs
only after the worker and Main turn settle. A successful pass reports the
before/after token counts.

## UI ownership

- `Alt+W` / `Option+W` remains entirely owned by Pavan's base workflow
  dashboard. The experiment neither imports itself into nor rewrites
  `workflow-dashboard-extension.ts` or `workflow-dashboard-panel.ts`.
- `Alt+A` remains OMP's native Agent Hub. The experiment registers no Alt+A
  shortcut and never changes `app.agents.hub`.
- `Alt+Q` is added only to `app.model.cycleForward`; `cycleOrder` contains the
  primary and backup Orchestrator roles.
- Main's normal OMP status line shows `MAIN ctx …`; workers show no
  context-economy status or warning.

## Workflow memory

`workflow_context` is a Main-only compact read-only navigation index. Canonical
workflow files, source, repository diff, tests, and artifacts remain
authoritative. Main compaction receives a bounded workflow anchor with the
current step, work item, open items, active worker, latest Human instruction,
and canonical file hashes.

## Commands

```text
/workflow-context                 # Main-only snapshot
/workflow-context-economy         # scope, Main context, waiting reason, last pass
/workflow-experiment status
/workflow-experiment doctor
/workflow-experiment update
/workflow-experiment rollback
```
