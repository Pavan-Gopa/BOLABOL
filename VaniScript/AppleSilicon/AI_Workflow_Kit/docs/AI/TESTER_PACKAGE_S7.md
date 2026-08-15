# S7 Tester Assignment (prepared)

```text
QA: S7 — Document contracts, bundle v4, visible document attach,
live runtime recovery candidates 15-17.

Feature:
- Gemini 3.x structured document output: LOW thinking, 32768 maxOutputTokens,
  five-key rotation, MAX_TOKENS/SAFETY terminal honesty.
- Dual-pane scroll: two NSScrollView, normalized 0…1 position, all scroll
  paths (wheel, scrollbar, keyboard), chunk-change re-sync after layout.
- Validator/merge: deterministic empty/protected echo deduplication in
  reconstructedResponse; decade-safe number comparison (1970s ≡ 1970-х);
  validation issue codes logged metadata-only.
- Empty-chunk approval: source-empty chunks advance without translation.
- Document export: DOCX (in-place paragraph rewriting), PDF (CoreText A4),
  TXT (UTF-8), user-selectable via Export chooser.

Source of truth:
- AI_Workflow_Kit/docs/PROJECT_CONTEXT.md
- AI_Workflow_Kit/docs/AI/STATE.yaml
- AI_Workflow_Kit/docs/STEPS.md (S7 card)
- AI_Workflow_Kit/docs/AI/FEEDBACK.md (candidates 15–17, Main verification)

Writable test/QA paths only:
- Tests/VaniScriptCoreTests/
- Tests/VaniScriptTests/
- QA/scripts/

QA Objective gates:
- [x] focused document-model and migration tests pass
- [x] focused classifier/import/reader tests pass
- [x] focused document-config/session tests pass
- [x] focused semantic-planner/document-review tests pass
- [x] focused document-translation/coordinator/targeted-retranslate tests pass
- [x] focused live document-runtime request/error-visibility tests pass
- [x] focused source-aware validator/deterministic-blank/subset-repair tests pass
- [x] focused document dual-pane scroll synchronization tests pass
- [x] focused Gemini five-key rotation, structured-output budget, terminal-diagnostic tests pass
- [x] focused chunk-29-shaped reconstruction, decade parity, chunk-change re-sync tests pass
- [x] focused empty-chunk approval and DOCX/PDF/TXT export writer tests pass
- [x] swift build and swift test exit 0
- [ ] coverage gaps mapped and documented (memory, edge cases, regression risk)
- [ ] any missing observable-behavior tests added

Commands:
- swift test
- swift test --filter DocumentTranslationEngine --filter DocumentTranslationValidator --filter DocumentTranslationRuntime --filter DocumentCloudStructuredOutput --filter DocumentCoordinator --filter DocumentReviewScrollSync --filter DocumentExport --filter DocumentTranslationExport --filter WorkflowStoreDocument
- look for any QA/scripts/cps_* scripts relevant to document translation
```