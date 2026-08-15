# S7 Tester Bug Report — Candidate 17

## Status

**Tester status: `blocked` for full macOS runtime execution, with 3 source-confirmed product bugs. One of the three is additionally reproduced by an actually executed static QA gate.**

The previous candidate-17 evidence reports **556/556** Swift tests green. That evidence predates this Tester expansion and was **not re-executed by this Tester session**. This Tester added **86 Swift tests**, bringing the intended Swift corpus to **642 tests**.

No GitHub Actions workflow exists on the working branch and GitHub reports zero workflow runs for the Tester head. The available ChatGPT execution host is Linux `x86_64`, while `Package.swift` targets macOS 14 and the executable target depends on macOS/Apple-Silicon-oriented packages. Therefore the 642-test Swift suite cannot be honestly reported as executed here.

Run on the project Mac:

```bash
bash QA/scripts/run_expanded_regression.sh
```

The runner now persists a complete transcript, gate status table, coverage-gap JSON and Markdown summary under `QA/scripts/results/<UTC-run-id>/`, and refreshes `QA/scripts/results/latest-*`.

---

## BUG-S7-T01 — Mixed translated chunk can trigger a second provider call

**Severity:** High — correctness/cost regression
**Confidence:** Source-confirmed; runtime regression tests prepared
**Suspect:** `Sources/VaniScript/Services/DocumentTranslationCoordinator.swift`

### Reproduction contract

A document chunk contains:

1. a source-empty deterministic structural block;
2. a normal translatable block;
3. another source-empty deterministic structural block.

The first coordinator run successfully commits all three archive entries. The deterministic entries correctly contain empty output text. A new coordinator instance then checks readiness.

### Defect

`hasReadyTranslation(at:)` has a presence-only rule only when the **entire** plan is deterministic. Mixed plans fall through to a per-block `TranslationArchive.isUsableTranslationText(stored.text)` check. Empty deterministic output is intentionally valid but fails that non-empty usability predicate.

The previously completed chunk can therefore be classified as not ready and sent to the translation provider again.

### Regression tests

`Tests/VaniScriptTests/S7AdversarialCoordinatorTests.swift`

- `mixedChunkDoesNotRetranslateAfterSuccessfulCommit`
- `automaticResumeDoesNotRepayForMixedChunk`

Expected product behavior: second pass makes **0 additional provider calls**.

### Coder fix target

Readiness must be evaluated per planned block:

- deterministic block: archive entry presence is sufficient, including empty output for source-empty blocks;
- translatable block: archive entry must contain usable translated text.

Do not weaken the regression assertions to accept another provider call.

---

## BUG-S7-T02 — Oversized paragraph slices are not end-to-end safe

**Severity:** Critical for oversized-document fallback
**Confidence:** Source-confirmed across planner → engine → coordinator/archive; runtime regression tests prepared
**Suspects:**

- `Sources/VaniScriptCore/SemanticChunkPlanner.swift`
- `Sources/VaniScript/Services/DocumentTranslationEngine.swift`
- `Sources/VaniScript/Services/DocumentTranslationCoordinator.swift`
- document translation/archive contracts

### Defect A — selected slice is not carried to provider request

`SemanticChunkPlanner` can create multiple `DocumentChunkPlan`s using `DocumentBlockSlice` for one oversized paragraph. Downstream request construction resolves the plan's `blockIDs` back to the full source `DocumentBlock`; the provider contract has no stable slice identity/range that guarantees only the selected substring is translated.

### Defect B — sibling slice plans have ambiguous plan identity

Two slices of the same source paragraph both have the same first and last `blockID`. Coordinator plan lookup first matches by `DocumentRange(startBlockID:endBlockID)` and uses `first(where:)`, so a chunk representing the second slice can resolve to the first slice plan.

### Defect C — archive persistence overwrites sibling slices

Coordinator commit converts provider outputs to `TranslatedBlock` values and writes them into `translationsByLanguage[language]` keyed by `sourceBlockID`. Sibling slices retain the same source block ID, so distinct slice outputs cannot be safely persisted independently and can overwrite one another.

### Regression tests

`Tests/VaniScriptTests/S7AdversarialCoordinatorTests.swift`

- `requestBuilderHonorsBlockSlice`
- `secondSlicePlanKeepsItsIdentity`
- `siblingSlicesDoNotOverwriteEachOther`

Expected product behavior: every slice has a stable unique identity, only its selected source range reaches the provider, sibling slices are translated once each, and their outputs are deterministically reassembled into the parent paragraph without archive overwrite.

### Coder fix target

Make the full planner → request → response → persistence path slice-aware. Plan/chunk identity must not rely solely on first/last source block IDs when multiple plans can reference the same block. Reassemble the translated parent block deterministically before review/export.

---

## BUG-S7-T03 — PDF/TXT can silently export untranslated source as translated output

**Severity:** High — user-visible data correctness
**Confidence:** **Reproduced by executed static QA gate, exit code 1**
**Suspects:**

- `Sources/VaniScriptCore/DocumentTranslationExportBuilder.swift`
- `Sources/VaniScript/Stores/WorkflowStore.swift`

### Reproduction contract

Export a document to PDF or TXT when:

1. no blocks have translations; or
2. only a subset of blocks have translations.

### Defect

The export builder intentionally falls back to original source text for missing translated blocks (needed by the current DOCX preservation behavior). `WorkflowStore.exportDocument(format:)` then validates the aggregate rendered text rather than semantic translation completeness. Because the source fallback is non-empty, zero/partial translation can pass the export guard and be presented as translated PDF/TXT.

### Executed QA evidence

The repository's `QA/scripts/s7_export_completeness_guard.py` logic was actually executed against the exact current `WorkflowStore.exportDocument(format:)` function body fetched from this branch.

```text
FAIL: PDF/TXT export reaches NSSavePanel without checking translation completeness.
The current aggregate non-empty check can pass on source fallback from DocumentTranslationExportBuilder.
EXIT_CODE=1
```

Saved evidence: `QA/scripts/results/static-export-gate.log`.

This is an executed deterministic static QA failure, not merely a source inference.

### Coder fix target

Keep DOCX fallback behavior if required, but PDF/TXT must inspect document/archive completeness before save/write. Either block incomplete export with an explicit error or expose an explicit incomplete/source-fallback contract; never silently present fallback source as completed translation.

---

## Runtime execution required after fixes

Focused first:

```bash
swift test --filter S7AdversarialCoordinatorTests
python3 QA/scripts/s7_export_completeness_guard.py
```

Then full destructive QA:

```bash
bash QA/scripts/run_expanded_regression.sh
```

Do not mark Tester `qa_green` until the saved `latest-summary.md` is GREEN and the full Swift transcript reports the exact test count with zero failures. The 556/556 candidate-17 baseline is historical evidence only; the new 86 tests must be compiled and executed on the target macOS environment.