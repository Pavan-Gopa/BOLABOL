# Canary 1B Core ML — Fix Plan (S4b)

**Step ID:** `S4b`  
**Status:** Ready to schedule (parallel to Human GO list / Track C for Flash+GigaAM)  
**Goal:** Ship a **Bolabol-hosted**, **preflight-green** Canary 1B v2 Core ML package so product can later download it from **our cloud** (not broken Hugging Face exports).

**Supersedes as candidate runtime:**  
- `FluidInference/canary-1b-v2-coreml` — S4 **NO-GO** (ADR-013)  
- `alexwengg/canary-1b-v2-coreml` — B6 **NO-GO** (ADR-012)

**Does not supersede:** ADR-012/013 remain true for those artifacts. S4b produces a **new** package id (e.g. `bolabol-canary-1b-v2-coreml-r1`).

---

## 0. Internet survey (2026-08-04) — other “Canary 1B Core ML” options?

Survey (HF search `canary`+`coreml`, quantized tree of `nvidia/canary-1b-v2`, FluidAudio issues, ONNX/GGUF/MLX neighbors). **Not a claim of exhaustive eternal truth** — Hub can gain new repos; S4b should re-check before closing DIY.

### 0.1 Core ML packages aimed at Canary **1B v2** (native Apple)

| Repo | Role | Bolabol status |
|------|------|----------------|
| [FluidInference/canary-1b-v2-coreml](https://huggingface.co/FluidInference/canary-1b-v2-coreml) | Official-looking int4 ANE package for FluidAudio | **S4 NO-GO** (ADR-013): mel F1 + decode loops in raw Core ML harness |
| [alexwengg/canary-1b-v2-coreml](https://huggingface.co/alexwengg/canary-1b-v2-coreml) | Early community export (no card) | **B6 NO-GO** (ADR-012): same defect class |
| [smdesai/canary-1b-v2-coreml](https://huggingface.co/smdesai/canary-1b-v2-coreml) | **Third** layout: `canary_preprocessor` + `canary_encoder` + **KV** `canary_decoder_kv` + `canary_cross_kv` + `canary_spe.model` (revision `3002858…`, no model card) | **P0 spiked:** Core ML preprocessor NO-GO; encoder/KV stack is a Path B candidate only |
| [FluidInference/canary-speech-translation-coreml](https://huggingface.co/FluidInference/canary-speech-translation-coreml) | Docs/benchmarks only; **reuses same weights** as FluidInference 1B Core ML | Not a second weight set; claims FLEURS BLEU via **FluidAudio** path (see §0.3) |

### 0.2 Not Core ML / not Bolabol product path (do not confuse)

| Family | Examples | Why not “working Core ML 1B for Bolabol” |
|--------|----------|------------------------------------------|
| **ONNX** | istupakov, Masterx, rcspam, Sarphix sherpa-onnx | Not Core ML; needs ONNX Runtime / other stack |
| **GGUF** | cstr, handy-computer, memoravox | Not Core ML |
| **MLX** | qfuxa/canary-mlx, Mediform/canary-1b-v2-mlx-q8 (mlx-audio) | Apple MLX, **not** Core ML ANE package; product policy is Core ML for this train |
| **Canary-Qwen Core ML** | phequals/canary-qwen-2.5b-coreml-* | **Different model** (Canary-Qwen 2.5B), not nvidia/canary-1b-v2 |
| **Canary Flash Core ML** | aufklarer/Canary-180M-Flash-CoreML | **~180M Flash**, not 1B — already S5 **GO candidate** |
| **NeMo / Python** | nvidia/canary-1b-v2 upstream | Works in research (GPU/CPU NeMo); **no** in-app Python for Bolabol |

### 0.3 Nuance: FluidInference claims “working” benchmarks

`canary-speech-translation-coreml` documents FLEURS BLEU/COMET on **Apple M5 Pro** using the **same** `FluidInference/canary-1b-v2-coreml` weights via **FluidAudio `CanaryManager`**, not via Bolabol’s standalone preprocessor harness.

Implications for S4b:

1. Possible that FluidAudio uses a **different frontend path** (native mel / different length handling) than Core ML `Preprocessor.mlmodelc` as driven by `CanaryFluidSpike`.
2. Possible that a **newer FluidAudio branch** works while pinned **0.15.5** does not expose Canary (S4 F6).
3. Bolabol S4 still stands for **raw Core ML preprocessor → encoder → decoder** as we implemented it (mel preflight failed hard).

**S4b P0 result:** the public `canary` branch's `CanaryManager` explicitly loads and invokes a Core ML preprocessor (`audio_signal` -> `audio_features`) and does not implement a native mel frontend. The pinned `0.15.5` checkout contains no `CanaryManager` or `CanaryModels`. Therefore FluidAudio provides no Path B evidence and is not a package/runtime dependency for S4b.

Do not assume HF README alone = GO for our engine.

### 0.4 Survey conclusion (as of 2026-08-04)

- There is **no third publicly proven GO Core ML 1B export** that Bolabol can adopt as-is.
- Known **1B-v2 Core ML weight trees** on Hub: **FluidInference** (spiked NO-GO raw path), **alexwengg** (NO-GO), **smdesai** (Core ML preprocessor NO-GO; encoder/KV usable only with the separately proven Path B frontend).
- “Working” claims for FluidInference go through **FluidAudio**, not an independent third export.
- S4b P0/P1 result: smdesai's preprocessor reproduces the F1 class (`pearson=0.019`, valid-region zero fraction `0.671`), while native NeMo-style mel feeding its encoder/KV stack passes the mel gate and is the selected **Path B** package path.

---

## 1. What is actually broken (must fix)

From `docs/asr/canary-1b/COREML_SPIKE.md` rev.2 (valid-length harness correct):

| ID | Symptom | Root cause class | Where to fix |
|----|---------|------------------|--------------|
| **F1** | Mel has no frequency discrimination; ~67% zeros in valid region; pearson(mel, envelope) ≈ **0.009** (need **> 0.5**) | **Core ML Preprocessor / mel export** does not implement NeMo Canary frontend | **Exporter** (or Path B native mel) |
| **F2** | Encoder cos(diff EN) ≈ 0.97 — content-free | Almost always **garbage-in from F1**; rare second-order quant bug | Re-test after F1; re-export encoder only if still red |
| **F3** | Decoder loops; **EOS never** (id 3) | Follow-on of F1/F2; isolate still looped | Re-test after F1; decoder export only if still red |
| **F4** | README WER/RTFx not real | Consequence of F1–F3 | No separate fix |
| **F5** | Same defect class as alexwengg | Two bad exporters | Do not use those trees as base “with minor edits” without mel proof |
| **F6** | FluidAudio 0.15.5 has no matching CanaryManager | Integration | **Bolabol engine** in S7–S9; not part of mel fix |

### What is **not** broken (do not waste time)

- Load of Encoder/Decoder/Projection on CPU/ANE (S4 load **PASS**)
- Vocab / prompt token layout (startofcontext … nodiarize) — verified
- Projection as Core ML (no need for `.npz` / Python weights)
- Valid-length plumbing in app harness (rev.2) — **reuse** for preflight
- Desire for custom CDN host — **allowed** once package is GO

### What must **not** be “fixed” only in product UI

Changing Settings, HUD, or download URL **cannot** repair F1.  
A beautiful CDN of the **same** FluidInference preprocessor remains NO-GO.

---

## 2. Fix paths

### Path A — Full Core ML re-export (preferred for “one folder on cloud”)

Rebuild from upstream weights `nvidia/canary-1b-v2` with a **known-good mel** path (mobius `convert-coreml` or equivalent), targeting Apple Silicon.

**Minimum hosted set (example layout):**

```text
bolabol-canary-1b-v2-coreml-r1/
  MANIFEST.json
  LICENSE.txt                 # NVIDIA + export attribution
  metadata.json               # honest shapes, eos/pad/bos, window, OS min
  vocab.json                  # or tokenizer layout engine will use
  Preprocessor.mlmodelc/      # FIXED mel (or omit if Path B)
  Encoder*.mlmodelc/
  Decoder*.mlmodelc/
  Projection.mlmodelc/        # or projection weights if documented
```

**Success condition:** Preprocessor alone passes mel preflight; full pipeline passes ASR preflight.

### Path B — Hybrid (Flash lesson)

S5 Flash worked with **native mel** (NeMo-aligned) + Core ML encoder/decoder, avoiding a broken Core ML preprocessor.

For 1B:

1. Implement / port **verified** Canary 1B log-mel (match NeMo feature extractor: n_mels, hop, window, fmin/fmax, log, normalize).
2. Feed Encoder with tensors matching MIL input (`features` / length contract from S4 or new export).
3. Host package **without** broken Preprocessor, **with** `FRONTEND.md` pinning mel hyperparams + reference vectors.
4. Product engine (S9) must use the **same** mel code path as the spike harness.

Use Path B if re-export of Preprocessor is blocked but Encoder/Decoder are trustworthy **when fed correct mel**.  
Prove with probes: correct Swift mel → encoder embeddings must **not** be content-free (F2 green).

**S4b selection:** Path B was selected after the smdesai preprocessor failed the
same mel gate as the FluidInference export. The smdesai encoder + cross-KV +
stateful KV decoder passed with the native frontend, so the Bolabol package
omits `canary_preprocessor.mlmodelc` and carries `FRONTEND.md` instead.

---

## 3. Preflight gate (GO checklist)

All items required for `BOLABOL_COREML_SPIKE.md` **Status: GO**.

### 3.1 Mel (kills F1)

| Test | Pass criterion |
|------|----------------|
| 1 kHz vs 4 kHz sine (2.5 s, true length) | Narrow mel bands; little channel overlap (healthy: ~1–3 peak channels near expected band) |
| Envelope correlation | pearson(frame energy, |waveform| envelope) **> 0.5** |
| Zero fraction | Valid-region exact-zero rate not pathological (document; not ~0.67 of content frames) |

### 3.2 ASR (kills F3 / end-to-end)

| Test | Pass criterion |
|------|----------------|
| EN short (e.g. “quick brown fox…”) | Non-empty, sensible transcript; **EOS true**; no token loop |
| EN second clip | Same |
| Second language **or** AST | Document result; if only EN GO, capability claim must be EN-only until proven |
| True valid length | Short clip → mel/enc lengths scale with duration (S4 rev.2 style logs) |

### 3.3 Platform / policy

| Test | Pass criterion |
|------|----------------|
| Load | CPU + ANE (or explicit OS gate) |
| No Python | Inference path Swift/Core ML/Accelerate only |
| OS | Document min macOS (int4 often **15+**) |
| License | Redistribution of weights/export allowed for Bolabol CDN; LICENSE in package |

### 3.4 Package integrity

| Item | Pass criterion |
|------|----------------|
| MANIFEST.json | version, created, files[], sha256, sizeBytes, minOS, frontend path A|B |
| gitignore | large bins under `scratch/`; no force-commit of weights |
| Repro | Harness commands in spike doc |

**NO-GO** if any of 3.1–3.2 fail. Cloud upload of a red package is forbidden for product.

---

## 4. Cloud packaging (for “our cloud”, not HF)

### 4.1 Versioning

- Package id: `bolabol-canary-1b-v2-coreml-r{N}`  
- Immutable: never overwrite `r1` in place; ship `r2` if fix continues  
- App later pins `packageId` + expected SHA-256 of MANIFEST or root archive

### 4.2 MANIFEST.json (schema)

```json
{
  "packageId": "bolabol-canary-1b-v2-coreml-r1",
  "modelFamily": "canary-1b-v2",
  "frontend": "coreml-preprocessor | native-nemo-mel",
  "windowSeconds": 15,
  "sampleRate": 16000,
  "minMacOS": "15.0",
  "license": "see LICENSE.txt",
  "upstreamWeights": "nvidia/canary-1b-v2",
  "created": "YYYY-MM-DD",
  "files": [
    { "path": "EncoderInt4.mlmodelc/...", "sha256": "...", "sizeBytes": 0 }
  ]
}
```

### 4.3 Distribution object (Human ops)

Suggested (not committed secrets):

```text
https://<cdn-host>/bolabol/models/canary-1b-v2/r1/MANIFEST.json
https://<cdn-host>/bolabol/models/canary-1b-v2/r1/<file>
# or single .zip/.tar.zst of the folder + MANIFEST inside
```

S4b deliverable: **local package tree + MANIFEST + upload checklist**.  
Live CDN URL may be filled by Human; product download URL is **S8**, after GO.

### 4.4 What product will need later (out of S4b code, in plan)

| Later step | Use of package |
|------------|----------------|
| S7 | Descriptor: id, size, minOS, languages claim, `downloadBaseURL` / packageId |
| S8 | Download + verify SHA-256 + complete-folder presence |
| S9 | `CanaryCoreMLEngine` (custom adapter; **not** FluidAudio canary branch) |
| S10–S12 | UI, OS gate, ranking only if present |

---

## 5. Work breakdown (S4b coder)

| Phase | Work | Exit |
|-------|------|------|
| **P0** | **Survey + triage:** re-list HF Core ML 1B repos; spike **smdesai/canary-1b-v2-coreml** (KV layout); inspect FluidAudio Canary path (native mel vs Preprocessor); reaffirm FI/alexwengg NO-GO | Written triage in FEEDBACK; choose Path A / B / adopt smdesai if GO |
| **P1** | Fix mel (export or native) **or** adopt smdesai if it passes mel+ASR preflight | Mel preflight green |
| **P2** | End-to-end greedy (or KV) decode harness on fixed stack | EOS + sensible EN |
| **P3** | Freeze package tree + MANIFEST + LICENSE for **Bolabol CDN** (not “re-host NO-GO HF as-is”) | Integrity ready |
| **P4** | Write `BOLABOL_COREML_SPIKE.md` GO/NO-GO | Reviewable spike |
| **P5** | Mel/enc probes under `docs/asr/canary-1b/fix/probes/` (not only /tmp) | Reproducible |

### Recommended harness reuse

- Start from `docs/canary/harness/CanaryFluidSpike.swift` (valid-length, logging).  
- Or new `Canary1BBolabolSpike.swift` if I/O names change after re-export.  
- Do not break S4/S5/S6 harnesses or dual-checks.

### Suggested dirs

```text
docs/asr/canary-1b/
  COREML_SPIKE.md              # historical S4 NO-GO (keep)
  FIX_PLAN.md                  # this file
  BOLABOL_COREML_SPIKE.md      # S4b result (create)
  fix/                         # export scripts notes, probe sources
scratch/canary-1b-fix/         # gitignored
  work/                        # intermediate exports
  package/bolabol-canary-1b-v2-coreml-r1/
  audio/
  bin/
```

---

## 6. Explicit non-goals

- Calling the FluidInference HF tree “fixed” by re-hosting unchanged files  
- Product catalog entry before GO  
- Requiring Hugging Face as origin  
- Claiming 25 languages until proven  
- MLX / PyTorch / NeMo **in-app** runtime  

---

## 7. Exit → Orchestrator

| Result | Orchestrator action |
|--------|---------------------|
| **GO** | ADR (accept Bolabol package candidate); may add 1B to Human GO list for S7+; keep HF NO-GO ADRs |
| **NO-GO** | Document residual defects; Flash+GigaAM path unchanged; 1B stays closed |

---

## 8. Relationship to GO-LIST / Track C

- **S4b is independent** of Flash/GigaAM product wiring.  
- Human may ship Flash + GigaAM first; 1B joins when S4b = GO.  
- Or Human prioritizes S4b before S7 if 1B is must-have.

---

## 9. References

- S4 report: `docs/asr/canary-1b/COREML_SPIKE.md`  
- B6 report: `docs/canary/COREML_SPIKE.md`  
- ADR-012, ADR-013 (HF 1B NO-GO)  
- S5 Flash (working pattern Path B): `docs/asr/canary-flash/COREML_SPIKE.md`  
- Plan: `BOLABOL_ASR_COREML_INTEGRATION_PLAN.md` §1.2  
- Step card: `AI_Workflow_Kit/docs/ASR_COREML_STEPS.md` → **S4b**
