# S7 Reviewer Result — Candidate 17

## Meta

| Field | Value |
|---|---|
| Step | S7 |
| Actor | reviewer |
| Timestamp | 2026-08-15T01:45:00Z |
| Candidate | `S7EmptyChunkExportChooserCandidate17` |
| RESULT | `changes_requested` |
| Verdict | `CHANGES_REQUESTED` |
| Reviewer | ChatGPT GPT-5.6 Sol |

## Scope reviewed

The review followed `AI_Workflow_Kit/docs/AI/REVIEW_PACKAGE_S7.md` and inspected the S7 source of truth, candidate-15/16/17 evidence, the listed implementation files, relevant callers/callees/contracts, and document-focused tests. Product source was not modified by this review.

Reviewed areas include:

- document contracts, project/bundle migration, and legacy media decoding;
- `SemanticChunkPlanner` / document request construction / translation archive interaction;
- `DocumentTranslationEngine`, repair/reconstruction, source-aware validation and failure preservation;
- `DocumentTranslationCoordinator` ready/advance semantics;
- Gemini structured-output transport and key-attempt behavior;
- document Dual View scroll synchronization and relayout recovery;
- empty-source approval policy;
- DOCX/PDF/TXT export builder/writers and their WorkflowStore entry point;
- document unit/integration coverage around the above paths.

## Verdict

**CHANGES_REQUESTED.**

Candidates 15–17 contain substantive fixes and several Reviewer gates are satisfied, but three cross-contract correctness gaps remain. They are not cosmetic and are not covered by the current 556-test suite.

## Blocking findings

### 1. Oversized-paragraph `blockSlices` stop at the planner boundary

`SemanticChunkPlanner` correctly splits an exceptional ordinary paragraph into multiple plans using `DocumentBlockSlice`, while retaining the same source `blockID`. The downstream translation path does not consume those slices:

- request construction resolves `plan.blockIDs` back to the full `DocumentBlock` and builds `DocumentTranslationInputBlock(block:)` from the entire paragraph;
- the wire contract has no slice identity/range that would let a response refer to one bounded fragment;
- `DocumentState.translationsByLanguage` is keyed by `blockID`, so multiple translated pieces of one oversized paragraph cannot coexist safely and later pieces can overwrite earlier ones.

**Impact:** the planner's advertised hard-limit fallback is not end-to-end. A paragraph that actually requires splitting can still be sent whole to the provider, and a future partial implementation risks translation loss during archive/reassembly.

**Required correction:** make the planner → request → response → archive path slice-aware, with stable unique slice identity and deterministic reassembly into the parent block before review/export. Add an integration regression that starts with one paragraph exceeding the hard source-token limit, produces multiple slices, translates every slice, persists them without overwrite, and reconstructs the complete paragraph exactly once and in order.

### 2. A valid mixed chunk containing source-empty deterministic blocks is not considered ready

`DocumentTranslationCoordinator.hasReadyTranslation(at:)` has a special presence-only rule for a *deterministic-only* chunk, but a mixed chunk falls through to:

`plan.blockIDs.allSatisfy { stored[$0].map { TranslationArchive.isUsableTranslationText($0.text) } ?? false }`

Source-empty deterministic blocks are intentionally reconstructed and archived with empty text. `TranslationArchive.isUsableTranslationText("")` is false. Therefore a successfully translated mixed chunk — including the live-shaped front matter used by S7, with ordinary translatable blocks plus structural empty blocks — can be committed and still be classified as "not ready" on the next coordinator run.

**Impact:** revisiting the chunk, `manualCurrent`, or a subsequent automatic pass can invoke the provider again for content that already has a valid committed translation. This violates ADR-001's ready-next/no-extra-provider-call invariant and can create unnecessary paid calls.

**Required correction:** readiness must be evaluated per block type: deterministic IDs require an archive entry/presence (empty text is valid for source-empty blocks); translatable IDs require usable translated text. Add a regression that processes a mixed 33-block live-shaped chunk with source-empty blocks, creates a fresh coordinator/pass, and proves `manualCurrent`/automatic continuation makes zero additional provider calls for that already-valid chunk.

### 3. PDF/TXT export is not honest when translations are missing

`DocumentTranslationExportBuilder.translatedDocumentText(...)` falls back to the original source text for every block without a translation. `WorkflowStore.exportDocument(format:)` then checks only whether the resulting aggregate text is nonblank before invoking PDF/TXT writers. Because source text itself is nonblank:

- a completely untranslated document can pass the export guard and be emitted as a PDF/TXT "reviewed document" containing the original source;
- a partially translated document can silently mix translated and untranslated source paragraphs without a completeness warning.

DOCX intentionally preserving untranslated package paragraphs is compatible with the current S7 gate, but the review package explicitly requires **PDF/TXT to be honest about missing translation**. The current behavior fails that gate.

**Required correction:** export must compute translation completeness from the document/archive (and preferably approval/review state), not from the fallback-rendered string. For PDF/TXT either block incomplete export with a clear error or make the incomplete/source fallback explicit in the UI/output contract. Add WorkflowStore-level regressions for zero translations and partial translations; both must not silently export as a completed translated document.

## Reviewer gates that passed on source/test inspection

1. **Backward compatibility:** new S7 Codable fields use additive/default decoding; missing `sourceKind` remains media, old media anchors are reconstructed, project migration accepts v1/v2/v3 and current v4 while rejecting unsupported schemas. Existing media output enum remains separate from `DocumentOutputFormat`.
2. **Failure preservation:** provider/validation failure paths in the document engine/coordinator do not erase a prior valid committed translation; targeted retranslation failure keeps the previous valid result.
3. **Deterministic echo dedupe:** `reconstructedResponse` consumes/synthesizes deterministic echoes without hiding genuine duplicate *translatable* IDs; those remain visible to the validator.
4. **Number parity:** decade/ordinal handling accepts `1970s` → `1970-х` while tests still reject genuinely changed and reordered numbers.
5. **Empty-source approval:** `DocumentApprovalAdvancePolicy.isSourceEmptyChunk` requires both the aggregate original and planned block texts to be empty; non-empty untranslated chunks keep the approval guard.
6. **Scroll re-sync:** normalized progress is re-applied without animation; relayout reapply is deferred while a pane is in live scroll, so it does not steal in-flight user leadership. AppKit bridge tests cover distinct pane ownership plus live and non-live scroll paths.
7. **Validation logging:** validation diagnostics log issue code + block hash metadata and provider attempt metadata, not manuscript text or credentials.

## Non-blocking findings / follow-up

1. **Header/footer ordinal mismatch:** `DOCXPackageReader` advances `paragraphOrdinal` across all parts sharing the enum role (`header` / `footer`), while `DocumentExportWriters.writeDOCX` groups by exact `partPath` and indexes the paragraph array within each individual XML file. With multiple header/footer parts, later parts can miss or target the wrong paragraph. This can remain deferred only if S8/S12 explicitly owns multi-part DOCX support; add a multi-header/footer fixture before claiming it.
2. **Translated mixed-run formatting:** current DOCX replacement puts translated paragraph text in the first text node and empties the remaining run text nodes. Paragraph properties/package entries are preserved, but inline style distribution across translated runs is not a true round-trip. This belongs to the later exact writer slice, not an S7 release-quality claim.
3. **Dead `.markdown` surface:** `DocumentOutputFormat.markdown` exists, is not offered by the UI, and is mapped to TXT by the store. Remove it for a clean cutover or expose a real Markdown contract later.
4. **System ZIP tools:** DOCX writing shells out to `/usr/bin/unzip` and `/usr/bin/zip`. This is acceptable for the current macOS-only target but is operational/implementation debt compared with the in-process reader path.

## Test/evidence assessment

Recorded Main evidence for candidate 17 is strong: focused 48/48, full 556/556, fresh build/app PID 71025, on top of candidate-15/16 focused/full evidence and Human live acceptance of Gemini translation, Dual View synchronization, and chunk-30 recovery. This review inspected the relevant tests and source contracts but did **not** independently re-execute the macOS Swift suite from the ChatGPT connector environment.

The three blocking findings are specifically coverage gaps across subsystem boundaries:

- planner slice → request/response/archive reassembly;
- mixed deterministic-empty + translated archive → second coordinator pass/zero-call readiness;
- export builder + WorkflowStore completeness policy for zero/partial PDF/TXT translations.

## Routing

Candidate 17 is not Reviewer-approved. Route back to Coder for a changed candidate addressing the three blocking findings while preserving the already-verified candidate-15/16/17 behavior. After Main verification and Human acceptance of the changed candidate, run one fresh Reviewer verdict under the established workflow policy; Tester remains gated on Reviewer approval.
