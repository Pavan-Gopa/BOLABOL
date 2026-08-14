# S7 Review Package (prepared, Reviewer NOT dispatched)

> Human instructed Main to prepare everything for review but hold the
> `workflow-reviewer` dispatch until an explicit go-ahead after the Human's
> experiment. This file is the complete, self-contained assignment Main will
> hand to a fresh `workflow-reviewer` run.

## Assignment (KICK_REVIEWER template filled)

```text
Review: S7 — Document contracts, bundle v4, visible document attach,
live runtime recovery candidates 15-17.
Source of truth:
- AI_Workflow_Kit/docs/PROJECT_CONTEXT.md
- AI_Workflow_Kit/docs/AI/STATE.yaml
- AI_Workflow_Kit/docs/STEPS.md (S7 card)
- AI_Workflow_Kit/docs/AI/FEEDBACK.md (candidate 15-17 entries)
Scope / target files:
- Sources/VaniScript/Services/DocumentTranslationEngine.swift
- Sources/VaniScript/Services/DocumentTranslationCoordinator.swift
- Sources/VaniScriptCore/DocumentTranslationValidator.swift
- Sources/VaniScript/Services/CloudTextTranslationEngine.swift
- Sources/VaniScript/Views/ThinScrollbarTuner.swift (dual-pane scroll bridge)
- Sources/VaniScript/Views/ReviewWorkspaceView.swift (document dual view)
- Sources/VaniScriptCore/WorkflowState.swift (approval policy)
- Sources/VaniScript/Stores/WorkflowStore.swift (approve/advance + export entry)
- Sources/VaniScript/Views/ExportWorkspaceView.swift (DOCX/PDF/TXT chooser)
- Sources/VaniScriptCore/DocumentTranslationExportBuilder.swift
- Sources/VaniScript/Services/DocumentExportWriters.swift
- Sources/VaniScriptCore/DocumentModels.swift (DocumentOutputFormat)
- Tests/VaniScriptCoreTests/*, Tests/VaniScriptTests/* document suites
Objective Gate evidence from Coder + Main:
- candidate 15: focused 34/34, full 540/540, fresh app; Human live-accepted
  Gemini translation and dual-pane scroll on chunks 1-29.
- candidate 16: focused 52/52, full 546/546, fresh app; Human live-accepted
  chunk 30 commit (1587 chars persisted, approved).
- candidate 17: focused 48/48, full 556/556 (76 suites), fresh app pid 71025;
  Human live acceptance of empty-chunk pass and export chooser pending.
Judgment gates (Reviewer owns):
- media projects and old .vaniscript bundles decode without content change;
  new fields additive decodeIfPresent only.
- provider/validator failure cannot erase a prior valid translation.
- deterministic echo dedupe must not hide genuine translatable duplicates.
- decade number parity must not accept genuinely changed numbers.
- empty-chunk approval must not approve non-empty untranslated chunks.
- DOCX export must preserve package entries, paragraph properties, and
  untranslated paragraphs; PDF/TXT must be honest about missing translation.
- scroll re-sync must not steal in-flight user leadership or animate.
- validation issue logging must remain metadata-only (no manuscript text,
  no credentials).
Inspect:
- actual diff of the listed files
- relevant callers/callees/contracts (engine <-> coordinator <-> store <-> view)
- intended semantics and bounded scope
```

## Main's pre-review observations (non-blocking candidates for Reviewer)

1. `DocumentOutputFormat` still declares an unused `.markdown` case
   (Sources/VaniScriptCore/DocumentModels.swift:138-143); the store maps it to
   TXT and the UI never offers it. Dead weight or intentional future surface;
   decide per clean-cutover rules.
2. `DocumentExportWriters.writeDOCX` shells out to `/usr/bin/unzip` and
   `/usr/bin/zip`. macOS-only is acceptable for this product, but the writers
   depend on system binaries; DOCXPackageReader already parses zip in-process.
   Reviewer may request in-process zip write for symmetry (not required).
3. Paragraph replacement indexes `p` elements from XPath
   `.//*[local-name()="p"]` by `paragraphOrdinal`. Verify ordinal alignment
   with DOCXPackageReader's import indexing (nested text boxes/footnotes).
4. `reconstructedResponse` providerOrderIsValid now accepts three shapes;
   confirm no path lets a translatable-duplicate response be treated as valid.

## Dispatch (run only after Human go-ahead)

Main spawns one fresh `workflow-reviewer` task with the assignment above,
run name `S7ReviewCandidate17`, records the verdict in FEEDBACK.md and
STATE.yaml, and routes Tester only on APPROVED + Human acceptance.
