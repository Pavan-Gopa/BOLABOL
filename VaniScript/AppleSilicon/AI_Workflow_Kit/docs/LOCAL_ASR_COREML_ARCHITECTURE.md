# VaniScript Apple Silicon — LOCAL_ASR_COREML Architecture

> Архитектурный план добавления в существующий локальный ASR ровно трёх моделей:
> **Parakeet TDT 0.6B v3**, **Canary Flash 180M** и **Canary 1B v2**.
>
> **Track:** `LOCAL_ASR_COREML`  
> **Status:** Design; product-код не реализован.  
> **Companion docs:** `LOCAL_ASR_COREML_STEPS.md`, `LOCAL_ASR_COREML_ACCEPTANCE.md`, `DECISIONS.md`.  
> **Read-only implementation reference:** `/Users/pavan/Documents/AI Projects/Bolabol`.

**Accuracy tags:** `[high]` — подтверждено исходниками VaniScript/Bolabol; `[med]` — контракт выбран, деталь должна быть зафиксирована coding-шагом; `[low]` — требуется артефакт или решение Human.

---

## 1. Цель и границы

Цель — дать пользователю VaniScript Apple Silicon возможность скачать, выбрать и использовать из UI три дополнительных локальных Core ML/ANE ASR backend-а, не меняя существующую post-ASR цепочку glossary → translation → review/export. `[high]`

### In scope

1. `parakeet-tdt-06b-v3` — FluidAudio Core ML/ANE; download через FluidAudio/Hugging Face.
2. `canary-180m-flash-coreml` — native Canary Core ML/ANE; download из `aufklarer/Canary-180M-Flash-CoreML`.
3. `canary-1b-v2-coreml` — native Canary Core ML/ANE; generic remote package, который Human разместит в Google Drive или на совместимом configurable base URL.
4. Catalog, install sources, storage/presence, engines, routing, source-language policy, Settings/Models UI и acceptance-контур.

### Out of scope

- Любые другие новые ASR-модели, включая GigaAM.
- Удаление или redesign существующего WhisperKit-каталога; WhisperKit упоминается только как текущий путь и regression invariant.
- Electron.
- Cloud provider stabilization и возобновление `CLOUD_PROVIDER_STABILIZATION`.
- Speech translation внутри Canary: обе Canary-модели в этом треке — **ASR-only**.
- Python, NeMo runtime, ONNX Runtime, MLX для ASR и sidecar-процессы.

## 2. Подтверждённый VaniScript baseline

Graphify и точечное чтение показывают текущую цепочку: `[high]`

- `AppSettings.localAsrModels` хранит persisted install state; `LocalModelRuntime` уже имеет `.whisper` и `.parakeet`, но не Canary.
- `NativeModelCatalog.activeWhisperKitModel` знает только WhisperKit IDs и возвращает `ActiveWhisperKitModel`.
- `ProviderRegistry` добавляет downloaded local ASR, но проверяет каждый такой путь как WhisperKit.
- `ModelDownloadManager` выбирает Hugging Face repo/subfolder по hardcoded model ID; любой non-Whisper ID сейчас попадает в MLX storage.
- `SettingsView.modelsTab` уже показывает модели, progress, Locate, Use и Delete; metadata/download URL заданы отдельными switch-ами.
- `NativeProcessingReadiness` и обе local ветки `NativeProcessingPipeline` вызывают только `activeWhisperKitModel` и WhisperKit API.
- `NativeProcessingPipeline` сначала режет запись на VaniScript chunks, транскрибирует их последовательно, применяет source glossary, затем запускает translation.
- `Package.swift` имеет deployment target macOS 14 и не содержит FluidAudio; Bolabol закрепляет рабочую зависимость `FluidAudio` exact `0.15.5`.

Следствие: нельзя добавлять три IDs только в `AppSettings.defaults`. Нужен единый descriptor-driven local ASR contract, иначе download, presence, registry и pipeline продолжат считать их WhisperKit/MLX. `[high]`

## 3. Target topology

```text
Settings / Models UI
    │ catalog metadata + install state + OS/language availability
    ▼
NativeModelCatalog (VaniScriptCore)
    ├─ LocalASRModelDescriptor
    ├─ LocalASRBackend
    ├─ LocalASRInstallSource
    ├─ capabilities / required layout
    └─ ASRSourceLanguagePolicy
              │
              ├──────────► ModelDownloadManager
              │              ├─ FluidAudio downloader (Parakeet)
              │              ├─ Hugging Face tree downloader (Canary Flash)
              │              └─ RemoteModelPackageInstaller (Canary 1B)
              │
              ▼
ProviderRegistry / NativeProcessingReadiness
              │ active installed descriptor + explicit source-language preflight
              ▼
NativeProcessingPipeline
    └─ LocalASREngineRouter (one resident ASR engine)
         ├─ WhisperKit adapter                         [existing behavior]
         ├─ ParakeetTranscriptionEngine               [NEW]
         └─ CanaryCoreMLEngine
              ├─ Flash                                [NEW]
              └─ 1B Path B / MLState, macOS 15+       [NEW]
              │
              ▼
    source text/cues → source glossary → existing translation → review/export
```

## 4. Catalog and capabilities

### 4.1 Core types

`NativeModelCatalog.swift` becomes the single non-persisted source of model metadata. `LocalModelState` remains the persisted status/path record; network URLs, capability sets and package hashes are not duplicated into user settings. `[high]`

Required contracts:

```swift
public enum LocalASRBackend: String, Codable, Sendable {
    case whisperKitCoreML
    case fluidAudioCoreML
    case canaryCoreML
}

public enum LocalASRInstallSource: Equatable, Sendable {
    case whisperKit(repositoryID: String, subfolder: String)
    case fluidAudio(version: String, encoderPrecision: String)
    case huggingFace(repositoryID: String, revision: String)
    case remotePackage(RemoteModelPackageRelease)
}

public struct LocalASRCapabilities: Equatable, Sendable {
    public var supportsAutoLanguageDetect: Bool
    public var supportedLanguageCodes: [String]
    public var maxEngineWindowSeconds: Double
    public var minimumMacOSMajor: Int?
    public var approximateDownloadBytes: Int64
}

public struct LocalASRModelDescriptor: Identifiable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var backend: LocalASRBackend
    public var installSource: LocalASRInstallSource
    public var relativeStorageSubpath: String
    public var capabilities: LocalASRCapabilities
    public var requiredLayout: LocalASRRequiredLayout
}
```

Названия иллюстрируют контракт; Coder может согласовать Swift spelling с текущим style, но не должен разносить metadata по `AppSettings`, `SettingsView` и `ModelDownloadManager`. `[med]`

### 4.2 Три catalog entries

| ID | Backend / source | Languages | Auto | Engine window | OS gate | Approx size |
|---|---|---|---|---:|---|---:|
| `parakeet-tdt-06b-v3` | FluidAudio Core ML/ANE; `FluidInference/parakeet-tdt-0.6b-v3-coreml`, SDK `AsrModels` v3 int8 | 25: `bg hr cs da nl en et fi fr de el hu it lv lt mt pl pt ro sk sl es sv ru uk` | yes | 30 s capability | macOS 14 app minimum | ~482 MB |
| `canary-180m-flash-coreml` | Canary Core ML/ANE; HF `aufklarer/Canary-180M-Flash-CoreML` | `en de fr es` | **no** | 10 s | macOS 14 app minimum | ~180 MB |
| `canary-1b-v2-coreml` | Canary Core ML/ANE; app-owned remote package | same 25-language set, incl. `ru`, `uk` | **no** | 15 s | **macOS 15+** | ~1.88 GB for Bolabol working package |

The exact Parakeet SDK artifact and all Canary language/capability values above are taken from working Bolabol code. `[high]` The final Canary 1B archive byte count, package URL and digest remain `[low]` until Human supplies the release package.

### 4.3 Persistence migration

- Add `.canary` to `LocalModelRuntime`; preserve existing raw values for migration-safe decode. `[high]`
- Merge the three defaults into decoded `localAsrModels` exactly as `SettingsDiskStore` already merges default keys; never reset existing WhisperKit paths/selections. `[high]`
- Replace boolean `isWhisper` path verification with descriptor/runtime-aware verification. `[high]`
- `transcriptionProvider` remains a model/provider ID. Selecting any of the three models therefore uses existing settings/session synchronization instead of introducing a second active-model setting. `[high]`

## 5. Install sources and package integrity

### 5.1 Hugging Face and FluidAudio

- **Parakeet:** use FluidAudio `AsrModels.download(to:version:.v3, encoderPrecision:.int8)` and `AsrModels.load`; the HF repository remains catalog/source attribution. This is the working Bolabol path and avoids reimplementing FluidAudio’s private layout. `[high]`
- Pin FluidAudio to the known-working exact `0.15.5` first; upgrades require a separate dependency review because model layout and decode APIs are load-bearing. `[high]`
- **Canary Flash:** use the generic Hugging Face tree downloader against the explicit repo/revision. Validate every relative path before writing, retain directory structure, and do not use “file > 1 KiB” as completeness. `[high]`
- HF revision defaults to a pinned commit or immutable tag captured by ASR-01, not floating `main`, so presence and package layout remain reproducible. `[med]`

### 5.2 Generic remote package for Canary 1B

Do not port `.bolabolCDN` or `cdn.bolabol.app`. Introduce an app-neutral `remotePackage` source with two URL resolution modes: `[high]`

1. Direct archive URL override, e.g. `VANISCRIPT_CANARY_1B_PACKAGE_URL` for a Google Drive direct-download link.
2. Configurable base URL, e.g. `VANISCRIPT_MODEL_PACKAGE_BASE_URL + relativeArchivePath`, for later migration to any Human-controlled static host without code-level vendor naming.

The source is release configuration, not arbitrary end-user input in Settings. UI displays the source label but never accepts an untrusted URL. `[med]`

`RemoteModelPackageRelease` freezes:

- `packageID` and layout version;
- archive URL resolver;
- expected archive SHA-256;
- expected compressed/uncompressed size bounds;
- allowlisted relative files and per-file SHA-256 values;
- exact required engine layout.

The release manifest is app-owned/bundled or otherwise authenticated by an immutable digest in the catalog. A manifest downloaded from the same mutable URL without an independently trusted digest is insufficient. `[high]`

Install algorithm:

1. Resolve direct URL, otherwise configured base URL; fail with an actionable “package source not configured” error.
2. Download to a unique staging directory with progress; follow normal HTTPS redirects.
3. Reject HTML/login/confirmation responses and wrong archive magic. VaniScript does not scrape Google Drive confirmation pages.
4. Verify archive size and SHA-256 before extraction.
5. Extract only into staging; reject absolute paths, `..`, symlinks and any canonical path escaping staging.
6. Verify exact file allowlist, per-file sizes/hashes and required layout.
7. Atomically replace the final model directory only after all checks pass.
8. On cancellation/failure, remove untrusted staging. A previously verified installed package remains untouched.

**Human gate:** ASR-01 cannot close until Human supplies the exact Drive direct URL (or base URL), archive format/layout, archive SHA-256 and package byte sizes. `[low]`

## 6. Storage and presence

Use `SharedModelsRoot`; add explicit runtime directories instead of placing non-Whisper artifacts under `.whisperkit` or `.mlx`. `[high]`

```text
<SharedModelsRoot>/
  whisperkit/…                              # existing
  parakeet/parakeet-tdt-0.6b-v3/           # NEW
  canary/180m-flash/                        # NEW
  canary/1b-v2/                             # NEW
  mlx/…                                     # existing translation
```

Presence is a model-specific completeness predicate, never “directory exists”: `[high]`

- Parakeet: FluidAudio `AsrModels.modelsExist(... .v3, .int8)` plus the SDK layout frozen by ASR-01.
- Canary Flash required minimum: `CanaryEncoder.mlmodelc`, `CanaryPrefill.mlmodelc`, `CanaryDecoder.mlmodelc`, `config.json`, `vocab.json`.
- Canary 1B required minimum for the working Path B engine: `canary_encoder.mlmodelc`, `canary_cross_kv.mlmodelc`, `canary_decoder_kv.mlmodelc`, `canary_spe.model`; final package manifest may add required files but may not remove these without an engine change.
- Canary 1B additionally requires the trusted package manifest/hash contract to match the installed release.

`scanForLocalModels`, Locate, settings reconciliation, provider availability and pipeline lookup must all call the same presence policy. Partial downloads stay removable/retryable but never become Ready/selectable. `[high]`

Delete validates that the destination is the selected descriptor’s child directory under `SharedModelsRoot`, then removes that model directory and clears state. It must not recursively delete a user-selected arbitrary folder. `[high]`

## 7. Engines

### 7.1 Shared app-target contract

Introduce an app-target `LocalASREngine` protocol/result used by `NativeProcessingPipeline`; keep Core catalog/policy free of AVFoundation, Core ML and FluidAudio. `[med]`

Required semantics:

- `transcribe(audioURL:sourceLanguageCode:) async throws -> LocalASRResult`;
- ASR-only output text, optional timestamp cues; no speech-translation flag;
- explicit `unload()` or router-owned release;
- actor isolation: one mutable decoder/model state per engine instance;
- structured errors for missing/incomplete model, unsupported OS/language, audio conversion and empty result.

WhisperKit is wrapped by the same router without changing decode semantics. This removes duplicated “Whisper-only” branches while preserving existing behavior. `[med]`

### 7.2 Shared audio preparation

Port Bolabol’s proven conversion into a neutral `LocalASRAudioPreprocessor`: select the loudest physical channel before downmix, then resample to 16 kHz mono PCM WAV. This avoids cancellation on multichannel recordings and is shared by Parakeet and both Canary variants. `[high]`

The preprocessor writes a unique temporary file, checks a non-trivial result size and deletes it on success/error/cancellation. VaniScript’s existing `AudioChunkExporter` remains responsible for project chunks; the preprocessor handles only engine input format. `[high]`

### 7.3 Parakeet

Port from Bolabol nearly 1:1: `[high]`

- FluidAudio `AsrModels.load(... v3, int8)` → cached `AsrManager`.
- Fresh `TdtDecoderState` per transcription.
- `AsrManager.transcribe` over prepared audio.
- `auto`/empty source means unanchored auto-detect. An explicit supported source may map to FluidAudio `Language` as a hint/filter; stale unsupported values are not passed.
- Empty output is an error.

Adaptation: return VaniScript `LocalASRResult`, use VaniScript logging/temp naming, and obey pipeline residency instead of Bolabol `TranscriptionEngine`/session types.

### 7.4 Canary Flash and Canary 1B

Port the working `CanaryCoreMLEngine` implementation from Bolabol as one family engine with explicit variant dispatch. `[high]`

Common invariants:

- `.cpuAndNeuralEngine` only. Do not use `.all`; Bolabol documents an MPSGraph crash on Flash.
- Explicit source language is mandatory and must be supported by the selected variant.
- ASR only: source token is also decoder target token. No AST route.
- Greedy decode with bounded 256-token loop and empty-result guard.
- Long VaniScript chunks are internally segmented; texts are joined in order. There is no cross-window decoder context.

Flash:

- 10-second max engine window; silence-aware preferred windows from the Bolabol engine.
- Models: `CanaryEncoder`, `CanaryPrefill`, `CanaryDecoder`.
- `config.json` supplies prompt/language/special tokens; `vocab.json` supplies decoder pieces.

1B Path B:

- 15-second windows; `#available(macOS 15.0, *)` at UI, routing and engine load.
- Models: encoder → cross-attention KV → stateful decoder KV.
- Fresh `MLState` per internal audio window; `canary_spe.model` SentencePiece decode.
- The known-bad `alexwengg/canary-1b-v2-coreml` artifact is not a source or fallback.

## 8. Routing and chunk-pipeline adaptation

### 8.1 Descriptor-driven resolution

Replace `activeWhisperKitModel` as the universal local lookup with `activeLocalASRModel(settings:providerID:osVersion:)`. It returns descriptor + verified path only when status, runtime, layout and OS gate agree. `[high]`

`ProviderRegistry` and `NativeProcessingReadiness` use that resolver. A downloaded but incomplete, unsupported-OS or language-incompatible model is unavailable with a specific message; it is never silently replaced by WhisperKit. `[high]`

### 8.2 Pipeline behavior

Both `processCurrentChunk` and `process` use one helper for a local chunk: `[high]`

1. Resolve immutable descriptor/path/source-language plan.
2. Ask `LocalASREngineRouter` for the engine bound to that descriptor and path.
3. Transcribe the `AudioChunkExporter` output.
4. Convert engine timestamps when available; otherwise create the existing whole-chunk fallback cue.
5. Apply source glossary exactly once.
6. Continue through existing translation/review logic.

Canary’s 10/15-second windows are **inside** its engine and do not rewrite persisted VaniScript chunks. Parakeet/Whisper remain compatible with the same outer pipeline. `[high]`

Cloud transcription routing remains first and unchanged. The new local router must not affect cloud usage recording or translation provider selection. `[high]`

### 8.3 Residency

`NativeProcessingPipeline` owns at most one resident local ASR engine. On model/path switch it unloads the previous one. `[med]`

- Batch processing: keep the chosen ASR engine across all outer chunks, then release it before loading/using a local MLX translation model.
- Current-chunk processing: release Canary 1B before local MLX translation; Parakeet/Flash may be cached only if no MLX model is concurrently resident and memory measurements satisfy the acceptance gate.
- Canary 1B is never prewarmed at app launch.
- Cancellation releases temporary audio, decoder state and staged downloads.

This contract prevents an avoidable Canary/WhisperKit + MLX peak without changing the existing sequential product pipeline. `[med]`

## 9. Source-language policy

Catalog capabilities are the source of truth. Normalize UI names/ISO input to lowercase ISO-639-1 before preflight. `[high]`

| Backend | Allowed source selection | Runtime behavior |
|---|---|---|
| Parakeet | `auto` plus its supported explicit codes | `auto` is valid and preferred; explicit supported code is an optional hint |
| Canary Flash | exactly `en`, `de`, `fr`, `es` | no auto; unsupported/missing source blocks Start |
| Canary 1B | exactly its 25 catalog codes | no auto; unsupported/missing source blocks Start |

Rules:

1. Download is independent of source language.
2. Selecting/using Canary exposes a required source-language picker in Settings and workflow configuration.
3. `auto` is not silently converted to English or another default for Canary.
4. A saved source that becomes unsupported leaves the model installed but makes readiness false with an actionable message.
5. Target translation language stays a separate VaniScript setting. Canary never interprets it as an AST target.
6. MCP/session configuration is held to the same policy; UI and automation cannot produce different routing behavior.

## 10. UI download and selection

Keep the existing Models tab visual pattern, but drive it from the descriptor instead of `modelDownloadUrl`/`getModelMeta` switches. `[high]`

Each of the three cards shows:

- model name, runtime badge (`FluidAudio · Core ML/ANE` or `Canary · Core ML/ANE`);
- languages, auto/explicit-source policy, approximate size and macOS gate;
- states: Not installed, Downloading with progress, Ready, Failed/Retry, Unsupported OS;
- actions: Download, Locate, Use, Delete; browser/source action points to HF for Parakeet/Flash and a generic package-source label for 1B.

Specific behavior:

- Canary 1B card remains visible on macOS 14 but Download/Use are disabled with “Requires macOS 15 or later”.
- A partial or hash-invalid package shows Failed and Retry/Delete; never Ready.
- `Use` sets the model ID as `transcriptionProvider` through existing WorkflowStore synchronization.
- If Canary is selected, Settings and `ConfigWorkspaceView` show filtered explicit source choices; Initialize Engine is disabled until a valid source is chosen.
- Parakeet preserves `auto` and does not force a source choice.
- Existing WhisperKit cards and cloud/local provider selectors remain functional.

## 11. Что портируется и что адаптируется

| Area | Port from Bolabol | VaniScript adaptation |
|---|---|---|
| Model IDs/backends/capabilities | IDs, language sets, windows, macOS 15 gate, size estimates | Descriptor integrates with `AppSettings.localAsrModels` and `NativeModelCatalog` |
| Parakeet engine | FluidAudio v3 int8 load/decode, auto policy, audio prep | VaniScript result/cues, router, logging and residency |
| Canary engine | Flash + Path B loaders/frontends/greedy decode, `.cpuAndNeuralEngine`, explicit language | Outer chunk pipeline, VaniScript errors/cues, no Bolabol session types |
| HF download | Safe relative paths, per-file progress and exact completeness | Extend existing `ModelDownloadManager`; pin revision |
| Canary 1B install | Manifest/file integrity concept and atomic completeness | Generic archive package; direct Drive/configurable base URL; no Bolabol CDN enum/name |
| Storage | Separate Parakeet/Canary roots and exact layout checks | `SharedModelsRoot` runtime directories and current settings migration |
| Routing | Backend switch and cached engines | One `LocalASREngineRouter` inside both VaniScript pipeline entry points |
| Language | Canary explicit-source, Parakeet auto | Filtered Settings/config picker and readiness/MCP enforcement |
| UI | Download/progress/Ready/Use/Delete/OS states | Existing `SettingsView.modelsTab`, `WorkflowStore`, provider selector |

## 12. Risks and mitigations

| Risk | Mitigation / gate |
|---|---|
| FluidAudio API/layout drift | Exact `0.15.5` pin; ASR-01 compile/load probe; no upgrade in this track |
| Remote package tampering or partial install | Trusted archive digest + per-file manifest, path/symlink rejection, staging, atomic replace |
| Google Drive link expiry, permission page or large-file confirmation HTML | Direct URL override + configurable base URL; follow redirects; reject HTML/wrong magic; actionable source error; Human supplies stable link |
| Exact Canary 1B package layout is not yet supplied | Human gate before ASR-01 Done; freeze URL, layout, sizes and hashes in release descriptor |
| Model size and insufficient disk | Preflight free space against compressed + staging + uncompressed budget; show ~1.88 GB estimate; retain previous install until atomic success |
| ANE/Core ML memory overlap with WhisperKit or MLX | One resident ASR engine; release before local MLX; no launch prewarm; measure peak in acceptance |
| Canary `.all` computation crash | Force `.cpuAndNeuralEngine`; lock with code-level test/seam and real smoke |
| Outer chunks are minutes while Canary windows are seconds | Internal engine windowing; preserve persisted VaniScript chunk boundaries |
| User leaves `auto` with Canary | Shared language policy blocks readiness; explicit filtered picker; no default fallback |
| Existing ASR state is reset during migration | Merge defaults, preserve raw enum values and installed WhisperKit paths; migration regression tests |

## 13. Acceptance invariants

1. Exactly the three in-scope model IDs are added by this track.
2. All model bytes remain local after user-initiated download; ASR inference makes no network call.
3. Canary is ASR-only and never accepts `auto`.
4. Parakeet accepts auto-detect.
5. Canary 1B cannot download/select/load below macOS 15.
6. Partial, wrong-layout or hash-invalid models are never advertised as Ready.
7. No Bolabol CDN URL/package enum/name is present in VaniScript product code.
8. Both pipeline entry points route all three models and preserve glossary/translation behavior.
9. Existing WhisperKit, cloud transcription and MLX translation remain available.
10. No Python/NeMo/ONNX/MLX ASR runtime is introduced.

## 14. Open Human input

Required before the Canary 1B install coding gate can close:

- exact Google Drive direct-download URL or configured base URL;
- archive format and top-level package layout;
- package release ID/revision;
- compressed and uncompressed byte sizes;
- archive SHA-256 and per-file manifest/hashes.

Until supplied, the architecture and generic installer contract are fixed, but the concrete Canary 1B release descriptor remains `[low]` and must not be represented as downloadable in a production build.
