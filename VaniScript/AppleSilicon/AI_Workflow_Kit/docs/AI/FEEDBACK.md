# Architect Handoff — ASR-ARCH

**Track:** `LOCAL_ASR_COREML`  
**Role:** Architect  
**Date:** 2026-08-09  
**Status:** LASR-01 IMPLEMENTED; waiting for independent review/QA gate.

Спроектирован Apple Silicon track ровно для трёх моделей:

1. `parakeet-tdt-06b-v3` — FluidAudio Core ML/ANE, auto-detect allowed.
2. `canary-180m-flash-coreml` — HF Core ML/ANE, explicit EN/DE/FR/ES, ASR-only.
3. `canary-1b-v2-coreml` — generic integrity-checked remote package, explicit 25-language source incl. RU/UK, ASR-only, macOS 15+.

Deliverables:

- `LOCAL_ASR_COREML_ARCHITECTURE.md` — catalog/install/storage/engines/routing/language/UI/residency design.
- `LOCAL_ASR_COREML_STEPS.md` — LASR-01…LASR-09, coding QA gates and separate doc-only closeout.
- `LOCAL_ASR_COREML_ACCEPTANCE.md` — NOT RUN acceptance/smoke skeleton.
- `DECISIONS.md` — ADRs for backend port, install strategy and language/capability policy.

**Open Human input (blocking concrete Canary 1B release):** exact Google Drive direct-download URL or configurable base URL, archive format/top-level layout, package release ID, compressed/uncompressed sizes, archive SHA-256 and per-file manifest/hashes.

---

# Coder Handoff — LASR-01

**Role:** Implementation Engineer
**Status:** `implementation.status: waiting_review`; `next_actor: orchestrator`

## Done

- Added descriptor-driven Core contracts: `LocalASRModelDescriptor`, `LocalASRBackend`, capabilities, required layouts, remote package release metadata and install-source kinds.
- Added exactly three new descriptors: `parakeet-tdt-06b-v3`, `canary-180m-flash-coreml`, and `canary-1b-v2-coreml`; existing WhisperKit IDs remain available as regression metadata.
- Locked Parakeet to FluidAudio v3/int8, Canary Flash to the immutable HF revision `ca44e0f5d816a2362cf01f7316e4932c86aafef6`, and Canary 1B to a neutral remote-package placeholder with no concrete URL, digest or archive metadata.
- Added `.canary` to `LocalModelRuntime` without changing existing raw values; added `.parakeet` and `.canary` shared storage runtimes.
- Added canonical descriptor paths: `parakeet/parakeet-tdt-0.6b-v3`, `canary/180m-flash`, and `canary/1b-v2` below `SharedModelsRoot`.
- Merged new defaults during `AppSettings` decode and preserved existing ASR/MLX state and provider selection. New runtimes are not treated as WhisperKit during legacy disk synchronization.
- Added contract, capability, install-source, Codable migration and canonical-path tests.

## Verification

- `swift build` — PASS.
- `swift test` — PASS: 338 tests in 47 suites.

## Invariants

- No model bytes, downloader behavior, presence scanner, engine, pipeline routing or UI behavior was added.
- Canary models reject `auto`; Parakeet accepts `auto` and its 25 explicit language codes.
- Canary Flash exposes `en/de/fr/es`; Canary 1B exposes the 25-code catalog including `ru/uk` and requires macOS 15+.
- Canary 1B has no concrete archive URL or vendor CDN reference in the product contract.

## FluidAudio Pin Note

- `Package.swift` pins `https://github.com/FluidInference/FluidAudio.git` exact `0.15.5`; `Package.resolved` records revision `19600a485baa4998812e4654b70d2bab8f2c9949`.
- The resolved package declares Swift tools `6.0` and macOS `.v14`; the package `LICENSE` is Apache License 2.0. Its third-party license files remain in the dependency and were not copied into product code.
- FluidAudio is linked at the app target only; Core remains free of engine/download imports for this contract-only step.

## Open Human Input

The concrete Canary 1B release remains intentionally blocked for the later install step until Human supplies the archive URL/base URL, package layout/release ID, sizes, archive SHA-256 and per-file manifest/hashes.

---

# Verification Report — LASR-01

**Role:** Verification Engineer
**Date:** 2026-08-09
**Scope:** Catalog + install-source contracts

### 1. Build and Integration

- `swift build` — PASS (`Build complete`).
- `swift test` — PASS: 338 tests in 47 suites on arm64e macOS 14.
- Existing settings decode, shared paths and cloud/MLX state remain covered by the full suite.
- SwiftPM emitted only a dependency warning for FluidAudio's unhandled checkout `benchmark.md`; no build or test failure.

### 2. Logic and Plan Compliance

- Exactly three new ASR IDs are present: Parakeet, Canary Flash and Canary 1B v2.
- FluidAudio is resolved at exact `0.15.5`; Parakeet is v3/int8 and Canary Flash uses the pinned HF revision.
- Canary models reject `auto`; Parakeet accepts `auto`; Canary 1B has the 25-language catalog and macOS 15 gate.
- Canary 1B uses a neutral `remotePackage` placeholder with no concrete URL, digest or Bolabol CDN reference.
- Canonical Parakeet/Canary runtimes and storage paths are descriptor-backed. No download, presence installer, engine, pipeline or UI behavior was added.
- Diff is limited to the LASR-01 target files plus the required workflow `STATE.yaml` review transition. Pre-tag `local-asr-coreml/pre-LASR-01` exists.

### 3. Security and Contracts

- No token, API key, fake Drive URL or vendor CDN URL was added.
- The remote-package contract stores environment-key names only and leaves release URL/hash/archive fields unbound until the Human gate.
- Existing WhisperKit/MLX/cloud provider selection and paths are preserved during migration-safe decode.

### 4. Comments and Readability

- New catalog contracts have role/API comments and explain the LASR-01 boundary, placeholder intent and canonical-path ownership.
- The synchronization change explicitly documents why native ASR folders are not classified as WhisperKit before LASR-02 presence policy exists.

### 5. Findings

No blocking findings.

**RESULT:** [APPROVED]
