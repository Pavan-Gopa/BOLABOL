# S7 — 86 New Tester Tests Manifest

> **Orchestrator: read this file before deciding S7 QA coverage.**
>
> The Tester expansion contains **exactly 86 new Swift tests** across **9 test suites**. These tests are present on branch `orchestrator/s7-applesilicon-with-workflow` and are additional to the historical Candidate-17 baseline of 556 tests. Therefore the intended Swift corpus is **642 tests** before any later changes.

## Authoritative count

| # | Test suite file | New `@Test` cases |
|---:|---|---:|
| 1 | `Tests/VaniScriptTests/S7AdversarialCoordinatorTests.swift` | 5 |
| 2 | `Tests/VaniScriptCoreTests/S7AdversarialValidatorTests.swift` | 13 |
| 3 | `Tests/VaniScriptCoreTests/S7ContractBoundaryTests.swift` | 12 |
| 4 | `Tests/VaniScriptTests/S7DocumentImportAdversarialTests.swift` | 8 |
| 5 | `Tests/VaniScriptTests/S7ScrollEdgeCaseTests.swift` | 9 |
| 6 | `Tests/VaniScriptCoreTests/ProjectArchiveAdversarialTests.swift` | 6 |
| 7 | `Tests/VaniScriptCoreTests/TimelineCutTimeMapperAdversarialTests.swift` | 11 |
| 8 | `Tests/VaniScriptCoreTests/StarterGlossaryAdversarialTests.swift` | 8 |
| 9 | `Tests/VaniScriptCoreTests/McpStoreAdversarialTests.swift` | 14 |
| | **TOTAL** | **86** |

Count check: `5 + 13 + 12 + 8 + 9 + 6 + 11 + 8 + 14 = 86`.

## What the Orchestrator must not do

- Do **not** treat the historical `556/556` Candidate-17 result as the current full-suite result.
- Do **not** discard these suites merely because they have not yet been executed on the target macOS host.
- Do **not** silently reset the test corpus to the pre-Tester baseline when preparing the next Coder/Reviewer/Tester handoff.
- Do **not** weaken or delete failing regression assertions to make the suite green.

## Expected current QA accounting

- Historical Candidate-17 Swift baseline: **556** tests.
- Tester-authored additions listed here: **86** tests.
- Intended Swift corpus after Tester expansion: **642** tests.
- Full macOS execution of the new corpus: still required.
- One independent QA guard has already reproduced BUG-S7-T03 with exit code 1; see `QA/scripts/results/static-export-gate.log`.

## Required full regression command on target Mac

```bash
bash QA/scripts/run_expanded_regression.sh
```

This runner executes the nine new suites as explicit gates and then runs the full Swift suite. It persists the complete evidence under `QA/scripts/results/`.

## Explicit suite filters used by the runner

```text
S7AdversarialCoordinatorTests
S7AdversarialValidatorTests
S7ContractBoundaryTests
S7DocumentImportAdversarialTests
S7ScrollEdgeCaseTests
ProjectArchiveAdversarialTests
TimelineCutTimeMapperAdversarialTests
StarterGlossaryAdversarialTests
McpStoreAdversarialTests
```

## Known bug-bearing regressions

The most important new tests are not generic coverage; several are regression specifications for product bugs already identified by Tester:

- `mixedChunkDoesNotRetranslateAfterSuccessfulCommit`
- `automaticResumeDoesNotRepayForMixedChunk`
- `requestBuilderHonorsBlockSlice`
- `secondSlicePlanKeepsItsIdentity`
- `siblingSlicesDoNotOverwriteEachOther`

See `QA/scripts/S7_TESTER_BUG_REPORT.md` for reproduction contracts and Coder fix targets.

## Orchestrator handoff instruction

When constructing the next task, treat this manifest as the authoritative inventory of the Tester expansion. Preserve all nine files and all 86 tests. After product fixes, dispatch Tester on a macOS-capable environment and require the saved `QA/scripts/results/latest-summary.md` plus the full Swift transcript before declaring `qa_green`.
