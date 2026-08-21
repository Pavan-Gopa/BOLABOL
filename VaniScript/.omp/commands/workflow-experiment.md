---
description: Manage the additive Main-only context-economy experiment without replacing the base workflow dashboard
argument-hint: [status|doctor|update|rollback]
---

Run the experiment manager and report its exact output:

```bash
bash AI_Workflow_Kit/script/workflow_experiment.sh ${ARGUMENTS:-status}
```

Do not continue product routing after `update` or `rollback`; tell the Human to
restart OMP. Context compaction is owned only by the top-level interactive Main
session; worker sessions must remain uncompacted.
