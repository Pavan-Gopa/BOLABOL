# VaniScript Expanded Destructive QA — S7 and Whole-App Coverage

This file documents the additional Tester coverage added on top of the existing
556-test candidate-17 baseline and the manifest-driven `QA/run_all.sh` suites.

## Run everything

```bash
bash QA/scripts/run_expanded_regression.sh
```

The runner is intentionally **collect-all**. It does not stop after the first
failure; it runs every focused suite, the existing manifest QA, a coverage-gap
inventory, and the full Swift suite, then returns non-zero if any gate failed.

## New Swift coverage

### S7 cross-layer coordinator / slice integrity — 5 tests

`Tests/VaniScriptTests/S7AdversarialCoordinatorTests.swift`

Covers:
- committed mixed chunks containing deterministic source-empty blocks must be
  ready on a fresh coordinator instance without another provider call;
- automatic resume must not repay for an already committed mixed chunk;
- `DocumentBlockSlice` must reach the provider as the selected substring;
- sibling slice plans sharing the same source block must retain distinct plan
  identity;
- sibling slices must persist/reassemble without overwriting one another in the
  block-ID keyed archive.

**Expected red on candidate 17:** these tests pin the Reviewer findings around
mixed deterministic readiness and the non-end-to-end slice contract.

### S7 validator adversarial matrix — 13 tests

`Tests/VaniScriptCoreTests/S7AdversarialValidatorTests.swift`

Covers schema/chunk identity, duplicate IDs, source-empty mutation, Unicode
NFC/NFD, protected blocks/spans, placeholder order, decimal parity, duplicate
text source equivalence, length-ratio warning severity, source-language residue,
and strict malformed/unknown-field JSON.

### S7 contract / Codable boundaries — 12 tests

`Tests/VaniScriptCoreTests/S7ContractBoundaryTests.swift`

Covers source-anchor backward compatibility and rejection, block-slice clamping,
deterministic block classification, style inference, span synthesis, strict wire
fields, legacy response text compatibility, required response fields, complete
DocumentState round-trip, and extreme document offsets.

### Document import adversarial coverage — 8 tests

`Tests/VaniScriptTests/S7DocumentImportAdversarialTests.swift`

Covers CRLF/bare-CR normalization, NFC, Markdown role classification, empty text,
invalid UTF-8 cleanup, filename collisions, missing path versus directory, and
deterministic block identities across newline variants.

### Dual-pane scroll edge cases — 9 tests

`Tests/VaniScriptTests/S7ScrollEdgeCaseTests.swift`

Covers NaN/infinity clamping, degenerate geometry, reversed origins, one-shot
follower suppression, mismatched follower notifications, tolerance boundaries,
partial/final detach, and scope rebinding.

### Project archive / summary boundaries — 6 tests

`Tests/VaniScriptCoreTests/ProjectArchiveAdversarialTests.swift`

Covers normalized archive round-trip, single-record backward compatibility,
malformed archive rejection, deterministic recent sorting, summary completion
counting, and project-name fallback.

### Timeline cut mapping — 11 tests

`Tests/VaniScriptCoreTests/TimelineCutTimeMapperAdversarialTests.swift`

Covers overlapping/touching cut merge, trim clipping, sub-centisecond cuts,
non-finite inputs, negative geometry, intro/outro mapping, removed intervals,
physical/virtual round-trip, and incremental cut subtraction.

### Starter glossary data integrity — 8 tests

`Tests/VaniScriptCoreTests/StarterGlossaryAdversarialTests.swift`

Covers unique identities, complete translations, stable slug IDs, variant data
quality, empty merge, idempotence, existing-ID precedence, and case-insensitive
source precedence.

### MCP audit/cache/confirmation stores — 14 tests

`Tests/VaniScriptCoreTests/McpStoreAdversarialTests.swift`

Covers audit capacity/order/pagination, canonical request fingerprints,
idempotent replay, request-ID conflict detection, expiry, confirmation single
use, mismatch fail-closed behavior, operation/revision binding, expiry, and token
uniqueness.

**Total new Swift tests: 86.**

## New QA scripts

### `test_coverage_inventory.py`

Heuristically inventories every Swift production declaration against symbol
mentions in the Swift test corpus. It is not line coverage; it is a discovery
tool for forgotten public/internal surfaces. It can emit JSON for later triage.

```bash
python3 QA/scripts/test_coverage_inventory.py --json /tmp/vaniscript-test-coverage-gaps.json
```

### `s7_export_completeness_guard.py`

Pins the PDF/TXT export completeness boundary at `WorkflowStore.exportDocument`.
DOCX may preserve untranslated source blocks; PDF/TXT must not silently present
source fallback as a completed translated document.

**Expected red on candidate 17:** the current store reaches `NSSavePanel` after
checking only aggregate rendered text, which is non-empty even when the builder
fell back entirely or partially to source text.

### `run_expanded_regression.sh`

Runs all new suites, the existing S7 focused suites, the export guard, coverage
inventory, the existing `QA/run_all.sh`, and the entire `swift test` suite while
collecting all failures.

## Known product defects intentionally pinned by this package

1. **Oversized paragraph slices are planner-only.** Request construction still
   rehydrates the full `DocumentBlock`; sibling slice plans share ambiguous
   first/last block IDs; the translation archive is keyed only by source block
   ID and cannot safely store multiple sibling slices.
2. **Mixed deterministic-empty chunks are not ready on a later coordinator
   pass.** Empty deterministic archive entries are valid by presence but fail
   the mixed-chunk usable-text check, allowing repeat provider spend.
3. **PDF/TXT incomplete export is not honest.** Missing translations are
   replaced by source text before the store's non-empty guard, so zero/partial
   translations can pass as exportable translated text.

These failures should remain red until product fixes are implemented. Do not
weaken or delete the tests simply to restore a green suite.

## Execution limitation of this Tester session

The ChatGPT connector environment can inspect and write the GitHub branch but
cannot execute this macOS/AppKit Swift package: the local container has no
outbound GitHub clone access and is not the target macOS runtime. Therefore the
new tests were source-checked against the real declarations/contracts but were
not compiled/executed in this session.

Required execution on the project Mac:

```bash
bash QA/scripts/run_expanded_regression.sh
```

When run, classify failures in this order:
1. compiler/API mismatch in a new test -> fix the test;
2. assertion contradicts an explicit documented contract -> fix the test;
3. assertion matches the documented contract and source path -> product bug;
4. flaky timing/UI/hardware failure -> isolate and make deterministic before
   treating it as a product failure.
