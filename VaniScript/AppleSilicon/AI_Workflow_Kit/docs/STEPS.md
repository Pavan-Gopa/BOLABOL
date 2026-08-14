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
- [x] Orchestrator confirms: ready to work with this process.
- [x] Human provides project context.
- [x] Enough context → minimal plan (S1+). Thin context → Architect research + plan.
- [x] Confirm gates: review on by default; Tester recommended.

**Out of scope:**
- Large product implementation before plan exists

## Verification

### Objective gates

- [x] PROJECT_CONTEXT contains real project information

### Judgment gates

- [x] next step or Architect path is clear

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
- [x] Add minimal local ASR engine and audio preparation contracts
- [x] Port Parakeet v3/int8 loading, request validation, decoding, cancellation, and unload behavior
- [x] Preserve unanchored auto-detect and safe explicit language hints
- [x] Add deterministic tests without real model weights or network access
- [x] Repair the pre-existing Canary release namespace test blocker
- [x] Repair the stale Canary 1B download-source test blocker

**Out of scope:**
- Canary engines, pipeline routing, Models UI, or cloud package metadata

## Verification

### Objective gates

- [x] `swift build` exits 0
- [x] focused Parakeet/audio tests pass
- [x] `swift test` exits 0

### Judgment gates

- [x] BOLABOL behavior is ported without importing BOLABOL product dependencies
- [x] engine residency, cleanup, and error semantics are bounded

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
- [x] Port Canary Flash encoder/prefill/decoder execution and silence-aware windows
- [x] Port Canary 1B Path B stateful decoder with the macOS 15 gate
- [x] Require explicit supported source language and fail unknown variants closed
- [x] Add pure chunk, mask, position, language, and request tests

**Out of scope:**
- Pipeline/UI wiring and Canary translation

## Verification

### Objective gates

- [x] `swift build` and focused Canary tests pass
- [x] `swift test` exits 0

### Judgment gates

- [x] `.cpuAndNeuralEngine`, ASR-only, OS, window, and model-layout invariants match BOLABOL

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
- [x] Auto-connect verified BOLABOL Canary 1B packages from the shared root without main-thread integrity work
- [x] Prevent SmartAudioAnalyzer end-frame overflow during native processing
- [x] Resolve ready local ASR models through `activeLocalASRModel`
- [x] Allow Parakeet auto; require explicit supported sources for Canary
- [x] Distinguish incomplete model, unsupported OS, missing source, and unsupported source failures

**Out of scope:**
- Visual source picker and engine internals

## Verification

### Objective gates

- [x] focused Core routing/readiness tests pass
- [x] `swift test` exits 0

### Judgment gates

- [x] no local model silently falls back to WhisperKit

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
- [x] Bind each verified descriptor/path to its exact engine
- [x] Expose independent source and target language controls filtered by selected ASR capabilities
- [x] Skip translation when normalized source and target languages are the same
- [x] Preserve review-ready timed cues for WhisperKit, Parakeet, Canary Flash, and Canary 1B; never flatten a full processing chunk into one cue
- [x] Unload the previous ASR engine on model/path changes and before heavy local MLX work
- [x] Route live dictation through the same policy without MainActor package hashing
- [x] Show the exact local ASR model while loading and transcribing
- [x] Auto-discover and test the verified Canary 1B package from supported local/shared roots
- [x] Keep the Models `Active` badge, opened project/session provider, and processing engine on the same selected local ASR
- [x] Accept a verified Canary 1B package containing harmless Finder metadata without weakening its manifest allowlist
- [x] Bundle the required MLX Metal library in every fresh app build
- [x] Normalize shared MLX catalog labels and isolate test settings persistence
- [x] Preserve successful MLX cue batches and recover an empty batch without blanking the translation
- [x] Recover a terminal single-cue MLX sentinel without discarding valid translated cues
- [x] Reject partial or unstructured MLX cue batches instead of fabricating aligned cues
- [x] Retry only explicit MLX output-validation failures, not operational errors
- [x] Surface terminal MLX translation failure as an error instead of review-ready blank output
- [x] Parse MLX terminal markers case-insensitively without leaking sentinels
- [x] Recover one terminal END fence typo without weakening marker validation
- [x] Recover empty terminal END-only replies without blanking prior cues
- [x] Fall back empty terminal END-only leaves without blanking prior cues
- [x] Require canonical terminal END as absolute suffix
- [x] Prevent Parakeet without token timings from flattening a full chunk into one cue

**Out of scope:**
- Models UI redesign or cloud-provider changes

## Verification

### Objective gates

- [x] focused timed-cue, provider-selection, Canary 1B discovery, and MLX terminal-recovery tests pass
- [x] `swift build` and `swift test` exit 0

### Judgment gates

- [x] all local routes fail explicitly without Whisper fallback or duplicate glossary/translation work

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
- [ ] Keep Parakeet and Canary Flash downloads bound to their existing official sources
- [ ] Keep Canary 1B Locate/use functional without fabricating a cloud URL or successful Download
- [ ] Verify selection and state persistence

**Out of scope:**
- Publishing or inventing the future Canary 1B cloud package URL

## Verification

### Objective gates

- [ ] focused model UI/state tests pass
- [ ] `swift build` and `swift test` exit 0

### Judgment gates

- [ ] every UI state and error message is honest and accessible

**Ready for review when:** S5 implementation and objective gates are green.

**Stop-gate:** Reviewer APPROVED + Tester qa_green.

---

## S6 — End-to-end local ASR acceptance

**Goal:** Prove the three-model integration without committing weights or requiring Canary 1B cloud metadata.  
**Depends on:** S5  
**Target files (sketch):**
- applicable `Tests/` and `QA/` paths only

**Do:**
- [ ] Run complete build, Swift test, and QA gates
- [ ] Smoke Parakeet and Canary Flash download/select/offline routes where model assets are available
- [ ] Smoke Canary 1B locate/select/offline route when the local package is available
- [ ] Record unavailable real-weight scenarios honestly; never fake green

**Out of scope:**
- Model conversion, model weights, or future cloud hosting

## Verification

### Objective gates

- [ ] `swift build`, `swift test`, and applicable QA suite exit 0
- [ ] real-model smoke evidence is recorded for every locally available model

### Judgment gates

- [ ] no regression in WhisperKit, cloud transcription, or local MLX translation

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
- [x] Add `WorkflowSourceKind`, optional `SourceAnchor`, `DocumentState` / `DocumentBlock` / `RichTextSpan` / `DocumentLocation` / `DocumentChunkPlan`
- [x] Add `ApprovalMode`, `ReviewDisposition`, `ChunkQualityReport`; keep `approved` synchronized for old UI
- [x] Raise bundle schema to v4 with typed `ProjectAssetManifest`; import v1/v2/v3 unchanged
- [x] Decode missing `sourceKind` as media and missing `sourceAnchor` from `startSec`/`endSec`
- [x] Add a small synthetic DOCX fixture under `Tests/`; do not commit the publisher manuscript
- [x] First upload card: copy `Upload Media / Document`, detail names DOCX/TXT/MD/RTF/PDF; real drag-and-drop
- [x] `chooseSourceFile` classifies media vs document; documents skip `MediaDurationReader`
- [x] `DocumentImportService` copies the file into the project store, records SHA-256, sets `sourceKind`, builds `DocumentState` for docx/txt/md
- [x] `DOCXPackageReader` walks `w:p`, preserves `w:pPr`, merges only visually identical runs
- [x] Reject `.docm`, zip-slip, external relationships, XXE, oversized packages with honest errors
- [x] Config hides Audio Metadata / Transcription Model / Chunk Duration / Slice Mode for documents; shows document title/author, source/target language, translation model
- [x] Source Language auto-detects from the document text; no manual fill required
- [x] `startSession` consumes deterministic semantic `DocumentChunkPlan` groups; it must not create one chunk per block
- [x] Semantic planner groups chapter/paragraph/quote/verse atoms within provider-aware token budgets; a book with 872 blocks yields a bounded plan, not 872 chunks
- [x] Document Review renders non-empty source content with document block/chapter labels and no media waveform/timecodes
- [x] Initialize Engine transitions visibly to the document Review and persists the semantic plan/session
- [x] Config exposes a per-project Auto-approve checkbox; its value snapshots into `SessionState.approvalMode`
- [x] Add separate document prompts + strict block JSON contract/validator; never fill a missing block with source text
- [x] Sequential coordinator translates all pending chunks, autosaves each valid result, and in automatic mode auto-approves then continues through the end
- [x] Add `Retranslate Current`: exactly one selected chunk, no queue chaining even when Auto-approve is enabled, replacement remains pending manual `Approve & Next`
- [x] Targeted retranslation preserves the last valid translation on provider/validation failure
- [x] Manual `Approve & Next` navigates to an already translated next chunk without re-calling the provider; an untranslated next chunk is processed only through the normal manual workflow
- [x] Cloud document generation requests structured JSON (`application/json` / supported response-format); media generation payloads remain unchanged
- [x] Deterministic tests pin targeted success no-chain/manual-pending, ready-next zero calls, Auto-approve snapshot, and batch continuation past `Needs Review`
- [x] A selected chunk request contains only its planned blocks plus bounded neighboring context; the full project glossary is filtered/deduplicated instead of repeated through profile and memory
- [x] Provider prompt states the exact response JSON shape, required IDs, and allowed style IDs; live-shaped payloads remain within the selected model budget
- [x] Coordinator/store distinguish success, validation failure, provider failure, and cancellation; a failed request never reports “retranslated” or opens an empty result as success
- [x] Review visibly exposes the selected chunk's actionable quality/provider error and allows retry without losing a prior valid translation
- [x] Metadata-only diagnostics record provider ID, chunk index, source/prompt/output sizes, attempts, and failure class without logging manuscript text or credentials
- [x] Regression tests reproduce the current 105-entry glossary project shape and prove one selected 636-character chunk does not become a 150k-character prompt
- [x] Source-empty/protected structural blocks are deterministic: they are excluded from provider translation work, merged back in original order, and accepted empty only when the source is empty
- [x] Validator duplicate/explanation/residue checks are source-aware: identical source paragraphs may share a translation; a source label may translate as a label; ordinary copied prose and unsolicited wrappers still fail or warn
- [x] Repair calls contain only invalid translatable block IDs, merge repaired blocks into the prior candidate, and validate the reconstructed full response; never resend the entire chunk as an “invalid subset” repair
- [x] A live-shaped 33-block front-matter regression (11 empty blocks, repeated source paragraph, `Translation: [NAME]`, URL/copyright) commits the valid provider response instead of producing false blocking errors
- [x] Document Dual View uses one normalized `0...1` scroll position: direct live scrolling of either source or translated pane drives the other pane without animation
- [x] Unequal document heights map top-to-top and bottom-to-bottom exactly; either pane can reach its real bottom without clipping, jumping, or stale offset
- [x] Programmatic follower updates, text binding/layout changes, and caret visibility cannot create feedback loops or steal leadership; user scrolling remains immediately interruptible from either side
- [x] Chunk/language changes reset or rebind both panes deterministically; Source-only/Translated-only and all media Review paths remain unchanged
- [x] AppKit-level scroll tests cover unequal heights, exact boundaries, bidirectional leadership, feedback suppression, relayout/clamping, and chunk reset
- [x] The real SwiftUI/AppKit bridge resolves two distinct pane-owned `NSScrollView` instances; wheel/trackpad, scrollbar, and keyboard scrolling all drive the opposite pane
- [x] Gemini document translation exposes safe per-key attempt index/count, HTTP/failure class, elapsed time, response size, and finish reason without logging keys or manuscript content
- [x] Gemini rotates across every enabled key on rotatable quota/capacity failures; a deterministic five-key fixture proves ordered fallback and terminal behavior
- [x] Direct Gemini structured document generation uses an output budget/contract that returns complete JSON for the live 18-block and 37-block request shapes or reports an actionable terminal reason instead of an apparent reset
- [x] Deterministic empty/protected provider echoes are deduped in reconstruction; decade number parity is safe; validation issue codes are logged metadata-only (candidate 16)
- [x] Source-empty chunks approve and advance without translation; document export offers DOCX, PDF, and TXT chosen by the user (candidate 17)

**Out of scope:**
- Full block-level repair editor (DOCX translation export writer added by Human request)

## Verification

### Objective gates

- [x] focused document-model and migration tests pass
- [x] focused classifier/import/reader tests pass
- [x] focused document-config/session tests pass
- [x] focused semantic-planner/document-review tests pass
- [x] focused document-translation/coordinator/targeted-retranslate tests pass
- [x] focused live document-runtime request/error-visibility tests pass
- [x] focused source-aware validator/deterministic-blank/subset-repair tests pass
- [x] focused document dual-pane scroll synchronization tests pass
- [x] focused Gemini five-key rotation, structured-output budget, and terminal-diagnostic tests pass
- [x] focused chunk-29-shaped reconstruction, decade parity, and chunk-change scroll re-sync tests pass
- [x] focused empty-chunk approval and DOCX/PDF/TXT export writer tests pass
- [x] `swift build` and `swift test` exit 0

### Judgment gates

- [ ] media projects and old `.vaniscript` bundles decode without content change
- [ ] new fields are additive `decodeIfPresent` only
- [ ] a chosen `.docx`/`.txt` attaches and is visible as a document source; media path unchanged
- [ ] Config adapts to document type without manual intervention
- [ ] Auto-approve batch translates sequentially through the end and persists every locally valid result
- [ ] `Retranslate Current` processes only the selected chunk, never chains, and requires manual approval
- [x] provider/validator failure cannot erase a prior valid translation

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
- [ ] Walk `w:p` in tables and text boxes; headers/footers/footnotes/endnotes as parts
- [ ] Merge only visually identical runs; keep italic/bold/small-caps/hyperlink boundaries
- [ ] Normalize NFC without stripping diacritics; drop field instructions/bookmarks/drawings from translate-text
- [ ] Emit preflight counts (pages, words, sections, blocks, protected groups, font warnings)

**Out of scope:**
- PDF/RTF importers, chunk packing, translation, writer

## Verification

### Objective gates

- [ ] focused reader/preflight tests pass
- [ ] `swift build` and `swift test` exit 0

### Judgment gates

- [ ] original bytes stay identical; IR IDs are stable across two imports of the same file
- [ ] NSAttributedString officeOpenXML is fallback/preview only, never the round-trip source

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
- [x] Classify blocks from style ID, outline, emptiness, and neighbors
- [x] Mark protected Sanskrit/transliteration/names; keep verse+gloss+citation atomic
- [x] Attach chapter titles to the first body block; never cross a chapter unless required
- [x] Size chunks from real model context/output, not a global character cap
- [x] Attach read-only before/after context; hash plan from blocks + profile + glossary + prompt version

**Out of scope:**
- LLM calls, coordinator, UI preview screen (data only)

## Verification

### Objective gates

- [x] focused planner/budget tests pass, including deterministic IDs
- [x] `swift build` and `swift test` exit 0

### Judgment gates

- [ ] ordinary paragraphs never split; shlokas never detach from their gloss
- [ ] empty paragraphs stay in the output map but spend no LLM budget

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
- [x] Add separate prompt IDs; do not change active transcript presets
- [x] Require one output block per input ID, same order, known style IDs only
- [x] Treat a missing block ID as failure, never as a successful original-text fill
- [x] Auto-approve only after the local validator; two failed repairs → `Needs Review`
- [x] Ship a mock provider first; then wire cloud/MLX structured output

**Out of scope:**
- Queue/autosave UI, DOCX writer, package export

## Verification

### Objective gates

- [x] focused contract/validator/repair tests pass
- [x] `swift build` and `swift test` exit 0

### Judgment gates

- [ ] literary quality is inside the single strict pass; no second free polish of the whole book
- [ ] media cue translation behavior is unchanged

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
- [ ] Sequential coordinator with translation memory, atomic save, backoff, and `processing` → `pendingRetry` on reopen
- [x] Upload card accepts documents; real drag-and-drop; classifier routes media vs document
- [x] Config hides audio/ASR/chunk-minutes; shows profile, Sanskrit policy, auto-approve, preflight
- [x] Processing shows chapter/paragraphs, not timecode; counts auto-approved / needs review / failed
- [ ] Review hides waveform; locked protected verses; per-block edit / retranslate / repair / approve

**Out of scope:**
- DOCX writer, translation-package folder export

## Verification

### Objective gates

- [ ] focused coordinator/crash-recovery tests pass
- [ ] `swift build` and `swift test` exit 0

### Judgment gates

- [ ] automatic mode never auto-approves a validator failure
- [ ] media upload/config/review paths stay intact

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
- [ ] Copy original DOCX; replace only allowed text nodes; keep `w:pPr`, styles, fonts, relationships
- [ ] Fail closed if location/`sourceHash` no longer match
- [ ] Warn when Brill/Gentium are referenced but not embedded; do not ship font files
- [ ] Export package is three files in a chosen folder via temp dir + atomic move
- [ ] Reopen `.vaniscript` restores IR and output without reparse or retranslate

**Out of scope:**
- Pixel-identical pagination, TOC page-number rewrite, PDF reconstruction

## Verification

### Objective gates

- [ ] focused writer/package tests pass
- [ ] `swift build` and `swift test` exit 0

### Judgment gates

- [ ] original file stays byte-identical; localized file is a valid DOCX
- [ ] `DocumentOutputFormat` stays separate from media `OutputFormat`

**Ready for Human test when:** S12 implementation and Objective Gates are green and a fresh app exports a three-file package from the synthetic fixture.

**Stop-gate:** Human ACCEPTED + Reviewer APPROVED + (Tester qa_green | QA explicitly skipped by Human).

---

## S13 — Hardening and extra import tiers

**Goal:** Add honest non-DOCX import tiers and prove media + document suites together.  
**Depends on:** S12  
**Source of truth:** PRD §7.1, §19–20 Slice 9, §22  
**Target files (sketch):**
- `Sources/VaniScript/Services/PDFDocumentImporter.swift`
- applicable extra importers and `Tests/` / `QA/` paths

**Do:**
- [ ] TXT/Markdown/RTF as structural import with an honest accuracy badge
- [ ] Text-layer PDF as reconstruction; scanned PDF/OCR stays an explicit later stage
- [ ] Security limits, cancellation, and large-document tests
- [ ] Full media regression: WhisperKit, cloud transcription, local MLX translation

**Out of scope:**
- Vision OCR productization, `.docm`, pixel-identical page count

## Verification

### Objective gates

- [ ] `swift build`, `swift test`, and applicable QA suite exit 0
- [ ] unavailable OCR/real-manuscript cases are recorded honestly

### Judgment gates

- [ ] no media-pipeline regression; no fabricated format support

**Ready for review when:** automated gates and available smokes are complete.

**Stop-gate:** Reviewer APPROVED + Tester qa_green; unavailable external assets remain explicit blockers, not fabricated success.
