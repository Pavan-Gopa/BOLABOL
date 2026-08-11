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
- [ ] Add minimal local ASR engine and audio preparation contracts
- [ ] Port Parakeet v3/int8 loading, request validation, decoding, cancellation, and unload behavior
- [ ] Preserve unanchored auto-detect and safe explicit language hints
- [ ] Add deterministic tests without real model weights or network access

**Out of scope:**
- Canary engines, pipeline routing, Models UI, or cloud package metadata

## Verification

### Objective gates

- [ ] `swift build` exits 0
- [ ] focused Parakeet/audio tests pass
- [ ] `swift test` exits 0

### Judgment gates

- [ ] BOLABOL behavior is ported without importing BOLABOL product dependencies
- [ ] engine residency, cleanup, and error semantics are bounded

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
- [ ] Port Canary Flash encoder/prefill/decoder execution and silence-aware windows
- [ ] Port Canary 1B Path B stateful decoder with the macOS 15 gate
- [ ] Require explicit supported source language and fail unknown variants closed
- [ ] Add pure chunk, mask, position, language, and request tests

**Out of scope:**
- Pipeline/UI wiring and Canary translation

## Verification

### Objective gates

- [ ] `swift build` and focused Canary tests pass
- [ ] `swift test` exits 0

### Judgment gates

- [ ] `.cpuAndNeuralEngine`, ASR-only, OS, window, and model-layout invariants match BOLABOL

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

**Do:**
- [ ] Resolve ready local ASR models through `activeLocalASRModel`
- [ ] Allow Parakeet auto; require explicit supported sources for Canary
- [ ] Distinguish incomplete model, unsupported OS, missing source, and unsupported source failures

**Out of scope:**
- Visual source picker and engine internals

## Verification

### Objective gates

- [ ] focused Core routing/readiness tests pass
- [ ] `swift test` exits 0

### Judgment gates

- [ ] no local model silently falls back to WhisperKit

**Ready for review when:** S3 implementation and objective gates are green.

**Stop-gate:** Reviewer APPROVED + Tester qa_green.

---

## S4 — Pipeline and live route wiring

**Goal:** Route WhisperKit, Parakeet, Canary Flash, and Canary 1B through one resident local-ASR router in batch, current-chunk, and live-dictation paths.  
**Depends on:** S3  
**Target files (sketch):**
- `Sources/VaniScript/Services/LocalASREngineRouter.swift`
- `Sources/VaniScript/Services/NativeProcessingPipeline.swift`
- `Sources/VaniScript/Stores/WorkflowStore.swift`
- `Sources/VaniScript/Views/ChatSidebarView.swift`
- `Tests/VaniScriptTests/LocalASREngineRouterTests.swift`
- `Tests/VaniScriptTests/NativeProcessingPipelineASRTests.swift`

**Do:**
- [ ] Bind each verified descriptor/path to its exact engine
- [ ] Preserve chunks, cues, glossary-once, cloud transcription, and downstream translation
- [ ] Unload the previous ASR engine on model/path changes and before heavy local MLX work
- [ ] Route live dictation through the same policy

**Out of scope:**
- Models UI redesign or cloud-provider changes

## Verification

### Objective gates

- [ ] focused router/pipeline tests pass
- [ ] `swift build` and `swift test` exit 0

### Judgment gates

- [ ] all local routes fail explicitly without Whisper fallback or duplicate glossary/translation work

**Ready for review when:** S4 implementation and objective gates are green.

**Stop-gate:** Reviewer APPROVED + Tester qa_green.

---

## S5 — Models UI and local Canary 1B workflow

**Goal:** Expose honest download/locate/use/delete and source-language behavior for all three models, while treating Canary 1B as a verified local package until its cloud release exists.  
**Depends on:** S4  
**Target files (sketch):**
- `Sources/VaniScript/Views/SettingsView.swift`
- `Sources/VaniScript/Views/ConfigWorkspaceView.swift`
- `Sources/VaniScript/Stores/WorkflowStore.swift`
- applicable Core/UI tests

**Do:**
- [ ] Keep Parakeet and Canary Flash downloads bound to their existing official sources
- [ ] Keep Canary 1B Locate/use functional without fabricating a cloud URL or successful Download
- [ ] Filter source choices from descriptor capabilities and expose the macOS 15 gate
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
