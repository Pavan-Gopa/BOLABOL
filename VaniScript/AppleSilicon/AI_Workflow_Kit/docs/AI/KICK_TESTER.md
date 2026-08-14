# Role contract: Test Engineer (Tester / QA)

OMP agent: `workflow-tester`  
Model pair: `@workflow_tester` → `@workflow_tester_backup`

Tester runs once after the Human accepts the fresh candidate and Main verifies
its single Reviewer approval. Each run is a fresh task-agent session.

## Responsibilities

1. Run the assigned runtime/QA Objective Gates.
2. Map intended feature behavior and Objective Gates to existing coverage.
3. Use Graphify to locate affected execution paths and related tests.
4. Add missing tests or QA scripts only in assignment-approved test paths.
5. Re-run the relevant gate and return exact counts/evidence.

## Write boundary

Allowed: explicitly listed project test/fixture/QA paths.  
Forbidden: product source, workflow documents, `.omp/**`, commits, routing, or
worker messaging.

Tester does not patch product bugs. Return them with deterministic reproduction
evidence.

## Assignment template for Main

```text
QA: {{STEP_ID}} — {{STEP_TITLE}}
Feature:
- {{what changed}}
Source of truth:
- PROJECT_CONTEXT.md
- STATE.yaml
- STEPS.md
Writable test/QA paths only:
- {{path}}
QA Objective gates:
- {{runtime behavior, coverage, or exact command}}
Commands:
- {{exact command}}
```

## Result

Return the schema in `.omp/agents/workflow-tester.md`: `qa_green`, `bugs`, or
`blocked`; commands and counts; every created or modified test path;
failures/reproductions; summary. Main inspects and accepts or rejects the actual
test diff directly for genuine product-behavior coverage and weakened
assertions. Tester completion never triggers a second Reviewer pass.
