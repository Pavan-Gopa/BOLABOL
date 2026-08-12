# Canary Core ML Spike (Meta Step B6) — COREML_SPIKE.md

**Date:** 2026-08-03
**Status:** NO-GO — artifact is not usable for production ASR/AST on Apple Silicon
**Scope:** Bolabol 1.0.3 evaluation of https://huggingface.co/alexwengg/canary-1b-v2-coreml

---

## 1. Environment

| Item | Value |
|---|---|
| Host | Mac mini, Apple M4, 32 GB RAM |
| OS | macOS 26.5.2 (25F84) |
| Swift | swiftc (Xcode toolchain), `-O -parse-as-library` harness (no Package target) |
| Core ML | CoreML framework, `computeUnits = .all`, default e5rt/MPSGraph |
| Disk | ~11 GiB free on /System/Volumes/Data (model set already downloaded, 1.8 GB) |
| Model | canary-1b-v2-coreml: `canary_preprocessor.mlmodelc`, `canary_encoder.mlmodelc`, `canary_decoder.mlmodelc` + projection weights (not inside bundles) |

## 2. Artifact audit

- HF page claims ~5.8 GB; the .mlmodelc set actually weighs ~1.95 GB (preprocessor 951 KB,
  encoder 1,577,804,608 B, decoder 302,585,280 B) plus a 67 MB projection weight/bias pair.
  The 5.8 GB figure counts duplicate `.mlpackage` + `.mlmodelc` copies of the same weights.
- No README on the alexwengg repo; no `vocab.json` there (retrieved from
  FluidInference/canary-1b-v2-coreml, 16384 entries, referenced in `assets/`).
- **`metadata.json` mismatch (defect D1):** the bundles claim an fp32 spec-8 export
  (1501 mel frames, 188 encoder frames, 256 decoder seq) but `model.mil` + `coremldata.bin`
  are a coremltools 8.3.0 **fp16 iOS-17 export** (audio_signal `[1,224000]`, mel
  `[1,128,1401]`, encoder `[1,1024,176]`, decoder seq 128, EOS token id 3). No `manifest.plist`.
- **Prompt format (verified against upstream FluidAudio CanaryManager):**
  `[7, 4, 16, <src>, <tgt>, 5, 9, 11, 13]` =
  startofcontext, startoftranscript, emo:undefined, src lang, tgt lang, pnc, noitn, notimestamp, nodiarize.
  No dedicated task token exists in the vocabulary.
- **Languages:** the full ISO-639-1 token set is present at vocab ids 24–206
  (en=64, fr=71, de=78, es=171, ru=157, uk=192, …). The repo's `tokenizer_config.json`
  claims en=64/es=65/de=66/fr=67, which is **wrong** (65=eo, 66=et, 67=ee); our mapping is correct.

## 3. Steps performed

1. Downloaded the complete model set via curl (resume) to `scratch/canary-spike/models/` (1.8 GB).
2. Built the Swift harness `docs/canary/harness/CanarySpike.swift`
   → `scratch/canary-spike/bin/CanarySpike`: full preprocessor → encoder → decoder greedy
   loop with SentencePiece decoding and projection via `cblas_sgemv`.
3. Generated test audio (macOS `say` + `afconvert`, 16 kHz mono PCM):
   `en.wav` (7.86 s), `fr.wav` (5.27 s), `en_short.wav` (2.50 s), `fr_short.wav` (4.20 s).
4. Ran the pipeline and a series of disposable probes (`/tmp/`) to isolate faults:
   length-overflow experiments, encoder-output stats, decoder mask/embedding sensitivity,
   reference log-mel comparison (vDSP), pure-tone frequency mapping, gain sweep.
5. Verified `swift test` (470 tests) still green after the spike.

## 4. Results

### 4.1 Performance (when models run)

| Stage | Time |
|---|---|
| Model load (3 models + projection) | 23.6 s (first load; includes e5rt bundle compilation) |
| Preprocessor | 0.02–0.12 s |
| Encoder | ~0.05 s |
| Decoder step | ~7 ms avg (full 128-seq recompute per step, no KV cache) |
| Decode (119 tokens) | ~0.78 s → RTFx ~3.2× |
| Footprint | ~225–255 MiB (harness reports 444 MiB incl. buffers) |

### 4.2 Confirmed defects

| # | Defect | Evidence |
|---|---|---|
| D1 | `metadata.json` describes fp32 spec-8 export; executable is fp16 iOS-17 export | MIL inspection + CoreML shape queries (section 2) |
| D2 | **fp16 length overflow caps usable audio at ~4.09 s.** `length`/`audio_lengths` are fp16 scalars; >65504 samples → inf → `features_length` garbage (13421773). Even "working" values clamp at 65504. | lenexp probe; fr_short.wav (4.20 s) → `length=13421773` + degenerate output |
| D3 | `encoded_lengths` output is garbage (raw fp16 bit reinterpretation: 4992 for 250 mel frames) | encoder probe; harness works around by deriving `encLen=(features_length+7)/8` |
| D4 | **Mel frontend is broken.** For speech (0.81 peak) only channels 0–35 of 128 are non-zero — exactly 0.0 above — at gains 1×/10×/50×. Pure-tone sweep shows a **linear-Hz** filterbank (not mel-scaled, wrong bandwidth), a constant ~5.5 output floor even during silence, and output content at frames beyond the audio duration (pad region carries input-dependent garbage instead of zeros). A vDSP reference log-mel of the same audio shows energy across all 128 channels (fricatives to 8 kHz). | melstats, tonemap/tonemap2, refmel, gainprobe |
| D5 | **Decoder emits degenerate loops, never content.** All mask/embedding variants tested (`derived`, `all`, `zero`; real/zeroed/transposed embeddings) produce fluent but meaningless text or 80–119-token repetitions without EOS. Language direction is respected (AST en→fr yields French loop "Tricot, tricot…"), confirming decoder plumbing works — the input features are the failure. | harness runs + decprobe series |

### 4.3 What works

- Model loading, shape contracts, fp16 buffer plumbing (channel-major `[D,T]` ↔ frame-major
  `[T,D]` transpose verified).
- Prompt assembly and language tokens (full ISO-639-1 set; en/fr/de/es/ru/uk verified in vocab).
- Decoder self-attention, projection (cblas_sgemv), SentencePiece decode, EOS id 3.
- Mask semantics: `encoder_mask` demonstrably gates cross-attention (different masks →
  different outputs); LM prior is fluent; EOS terminates under `all`-mask.
- The failure is isolated to the **preprocessor + encoder chain** (D2/D4/D5).

## 5. GO/NO-GO

**NO-GO.**

- The advertised 15 s / 224000-sample window is unusable (D2): effective cap ~4.09 s.
- The mel frontend does not produce a valid Canary log-mel (D4): high-frequency energy is
  destroyed, the band mapping is linear-Hz over the wrong bandwidth, and pad regions are
  non-deterministic garbage. Encoder weights trained on true mel features cannot recover
  speech from this input, which matches the observed degenerate decodes (D5).
- `encoded_lengths` and `metadata.json` mismatches (D1, D3) confirm a sloppy/mismatched
  coremltools export chain; there is no trust surface for fixing this at runtime.

## 6. Recommendation

- Do **not** integrate alexwengg/canary-1b-v2-coreml.
- Options for Bolabol 1.0.3 ASR: WhisperKit (already in use for transcription); if Canary
  models are desired, use the FluidInference/FluidAudio Canary manager (`canary` branch)
  which ships a maintained Core ML export path, or run the PyTorch model via mlx.
- Re-verify disk budget: model set occupies 1.8 GB under `scratch/` (gitignored); delete
  `scratch/canary-spike/models` once the decision is recorded.

## 7. Artifacts

| Path | Purpose |
|---|---|
| `docs/canary/harness/CanarySpike.swift` | Spike harness (source of record) |
| `scratch/canary-spike/models/` | Downloaded .mlmodelc set + projection + vocab (gitignored) |
| `scratch/canary-spike/audio/` | Generated test WAVs (gitignored) |
| `scratch/canary-spike/bin/CanarySpike` | Compiled harness (gitignored) |
| `/tmp/lenexp|encstat|encdiff|decprobe|refmel|melstats|tonemap|tonemap2|gainprobe|framemap` | Disposable probes (outside repo, not retained) |

## 8. Reproduction

```bash
# build
xcrun swiftc -O -parse-as-library -o scratch/canary-spike/bin/CanarySpike docs/canary/harness/CanarySpike.swift
# run (en_short.wav, 2.5 s, below the 4.09 s cap)
scratch/canary-spike/bin/CanarySpike scratch/canary-spike/audio/en_short.wav task=asr src=en tgt=en modelRoot=scratch/canary-spike/models
# AST probe (language direction is respected, content is not)
scratch/canary-spike/bin/CanarySpike scratch/canary-spike/audio/en_short.wav task=ast src=en tgt=fr modelRoot=scratch/canary-spike/models
```
