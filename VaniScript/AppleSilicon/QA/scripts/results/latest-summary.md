# VaniScript Expanded Regression — Latest Tester Summary

- Tester result: **BLOCKED for full Swift runtime**
- Historical candidate-17 baseline: **556/556** Swift tests green (pre-existing Main evidence; not re-run here)
- New Swift tests added by this Tester: **86**
- Intended Swift corpus: **642**
- New Swift tests compiled/executed here: **0/86**
- QA gates actually executed here: **1**
- Executed QA result: **0 PASS / 1 FAIL**
- Source-confirmed product bugs: **3**
- GitHub Actions runs available for Tester head: **0**

## Actually executed failure

`QA/scripts/s7_export_completeness_guard.py` was executed against the exact current `WorkflowStore.exportDocument(format:)` function body fetched from this branch.

Result:

```text
FAIL: PDF/TXT export reaches NSSavePanel without checking translation completeness.
The current aggregate non-empty check can pass on source fallback from DocumentTranslationExportBuilder.
EXIT_CODE=1
```

Saved transcript: `QA/scripts/results/static-export-gate.log`.

## Confirmed bug inventory

1. **BUG-S7-T01:** mixed deterministic-empty + translated chunks can be classified not-ready on a later pass and trigger another provider call. Source-confirmed; macOS runtime regression pending.
2. **BUG-S7-T02:** oversized paragraph `blockSlices` are not end-to-end safe: request slicing, plan identity, archive persistence and reassembly are inconsistent. Source-confirmed; macOS runtime regressions pending.
3. **BUG-S7-T03:** PDF/TXT export lacks a semantic translation-completeness gate and can silently export source fallback as translated output. **Actually reproduced by executed QA gate, exit 1.**

See `QA/scripts/S7_TESTER_BUG_REPORT.md` for deterministic reproduction details and exact test names.

## Full-runtime blocker

The available Tester host is Linux x86_64 with Swift 6.2.1. `Package.swift` targets macOS 14 and the application target depends on Apple/macOS-oriented packages. The branch has no `.github/workflows` and no Actions run exists to delegate the macOS execution.

## Required target-Mac run

```bash
bash QA/scripts/run_expanded_regression.sh
```

The runner now replaces this file with the actual GREEN/RED result and saves the complete transcript, per-gate exit codes, durations and coverage inventory under `QA/scripts/results/<UTC-run-id>/`.