# Architect Handoff — ASR-ARCH

**Track:** `LOCAL_ASR_COREML`  
**Role:** Architect  
**Date:** 2026-08-09  
**Status:** DESIGN COMPLETE; implementation/verification/QA not started.

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

No product code, tests, `STATE.yaml`, git commits/tags, Electron, GigaAM or CPS changes were made.
