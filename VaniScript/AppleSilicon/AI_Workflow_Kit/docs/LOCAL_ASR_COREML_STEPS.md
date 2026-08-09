# LOCAL_ASR_COREML — Step cards (LASR-01…LASR-09)

> Authoritative architecture: `LOCAL_ASR_COREML_ARCHITECTURE.md`.  
> Acceptance skeleton: `LOCAL_ASR_COREML_ACCEPTANCE.md`.  
> Scope: Apple Silicon; exactly Parakeet TDT 0.6B v3, Canary Flash 180M and Canary 1B v2.

## Global quality (каждый coding-шаг LASR-01…LASR-08)

- Graphify first; затем только точечное чтение.
- Checkpoint выполняет Orchestrator до шага; rollback tag указан в карточке.
- Diff только в `target_files` открытого шага.
- Migration-safe decode; существующие WhisperKit/MLX/cloud settings и paths сохраняются.
- Product code has role header and why/constraint comments per `TEAM_CONTRACT.md` § Comments.
- No Python/NeMo/ONNX/MLX ASR, no Bolabol CDN URL/name, no Electron/GigaAM/CPS.
- После реализации Coder: `swift build` + `swift test`.
- Затем обязательны independent Verification approval и **QA gate GREEN** (все применимые suite, `bugs_open: 0`) до перехода дальше.
- Реальные модельные веса и скачанные packages не коммитятся.

## Dependency order

```text
LASR-01 → LASR-02 → LASR-03 → LASR-04 → LASR-05 → LASR-06 → LASR-07 → LASR-08 → LASR-09
```

`LASR-02` имеет Human input gate для concrete Canary 1B release. Остальные карточки не должны выдавать production-ready Canary 1B Download без закрытого gate.

---

## LASR-01 — Catalog + install-source contracts

### Goal

Создать единый descriptor-driven Core contract для существующего WhisperKit и трёх in-scope моделей. Зафиксировать install-source виды, capabilities, storage runtimes и migration-safe persisted runtime values; download/engine/UI ещё не подключать.

### Requirements

1. В `NativeModelCatalog` добавить `LocalASRModelDescriptor`, backend, capabilities, required-layout и install-source contracts.
2. Добавить catalog entries только для:
   - `parakeet-tdt-06b-v3`;
   - `canary-180m-flash-coreml`;
   - `canary-1b-v2-coreml`.
3. Зафиксировать Parakeet FluidAudio v3 int8; Canary Flash HF repo; Canary 1B generic `remotePackage`, без Bolabol CDN.
4. Добавить `.canary` в persisted `LocalModelRuntime` без изменения существующих raw values; использовать существующую `.parakeet`.
5. Добавить `.parakeet`/`.canary` в `SharedModelRuntime` и canonical paths §6 Architecture.
6. Merge три model states в defaults/legacy decode без сброса существующих installs/provider selection.
7. Pin FluidAudio exact `0.15.5` in `Package.swift`; подтвердить product license/Swift 6/macOS 14 compatibility в handoff.
8. Unit tests: exact IDs, unique IDs, capability/language/OS data, install-source kind, Codable migration, storage paths.

### target_files (Coder)

- `Package.swift` (MODIFY)
- `Package.resolved` (MODIFY, generated dependency lock only)
- `Sources/VaniScriptCore/NativeModelCatalog.swift` (MODIFY)
- `Sources/VaniScriptCore/AppSettings.swift` (MODIFY)
- `Sources/VaniScriptCore/SharedModelsRoot.swift` (MODIFY)
- `Sources/VaniScript/Services/SettingsDiskStore.swift` (MODIFY only if default merge needs adjustment)
- `Tests/VaniScriptCoreTests/NativeModelCatalogTests.swift` (MODIFY)
- `Tests/VaniScriptCoreTests/SharedModelsRootTests.swift` (MODIFY)
- `Tests/VaniScriptCoreTests/UniversalSettingsTests.swift` (MODIFY)
- `AI_Workflow_Kit/docs/AI/FEEDBACK.md` (MODIFY)

### Out of scope

- Download bytes/presence implementation.
- Engines, pipeline and UI behavior.
- Concrete Google Drive URL/package contents.

### Done

- [ ] Catalog contains exactly the three new IDs and no other new ASR model
- [ ] FluidAudio is pinned exact `0.15.5`; build resolves it
- [ ] Old settings decode and preserve installed WhisperKit/MLX paths
- [ ] Capability tests lock Canary no-auto, Parakeet auto and Canary 1B macOS 15+
- [ ] `swift build` and `swift test` green
- [ ] Verification approved
- [ ] QA gate GREEN; `bugs_open: 0`

### Rollback

Tag `local-asr-coreml/pre-LASR-01`

---

## LASR-02 — Download, storage, presence + remote package

### Goal

Реализовать complete install path для трёх sources: FluidAudio Parakeet, pinned Hugging Face Canary Flash и integrity-checked generic remote package Canary 1B. Модель становится Ready только после exact presence validation.

### Requirements

1. Refactor `ModelDownloadManager` from model-ID switches to catalog install sources.
2. Parakeet: `AsrModels.download` v3/int8; freeze SDK layout/presence behavior.
3. Canary Flash: safe recursive HF tree download at an immutable revision; reject unsafe paths; retain relative layout; byte-based progress.
4. Generic `RemoteModelPackageInstaller`:
   - direct URL override or configurable base URL;
   - HTTPS redirect support;
   - reject HTML/wrong archive magic;
   - archive size/SHA-256 verification;
   - isolated extraction, zip-slip/symlink/canonical-path checks;
   - per-file manifest/allowlist/size/SHA-256 verification;
   - atomic destination replace;
   - cleanup on error/cancel.
5. Human supplies and Coder freezes exact Canary 1B URL/base path, package ID/layout, compressed/uncompressed sizes and hashes. If absent, mark step blocked; do not ship a fake URL.
6. Implement one presence policy used by scan, Locate, settings reconciliation, registry lookup and completion.
7. Required Canary layouts match Architecture §6. Partial/hash-invalid packages are Failed, never Ready.
8. Delete only an owned descriptor directory beneath `SharedModelsRoot`; arbitrary located paths are disconnected, not recursively erased.
9. Disk-space preflight includes archive + staging + uncompressed budget.
10. Unit tests use tiny local fixtures/mock URL protocol; no network or real model weights.

### target_files (Coder)

- `Sources/VaniScript/Services/ModelDownloadManager.swift` (MODIFY)
- `Sources/VaniScript/Services/RemoteModelPackageInstaller.swift` (NEW)
- `Sources/VaniScriptCore/NativeModelCatalog.swift` (MODIFY)
- `Sources/VaniScriptCore/AppSettings.swift` (MODIFY)
- `Sources/VaniScriptCore/SharedModelsRoot.swift` (MODIFY)
- `Sources/VaniScript/Stores/WorkflowStore.swift` (MODIFY)
- `Tests/VaniScriptCoreTests/NativeModelCatalogTests.swift` (MODIFY)
- `Tests/VaniScriptCoreTests/NativeModelRoutingTests.swift` (MODIFY)
- `Tests/VaniScriptTests/ModelDownloadManagerTests.swift` (NEW)
- `Tests/VaniScriptTests/RemoteModelPackageInstallerTests.swift` (NEW)
- `Package.swift` (MODIFY only to register app test target/extraction dependency if approved)
- `AI_Workflow_Kit/docs/AI/FEEDBACK.md` (MODIFY)

### Out of scope

- ASR inference engines.
- Models tab visual changes.
- Background daemon/updater or arbitrary user-entered package URLs.

### Done

- [ ] All three source kinds install to canonical runtime directories
- [ ] Concrete Canary 1B release metadata is supplied by Human and frozen; no Bolabol CDN reference
- [ ] Wrong hash/layout/path traversal/HTML/insufficient disk/cancel cases fail without Ready state
- [ ] Existing verified install survives failed replacement
- [ ] Scan/Locate/reconcile/completion agree on presence
- [ ] Fixture tests run without network/model weights
- [ ] `swift build` and `swift test` green
- [ ] Verification approved
- [ ] QA gate GREEN; `bugs_open: 0`

### Rollback

Tag `local-asr-coreml/pre-LASR-02`

---

## LASR-03 — Parakeet engine

### Goal

Портировать рабочий Bolabol Parakeet TDT 0.6B v3 engine на VaniScript app-target, включая robust 16 kHz mono preparation и controlled model residency. Pipeline wiring откладывается до LASR-06.

### Requirements

1. Ввести минимальный `LocalASREngine` request/result/error contract для app-target.
2. Портировать neutral audio preprocessor: loudest physical channel → 16 kHz mono PCM WAV; deterministic cleanup.
3. Портировать `ParakeetTranscriptionEngine`:
   - `AsrModels.load` v3/int8;
   - cached `AsrManager`;
   - fresh `TdtDecoderState` per request;
   - translation unsupported by contract;
   - empty-result error.
4. `auto`/empty source = unanchored detect; explicit supported source may become FluidAudio language hint; unsupported stale hint is not passed.
5. Add unload/cancel semantics; no model prewarm at app launch.
6. Tests cover request validation, language mapping, audio preprocessing (mono/multichannel), temp cleanup, empty/error paths through injectable seams; no real download.

### target_files (Coder)

- `Sources/VaniScript/Services/LocalASREngine.swift` (NEW)
- `Sources/VaniScript/Services/LocalASRAudioPreprocessor.swift` (NEW)
- `Sources/VaniScript/Services/ParakeetTranscriptionEngine.swift` (NEW)
- `Tests/VaniScriptTests/LocalASRAudioPreprocessorTests.swift` (NEW)
- `Tests/VaniScriptTests/ParakeetTranscriptionEngineTests.swift` (NEW)
- `Package.swift` (MODIFY only if LASR-02 did not register `VaniScriptTests`)
- `AI_Workflow_Kit/docs/AI/FEEDBACK.md` (MODIFY)

### Out of scope

- Canary.
- `NativeProcessingPipeline` routing and Models UI.
- Actual model download/live quality acceptance.

### Done

- [ ] Engine loads v3/int8 through FluidAudio and exposes ASR-only result contract
- [ ] `auto` is accepted; unsupported stale hint is not forced
- [ ] Multichannel audio uses loudest channel before resampling
- [ ] Cancellation/error removes temporary WAV and unload works
- [ ] `swift build` and `swift test` green
- [ ] Verification approved
- [ ] QA gate GREEN; `bugs_open: 0`

### Rollback

Tag `local-asr-coreml/pre-LASR-03`

---

## LASR-04 — Canary Flash + Canary 1B engine

### Goal

Портировать Bolabol `CanaryCoreMLEngine` для двух in-scope variants: Flash и 1B Path B. Сохранить explicit-source ASR-only и `.cpuAndNeuralEngine` invariants.

### Requirements

1. Один family engine dispatches only the two known Canary IDs; unknown ID is an error, not Flash fallback.
2. Reuse LASR-03 audio preprocessor.
3. Flash:
   - load `CanaryEncoder/Prefill/Decoder` with `.cpuAndNeuralEngine`;
   - parse `config.json`/`vocab.json`;
   - silence-aware chunks, each ≤10 s;
   - bounded greedy decode.
4. 1B Path B:
   - compile/runtime guard macOS 15+;
   - encoder → cross KV → stateful decoder KV;
   - fresh `MLState` per ≤15 s window;
   - SentencePiece decode from `canary_spe.model`.
5. Require explicit supported ISO source language; reject `auto`, missing and unsupported values before model/audio work.
6. ASR-only: no source→target AST request/path.
7. No `.all` compute mode and no known-bad alexwengg artifact fallback.
8. Port pure chunk/mask/position/language seams and fixture tests; real weights remain manual smoke.

### target_files (Coder)

- `Sources/VaniScript/Services/CanaryCoreMLEngine.swift` (NEW)
- `Sources/VaniScript/Services/LocalASREngine.swift` (MODIFY)
- `Tests/VaniScriptTests/CanaryCoreMLEngineTests.swift` (NEW)
- `AI_Workflow_Kit/docs/AI/FEEDBACK.md` (MODIFY)

### Out of scope

- Pipeline/UI wiring.
- Canary AST/speech translation.
- New model export/conversion.

### Done

- [ ] Both exact Canary IDs resolve; unknown variant fails closed
- [ ] Flash windows ≤10 s; 1B windows ≤15 s with fresh state
- [ ] `auto`/missing/unsupported source fails before model load
- [ ] 1B reports macOS 15 requirement below gate
- [ ] Compute units are `.cpuAndNeuralEngine`; no `.all`
- [ ] `swift build` and `swift test` green
- [ ] Verification approved
- [ ] QA gate GREEN; `bugs_open: 0`

### Rollback

Tag `local-asr-coreml/pre-LASR-04`

---

## LASR-05 — Language and capability policy

### Goal

Сделать source-language compatibility одним pure Core policy для Settings, workflow/MCP preflight и engines: Canary only explicit supported source, Parakeet auto allowed.

### Requirements

1. Add `ASRSourceLanguagePolicy`/equivalent based only on catalog descriptor + normalized session source.
2. Normalize supported language names/codes to lowercase ISO-639-1 without inventing a fallback.
3. Parakeet accepts `auto` and its explicit supported codes.
4. Canary Flash accepts only `en/de/fr/es`; Canary 1B accepts only catalog 25.
5. `ProviderRegistry` verifies local models by descriptor/runtime, not `isWhisper: true`.
6. `NativeProcessingReadiness` returns specific unsupported OS/incomplete model/explicit source required/unsupported source messages.
7. Same policy is callable by MCP/session updates; automation cannot bypass UI behavior.
8. Tests cover every model, auto/missing/uppercase/name/code/unsupported cases and macOS 14/15 boundary.

### target_files (Coder)

- `Sources/VaniScriptCore/NativeModelCatalog.swift` (MODIFY)
- `Sources/VaniScriptCore/ProviderRegistry.swift` (MODIFY)
- `Sources/VaniScriptCore/NativeProcessingReadiness.swift` (MODIFY)
- `Sources/VaniScriptCore/AppSettings.swift` (MODIFY if normalization belongs there)
- `Sources/VaniScript/Stores/WorkflowStore.swift` (MODIFY for MCP/session validation only)
- `Tests/VaniScriptCoreTests/NativeModelRoutingTests.swift` (MODIFY)
- `Tests/VaniScriptCoreTests/ProviderRegistryTests.swift` (MODIFY)
- `Tests/VaniScriptCoreTests/NativeProcessingReadinessTests.swift` (MODIFY)
- `AI_Workflow_Kit/docs/AI/FEEDBACK.md` (MODIFY)

### Out of scope

- Source-language picker rendering (LASR-07).
- Engine internals and package download.

### Done

- [ ] One policy governs UI-callable and MCP/session preflight
- [ ] Canary never accepts/falls back from `auto`
- [ ] Parakeet auto remains valid
- [ ] Registry no longer validates Parakeet/Canary as WhisperKit
- [ ] OS/model/language failures are distinguishable and actionable
- [ ] `swift build` and `swift test` green
- [ ] Verification approved
- [ ] QA gate GREEN; `bugs_open: 0`

### Rollback

Tag `local-asr-coreml/pre-LASR-05`

---

## LASR-06 — Pipeline and live-dictation wiring

### Goal

Маршрутизировать WhisperKit, Parakeet и обе Canary variants через один local ASR resolver/router в обеих pipeline entry points и live dictation, сохранив outer chunks, cues, glossary и translation.

### Requirements

1. Add `LocalASREngineRouter` that binds descriptor + verified path to exactly one resident engine.
2. On model/path switch unload previous ASR engine; no silent fallback to WhisperKit.
3. Replace Whisper-only branches in `processCurrentChunk` and `process` with one local transcription helper.
4. Canary internally windows outer VaniScript chunks; persisted chunk boundaries are unchanged.
5. Map engine timestamps when present; otherwise use existing whole-chunk fallback cue; apply source glossary once.
6. Release Canary 1B before local MLX translation; do not prewarm at launch.
7. Route `WorkflowStore.transcribeDictation` through the same router/language policy instead of direct `loadWhisperKit` and partial language switch.
8. Update `ChatSidebarView` presence checks to descriptor-driven readiness.
9. Cloud transcription, usage recording, MLX translation and WhisperKit decode behavior remain unchanged.
10. Tests use mock engines to prove provider selection, no-fallback, both pipeline entry points, live dictation, outer-chunk preservation, glossary-once and unload order.

### target_files (Coder)

- `Sources/VaniScript/Services/LocalASREngineRouter.swift` (NEW)
- `Sources/VaniScript/Services/NativeProcessingPipeline.swift` (MODIFY)
- `Sources/VaniScript/Stores/WorkflowStore.swift` (MODIFY)
- `Sources/VaniScript/Views/ChatSidebarView.swift` (MODIFY)
- `Tests/VaniScriptTests/NativeProcessingPipelineASRTests.swift` (NEW)
- `Tests/VaniScriptTests/LocalASREngineRouterTests.swift` (NEW)
- `AI_Workflow_Kit/docs/AI/FEEDBACK.md` (MODIFY)

### Out of scope

- Models tab/source picker visuals.
- Cloud provider changes and translation redesign.

### Done

- [ ] All three new IDs produce their own engine route in batch/current/live paths
- [ ] Unknown/unready model fails explicitly; no Whisper fallback
- [ ] Canary internal windows do not alter stored VaniScript chunks
- [ ] Glossary/translation happen once after local ASR
- [ ] Residency/unload order prevents Canary 1B + local MLX overlap
- [ ] Existing WhisperKit and cloud route tests remain green
- [ ] `swift build` and `swift test` green
- [ ] Verification approved
- [ ] QA gate GREEN; `bugs_open: 0`

### Rollback

Tag `local-asr-coreml/pre-LASR-06`

---

## LASR-07 — Models UI download/select + source picker

### Goal

Expose the three catalog models in existing Apple Silicon Models UI with honest progress/readiness/OS states, selection and descriptor-filtered source-language controls.

### Requirements

1. Render ASR metadata/source links from `LocalASRModelDescriptor`; remove new-model duplication in `modelDownloadUrl`/`getModelMeta` switches.
2. Cards support Not installed, Downloading, Ready, Failed/Retry and Unsupported OS.
3. Canary 1B card is visible on macOS 14 but Download/Use disabled with macOS 15+ explanation.
4. `Use` updates `transcriptionProvider` through WorkflowStore/session synchronization.
5. Delete follows LASR-02 owned-path safety; partial install is removable/retryable.
6. Add source-language picker to default Settings and `ConfigWorkspaceView`:
   - Parakeet: `auto` + supported explicit languages;
   - Canary: only supported explicit languages, no `auto`.
7. Download may start regardless of source language; Initialize Engine/processing remains blocked until Canary has an explicit supported source.
8. Scanner copy/results name WhisperKit, Parakeet, Canary and MLX honestly.
9. Accessibility labels/help explain runtime, source policy, OS gate and current state.
10. UI smoke evidence must show each card state and filtered source choices; no real URL/hash/secret in screenshots/logs.

### target_files (Coder)

- `Sources/VaniScript/Views/SettingsView.swift` (MODIFY)
- `Sources/VaniScript/Views/ConfigWorkspaceView.swift` (MODIFY)
- `Sources/VaniScript/Stores/WorkflowStore.swift` (MODIFY)
- `Sources/VaniScriptCore/NativeModelCatalog.swift` (MODIFY only for UI projections)
- `Tests/VaniScriptCoreTests/NativeModelRoutingTests.swift` (MODIFY)
- `AI_Workflow_Kit/docs/AI/FEEDBACK.md` (MODIFY)

### Out of scope

- New onboarding flow or broad visual redesign.
- Electron.
- Canary AST or target-language coupling.

### Done

- [ ] Exactly three new cards appear with accurate metadata/source/size/languages
- [ ] Download/Retry/Locate/Use/Delete states work and persist
- [ ] Canary 1B OS gate is visible and enforced on macOS 14
- [ ] Canary source picker excludes `auto`; Parakeet includes it
- [ ] Unsupported/missing Canary source blocks Initialize with actionable copy
- [ ] Accessibility and UI smoke evidence recorded
- [ ] `swift build` and `swift test` green
- [ ] Verification approved
- [ ] QA gate GREEN; `bugs_open: 0`

### Rollback

Tag `local-asr-coreml/pre-LASR-07`

---

## LASR-08 — Tests and end-to-end acceptance

### Goal

Закрыть automated contracts и выполнить real-model acceptance/smoke для download → select → offline transcribe, integrity, language, OS and residency. Обновить acceptance evidence, не добавляя четвёртую модель или новую product feature.

### Requirements

1. Run all automated suites from LASR-01…LASR-07; add only missing observable-contract tests.
2. Add QA static checks: exact three IDs, no Bolabol CDN, no `.all` in Canary, no Python/NeMo/ONNX/MLX ASR route, no model weights tracked.
3. Real smoke on fresh built app:
   - Parakeet download/select/auto/transcribe;
   - Canary Flash download/select/explicit EN plus one non-EN supported language;
   - Canary 1B remote package download/select/explicit RU or UK on macOS 15+.
4. Negative smoke: Canary `auto`; unsupported language; corrupt/truncated package; invalid Drive HTML/expired link; incomplete folder; insufficient disk where reproducible.
5. Regression smoke: existing WhisperKit, cloud transcription and local MLX translation.
6. Measure model load time, peak resident memory and overlap at ASR→MLX boundary; record facts without silently weakening residency policy.
7. Fill `LOCAL_ASR_COREML_ACCEPTANCE.md` with commands, environment, evidence paths/hashes and PASS/FAIL; no secrets/model weights in repo.
8. QA gate remains RED if any one in-scope model cannot complete its real download/select/offline ASR scenario.

### target_files (Coder / QA as assigned by Orchestrator)

- `Tests/VaniScriptCoreTests/NativeModelCatalogTests.swift` (MODIFY if a contract gap exists)
- `Tests/VaniScriptCoreTests/NativeModelRoutingTests.swift` (MODIFY if a contract gap exists)
- `Tests/VaniScriptCoreTests/NativeProcessingReadinessTests.swift` (MODIFY if a contract gap exists)
- `Tests/VaniScriptTests/ModelDownloadManagerTests.swift` (MODIFY if a contract gap exists)
- `Tests/VaniScriptTests/RemoteModelPackageInstallerTests.swift` (MODIFY if a contract gap exists)
- `Tests/VaniScriptTests/ParakeetTranscriptionEngineTests.swift` (MODIFY if a contract gap exists)
- `Tests/VaniScriptTests/CanaryCoreMLEngineTests.swift` (MODIFY if a contract gap exists)
- `Tests/VaniScriptTests/NativeProcessingPipelineASRTests.swift` (MODIFY if a contract gap exists)
- `QA/scripts/local_asr_coreml_contract.sh` (NEW)
- `QA/manifest.json` (MODIFY)
- `QA/COVERAGE.md` (MODIFY)
- `AI_Workflow_Kit/docs/LOCAL_ASR_COREML_ACCEPTANCE.md` (MODIFY)
- `AI_Workflow_Kit/docs/AI/FEEDBACK.md` (MODIFY)

### Out of scope

- Fixing unrelated QA failures without a new Orchestrator-scoped fix step.
- Performance tuning that changes model/export semantics.
- Release notes/final ADR (LASR-09).

### Done

- [ ] `swift build` green
- [ ] `swift test` green with exact suite/test counts recorded
- [ ] QA static and black-box suites GREEN; `bugs_open: 0`
- [ ] Each of the three real models passes download → select → offline transcript
- [ ] Negative integrity/language/OS cases fail closed
- [ ] WhisperKit/cloud/MLX regression smoke passes
- [ ] Memory/load measurements and evidence are recorded
- [ ] Independent Verification approved

### Rollback

Tag `local-asr-coreml/pre-LASR-08`

---

## LASR-09 — Doc-only closeout

### Goal

Зафиксировать фактический shipped contract и acceptance result после LASR-08. Это отдельный doc-only шаг: product code, tests и QA scripts не меняются.

### Requirements

1. Reconcile Architecture capabilities/sizes/source revisions/package metadata with implemented facts; update accuracy tags.
2. Finalize acceptance status/evidence links without rerunning or fabricating missing scenarios.
3. Add completion ADR to `DECISIONS.md` only if LASR-08 is fully GREEN/approved.
4. Document remaining operational risk (for example Drive URL rotation) and owner.
5. Keep scope to the same three models.

### target_files (doc-only)

- `AI_Workflow_Kit/docs/LOCAL_ASR_COREML_ARCHITECTURE.md` (MODIFY)
- `AI_Workflow_Kit/docs/LOCAL_ASR_COREML_ACCEPTANCE.md` (MODIFY)
- `AI_Workflow_Kit/docs/DECISIONS.md` (MODIFY)
- `AI_Workflow_Kit/docs/AI/FEEDBACK.md` (MODIFY)

### Out of scope

- Any Swift/TS/JS/Python or QA script change.
- New model, Electron, GigaAM or CPS work.
- Declaring completion while acceptance contains a blocking FAIL/NOT RUN.

### Done

- [ ] Docs match implemented source revisions/layout/capabilities
- [ ] Acceptance has a grounded final status
- [ ] Completion ADR added only after full green gate
- [ ] Diff is doc-only
- [ ] Verification approved; Orchestrator may close track

### Rollback

Tag `local-asr-coreml/pre-LASR-09`
