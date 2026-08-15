# S7 Tester Result — Candidate 17

> **Orchestrator notice:** the authoritative inventory for the Tester expansion is `QA/scripts/S7_86_NEW_TESTS_MANIFEST.md`. It enumerates **exactly 86 new Swift tests across 9 suites**. Do not fall back to the historical 556-test baseline when carrying S7 forward.

```yaml
status: blocked
pass_count: 0
fail_count: 1
new_tests:
  - Tests/VaniScriptTests/S7AdversarialCoordinatorTests.swift
  - Tests/VaniScriptCoreTests/S7AdversarialValidatorTests.swift
  - Tests/VaniScriptCoreTests/S7ContractBoundaryTests.swift
  - Tests/VaniScriptTests/S7DocumentImportAdversarialTests.swift
  - Tests/VaniScriptTests/S7ScrollEdgeCaseTests.swift
  - Tests/VaniScriptCoreTests/ProjectArchiveAdversarialTests.swift
  - Tests/VaniScriptCoreTests/TimelineCutTimeMapperAdversarialTests.swift
  - Tests/VaniScriptCoreTests/StarterGlossaryAdversarialTests.swift
  - Tests/VaniScriptCoreTests/McpStoreAdversarialTests.swift
failures:
  - test_name: s7_export_completeness_guard.py
    error_excerpt: "FAIL: PDF/TXT export reaches NSSavePanel without checking translation completeness. The current aggregate non-empty check can pass on source fallback from DocumentTranslationExportBuilder. EXIT_CODE=1"
    suspect_file: Sources/VaniScript/Stores/WorkflowStore.swift
  - test_name: mixedChunkDoesNotRetranslateAfterSuccessfulCommit / automaticResumeDoesNotRepayForMixedChunk
    error_excerpt: Source inspection confirms mixed plans require non-empty stored text for deterministic source-empty blocks, so a committed chunk can be classified not-ready and repay the provider. Runtime execution remains pending macOS.
    suspect_file: Sources/VaniScript/Services/DocumentTranslationCoordinator.swift
  - test_name: requestBuilderHonorsBlockSlice / secondSlicePlanKeepsItsIdentity / siblingSlicesDoNotOverwriteEachOther
    error_excerpt: Source inspection confirms blockSlices do not have an end-to-end unique request/archive identity; same-block sibling plans are range-ambiguous and persistence is keyed by source block ID. Runtime execution remains pending macOS.
    suspect_file: Sources/VaniScript/Services/DocumentTranslationCoordinator.swift
blockers: Full Swift/runtime execution is unavailable in this Tester environment. GitHub Actions has no workflow on this branch and reports zero workflow runs for the Tester head. The available execution host is Linux x86_64 with Swift 6.2.1, while Package.swift targets macOS 14 and the VaniScript executable depends on Apple/macOS-oriented packages. Run bash QA/scripts/run_expanded_regression.sh on the project Mac; it now persists full evidence under QA/scripts/results/.
```

## Counts and evidence status

- Candidate-17 historical baseline from Main: **556/556** Swift tests green.
- New Tester-authored Swift tests: **86**.
- Intended Swift corpus after this expansion: **642**.
- New Swift tests actually compiled/executed by this ChatGPT Tester session: **0/86** — full Swift runtime is blocked by the non-macOS host.
- QA gates actually executed by this Tester session: **1**.
- Actually executed QA result: **0 PASS / 1 FAIL**.
- Executed failure: `s7_export_completeness_guard.py`, **exit code 1**.
- Source-confirmed product bugs prepared for deterministic runtime reproduction: **3**.
- GitHub Actions runs available for the Tester head before this result: **0**.

Authoritative 86-test inventory: `QA/scripts/S7_86_NEW_TESTS_MANIFEST.md`.

Executed transcript: `QA/scripts/results/static-export-gate.log`.

The detailed reproductions and Coder targets are in `QA/scripts/S7_TESTER_BUG_REPORT.md`.

## Required full-runtime command

```bash
bash QA/scripts/run_expanded_regression.sh
```

The runner records:

- `QA/scripts/results/<UTC-run-id>/full.log`
- `QA/scripts/results/<UTC-run-id>/gates.tsv`
- `QA/scripts/results/<UTC-run-id>/summary.md`
- `QA/scripts/results/<UTC-run-id>/coverage-gaps.json`
- refreshed `QA/scripts/results/latest-summary.md`
- refreshed `QA/scripts/results/latest-gates.tsv`
- refreshed `QA/scripts/results/latest.log`

Only a target-macOS execution may replace this `blocked` result with a complete runtime verdict. The already-executed export guard is a real failing QA result and must remain red until BUG-S7-T03 is fixed.