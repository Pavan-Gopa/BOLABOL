# Step cards

> Condensed cards for the current train. One step at a time.  
> Orchestrator opens a step in `STATE.yaml` only when the previous is green (or Human skips with a note).

---

## How to write a card

```markdown
## S1 — Short title

**Goal:** 1–3 sentences  
**Depends on:** S0 / none  
**Target files (sketch):**  
- path/a  
- path/b  

**Do:**
- [ ] first semantically verifiable work item
- [ ] next semantically verifiable work item

**Out of scope:**
- …

## Verification

### Objective gates

- [ ] `exact command` exits 0
- [ ] required artifact or behavior is deterministically present

### Judgment gates

- [ ] implementation follows the accepted architecture and intended semantics
- [ ] scope and public contracts remain bounded

**Ready for review when:** implementation is complete in scope and required
Objective gates are green.

**Stop-gate:** (Reviewer APPROVED | review explicitly skipped by Human) +
(Tester qa_green | QA explicitly skipped by Human)
```

---

## S0 — Ready + context

**Goal:** Orchestrator has read the workflow, received project context, and either opened a minimal plan or started Architect.  
**Depends on:** none  
**Target files (sketch):**
- `AI_Workflow_Kit/docs/PROJECT_CONTEXT.md`
- `AI_Workflow_Kit/docs/AI/STATE.yaml`
- `AI_Workflow_Kit/docs/STEPS.md`

**Do:**
- [x] [S0.D1] Orchestrator confirms: ready to work with this process.
- [x] [S0.D2] Human provides project context.
- [x] [S0.D3] Enough context → minimal plan (S1+). Thin context → Architect research + plan.
- [x] [S0.D4] Confirm gates: review on by default; Tester recommended.

**Out of scope:**
- Large product implementation before plan exists

## Verification

### Objective gates

- [x] [S0.O1] PROJECT_CONTEXT contains real project information

### Judgment gates

- [x] [S0.J1] next step or Architect path is clear

**Stop-gate:** Human agrees with the plan path

---

## S1 — Parakeet engine

**Goal:** Port the working BOLABOL Parakeet TDT 0.6B v3 engine and robust audio preparation into the VaniScript app target.  
**Depends on:** S0 and the existing catalog/download foundation  
**Target files (sketch):**
- `Sources/VaniScript/Services/LocalASREngine.swift`
- `Sources/VaniScript/Services/LocalASRAudioPreprocessor.swift`
- `Sources/VaniScript/Services/ParakeetTranscriptionEngine.swift`
- `Tests/VaniScriptTests/LocalASRAudioPreprocessorTests.swift`
- `Tests/VaniScriptTests/ParakeetTranscriptionEngineTests.swift`

**Do:**
- [x] [S1.D1] Add minimal local ASR engine and audio preparation contracts
- [x] [S1.D2] Port Parakeet v3/int8 loading, request validation, decoding, cancellation, and unload behavior
- [x] [S1.D3] Preserve unanchored auto-detect and safe explicit language hints
- [x] [S1.D4] Add deterministic tests without real model weights or network access
- [x] [S1.D5] Repair the pre-existing Canary release namespace test blocker
- [x] [S1.D6] Repair the stale Canary 1B download-source test blocker

**Out of scope:**
- Canary engines, pipeline routing, Models UI, or cloud package metadata

## Verification

### Objective gates

- [x] [S1.O1] `swift build` exits 0
- [x] [S1.O2] focused Parakeet/audio tests pass
- [x] [S1.O3] `swift test` exits 0

### Judgment gates

- [x] [S1.J1] BOLABOL behavior is ported without importing BOLABOL product dependencies
- [x] [S1.J2] engine residency, cleanup, and error semantics are bounded

**Ready for review when:** S1 implementation and objective gates are green.

**Stop-gate:** Reviewer APPROVED + Tester qa_green.

---

## S2 — Canary Flash and Canary 1B engines

**Goal:** Port BOLABOL’s Canary family Core ML engine for the exact Flash and 1B variants.  
**Depends on:** S1  
**Target files (sketch):**
- `Sources/VaniScript/Services/CanaryCoreMLEngine.swift`
- `Sources/VaniScript/Services/LocalASREngine.swift`
- `Tests/VaniScriptTests/CanaryCoreMLEngineTests.swift`

**Do:**
- [x] [S2.D1] Port Canary Flash encoder/prefill/decoder execution and silence-aware windows
- [x] [S2.D2] Port Canary 1B Path B stateful decoder with the macOS 15 gate
- [x] [S2.D3] Require explicit supported source language and fail unknown variants closed
- [x] [S2.D4] Add pure chunk, mask, position, language, and request tests

**Out of scope:**
- Pipeline/UI wiring and Canary translation

## Verification

### Objective gates

- [x] [S2.O1] `swift build` and focused Canary tests pass
- [x] [S2.O2] `swift test` exits 0

### Judgment gates

- [x] [S2.J1] `.cpuAndNeuralEngine`, ASR-only, OS, window, and model-layout invariants match BOLABOL

**Ready for review when:** S2 implementation and objective gates are green.

**Stop-gate:** Reviewer APPROVED + Tester qa_green.

---

## S3 — Local ASR language and readiness policy

**Goal:** Make descriptor-driven model, OS, presence, and source-language validation authoritative for all local ASR models.  
**Depends on:** S2  
**Target files (sketch):**
- `Sources/VaniScriptCore/NativeModelCatalog.swift`
- `Sources/VaniScriptCore/ProviderRegistry.swift`
- `Sources/VaniScriptCore/NativeProcessingReadiness.swift`
- `Tests/VaniScriptCoreTests/NativeModelRoutingTests.swift`
- `Tests/VaniScriptCoreTests/NativeProcessingReadinessTests.swift`
- `Sources/VaniScriptCore/AppSettings.swift`
- `Sources/VaniScript/Services/SettingsDiskStore.swift`
- `Sources/VaniScript/Stores/WorkflowStore.swift`
- `Sources/VaniScript/Services/SmartAudioAnalyzer.swift`
- `Tests/VaniScriptCoreTests/NativeModelCatalogTests.swift`
- `Tests/VaniScriptTests/RemoteModelPackageInstallerTests.swift`
- `Tests/VaniScriptTests/WorkflowStoreLocalModelTests.swift`
- `Tests/VaniScriptTests/SmartAudioAnalyzerTests.swift`

**Do:**
- [x] [S3.D1] Auto-connect verified BOLABOL Canary 1B packages from the shared root without main-thread integrity work
- [x] [S3.D2] Prevent SmartAudioAnalyzer end-frame overflow during native processing
- [x] [S3.D3] Resolve ready local ASR models through `activeLocalASRModel`
- [x] [S3.D4] Allow Parakeet auto; require explicit supported sources for Canary
- [x] [S3.D5] Distinguish incomplete model, unsupported OS, missing source, and unsupported source failures

**Out of scope:**
- Visual source picker and engine internals

## Verification

### Objective gates

- [x] [S3.O1] focused Core routing/readiness tests pass
- [x] [S3.O2] `swift test` exits 0

### Judgment gates

- [x] [S3.J1] no local model silently falls back to WhisperKit

**Ready for review when:** S3 implementation and objective gates are green.

**Stop-gate:** Reviewer APPROVED + (Tester `qa_green` | QA explicitly skipped by Human).

---

## S4 — Pipeline and live route wiring

**Goal:** Route WhisperKit, Parakeet, Canary Flash, and Canary 1B through one resident local-ASR router in batch, current-chunk, and live-dictation paths.  
**Depends on:** S3  
**Target files (sketch):**
- `Sources/VaniScriptCore/NativeProcessingReadiness.swift`
- `Sources/VaniScript/Services/LocalASREngine.swift`
- `Sources/VaniScript/Services/ParakeetTranscriptionEngine.swift`
- `Sources/VaniScript/Services/CanaryCoreMLEngine.swift`
- `Sources/VaniScript/Services/LocalASREngineRouter.swift`
- `Sources/VaniScript/Services/NativeProcessingPipeline.swift`
- `Sources/VaniScript/Stores/WorkflowStore.swift`
- `Sources/VaniScript/Views/ProcessingWorkspaceView.swift`
- `Sources/VaniScriptCore/NativeModelCatalog.swift`
- `Sources/VaniScript/Views/ChatSidebarView.swift`
- `Sources/VaniScript/Views/ConfigWorkspaceView.swift`
- `Tests/VaniScriptTests/LocalASREngineRouterTests.swift`
- `Tests/VaniScriptTests/NativeProcessingPipelineASRTests.swift`
- `Tests/VaniScriptCoreTests/NativeProcessingReadinessTests.swift`

**Do:**
- [x] [S4.D1] Bind each verified descriptor/path to its exact engine
- [x] [S4.D2] Expose independent source and target language controls filtered by selected ASR capabilities
- [x] [S4.D3] Skip translation when normalized source and target languages are the same
- [x] [S4.D4] Preserve review-ready timed cues for WhisperKit, Parakeet, Canary Flash, and Canary 1B; never flatten a full processing chunk into one cue
- [x] [S4.D5] Unload the previous ASR engine on model/path changes and before heavy local MLX work
- [x] [S4.D6] Route live dictation through the same policy without MainActor package hashing
- [x] [S4.D7] Show the exact local ASR model while loading and transcribing
- [x] [S4.D8] Auto-discover and test the verified Canary 1B package from supported local/shared roots
- [x] [S4.D9] Keep the Models `Active` badge, opened project/session provider, and processing engine on the same selected local ASR
- [x] [S4.D10] Accept a verified Canary 1B package containing harmless Finder metadata without weakening its manifest allowlist
- [x] [S4.D11] Bundle the required MLX Metal library in every fresh app build
- [x] [S4.D12] Normalize shared MLX catalog labels and isolate test settings persistence
- [x] [S4.D13] Preserve successful MLX cue batches and recover an empty batch without blanking the translation
- [x] [S4.D14] Recover a terminal single-cue MLX sentinel without discarding valid translated cues
- [x] [S4.D15] Reject partial or unstructured MLX cue batches instead of fabricating aligned cues
- [x] [S4.D16] Retry only explicit MLX output-validation failures, not operational errors
- [x] [S4.D17] Surface terminal MLX translation failure as an error instead of review-ready blank output
- [x] [S4.D18] Parse MLX terminal markers case-insensitively without leaking sentinels
- [x] [S4.D19] Recover one terminal END fence typo without weakening marker validation
- [x] [S4.D20] Recover empty terminal END-only replies without blanking prior cues
- [x] [S4.D21] Fall back empty terminal END-only leaves without blanking prior cues
- [x] [S4.D22] Require canonical terminal END as absolute suffix
- [x] [S4.D23] Prevent Parakeet without token timings from flattening a full chunk into one cue

**Out of scope:**
- Models UI redesign or cloud-provider changes

## Verification

### Objective gates

- [x] [S4.O1] focused timed-cue, provider-selection, Canary 1B discovery, and MLX terminal-recovery tests pass
- [x] [S4.O2] `swift build` and `swift test` exit 0

### Judgment gates

- [x] [S4.J1] all local routes fail explicitly without Whisper fallback or duplicate glossary/translation work

**Ready for Human test when:** S4 implementation and Objective Gates are green,
Main has built/opened the fresh app, and no Reviewer or Tester has run yet.

**Stop-gate:** Human ACCEPTED + Reviewer APPROVED + Tester `qa_green` (Tester explicitly skipped by Human).

---

## S5 — Models UI and local Canary 1B workflow

**Goal:** Expose honest download/locate/use/delete behavior for all three models, while treating Canary 1B as a verified local package until its cloud release exists.  
**Depends on:** S4  
**Target files (sketch):**
- `Sources/VaniScript/Views/SettingsView.swift`
- `Sources/VaniScript/Views/ConfigWorkspaceView.swift`
- `Sources/VaniScript/Stores/WorkflowStore.swift`
- applicable Core/UI tests

**Do:**
- [ ] [S5.D1] Keep Parakeet and Canary Flash downloads bound to their existing official sources
- [ ] [S5.D2] Keep Canary 1B Locate/use functional without fabricating a cloud URL or successful Download
- [ ] [S5.D3] Verify selection and state persistence

**Out of scope:**
- Publishing or inventing the future Canary 1B cloud package URL

## Verification

### Objective gates

- [ ] [S5.O1] focused model UI/state tests pass
- [ ] [S5.O2] `swift build` and `swift test` exit 0

### Judgment gates

- [ ] [S5.J1] every UI state and error message is honest and accessible

**Ready for review when:** S5 implementation and objective gates are green.

**Stop-gate:** Reviewer APPROVED + Tester qa_green.

---

## S6 — End-to-end local ASR acceptance

**Goal:** Prove the three-model integration without committing weights or requiring Canary 1B cloud metadata.  
**Depends on:** S5  
**Target files (sketch):**
- applicable `Tests/` and `QA/` paths only

**Do:**
- [ ] [S6.D1] Run complete build, Swift test, and QA gates
- [ ] [S6.D2] Smoke Parakeet and Canary Flash download/select/offline routes where model assets are available
- [ ] [S6.D3] Smoke Canary 1B locate/select/offline route when the local package is available
- [ ] [S6.D4] Record unavailable real-weight scenarios honestly; never fake green

**Out of scope:**
- Model conversion, model weights, or future cloud hosting

## Verification

### Objective gates

- [ ] [S6.O1] `swift build`, `swift test`, and applicable QA suite exit 0
- [ ] [S6.O2] real-model smoke evidence is recorded for every locally available model

### Judgment gates

- [ ] [S6.J1] no regression in WhisperKit, cloud transcription, or local MLX translation

**Ready for review when:** automated gates and available real-model smokes are complete.

**Stop-gate:** Reviewer APPROVED + Tester qa_green; unavailable external assets remain explicit blockers, not fabricated success.


---

## S7 — Document contracts, bundle v4, and visible document attach

**Goal:** Deliver a coherent document translation vertical slice: import, semantic planning, structured translation, sequential auto-approve, isolated chunk retranslation, and usable Review.  
**Depends on:** S5 parked by Human; S6 remains parked  
**Source of truth:** `docs/PRD-Document-Literary-Translation.md` §5–13, §16.1–16.4, §18, §20 Slices 1–6; `AI_Workflow_Kit/docs/DECISIONS.md` ADR-001  
**Target files (sketch):**
- `Sources/VaniScriptCore/DocumentModels.swift`
- `Sources/VaniScriptCore/DocumentTranslationProfile.swift`
- `Sources/VaniScriptCore/ProjectAssetManifest.swift`
- `Sources/VaniScriptCore/ProjectMigrator.swift`
- `Sources/VaniScriptCore/WorkflowState.swift`
- `Sources/VaniScriptCore/SessionModels.swift`
- `Sources/VaniScriptCore/AppSettings.swift`
- `Sources/VaniScriptCore/ProjectArchive.swift`
- `Sources/VaniScriptCore/ProjectBundleExporter.swift`
- `Sources/VaniScriptCore/ProjectBundleImporter.swift`
- `Sources/VaniScript/Views/UploadWorkspaceView.swift`
- `Sources/VaniScript/Stores/WorkflowStore.swift`
- `Sources/VaniScript/Services/SourceClassifier.swift`
- `Sources/VaniScript/Services/DocumentImportService.swift`
- `Sources/VaniScript/Services/DOCXPackageReader.swift`
- `Sources/VaniScript/Services/AppStoragePaths.swift`
- `Sources/VaniScript/Views/ConfigWorkspaceView.swift`
- `Sources/VaniScript/Views/ReviewWorkspaceView.swift`
- `Sources/VaniScriptCore/SemanticChunkPlanner.swift`
- `Sources/VaniScriptCore/TranslationBudgetPlanner.swift`
- `Sources/VaniScriptCore/DefaultPrompts.swift`
- `Sources/VaniScriptCore/DocumentTranslationContracts.swift`
- `Sources/VaniScriptCore/DocumentTranslationValidator.swift`
- `Sources/VaniScript/Services/DocumentTranslationEngine.swift`
- `Sources/VaniScript/Services/DocumentTranslationCoordinator.swift`
- `Sources/VaniScript/Services/CloudTextTranslationEngine.swift`
- `Sources/VaniScript/Services/MLXTextGenerationEngine.swift`
- `Sources/VaniScript/Views/ProcessingWorkspaceView.swift`
- `Sources/VaniScript/Views/ThinScrollbarTuner.swift`
- `Tests/VaniScriptCoreTests/DocumentModelTests.swift`
- `Tests/VaniScriptCoreTests/ProjectMigrationTests.swift`
- `Tests/VaniScriptTests/SourceClassifierTests.swift`
- `Tests/VaniScriptTests/DocumentImportServiceTests.swift`
- `Tests/VaniScriptTests/DOCXPackageReaderTests.swift`
- `Tests/VaniScriptTests/DocumentConfigWorkflowTests.swift`
- `Tests/VaniScriptCoreTests/SemanticChunkPlannerTests.swift`
- `Tests/VaniScriptCoreTests/TranslationBudgetPlannerTests.swift`
- `Tests/VaniScriptTests/DocumentReviewWorkflowTests.swift`
- `Tests/VaniScriptCoreTests/DocumentTranslationContractTests.swift`
- `Tests/VaniScriptCoreTests/DocumentTranslationValidatorTests.swift`
- `Tests/VaniScriptTests/DocumentTranslationEngineTests.swift`
- `Tests/VaniScriptTests/DocumentCoordinatorTests.swift`
- `Tests/VaniScriptTests/DocumentCloudStructuredOutputTests.swift`
- `Tests/VaniScriptTests/DocumentTranslationRuntimeTests.swift`
- `Tests/VaniScriptTests/DocumentReviewScrollSyncTests.swift`
- `Tests/Fixtures/synthetic-document.docx`

**Do:**
- [x] [S7.D1] Add `WorkflowSourceKind`, optional `SourceAnchor`, `DocumentState` / `DocumentBlock` / `RichTextSpan` / `DocumentLocation` / `DocumentChunkPlan`
- [x] [S7.D2] Add `ApprovalMode`, `ReviewDisposition`, `ChunkQualityReport`; keep `approved` synchronized for old UI
- [x] [S7.D3] Raise bundle schema to v4 with typed `ProjectAssetManifest`; import v1/v2/v3 unchanged
- [x] [S7.D4] Decode missing `sourceKind` as media and missing `sourceAnchor` from `startSec`/`endSec`
- [x] [S7.D5] Add a small synthetic DOCX fixture under `Tests/`; do not commit the publisher manuscript
- [x] [S7.D6] First upload card: copy `Upload Media / Document`, detail names DOCX/TXT/MD/RTF/PDF; real drag-and-drop
- [x] [S7.D7] `chooseSourceFile` classifies media vs document; documents skip `MediaDurationReader`
- [x] [S7.D8] `DocumentImportService` copies the file into the project store, records SHA-256, sets `sourceKind`, builds `DocumentState` for docx/txt/md
- [x] [S7.D9] `DOCXPackageReader` walks `w:p`, preserves `w:pPr`, merges only visually identical runs
- [x] [S7.D10] Reject `.docm`, zip-slip, external relationships, XXE, oversized packages with honest errors
- [x] [S7.D11] Config hides Audio Metadata / Transcription Model / Chunk Duration / Slice Mode for documents; shows document title/author, source/target language, translation model
- [x] [S7.D12] Source Language auto-detects from the document text; no manual fill required
- [x] [S7.D13] `startSession` consumes deterministic semantic `DocumentChunkPlan` groups; it must not create one chunk per block
- [x] [S7.D14] Semantic planner groups chapter/paragraph/quote/verse atoms within provider-aware token budgets; a book with 872 blocks yields a bounded plan, not 872 chunks
- [x] [S7.D15] Document Review renders non-empty source content with document block/chapter labels and no media waveform/timecodes
- [x] [S7.D16] Initialize Engine transitions visibly to the document Review and persists the semantic plan/session
- [x] [S7.D17] Config exposes a per-project Auto-approve checkbox; its value snapshots into `SessionState.approvalMode`
- [x] [S7.D18] Add separate document prompts + strict block JSON contract/validator; never fill a missing block with source text
- [x] [S7.D19] Sequential coordinator translates all pending chunks, autosaves each valid result, and in automatic mode auto-approves then continues through the end
- [x] [S7.D20] Add `Retranslate Current`: exactly one selected chunk, no queue chaining even when Auto-approve is enabled, replacement remains pending manual `Approve & Next`
- [x] [S7.D21] Targeted retranslation preserves the last valid translation on provider/validation failure
- [x] [S7.D22] Manual `Approve & Next` navigates to an already translated next chunk without re-calling the provider; an untranslated next chunk is processed only through the normal manual workflow
- [x] [S7.D23] Cloud document generation requests structured JSON (`application/json` / supported response-format); media generation payloads remain unchanged
- [x] [S7.D24] Deterministic tests pin targeted success no-chain/manual-pending, ready-next zero calls, Auto-approve snapshot, and batch continuation past `Needs Review`
- [x] [S7.D25] A selected chunk request contains only its planned blocks plus bounded neighboring context; the full project glossary is filtered/deduplicated instead of repeated through profile and memory
- [x] [S7.D26] Provider prompt states the exact response JSON shape, required IDs, and allowed style IDs; live-shaped payloads remain within the selected model budget
- [x] [S7.D27] Coordinator/store distinguish success, validation failure, provider failure, and cancellation; a failed request never reports “retranslated” or opens an empty result as success
- [x] [S7.D28] Review visibly exposes the selected chunk's actionable quality/provider error and allows retry without losing a prior valid translation
- [x] [S7.D29] Metadata-only diagnostics record provider ID, chunk index, source/prompt/output sizes, attempts, and failure class without logging manuscript text or credentials
- [x] [S7.D30] Regression tests reproduce the current 105-entry glossary project shape and prove one selected 636-character chunk does not become a 150k-character prompt
- [x] [S7.D31] Source-empty/protected structural blocks are deterministic: they are excluded from provider translation work, merged back in original order, and accepted empty only when the source is empty
- [x] [S7.D32] Validator duplicate/explanation/residue checks are source-aware: identical source paragraphs may share a translation; a source label may translate as a label; ordinary copied prose and unsolicited wrappers still fail or warn
- [x] [S7.D33] Repair calls contain only invalid translatable block IDs, merge repaired blocks into the prior candidate, and validate the reconstructed full response; never resend the entire chunk as an “invalid subset” repair
- [x] [S7.D34] A live-shaped 33-block front-matter regression (11 empty blocks, repeated source paragraph, `Translation: [NAME]`, URL/copyright) commits the valid provider response instead of producing false blocking errors
- [x] [S7.D35] Document Dual View uses one normalized `0...1` scroll position: direct live scrolling of either source or translated pane drives the other pane without animation
- [x] [S7.D36] Unequal document heights map top-to-top and bottom-to-bottom exactly; either pane can reach its real bottom without clipping, jumping, or stale offset
- [x] [S7.D37] Programmatic follower updates, text binding/layout changes, and caret visibility cannot create feedback loops or steal leadership; user scrolling remains immediately interruptible from either side
- [x] [S7.D38] Chunk/language changes reset or rebind both panes deterministically; Source-only/Translated-only and all media Review paths remain unchanged
- [x] [S7.D39] AppKit-level scroll tests cover unequal heights, exact boundaries, bidirectional leadership, feedback suppression, relayout/clamping, and chunk reset
- [x] [S7.D40] The real SwiftUI/AppKit bridge resolves two distinct pane-owned `NSScrollView` instances; wheel/trackpad, scrollbar, and keyboard scrolling all drive the opposite pane
- [x] [S7.D41] Gemini document translation exposes safe per-key attempt index/count, HTTP/failure class, elapsed time, response size, and finish reason without logging keys or manuscript content
- [x] [S7.D42] Gemini rotates across every enabled key on rotatable quota/capacity failures; a deterministic five-key fixture proves ordered fallback and terminal behavior
- [x] [S7.D43] Direct Gemini structured document generation uses an output budget/contract that returns complete JSON for the live 18-block and 37-block request shapes or reports an actionable terminal reason instead of an apparent reset
- [x] [S7.D44] Deterministic empty/protected provider echoes are deduped in reconstruction; decade number parity is safe; validation issue codes are logged metadata-only (candidate 16)
- [x] [S7.D45] Source-empty chunks approve and advance without translation; document export offers DOCX, PDF, and TXT chosen by the user (candidate 17)

**Out of scope:**
- Full block-level repair editor (DOCX translation export writer added by Human request)

## Verification

### Objective gates

- [x] [S7.O1] focused document-model and migration tests pass
- [x] [S7.O2] focused classifier/import/reader tests pass
- [x] [S7.O3] focused document-config/session tests pass
- [x] [S7.O4] focused semantic-planner/document-review tests pass
- [x] [S7.O5] focused document-translation/coordinator/targeted-retranslate tests pass
- [x] [S7.O6] focused live document-runtime request/error-visibility tests pass
- [x] [S7.O7] focused source-aware validator/deterministic-blank/subset-repair tests pass
- [x] [S7.O8] focused document dual-pane scroll synchronization tests pass
- [x] [S7.O9] focused Gemini five-key rotation, structured-output budget, and terminal-diagnostic tests pass
- [x] [S7.O10] focused chunk-29-shaped reconstruction, decade parity, and chunk-change scroll re-sync tests pass
- [x] [S7.O11] focused empty-chunk approval and DOCX/PDF/TXT export writer tests pass
- [x] [S7.O12] `swift build` and `swift test` exit 0

### Judgment gates

- [ ] [S7.J1] media projects and old `.vaniscript` bundles decode without content change
- [ ] [S7.J2] new fields are additive `decodeIfPresent` only
- [ ] [S7.J3] a chosen `.docx`/`.txt` attaches and is visible as a document source; media path unchanged
- [ ] [S7.J4] Config adapts to document type without manual intervention
- [ ] [S7.J5] Auto-approve batch translates sequentially through the end and persists every locally valid result
- [ ] [S7.J6] `Retranslate Current` processes only the selected chunk, never chains, and requires manual approval
- [x] [S7.J7] provider/validator failure cannot erase a prior valid translation

**Ready for Human test when:** a fresh app translates the manuscript sequentially with optional Auto-approve, and Review can retranslate one chosen chunk without starting another.

**Stop-gate:** Human ACCEPTED + Reviewer APPROVED + (Tester qa_green | QA explicitly skipped by Human).

---

## S8 — Document IR depth and preflight

**Goal:** Deepen DOCX IR (tables, headers/footers, run merging, NFC) and expose honest preflight counts.  
**Depends on:** S7  
**Source of truth:** PRD §7, §19.1–19.2, §20 Slice 2  
**Target files (sketch):**
- `Sources/VaniScript/Services/DOCXPackageReader.swift`
- `Sources/VaniScript/Services/DocumentImportService.swift`
- `Tests/VaniScriptTests/DOCXPackageReaderTests.swift`
- `Tests/VaniScriptTests/DocumentImportServiceTests.swift`

**Do:**
- [ ] [S8.D1] Walk `w:p` in tables and text boxes; headers/footers/footnotes/endnotes as parts
- [ ] [S8.D2] Merge only visually identical runs; keep italic/bold/small-caps/hyperlink boundaries
- [ ] [S8.D3] Normalize NFC without stripping diacritics; drop field instructions/bookmarks/drawings from translate-text
- [ ] [S8.D4] Emit preflight counts (pages, words, sections, blocks, protected groups, font warnings)

**Out of scope:**
- PDF/RTF importers, chunk packing, translation, writer

## Verification

### Objective gates

- [ ] [S8.O1] focused reader/preflight tests pass
- [ ] [S8.O2] `swift build` and `swift test` exit 0

### Judgment gates

- [ ] [S8.J1] original bytes stay identical; IR IDs are stable across two imports of the same file
- [ ] [S8.J2] NSAttributedString officeOpenXML is fallback/preview only, never the round-trip source

**Ready for Human test when:** S8 implementation and Objective Gates are green and a fresh app shows preflight for the synthetic fixture.

**Stop-gate:** Human ACCEPTED + Reviewer APPROVED + (Tester qa_green | QA explicitly skipped by Human).

---

## S9 — Semantic chunk planner

**Status:** absorbed into S7 after Human acceptance feedback; do not dispatch separately. S7 candidate 04 owns this card's implementation and gates.

**Goal:** Pack atomic document groups into provider-aware token budgets without splitting paragraphs, quotes, or shlokas.  
**Depends on:** S8  
**Source of truth:** PRD §8, §20 Slice 3  
**Target files (sketch):**
- `Sources/VaniScriptCore/SemanticChunkPlanner.swift`
- `Sources/VaniScriptCore/TranslationBudgetPlanner.swift`
- `Tests/VaniScriptCoreTests/SemanticChunkPlannerTests.swift`
- `Tests/VaniScriptCoreTests/TranslationBudgetPlannerTests.swift`

**Do:**
- [x] [S9.D1] Classify blocks from style ID, outline, emptiness, and neighbors
- [x] [S9.D2] Mark protected Sanskrit/transliteration/names; keep verse+gloss+citation atomic
- [x] [S9.D3] Attach chapter titles to the first body block; never cross a chapter unless required
- [x] [S9.D4] Size chunks from real model context/output, not a global character cap
- [x] [S9.D5] Attach read-only before/after context; hash plan from blocks + profile + glossary + prompt version

**Out of scope:**
- LLM calls, coordinator, UI preview screen (data only)

## Verification

### Objective gates

- [x] [S9.O1] focused planner/budget tests pass, including deterministic IDs
- [x] [S9.O2] `swift build` and `swift test` exit 0

### Judgment gates

- [ ] [S9.J1] ordinary paragraphs never split; shlokas never detach from their gloss
- [ ] [S9.J2] empty paragraphs stay in the output map but spend no LLM budget

**Ready for Human test when:** absorbed implementation and Objective Gates are verified with S7 candidate 04.

**Stop-gate:** Human ACCEPTED + Reviewer APPROVED + (Tester qa_green | QA explicitly skipped by Human).

---

## S10 — Structured literary translation

**Status:** absorbed into S7 after Human acceptance feedback; do not dispatch separately. S7 candidate 05 owns this card's implementation and gates.

**Goal:** Translate planned chunks through a strict JSON contract with deterministic validation and targeted repair.  
**Depends on:** S9  
**Source of truth:** PRD §9–11, §20 Slice 4  
**Target files (sketch):**
- `Sources/VaniScriptCore/DefaultPrompts.swift`
- `Sources/VaniScriptCore/DocumentTranslationContracts.swift`
- `Sources/VaniScriptCore/DocumentTranslationValidator.swift`
- `Sources/VaniScript/Services/DocumentTranslationEngine.swift`
- `Sources/VaniScript/Services/CloudTextTranslationEngine.swift`
- `Sources/VaniScript/Services/MLXTextGenerationEngine.swift`
- `Tests/VaniScriptCoreTests/DocumentTranslationContractTests.swift`
- `Tests/VaniScriptCoreTests/DocumentTranslationValidatorTests.swift`

**Do:**
- [x] [S10.D1] Add separate prompt IDs; do not change active transcript presets
- [x] [S10.D2] Require one output block per input ID, same order, known style IDs only
- [x] [S10.D3] Treat a missing block ID as failure, never as a successful original-text fill
- [x] [S10.D4] Auto-approve only after the local validator; two failed repairs → `Needs Review`
- [x] [S10.D5] Ship a mock provider first; then wire cloud/MLX structured output

**Out of scope:**
- Queue/autosave UI, DOCX writer, package export

## Verification

### Objective gates

- [x] [S10.O1] focused contract/validator/repair tests pass
- [x] [S10.O2] `swift build` and `swift test` exit 0

### Judgment gates

- [ ] [S10.J1] literary quality is inside the single strict pass; no second free polish of the whole book
- [ ] [S10.J2] media cue translation behavior is unchanged

**Ready for Human test when:** S10 implementation and Objective Gates are green.

**Stop-gate:** Human ACCEPTED + Reviewer APPROVED + (Tester qa_green | QA explicitly skipped by Human).

---

## S11 — Coordinator and document workspace UX

**Status:** absorbed into S7 after Human acceptance feedback; do not dispatch separately. S7 candidate 05 owns this card's implementation and gates.

**Goal:** Run a sequential document queue with pause/resume/crash recovery, and show document-specific upload/config/processing/review.  
**Depends on:** S10  
**Source of truth:** PRD §12–13, §16, §20 Slices 5–6  
**Target files (sketch):**
- `Sources/VaniScript/Services/DocumentTranslationCoordinator.swift`
- `Sources/VaniScript/Stores/WorkflowStore.swift`
- `Sources/VaniScript/Views/UploadWorkspaceView.swift`
- `Sources/VaniScript/Views/ConfigWorkspaceView.swift`
- `Sources/VaniScript/Views/ProcessingWorkspaceView.swift`
- `Sources/VaniScript/Views/ReviewWorkspaceView.swift`
- `Tests/VaniScriptTests/DocumentCoordinatorTests.swift`

**Do:**
- [ ] [S11.D1] Sequential coordinator with translation memory, atomic save, backoff, and `processing` → `pendingRetry` on reopen
- [x] [S11.D2] Upload card accepts documents; real drag-and-drop; classifier routes media vs document
- [x] [S11.D3] Config hides audio/ASR/chunk-minutes; shows profile, Sanskrit policy, auto-approve, preflight
- [x] [S11.D4] Processing shows chapter/paragraphs, not timecode; counts auto-approved / needs review / failed
- [ ] [S11.D5] Review hides waveform; locked protected verses; per-block edit / retranslate / repair / approve

**Out of scope:**
- DOCX writer, translation-package folder export

## Verification

### Objective gates

- [ ] [S11.O1] focused coordinator/crash-recovery tests pass
- [ ] [S11.O2] `swift build` and `swift test` exit 0

### Judgment gates

- [ ] [S11.J1] automatic mode never auto-approves a validator failure
- [ ] [S11.J2] media upload/config/review paths stay intact

**Ready for Human test when:** S11 implementation and Objective Gates are green and a fresh app can import, queue, and review the synthetic fixture.

**Stop-gate:** Human ACCEPTED + Reviewer APPROVED + (Tester qa_green | QA explicitly skipped by Human).

---

## S12 — DOCX round-trip and translation package

**Goal:** Patch the original OOXML with accepted block translations and export original + localized DOCX + `.vaniscript`.  
**Depends on:** S11  
**Source of truth:** PRD §14–15, §20 Slices 7–8  
**Target files (sketch):**
- `Sources/VaniScript/Services/DOCXRoundTripWriter.swift`
- `Sources/VaniScript/Services/TranslationPackageExporter.swift`
- `Sources/VaniScriptCore/ProjectBundleExporter.swift`
- `Sources/VaniScriptCore/ProjectBundleImporter.swift`
- `Sources/VaniScript/Views/ExportWorkspaceView.swift`
- `Tests/VaniScriptTests/DOCXRoundTripWriterTests.swift`
- `Tests/VaniScriptTests/TranslationPackageExporterTests.swift`

**Do:**
- [ ] [S12.D1] Copy original DOCX; replace only allowed text nodes; keep `w:pPr`, styles, fonts, relationships
- [ ] [S12.D2] Fail closed if location/`sourceHash` no longer match
- [ ] [S12.D3] Warn when Brill/Gentium are referenced but not embedded; do not ship font files
- [ ] [S12.D4] Export package is three files in a chosen folder via temp dir + atomic move
- [ ] [S12.D5] Reopen `.vaniscript` restores IR and output without reparse or retranslate

**Out of scope:**
- Pixel-identical pagination, TOC page-number rewrite, PDF reconstruction

## Verification

### Objective gates

- [ ] [S12.O1] focused writer/package tests pass
- [ ] [S12.O2] `swift build` and `swift test` exit 0

### Judgment gates

- [ ] [S12.J1] original file stays byte-identical; localized file is a valid DOCX
- [ ] [S12.J2] `DocumentOutputFormat` stays separate from media `OutputFormat`

**Ready for Human test when:** S12 implementation and Objective Gates are green and a fresh app exports a three-file package from the synthetic fixture.

**Stop-gate:** Human ACCEPTED + Reviewer APPROVED + (Tester qa_green | QA explicitly skipped by Human).

---

## S13 — Hardening and extra import tiers

**Goal:** Add honest non-DOCX import tiers and prove media + document suites together.  
**Depends on:** S12  
**Source of truth:** PRD §7.1, §19–20 Slice 9, §22  
**Target files (sketch):**
- `Sources/VaniScript/Services/PDFDocumentImporter.swift`
- `Sources/VaniScriptCore/ProjectArchive.swift`
- `Sources/VaniScriptCore/ProjectBundleImporter.swift`
- `Sources/VaniScript/Stores/WorkflowStore.swift`
- `Sources/VaniScript/Views/ProjectSidebarView.swift`
- applicable extra importers and `Tests/` / `QA/` paths
**Do:**
- [x] [S13.D1] TXT/Markdown/RTF as structural import with an honest accuracy badge
- [x] [S13.D2] Text-layer PDF as reconstruction; scanned PDF/OCR stays an explicit later stage
- [x] [S13.D3] Security limits, cancellation, and large-document tests
- [x] [S13.D4] Full media regression: WhisperKit, cloud transcription, local MLX translation
- [x] [S13.D5] Import one or more `.vaniscript` files from Finder into the sidebar; use each archive's current filename as its persisted project display name while retaining source metadata
- [x] [S13.D6] Preserve explicit source foreground colors through rich import, strict translation, attributed Review editing, persistence, rich export; keep plain formats honestly plain
- [ ] [S13.D7] Replace Light-mode-invisible chrome across Upload, Config, Processing, Review, Export, Settings, and sidebars with the existing semantic dynamic-color system
- [x] [S13.D8] Make proofreading highlights visually prominent and legible in both appearances without changing persisted/exported document formatting
- [x] [S13.D9] Make project deletion conditional: remove clean imported projects without warning, protect dirty imported projects with save/discard/export choices, and keep destructive confirmation for new local projects
**Out of scope:**
- Vision OCR productization, `.docm`, pixel-identical page count

## Verification

### Objective gates

- [x] [S13.O1] `swift build`, `swift test`, and applicable QA suite exit 0
- [x] [S13.O2] unavailable OCR/real-manuscript cases are recorded honestly
- [x] [S13.O3] focused rich-color import/translation/edit/export tests pass
- [x] [S13.O4] focused dynamic Light/Dark contrast, disabled-state, and attributed-editor tests pass
- [ ] [S13.O5] fresh-app Light and Dark workflow smoke confirms readable text, icons, editors, errors, disabled controls, and action bars
- [x] [S13.O6] focused project-bundle import and multi-file Finder-drop tests pass
- [x] [S13.O7] focused project-deletion policy and action tests pass
### Judgment gates

- [ ] [S13.J1] no media-pipeline regression; no fabricated format support
- [ ] [S13.J2] provider output cannot invent trusted document formatting; old projects decode with automatic foreground color
- [ ] [S13.J3] every primary workflow surface remains readable and editable in both appearances
- [ ] [S13.J4] renamed project display names stay distinct from original document/media metadata across import, reopen, and re-export

**Ready for review when:** automated gates and available smokes are complete.

**Stop-gate:** Reviewer APPROVED + Tester qa_green; unavailable external assets remain explicit blockers, not fabricated success.

---

## S14 — Editorial workspace: AI selection retranslation

**Goal:** One context-menu command in the translated Document Review pane: retranslate only the selected phrase through the configured AI provider with trusted structural source context, applying the result through the canonical rich-text mutation path (PRD §10, slice E4; scope change ADR-003).
**Depends on:** S13 base (parked; rich-text identity verified in candidate 24)
**Source of truth:** `docs/PRD-Editorial-Review-Workspace.md` §6, §10, §20, §24, §26.5, ADR-E3/E4; `AI_Workflow_Kit/docs/DECISIONS.md` ADR-003
**Target files (sketch):**
- `Sources/VaniScriptCore/DocumentSelectionTranslationContracts.swift` (new)
- `Sources/VaniScriptCore/DocumentSelectionTranslationValidator.swift` (new)
- `Sources/VaniScript/Services/DocumentSelectionTranslationEngine.swift` (new)
- `Sources/VaniScriptCore/DocumentRichTextMutation.swift`
- `Sources/VaniScript/Views/ReviewWorkspaceView.swift`
- new tests under `Tests/VaniScriptCoreTests/` and `Tests/VaniScriptTests/`

**Do:**
- [x] [S14.D1] Remove the rejected candidate 02 custom formatting UI: Formatting submenu, ⌘B/⌘I/⌘U trait shortcuts, Clear Manual Formatting item, and their View-layer plumbing; standard macOS system formatting stays untouched
- [x] [S14.D2] Keep the selection bridge (`DocumentTextSelectionSnapshot`/`DocumentTextFragment`, UTF-16, deterministic SHA-256 block hashes), the pure `DocumentRichTextMutation` replace path, and paste sanitization (INV-7) as the canonical foundation
- [x] [S14.D3] Add one context-menu item `Retranslate Selection with AI…` in the translated pane only; enabled only for a non-empty selection inside one logical `DocumentBlock`; disabled for empty or cross-block selections
- [x] [S14.D4] Build the structural request from trusted attributes: selected target fragment, small target prefix/suffix, mapped source spans (or the whole source block marked as block-level context); never resolve the selection by string search; never send the whole chunk
- [x] [S14.D5] Route through the existing `editingProviderID` provider selection used by document retranslation; strict `vaniscript.document.selection.v1` response: `replacementText` plain text only; AI never supplies blockID/spanID/styleKey/color/policy (INV-4)
- [x] [S14.D6] Validate the response (schema, operationID match, non-empty, protected-term preservation); verify the affected block hash is still current before applying; a stale response surfaces a review suggestion instead of overwriting newer manual edits
- [x] [S14.D7] Apply the validated replacement atomically through `DocumentRichTextMutation` with trusted formatting inheritance; provider/validation failure preserves the original selection and shows an honest error
- [x] [S14.D8] AI selection tests per PRD §26.5: request shape, source mapping, provider-failure preservation, schema/operationID rejection, stale-response gate, cross-block disabled, trusted formatting inheritance

**Out of scope:**
- Custom formatting commands and trait toggles (standard macOS formatting is sufficient — ADR-003), Replace Everywhere, freshness policy, autosave redesign, export overlay, media paths, source-pane `Translate Selection` (later slice)

## Verification

### Objective gates

- [x] [S14.O1] `swift build` exits 0
- [x] [S14.O2] focused AI-selection and mutation tests pass
- [x] [S14.O3] `swift test` exits 0

### Judgment gates

- [x] [S14.J1] one canonical mutation path; AI replacement updates `DocumentState`, not just the screen string
- [x] [S14.J2] AI response cannot overwrite newer manual edits
- [x] [S14.J3] media review behavior unchanged

**Ready for review when:** implementation is complete in scope and required Objective gates are green.

**Stop-gate:** Reviewer APPROVED + Tester qa_green.

---

## S15 — Editorial workspace: freshness and transactional mutations

**Goal:** Source edits mark dependent translations stale without deleting them; every programmatic edit becomes one atomic transaction with a single Undo and debounced autosave (PRD slice E2).  
**Depends on:** S14  
**Source of truth:** `docs/PRD-Editorial-Review-Workspace.md` §9, §14, §15, §23, §26.4, ADR-E5  
**Target files (sketch):**
- `Sources/VaniScriptCore/DocumentTranslationFreshness.swift` (new)
- `Sources/VaniScript/Services/DocumentEditingCoordinator.swift` (new)
- `Sources/VaniScript/Stores/WorkflowStore.swift`
- `Sources/VaniScript/Views/ReviewWorkspaceView.swift`
- new tests under `Tests/`

**Do:**
- [x] [S15.D1] `TranslationFreshness` (missing/fresh/stale) derived from existing `sourceHash` comparison; no new mandatory state
- [x] [S15.D2] Source text edit recomputes `DocumentBlock.sourceHash`, keeps the previous `TranslatedBlock` intact, and moves previously approved chunks to `needsReview`
- [x] [S15.D3] Formatting-only source edit keeps the text hash and does not stale translations
- [x] [S15.D4] `DocumentEditingCoordinator` applies `DocumentEditTransaction` (before/after block patches) and registers inverse operations with `UndoManager`; one mutation = one Undo step
- [x] [S15.D5] Programmatic undo/redo mutate the canonical model through the coordinator, never `NSTextStorage` alone
- [x] [S15.D6] Debounced disk autosave (~300–500 ms) with mandatory flush on chunk change, focus loss, before export, project switch, termination, and after every transaction; save failure keeps in-memory edits and surfaces a persistent retryable error
- [x] [S15.D7] Review UI shows `Source changed — translation needs review` for stale blocks
- [x] [S15.D8] Freshness, transaction, undo, and save/reopen tests per PRD §26.4

**Out of scope:**
- Replace Everywhere, AI selection, export overlay, media paths

## Verification

### Objective gates

- [x] [S15.O1] `swift build` exits 0
- [x] [S15.O2] focused freshness/transaction/reopen tests pass
- [x] [S15.O3] `swift test` exits 0

### Judgment gates

- [x] [S15.J1] no translation is ever deleted by a source edit
- [x] [S15.J2] model, editor, and persisted project agree after undo and reopen
- [x] [S15.J3] typing path does not save the project per keystroke

**Ready for review when:** implementation is complete in scope and required Objective gates are green.

**Stop-gate:** Reviewer APPROVED + Tester qa_green.

---

## S16 — Editorial workspace: Replace Everywhere

**Goal:** Document-wide terminology replacement directly through canonical `DocumentState` — rich-text safe, protected-span aware, one atomic transaction with one Undo and one save (PRD slice E3).  
**Depends on:** S15  
**Source of truth:** `docs/PRD-Editorial-Review-Workspace.md` §11, §12, §25, §26.6, ADR-E2/E6  
**Target files (sketch):**
- `Sources/VaniScriptCore/DocumentFindReplaceEngine.swift` (new)
- `Sources/VaniScript/Stores/WorkflowStore.swift`
- `Sources/VaniScript/Views/ReviewWorkspaceView.swift`
- new tests under `Tests/`

**Do:**
- [x] [S16.D1] `DocumentFindReplaceEngine` searches `DocumentState.blocks` / `translationsByLanguage` (never aggregate `ChunkData` strings) with `DocumentTextMatch` + `DocumentSearchScope` (current source document, current translation language)
- [x] [S16.D2] Unicode-aware whole-word matching reuses the `GlossaryTextRewriter` `(?<![\p{L}\p{N}_])…(?![\p{L}\p{N}_])` boundary; case-sensitivity toggle; regex compiled once per operation
- [x] [S16.D3] Preview sheet: find/replace fields, scope label, whole word / case sensitive / skip protected / save-as-glossary options, found + skipped counts
- [x] [S16.D4] Matches applied back-to-front inside each block; replacement inherits the host span style; mixed-style matches never silently flatten; protected spans skipped and counted
- [x] [S16.D5] Replace All = one multi-block transaction, one Undo, one project save; 0 matches is a no-op
- [x] [S16.D6] Source-side replace recomputes hashes and stales touched translations without deleting them; translation-side replace keeps `sourceHash`, marks touched approved blocks `manuallyApproved`, leaves pending blocks pending
- [x] [S16.D7] Optional glossary entry created only when the checkbox is set and the source term is unambiguous; otherwise offer `Open Glossary…`
- [x] [S16.D8] Replace Everywhere tests per PRD §26.6

**Out of scope:**
- cross-document or all-languages scopes, AI selection, media `globalSearchAndReplace` changes

## Verification

### Objective gates

- [x] [S16.O1] `swift build` exits 0
- [x] [S16.O2] focused document find/replace tests pass
- [x] [S16.O3] `swift test` exits 0

### Judgment gates

- [x] [S16.J1] media search/replace path unchanged
- [x] [S16.J2] no partial-failure mode: plan fully, then apply atomically
- [x] [S16.J3] rich formatting and protected spans survive mass replacement

**Ready for review when:** implementation is complete in scope and required Objective gates are green.

**Stop-gate:** Reviewer APPROVED + Tester qa_green.

---

## S17 — Editorial workspace: AI selected retranslation — test hardening

**Goal:** Harden the already-shipped slice E4 (Retranslate Selection with AI, delivered in S14 by ADR-003) with a new deterministic test battery covering the validator, strict wire-contract decoding, and engine edge gates. No product-code changes (PRD §10, §26.5).  
**Depends on:** S16  
**Scope note:** the Human confirmed on 2026-08-16 that E4 works and must not be rebuilt; S17 is re-scoped by ADR-006 from feature work to test hardening of the existing implementation.
**Source of truth:** `docs/PRD-Editorial-Review-Workspace.md` §10, §26.5; ADR-003, ADR-006  
**Target files:**
- `Tests/VaniScriptCoreTests/DocumentSelectionTranslationValidatorTests.swift` (new)
- `Tests/VaniScriptTests/DocumentSelectionTranslationEngineTests.swift` (extend)

**Do:**
- [x] [S17.D1] Validator error paths: `emptyReplacement` (empty + whitespace-only), `unicodeNFC` (decomposed input), `markdownFence`, `modelExplanation` (EN + RU wrapper prefixes)
- [x] [S17.D2] Validator warning paths: `lengthRatio` (< 0.1 and > 4.0, in-range silent), `surroundingTarget`; protected-token normalization (case/diacritic-insensitive) passes, tokens absent from selection and source context are ignored
- [x] [S17.D3] `validateJSON`: malformed JSON and unexpected fields → `invalidJSON` error; valid strict JSON proceeds to field validation
- [x] [S17.D4] Request strict decoding: missing required field → `missingField`, unexpected field → `unexpectedField`; camelCase wire keys (`operationId`, `sourceBlockId`) round-trip
- [x] [S17.D5] Engine pre-provider gates: `missingTargetHash`, `selectionChanged` (snapshot ≠ live text) without invoking the provider
- [x] [S17.D6] Engine stale gates: formatting-only change while AI runs → `staleResponse`; `currentTargetBlock` nil after provider → `missingTargetBlock`
- [x] [S17.D7] Engine response gates: non-JSON provider output → `invalidResponse`; `CancellationError` propagates unwrapped; validation warnings surface in `outcome.warningCodes` without blocking application
- [x] [S17.D8] Outcome contract: `replacementUTF16Length` counts UTF-16 units (surrogate pairs)
- [x] [S17.D9] Request context bounds: `targetPrefix`/`targetSuffix` content, 120-unit cap, empty at block edges
- [x] [S17.D10] Request enrichment: glossary per-language lookup + 64-entry cap; protected tokens from protect-policy spans deduplicated; `sourceBlockHash` fallback for empty hash; spanless target block synthesizes a selection span
- [x] [S17.D11] Multi-fragment same-style selection across two spans applies one replacement through the full `execute` path; `isEligible` positive case
- [x] [S17.D12] Prompt rendering carries the schema constant, the operation ID, and the no-markdown instruction

**Out of scope:**
- product-code changes (any bug found is reported to Main, not fixed in this step)
- source-pane `Translate Selection`, polish commands, new provider UI

## Verification

### Objective gates

- [x] [S17.O1] `swift build` exits 0
- [x] [S17.O2] new focused validator/contract/engine suites pass without network access
- [x] [S17.O3] `swift test` exits 0 (baseline 775 tests / 101 suites plus the new tests)

### Judgment gates

- [x] [S17.J1] every new test defends observable contract behavior, not plumbing or source text
- [x] [S17.J2] no existing test is weakened, deleted, or duplicated
- [x] [S17.J3] all new tests are deterministic and isolated (injected providers, no disk, no network)

**Ready for review when:** all new tests are green and the full suite is green.

**Stop-gate:** Human ACCEPTED + Reviewer APPROVED + Tester qa_green.

---

## S18 — Editorial workspace: export fidelity

**Goal:** DOCX and PDF export reflect editor formatting, including explicit removal of inherited traits; plain formats stay honestly plain (PRD slice E5).  
**Depends on:** S17  
**Source of truth:** `docs/PRD-Editorial-Review-Workspace.md` §16, §26.7, ADR-E8  
**Target files (sketch):**
- `Sources/VaniScript/Services/DocumentExportWriters.swift`
- `Sources/VaniScriptCore/DocumentModels.swift`
- new/extended tests under `Tests/`

**Do:**
- [x] [S18.D1] `EditorRunPropertyOverlay` over trusted source `w:rPr`: bold, italic, underline, strikethrough, superscript/subscript `w:vertAlign`, small caps, `w:color`
- [x] [S18.D2] Explicit trait removal writes `w:… w:val="0"` so user-disabled inherited formatting survives export
- [x] [S18.D3] PDF writer renders superscript, subscript, small caps, and mixed runs after user edits
- [x] [S18.D4] TXT/Markdown export contracts unchanged
- [x] [S18.D5] OOXML overlay tests per PRD §26.7, including unchanged unrelated package entries

**Out of scope:**
- font family/size overrides, paragraph layout, semantic Markdown export

## Verification

### Objective gates

- [x] [S18.O1] `swift build` exits 0
- [x] [S18.O2] focused DOCX overlay and PDF trait tests pass
- [x] [S18.O3] `swift test` exits 0

### Judgment gates

- [x] [S18.J1] round-trip preserves imported formatting plus editor overrides
- [x] [S18.J2] no formatting is visual-only: what the editor shows, export writes

**Ready for review when:** implementation is complete in scope and required Objective gates are green.

**Stop-gate:** Reviewer APPROVED + Tester qa_green. **CLOSED 2026-08-17** (Human ACCEPTED + Reviewer APPROVED + Tester qa_green 837/106).

---

## S19 — Editorial workspace: hardening and destructive QA

**Goal:** Prove the editorial workspace under abusive workloads and confirm zero media regression (PRD slice E6).  
**Depends on:** S18  
**Source of truth:** `docs/PRD-Editorial-Review-Workspace.md` §25, §26.8, §29  
**Target files (sketch):**
- applicable `Tests/` and `QA/` paths
- performance-sensitive sources identified by the run

**Do:**
- [ ] [S19.D1] Long-manuscript (tens of thousands of words) Replace Everywhere stays cheap: one regex compile, one pass, back-to-front application, one normalization, one save
- [ ] [S19.D2] Typing path serializes only touched blocks, never all paragraphs per keystroke
- [ ] [S19.D3] Rapid typing during an in-flight AI request cannot be overwritten by the response
- [ ] [S19.D4] Repeated Undo/Redo, save/reopen, multi-language archives, protected Sanskrit spans, hundreds of replacements
- [ ] [S19.D5] End-to-end editor sequence per PRD §26.8 (open DOCX → edit → format → replace → AI → undo/redo → reopen → export → verify runs)
- [ ] [S19.D6] Old media projects open unchanged; full media regression (WhisperKit, cloud transcription, local MLX translation)
- [ ] [S19.D7] Full suite and QA green

**Out of scope:**
- new features beyond E1–E5

## Verification

### Objective gates

- [ ] [S19.O1] `swift build`, `swift test`, and applicable QA suite exit 0
- [ ] [S19.O2] end-to-end editor sequence passes on a real DOCX fixture
- [ ] [S19.O3] media regression suite passes

### Judgment gates

- [ ] [S19.J1] Definition of Done §29 satisfied end to end
- [ ] [S19.J2] no performance cliff on book-scale documents

**Ready for review when:** automated gates and available smokes are complete.

**Stop-gate:** Reviewer APPROVED + Tester qa_green; unavailable external assets remain explicit blockers, not fabricated success.

---

## S20 — Refresh Source on existing document projects

**Goal:** Let the user replace the source file of an existing document project (path/name may change), keep translations whose block text still matches, refresh source formatting/colors from the new file, and offer retranslation only for changed material (ADR-007).
**Depends on:** S15 freshness contracts (PRD §9), document import pipeline
**Source of truth:** `AI_Workflow_Kit/docs/DECISIONS.md` ADR-007; `docs/PRD-Editorial-Review-Workspace.md` §9 freshness; existing `DocumentImportService` / `TranslationFreshness`
**Target files (sketch):**
- `Sources/VaniScriptCore/DocumentSourceRefresh.swift` (new pure merge helper) or equivalent under Core
- `Sources/VaniScript/Stores/WorkflowStore.swift` (picker + apply + summary + retranslate-changed entry)
- `Sources/VaniScript/Views/ProjectSidebarView.swift` and/or Review document chrome (Refresh Source action)
- `Sources/VaniScript/Services/DocumentImportService.swift` only if a project-directory refresh overload is required
- new/extended tests under `Tests/`

**Do:**
- [x] [S20.D1] `DocumentSourceRefresh.merge(old:new:)` pure function:
  - text identity = SHA-256(NFC joined span text)
  - matched blocks reuse old block IDs; source spans/colors/style/sourceHash come from new import
  - kept translations (all languages) re-point `sourceHash` to the new block hash when text matched
  - unmatched new blocks keep new IDs with no translation
  - unmatched old translations dropped
  - rebuild `DocumentChunkPlan`s and return counts: matched, added, removed, staleChunkIndices
- [x] [S20.D2] WorkflowStore: file picker → import into existing project source dir → merge → persist project → status/summary
- [x] [S20.D3] UI: **Refresh Source…** on document project row and/or open document session
- [x] [S20.D4] After success: summary sheet/banner with matched/added/removed + **Retranslate N changed chunks** (only stale/changed indices; uses existing document translation intents)
- [x] [S20.D5] Formatting-only source upgrade (same text, new colors) does **not** force retranslate
- [x] [S20.D6] Text change marks affected chunks `needsReview` and leaves prior translation only where text still matches
- [x] [S20.D7] Deterministic tests: identical text keeps translation + new colors; text edit stales/retranslate offer; path/name change OK; media project rejected; empty/cancelled picker no-ops

**Out of scope:**
- media source refresh
- automatic full-book retranslate without user confirmation
- fuzzy/semantic matching beyond exact text-hash identity
- OCR / scanned PDF improvements

## Verification

### Objective gates

- [x] [S20.O1] `swift build` exits 0
- [x] [S20.O2] focused Refresh Source unit + store tests pass
- [x] [S20.O3] `swift test` exits 0
- [x] [S20.O4] fresh-app smoke: open old project → Refresh Source to colored DOCX → matching chunks keep translation and show new red placeholders; changed chunks offered for retranslate

### Judgment gates

- [ ] [S20.J1] no silent data loss of still-matching translations
- [ ] [S20.J2] freshness derivation stays canonical (hash-based); no second parallel stale system
- [ ] [S20.J3] provider is never invoked during refresh itself

**Ready for review when:** implementation is complete in scope and Objective gates are green.

**Stop-gate:** Human ACCEPTED + Reviewer APPROVED + Tester qa_green.

---

## S21 — In-app update release identity and packaging

**Goal:** Make direct-distribution release artifacts versioned, signed, notarized, and Sparkle-ready without ad-hoc production fallbacks or machine-specific asset selection.
**Depends on:** S20 baseline; user-approved VaniScript in-app update architecture (2026-08-18)
**Source of truth:** User-provided `VANISCRIPT_IN_APP_UPDATE_ARCHITECTURE.md`, §§3, 10–13, 18, 20–24
**Target files (sketch):**
- `Package.swift`
- `Package.resolved`
- `script/build_release_dmg.sh`
- `Sources/VaniScript/Services/AppBuildIdentity.swift`
- `Tests/VaniScriptCoreTests/AppStoreNativeComplianceTests.swift`
- focused release/build tests as needed

**Do:**
- [x] [S21.D1] Parameterize semantic version and strictly numeric build number in release packaging and expose both through `AppBuildIdentity`.
- [x] [S21.D2] Make production signing, notarization, stapling, architecture, bundle identity, and minimum OS checks fail closed; keep ad-hoc signing only for debug packaging.
- [x] [S21.D3] Pin Sparkle 2 and make the custom SwiftPM app bundle embed its framework/runtime search path safely.
- [x] [S21.D4] Produce a signed update ZIP alongside the first-install DMG with deterministic manifests/checksums and no absolute user-cache dependencies.

**Out of scope:**
- publishing credentials or private keys into the repository
- changing the Electron or sibling projects
- Mac App Store updater support

## Verification

### Objective gates

- [x] [S21.O1] focused release-script/source compliance tests pass
- [x] [S21.O2] `swift build` exits 0
- [x] [S21.O3] release script rejects missing production prerequisites before packaging

### Judgment gates

- [x] [S21.J1] no production path can silently emit an ad-hoc or non-notarized artifact
- [x] [S21.J2] update archives contain one self-contained arm64 app with stable identity and no user-specific absolute paths

**Ready for review when:** implementation is complete in scope and Objective gates are green.

**Stop-gate:** Human ACCEPTED + Reviewer APPROVED + Tester qa_green.

---

## S22 — Sparkle update service and visible update UX

**Goal:** Let VaniScript discover signed updates in the background and start installation only from an explicit user action in the app.
**Depends on:** S21
**Source of truth:** User-provided `VANISCRIPT_IN_APP_UPDATE_ARCHITECTURE.md`, §§4–7, 10, 18, 20, 22
**Target files (sketch):**
- `Sources/VaniScript/Updates/`
- `Sources/VaniScript/App/VaniScriptApp.swift`
- `Sources/VaniScript/Views/ContentView.swift`
- `Sources/VaniScript/Views/SettingsView.swift`
- `Sources/VaniScript/Models/SettingsTab.swift`
- `Tests/VaniScriptTests/UpdateCoordinatorTests.swift`
- `Tests/VaniScriptTests/UpdateUserDriverTests.swift`

**Do:**
- [x] [S22.D1] Add a pinned Sparkle-backed service, update descriptor/phase model, custom user driver, and diagnostic error mapping.
- [x] [S22.D2] Start scheduled background checks without automatic installation and expose a manual Check for Updates command.
- [x] [S22.D3] Add the versioned update button, progress/retry states, reduced-motion behavior, accessibility, and Settings → Updates.

## Verification

### Objective gates

- [x] [S22.O1] focused update model/service/driver tests pass without network access
- [x] [S22.O2] `swift build` exits 0
- [x] [S22.O3] a fresh app exposes the update command/button without auto-installing

### Judgment gates

- [x] [S22.J1] discovery never installs without the explicit user action.
- [x] [S22.J2] Sparkle remains the only executable-code installer; no curl/unzip/sudo replacement path exists

**Ready for review when:** implementation is complete in scope and Objective gates are green.

**Stop-gate:** Human ACCEPTED + Reviewer APPROVED + Tester qa_green.

---

## S23 — Update readiness and safe termination

**Goal:** Gate installation on durable project/settings state and active-operation safety, then allow Sparkle to terminate and relaunch the app through AppKit’s asynchronous lifecycle.
**Depends on:** S22
**Source of truth:** User-provided `VANISCRIPT_IN_APP_UPDATE_ARCHITECTURE.md`, §§6–7, 13, 15, 18, 20
**Target files (sketch):**
- `Sources/VaniScript/Updates/UpdateReadinessProviding.swift`
- `Sources/VaniScript/Updates/UpdateTerminationCoordinator.swift`
- `Sources/VaniScript/Updates/UpdateReceiptStore.swift`
- `Sources/VaniScript/Updates/UpdateCoordinator.swift`
- `Sources/VaniScript/Updates/UpdateUserDriver.swift`
- `Sources/VaniScript/Stores/WorkflowStore+UpdateReadiness.swift`
- `Sources/VaniScript/Stores/WorkflowStore.swift`
- `Sources/VaniScript/App/VaniScriptApp.swift`
- `Sources/VaniScript/Services/AppStoragePaths.swift`
- `Tests/VaniScriptTests/UpdateReadinessTests.swift`
- `Tests/VaniScriptTests/UpdateTerminationTests.swift`

**Do:**
- [x] [S23.D1] Expose explicit dirty-state/revision and active-operation readiness through a narrow WorkflowStore contract.
- [x] [S23.D2] Save all pending state, create metadata backup, freeze editing, and re-check readiness before Sparkle termination.
- [x] [S23.D3] Persist update receipt/health state and show a post-relaunch success message without touching recordings/models.

## Verification

### Objective gates

- [x] [S23.O1] focused readiness/save/termination/receipt tests pass
- [x] [S23.O2] `swift build` exits 0
- [x] [S23.O3] save failure, active recording, and retry paths keep the app open

### Judgment gates

- [x] [S23.J1] no update path can discard unsaved user work or interrupt active operations silently
- [x] [S23.J2] the updater never writes executable code or mutates TCC permissions

**Ready for review when:** implementation is complete in scope and Objective gates are green.

**Stop-gate:** Human ACCEPTED + Reviewer APPROVED + Tester qa_green.

---

## S24 — Public release channel and update qualification

**Goal:** Publish signed artifacts and appcast in a protected, auditable order and qualify upgrade, tamper, downgrade, and clean-machine behavior.
**Depends on:** S21–S23
**Source of truth:** User-provided `VANISCRIPT_IN_APP_UPDATE_ARCHITECTURE.md`, §§4, 12, 14, 15, 17–20
**Target files (sketch):**
- `.github/workflows/release.yml`
- `script/verify_release_artifacts.sh`
- `Tests/VaniScriptCoreTests/UpdateQualificationTests.swift`
- release/runbook files only where explicitly required by the workflow

**Do:**
- [x] [S24.D1] Add protected-tag/manual release workflow with version/build monotonicity, QA, signing, notarization, stapling, and Sparkle appcast generation.
- [x] [S24.D2] Publish ZIP/DMG/notes/checksums to the artifact-only release channel without embedding credentials and publish appcast last.
- [x] [S24.D3] Add deterministic feed/archive qualification for valid, tampered, wrong-team, unsigned, downgrade, interrupted, and unsupported updates.

## Verification

### Objective gates

- [x] [S24.O1] release workflow and artifact verification checks pass in a configured release environment
- [x] [S24.O2] focused update qualification tests pass without network credentials
- [ ] [S24.O3] previous-production → candidate update smoke evidence is recorded — deferred to the next release because v3.0.0 is the first public production baseline

### Judgment gates

- [x] [S24.J1] release is fail-closed at every trust boundary and appcast is published only after verified assets
- [x] [S24.J2] rollback uses a higher build number and never silently downgrades clients

**Ready for review when:** implementation is complete in scope and Objective gates are green.

**Stop-gate:** Human ACCEPTED + Reviewer APPROVED + Tester qa_green.

---

## S25 — Batch canonical media naming

**Goal:** Establish a pure, round-trippable batch filename domain before any queue or watcher exists.  
**Depends on:** S24; ADR-009  
**Source of truth:** `docs/BATCH_TRANSCRIPTION_ARCHITECTURE_PLAN.md` §§4–5, 25 PR 1, 26.1, 28–30  
**Target files (sketch):**
- `Sources/VaniScriptCore/Batch/CanonicalMediaName.swift`
- `Sources/VaniScriptCore/Batch/MediaNamingConvention.swift`
- `Tests/VaniScriptCoreTests/BatchMediaNamingTests.swift`

**Do:**
- [x] [S25.D1] Implement canonical DATE/WHO/WHAT/WHERE/COUNTRY parsing, validation, rendering, and exact-stem companion URLs.
- [x] [S25.D2] Report typed violations/warnings, legacy compatibility, and case-insensitive output collisions without semantic guessing.
- [x] [S25.D3] Add deterministic boundary and parse-render round-trip tests from the architecture fixture matrix.

**Out of scope:** timed text, filesystem writes, ASR, queue, watcher, UI, or changes to manual export naming.

## Verification

### Objective gates
- [x] [S25.O1] `swift test --filter BatchMediaNamingTests` exits 0
- [x] [S25.O2] canonical parse → render preserves the original stem and companion URL changes only the extension

### Judgment gates
- [x] [S25.J1] parser behavior exactly matches ADR-009 and never delegates authority to heuristic metadata extraction
- [x] [S25.J2] the API remains pure `VaniScriptCore` with no filesystem watcher/runtime abstraction

**Stop-gate:** Human ACCEPTED + Reviewer APPROVED + Tester qa_green.

---

## S26 — Batch timed TXT and atomic companion writer

**Goal:** Safely render validated absolute cues and atomically commit exact-stem TXT without overwriting user work.  
**Depends on:** S25  
**Source of truth:** batch architecture §§15, 17–19, 25 PR 2, 26.4  
**Target files (sketch):**
- `Sources/VaniScriptCore/Batch/BatchTimedTextRenderer.swift`
- `Sources/VaniScriptCore/Batch/BatchOutputModels.swift`
- `Sources/VaniScript/Services/AtomicCompanionWriter.swift`
- focused Core/app tests

**Do:**
- [x] [S26.D1] Validate finite monotonic in-duration cues and render deterministic timed TXT.
- [x] [S26.D2] Commit via same-directory temporary file, fsync/close, and atomic rename with output SHA-256.
- [x] [S26.D3] Enforce replaceGeneratedOnly, source recheck, collision, permission, and crash-temp cleanup behavior.

**Out of scope:** ASR execution, queue, watcher, bookmarks, or UI.

## Verification
### Objective gates
- [x] [S26.O1] focused renderer/writer tests pass
- [x] [S26.O2] final TXT is never observable partially and unknown/modified TXT is preserved
### Judgment gates
- [x] [S26.J1] exact-stem and user-edit safety are fail-closed

**Stop-gate:** Human ACCEPTED + Reviewer APPROVED + Tester qa_green.

---

## S27 — Shared ASR-only file transcription runtime

**Goal:** Transcribe one file programmatically with absolute timed cues, no translation/UI mutation, and one scheduler/router shared with manual work.  
**Depends on:** S26  
**Source of truth:** batch architecture §§3, 8, 9.4, 14–16, 25 PR 3, 26.5  
**Target files (sketch):**
- `Package.swift`
- `Sources/VaniScriptRuntime/Transcription/**`
- existing local-ASR router/preprocessor/chunk services
**Do:**
- [x] [S27.D1] Add the physical `VaniScriptRuntime` target and move shared ASR runtime behind bounded contracts.
- [x] [S27.D2] Implement FileTranscriptionService with chunk ownership, checkpoints, cleanup, and exactly-once absolute timing offsets.
- [x] [S27.D3] Route manual and batch requests through one scheduler with manual priority and no provider fallback.

**Out of scope:** durable queue, watched folders, or batch UI.

## Verification
- [x] [S27.O1] focused ASR-only/scheduler/manual-regression tests pass
- [x] [S27.O2] batch path never invokes translation and local ASR concurrency is one
### Judgment gates
- [x] [S27.J1] target boundaries and scheduler ownership prevent duplicate resident engines

**Stop-gate:** Human ACCEPTED + Reviewer APPROVED + Tester qa_green.

---

## S28 — Durable one-shot batch queue

**Goal:** Process a chosen folder end-to-end through a crash-recoverable SQLite job state machine.  
**Depends on:** S27  
**Source of truth:** batch architecture §§9.2–13, 19, 23, 25 PR 4, 26.2, 26.6  

**Do:**
- [x] [S28.D1] Add BatchJob models, typed transitions, SQLite repository, indexes, generations, and chunk checkpoints.
- [x] [S28.D2] Implement one-shot reconciliation, deduplication, retry/cancel, recovery, and per-file failure isolation.
- [x] [S28.D3] Complete Choose Folder → Scan Once → Process → atomic companion TXT without ProjectRecord creation.
**Out of scope:** continuous FSEvents, persisted security bookmarks, or polished UI.

## Verification
- [x] [S28.O1] state-machine/repository/recovery and end-to-end fixture tests pass
- [x] [S28.J1] queue transitions are durable, idempotent, and never identify work only by absolute path

**Stop-gate:** Human ACCEPTED + Reviewer APPROVED + Tester qa_green.

---

## S29 — Watched folders and file stability

**Goal:** Automatically reconcile stable audio files from persisted security-scoped folder profiles.  
**Depends on:** S28  
**Source of truth:** batch architecture §§12–13, 20, 22, 25 PR 5, 26.3  

**Do:**
- [x] [S29.D1] Persist and restore security-scoped bookmarks with explicit stale/revoked states.
- [x] [S29.D2] Use FSEvents only as a reconciliation signal; add startup scan, recursive policy, filtering, and symlink exclusion.
- [x] [S29.D3] Require two stable probes plus readable audio metadata before enqueueing.

**Out of scope:** background login agent or XPC ownership.

## Verification
### Objective gates
- [x] [S29.O1] watcher/stability/bookmark tests cover partial copy, rename, duplicate events, startup recovery, recursion, symlinks, and temp files
### Judgment gates
- [x] [S29.J1] no event path bypasses reconciliation, stability, naming, or security-scope gates

**Stop-gate:** Human ACCEPTED + Reviewer APPROVED + Tester qa_green.

---

## S30 — Batch workspace and production hardening

**Goal:** Ship an app-resident batch workspace with observable queue control, safe defaults, and manual-workflow priority.  
**Depends on:** S29  
**Source of truth:** batch architecture §§21–23, 25 PR 6, 27–28  

**Do:**
- [x] [S30.D1] Add BatchTranscriptionStore/workspace, folder profiles, job details, retry/cancel, and notifications.
- [x] [S30.D2] Compose the app-level runtime outside views and expose exact provider, naming, conflict, and recovery states.
- [x] [S30.D3] Harden privacy-safe logging, budgets, cleanup, manual priority, and manual Upload/Review/Export regressions.
- [x] [S30.D4] Accept Human archive `DATE_WHO-WHAT_WHERE_cc` names with exact-stem TXT, and show each naming/conflict issue with a reason instead of a count-only badge.
- [x] [S30.D5] Route batch through the same cloud/local transcription path as manual work, show live per-file progress and lastError, and delete a profile's jobs on Remove.
- [x] [S30.D6] Show frozen elapsed processing time and chunk N of M on every job; keep the real provider error; stop Retry from incrementing past the automatic cap and overwriting lastError.
- [x] [S30.D7] Scan/add-folder only queues files; Start begins transcription; Remove is disabled while processing; the detail pane follows the active job; double-click opens the companion TXT.
- [x] [S30.D8] Add a default-on canonical-name toggle (off accepts any audio with exact-stem TXT), a Batch transcription provider/model picker, and two-way sync with Settings plus Review editing provider.
- [x] [S30.D9] Port BOLABOL-style starred favorites into Settings model picker; Batch/Review pickers show those favorites; drop stub WhisperKit Core ML and MLX Swift Local rows; separate cloud vs local; Settings Cloud Provider follows the active translation provider; canonical-name toggle shows the DATE_WHO_WHAT_WHERE_cc formula.

**Out of scope:** login item/background agent; that remains an optional future train.

## Verification
### Objective gates
- [x] [S30.O1] focused integration tests and the architecture end-to-end folder fixture pass
- [x] [S30.O2] fresh-app manual acceptance proves automatic exact-stem output, restart recovery, and preserved manual workflow
### Judgment gates
- [x] [S30.J1] all 17 architecture acceptance criteria are satisfied without hidden provider fallback or user-file overwrite

**Stop-gate:** Human ACCEPTED + Reviewer APPROVED + Tester qa_green.

---

## S31 — Batch workspace interaction and visual redesign

**Goal:** Redesign the Batch Workspace from the Human's two annotated
screenshots into a coherent native macOS utility surface. Remove duplicate scan
affordance, make naming-policy feedback honest, and give empty, populated,
issue, folder, and job states one clear hierarchy.
**Depends on:** S30
**Source of truth:** Human screenshot feedback recorded in
`AI_Workflow_Kit/docs/AI/FEEDBACK.md`; ADR-009; ADR-010
**Target files:**
- `Sources/VaniScript/BatchUI/BatchWorkspaceView.swift`
- `Sources/VaniScript/BatchUI/BatchFolderProfileView.swift`
- `Sources/VaniScript/BatchUI/BatchJobRowView.swift`
- `Sources/VaniScript/BatchUI/BatchJobDetailsView.swift`
- `Sources/VaniScript/BatchUI/BatchTranscriptionStore.swift`
- `Sources/VaniScriptCore/Batch/BatchTranscriptionModels.swift`
- `Sources/VaniScriptCore/Batch/BatchJobStateMachine.swift`
- `Sources/VaniScriptCore/Batch/BatchOutputModels.swift`
- `Tests/VaniScriptTests/BatchWorkspaceIntegrationTests.swift`
- `Sources/VaniScriptRuntime/Batch/WatchedFolderService.swift`
- `Tests/VaniScriptTests/WatchedFolderServiceTests.swift`
- `Sources/VaniScriptRuntime/Batch/FileStabilityProbe.swift`
- `Sources/VaniScriptRuntime/Batch/FolderReconciler.swift`
- `Sources/VaniScriptRuntime/Batch/SQLiteBatchJobRepository.swift`
- `Sources/VaniScript/Services/NativeProcessingPipeline.swift`
- `Sources/VaniScript/Services/LocalASREngine.swift`
- `Sources/VaniScript/Services/LocalASREngineRouter.swift`
- `Sources/VaniScriptRuntime/Transcription/AudioChunkProcessingService.swift`
- `Sources/VaniScriptRuntime/Transcription/FileTranscriptionService.swift`
- `Tests/VaniScriptTests/FileStabilityProbeTests.swift`
- `Tests/VaniScriptTests/SQLiteBatchJobRepositoryTests.swift`
- `Tests/VaniScriptTests/NativeProcessingPipelineASRTests.swift`
- `Tests/VaniScriptTests/LocalASREngineRouterTests.swift`
- `Tests/VaniScriptTests/FileTranscriptionServiceTests.swift`
- `Sources/VaniScriptRuntime/Batch/BatchTranscriptionCoordinator.swift`
- `Sources/VaniScript/App/VaniScriptApp.swift`
- `Tests/VaniScriptTests/BatchTranscriptionCoordinatorTests.swift`
- `Tests/VaniScriptTests/BatchArchitectureAcceptanceTests.swift`
- `Tests/VaniScriptCoreTests/NativeProcessingReadinessTests.swift`

**Do:**
- [x] [S31.D1] Remove `Scan Now`; make Start/Stop the single primary execution affordance without changing queue/runtime contracts
- [x] [S31.D2] Present canonical-name policy and rejected-file issues honestly; disabling the policy must not continue to present naming-only rejections as current
- [x] [S31.D3] Redesign the no-folder and no-job states with a clear next action, balanced split-view composition, and no duplicated empty messages
- [x] [S31.D4] Redesign populated controls, issues/jobs list, folder inspector, and job detail hierarchy for readable professional density
- [x] [S31.D5] Preserve native macOS behavior, dark/light appearance, VoiceOver labels, keyboard focus, narrow/wide reflow, provider/model selection, and Start/Stop semantics
- [x] [S31.D6] Prevent Start or a late watcher reconciliation from republishing filename-validation issues after the live canonical-name policy is OFF; the setting must remain OFF and supported arbitrary filenames must stay queued
- [x] [S31.D7] Admit a folder's candidate files after one shared stability observation interval instead of one full delay per file; preserve readability, fingerprint, symlink, recursion, and partial-copy gates
- [x] [S31.D8] On Start after provider/model change, supersede obsolete pending jobs safely and enqueue/process the same files with the currently selected provider/model; preserve failed history, retry caps, output safety, and ASR concurrency one
- [x] [S31.D9] Plan Batch file transcription through the same `SmartAudioAnalyzer` silence-aware chunking path and settings as manual processing, with the existing fixed-duration fallback
- [x] [S31.D10] Use automatic source-language detection for Batch and block Start for models without auto-detect (including Canary Flash/1B) with an actionable Whisper/Parakeet/cloud warning; never silently assume English or fallback
- [x] [S31.D11] Keep the Canary/explicit-language readiness warning visible without expanding or translating the Batch NavigationSplitView outside its viewport
- [x] [S31.D12] Recover interrupted `.processing` rows to pending before Auto Detect readiness can block new Batch work; a blocked Canary selection must never display phantom processing
- [x] [S31.D13] Serialize ASR invalidation/unload behind the shared transcription scheduler so provider changes cannot tear down WhisperKit during an active Batch decode
- [x] [S31.D14] Activate watched folders and claim existing current-configuration pending work without waiting for full-folder stability/readability reconciliation; reconciliation continues safely and newly admitted jobs are processed
- [ ] [S31.D15] Forward local-ASR per-chunk progress and total-chunk count through the batch progress/checkpoint path so the UI reports honest progress instead of permanent 0%
- [ ] [S31.D16] Replace the 1% alive placeholder with truthful persisted Batch phases and real WhisperKit sub-chunk audio coverage; show planning/model-load/audio-conversion/inference/finalizing state in row, detail, and workspace status, and route existing-output safety failures to actionable output-conflict state instead of generic Failed
- [x] [S31.D22] Move live time/chunk/percentage into each job row; add shared Chunk Duration, Silence Threshold, and Minimum Silence controls to Batch configuration without Slice Mode; style Start green/play and Stop red/stop while preserving disabled semantics
- [x] [S31.D23] Normalize malformed cloud cue timelines per planned chunk and repair already persisted completed checkpoints during resume so all transcribed text reaches atomic companion writing without duplicate provider inference

**Out of scope:** background/login agent, parallel ASR, automatic provider
fallback, Batch translation, unrelated screens, new dependencies, or duplicated
silence/language logic. A bounded additive SQLite migration for persisted
progress phase/detail is in scope for S31.D16.
## Verification

### Objective gates
- [x] [S31.O1] `swift build` exits 0
- [ ] [S31.O2] fresh app is inspected in no-folder, no-job, naming-issues, queued/processing, completed/error, and blocked-readiness states at narrow and wide window sizes
- [x] [S31.O3] focused toggle-off scan regression proves naming-only issues clear and a supported arbitrary-name file queues
- [x] [S31.O4] fresh-app OFF → Start → settle keeps the toggle OFF, shows no invalid-name issues, and retains queued arbitrary filenames
- [x] [S31.O5] deterministic gates prove one shared stability delay for many files, cloud-failed/pending work continues under the selected local configuration, and a silence fixture yields multiple Batch checkpoints
- [x] [S31.O6] deterministic capability gates prove Auto reaches compatible cloud/local routes and Canary Batch is blocked before queue mutation or provider invocation
- [x] [S31.O7] fresh packaged app with Canary selected renders all three Batch columns, actionable warning, disabled Start, provider/toggle controls, folders/jobs, and detail content inside the visible sheet
- [x] [S31.O8] deterministic and fresh-app crash-recovery gates prove Canary performs zero watch/claim/provider calls while interrupted rows become pending with honest recovery state
- [x] [S31.O9] deterministic concurrency gate proves provider-change invalidation waits for active Batch local ASR, unloads only after inference exits, and permits the next selected binding without overlap or process trap
- [x] [S31.O10] deterministic startup gate proves an existing current pending job reaches processing before a blocked folder reconciliation completes, while newly reconciled jobs are still processed afterward
- [x] [S31.O11] deterministic WhisperKit callback gate proves planning/load/conversion phases are visible and segment timestamps advance persisted progress within one long outer chunk before completion
- [x] [S31.O12] packaged-app runtime proves callback bridge lifetime keeps stable-height rows live: while the third real file was still processing, the first two fixed rows already showed Completed with green-check semantics
- [x] [S31.O13] companion replacement gate and Human runtime evidence prove an existing same-stem `.txt` companion is atomically overwritten without a collision stop or duplicate manual cleanup
- [ ] [S31.O14] fresh packaged app with several real local-ASR files visibly moves one compact spinner from the active row to the next, leaves green completed checkmarks behind, writes companions, and returns the primary action to Start without resizing the sheet
- [x] [S31.O15] fresh packaged Batch sheet shows row-owned live progress, edits the same three persisted chunking settings as Settings, keeps configuration order readable, and renders unmistakable green Start/red Stop states without geometry regressions
- [x] [S31.O16] focused regression proves oversized/equal/outlier cloud timestamps become bounded monotonic cues without losing or reordering transcript text
- [x] [S31.O17] all-11-checkpoint resume repairs persisted malformed cues, writes the complete companion, and performs zero cloud transcription calls
- [x] [S31.O18] Tester inventories observable Batch contracts across profiles, reconciliation, repository/state machine, coordinator/resume, cloud/local routing, timed-text recovery, atomic companions, store/UI publication, readiness, cancellation, and sequential queue behavior
- [x] [S31.O19] focused deterministic tests close every material uncovered Batch contract gap without network calls, real model weights, source-text assertions, or duplicating existing coverage
- [x] [S31.O20] complete Batch-focused test inventory passes together and the exact suite/count/evidence is recorded before release packaging

### Judgment gates
- [x] [S31.J1] Human visually and operationally accepts Candidate 10
- [x] [S31.J2] Reviewer confirms the app-level callback bridge survives `makeBatchStore`, fixes the packaged stale-spinner path, and corresponds to the Human-requested live sequential file-state presentation without test-only bridge retention
- [x] [S31.J3] Reviewer confirms the candidate matches every Candidate 8 screenshot request and preserves the accepted sequential callback/runtime behavior
- [x] [S31.J4] Reviewer confirms long-file recovery is text-lossless, avoids duplicate inference, retains strict non-timeline validation, and preserves atomic output safety

**Ready for release qualification when:** Main verifies the final diff, build,
complete Batch-focused QA, and fresh app; Reviewer approves and Tester returns
`qa_green`.

**Stop-gate:** Human ACCEPTED + Reviewer APPROVED + Tester qa_green.

---

## S32 — VaniScript 3.1.0 Batch release and first Sparkle upgrade

**Goal:** Ship the Human-accepted Batch module as VaniScript 3.1.0 through the
existing signed/notarized GitHub channel, while proving users on 3.0.0 can
upgrade from inside the app and new users can install the stapled DMG.

**Depends on:** S31; S21–S24 release/update architecture

**Source of truth:** Human release instruction (2026-08-20);
`AI_Workflow_Kit/docs/DECISIONS.md` ADR-013; `.github/workflows/release.yml`;
`script/build_release_dmg.sh`; `Tests/VaniScriptCoreTests/UpdateQualificationTests.swift`

- [x] [S32.D1] Cut an isolated VaniScript release source commit containing the accepted 3.1.0 app and tests without unrelated workspace-project changes
- [x] [S32.D2] Produce version 3.1.0 with a strictly increasing numeric build and the existing VaniScript bundle/feed identity
- [x] [S32.D3] Build arm64 Release, sign nested code with hardened runtime, notarize the final DMG, staple and validate the final versioned copy, and generate the signed Sparkle update ZIP/manifests/checksums
- [x] [S32.D4] Publish GitHub release notes centered on the new Batch module while identifying 3.0.0 as the editorial-workspace release; upload appcast last

### Objective gates

- [x] [S32.O1] complete Batch-focused gate passes 151/151 with zero failures
- [x] [S32.O2] live 3.0.0 appcast identity is valid and 21/21 deterministic update/release qualification tests pass
- [x] [S32.O3] release app, ZIP, DMG, manifest, notes, and checksums match version/build/arm64/bundle/feed requirements
- [x] [S32.O4] codesign, notarization, stapler, Gatekeeper, architecture, minimum macOS, and local-Xcode-coupling checks pass on the exact final artifacts
- [x] [S32.O5] installed 3.0.0 discovers and installs 3.1.0 through Sparkle, relaunches healthy, and preserves user data
- [x] [S32.O6] GitHub v3.1.0 exposes DMG for new users plus signed ZIP, notes, manifest, checksums, and appcast published last

### Judgment gates

- [x] [S32.J1] release chain of custody is fail-closed and the published appcast references only the verified immutable 3.1.0 ZIP
- [ ] [S32.J2] Human accepts release notes and the installed/upgraded 3.1.0 application

**Stop-gate:** verified release source + signed/notarized/stapled artifacts +
successful 3.0.0 → 3.1.0 Sparkle upgrade + published GitHub release.
