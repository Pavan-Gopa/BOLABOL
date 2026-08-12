# GigaAM v3 RU Core ML - S6 Spike Report

**Date:** 2026-08-04
**Status:** GO (spike candidate only; product wiring remains S7+ and Human-gated)
**Scope:** Bolabol 1.0.4 evaluation of a community GigaAM v3 Core ML RNN-T export for offline **RU-focused** ASR, per `BOLABOL_ASR_COREML_INTEGRATION_PLAN.md` section 1.1 / S6.

**Verdict in one line:** `huggingfinger0/gigaam-v3-coreml` loaded and decoded native Core ML RNNT on Apple Silicon with a non-empty sensible Russian transcript, blank termination, and approximately 57-68x decode real-time on the test clips. It is a **GO candidate for a later RU-only product path**, not permission to add GigaAM to Bolabol catalog, engine, UI, or Sources during S6.

## Evidence provenance

- **A-class harness evidence:** all runtime claims in this report come from `docs/asr/gigaam-v3/GigaAMCoreMLSpike.swift`, compiled with `xcrun swiftc -O -parse-as-library`. The harness prints the actual input/output names, shapes, valid lengths, transcript, timings, and footprint.
- **Artifact evidence:** HF API/tree metadata, downloaded file sizes, local `metadata.json`, and SHA-256 hashes. Candidate README claims and upstream benchmark claims are not treated as runtime evidence.
- **No quality benchmark claim:** this spike uses two macOS `say`-generated RU clips with known reference text. It does not establish WER, CER, or production quality across speakers/domains.

## 1. Environment

| Item | Value |
|---|---|
| Host | Mac mini, Apple M4, 32 GB RAM |
| OS | macOS 26.5.2 (25F84) |
| Xcode / Swift | Xcode 26.6 (Build 17F113), Swift 6.3.3, arm64 |
| Core ML | `MLModel`, tested with `.cpuAndNeuralEngine`, `.cpuOnly`, and `.all` |
| Harness build | `xcrun swiftc -O -parse-as-library` (no Package target) |
| Audio | 16 kHz, mono, signed 16-bit WAV generated with macOS `say` + `afconvert` |
| Disk before model download | Approximately 11 GiB free |
| Runtime policy | Swift + Core ML + Accelerate only; no external inference runtime |

## 2. Artifact audit

### 2.1 Candidate search and selection

The three candidates from plan section 1.1 were audited through the Hugging Face API before downloading a runtime artifact.

Candidate URLs: `https://huggingface.co/huggingfinger0/gigaam-v3-coreml`, `https://huggingface.co/smkrv/gigaam-v3-e2e-rnnt-coreml`, and `https://huggingface.co/vadimsuhanov/gigaam-v3-e2e-rnnt-coreml`. Upstream references: `https://huggingface.co/ai-sage/GigaAM-v3` and `https://github.com/salute-developers/GigaAM`.

| Candidate | HF revision / reported storage | Published contract | S6 decision |
|---|---|---|---|
| `huggingfinger0/gigaam-v3-coreml` | `db44a79c2244cb9eb8178e383bd1ee92ec7fea25`, 223,472,819 B used storage (about 213.1 MiB payload) | RU, MIT, three `.mlmodelc` bundles, int8 weights, fixed 30 s / 3000 mel-frame encoder, macOS 14 metadata | **Selected and run** |
| `smkrv/gigaam-v3-e2e-rnnt-coreml` | `846833ef075fde2a8e50521d093ddb9ed7b7fd45`, 445,884,153 B (about 425.3 MiB) | RU, fp16 `.mlpackage` encoder/decoder/joint, 30 s contract, separate `tokens.json` and SentencePiece model | Audited, not run; larger and a different package contract was unnecessary after the selected artifact passed |
| `vadimsuhanov/gigaam-v3-e2e-rnnt-coreml` | `0bb1c6b9a045ef9032443ba443ec4436d86db11b`, 890,693,891 B (about 849.5 MiB) | RU, `.mlpackage` encoder/predictor/joiner; validation manifest declares minimum deployment target `macOS26` | Audited, not selected for the macOS 14 product baseline |

The selected artifact is the plan's first candidate, the smallest published bundle, and the only selected option with an explicit macOS 14 Core ML metadata contract. The alternatives remain possible follow-up comparisons; their published validation reports are not runtime evidence in this spike.

### 2.2 Selected artifact contents

Downloaded at the pinned HF revision into `scratch/gigaam-spike/models/` (gitignored):

| File | Bytes on disk | Role |
|---|---:|---|
| `Encoder.mlmodelc/weights/weight.bin` | 221,625,664 | Conformer encoder, mixed Float16/Int8 storage |
| `Predictor.mlmodelc/weights/weight.bin` | 1,160,000 | One-layer RNNT LSTM predictor |
| `JointDecision.mlmodelc/weights/weight.bin` | 685,058 | Fused joint + argmax, emits `token_id` |
| `vocab.txt` | 13,354 | 1,025 entries; `<blk>` is id 1024 |
| Local model directory | 231,936 KiB allocated | Includes Core ML metadata and bundle overhead |

Hashes of the principal payload files:

```text
Encoder weight.bin:       2afb4fbda5ab5a206d3e8614602296619c853526ecd1538f78277751d275da23
Predictor weight.bin:     3404b36092a5d96a15327ecdcf7aa31be0cedb80157b770f36c1be114b6e8ca6
JointDecision weight.bin: 75da0fdfbe8370a8c95d1e3819d4896a9ceb8674fd12fc6c40156e68c0eb1739
vocab.txt:                39abae20e692998290c574e606f11a9edef2902a1995463fcff63d1490cf22b7
```

### 2.3 Metadata honesty and model contract

The candidate README says RU-only, int8 quantization, 16 kHz mono, and a fixed 30 s window. The checked-in Core ML metadata agrees on the important executable facts:

- Encoder input is `audio_signal` Float32 `[1, 64, 3000]`.
- Encoder output is `encoded` Float16 `[1, 768, 750]`.
- Predictor input is `x` Int32 `[1, 1]` plus Float32 `[1, 1, 320]` states; outputs are `dec`, `ho`, and `co`.
- JointDecision inputs are Float32 `[1, 768, 1]` and `[1, 320, 1]`; output is Int32 `token_id` `[1, 1, 1]`.
- All three bundles report `MLModelType_mlProgram`, specification version 8, and macOS 14 availability.
- The model has no valid-length input. The host must compute the valid audio/mel/encoder region and must not decode padded encoder frames.
- The exported RNNT uses blank id 1024, not an EOS token. A frame is complete when the joint emits blank; the harness carries predictor state only after a non-blank emission.

The frontend constants are cross-checked against the upstream `v3_e2e_rnnt.yaml` and the independently documented GigaAM v3 Core ML contract: 64 HTK mel bins, `n_fft=320`, `win_length=320`, `hop_length=160`, `center=false`, no mel normalization, and `log(clamp(mel, 1e-9, 1e9))`. The selected candidate README does not publish a WER/RTFx result, so none is claimed here.

## 3. Load

The three bundles loaded without crash or shape-contract failure on all tested compute selections. The harness printed the expected model names and shapes before inference.

| Compute selection | Observed load | Encoder | RNNT decode | Result |
|---|---:|---:|---:|---|
| `.cpuAndNeuralEngine` | 8.49 s on first cold run; 0.07-0.14 s on later runs | 0.073-0.077 s | 0.056-0.087 s | Pass |
| `.cpuOnly` | 0.96 s | 0.194 s | 0.084 s | Pass |
| `.all` | 8.11 s on first run | 0.075 s | 0.088 s | Pass |

The first ANE and `.all` load include Core ML compilation/cache effects and are not a steady-state benchmark.

## 4. Results

### 4.1 Short RU audio ASR

Both clips were native Swift/Core ML runs with `compute=ane`, `maxSymbols=10`, and `maxTokens=512`.

| Clip | Audio | Valid mel / encoder frames | Tokens | Blank termination | Transcript |
|---|---:|---:|---:|---|---|
| `ru_short.wav` | 59,944 samples / 3.75 s | 373 / 94 | 32 | 94/94 frames, no symbol cap | **Exact:** `Сегодня мы проверяем точность русской диктовки на компьютере Apple` |
| `ru.wav` | 91,784 samples / 5.74 s | 572 / 143 | 44 | 143/143 frames, no symbol cap | Sensible RU text; proper noun variation: `... в приложении Balable` vs reference `... в приложении Болабол` |

This is sufficient for a spike GO signal: the selected graph emits non-empty, linguistically sensible Russian speech text and terminates each valid encoder frame with blank. It is not sufficient for a WER claim. The first clip is an exact TTS reference; the second exposes a reasonable proper-noun error rather than being hidden as an exact match.

### 4.2 Latency and RAM

Measured harness output on the same Apple M4 host:

| Run | Frontend | Encoder | RNNT loop | Decode RTFx | Footprint |
|---|---:|---:|---:|---:|---:|
| `ru_short.wav`, ANE | 0.009 s | 0.077 s | 0.056 s | 67.4x | 25 MiB |
| `ru.wav`, ANE | 0.009 s | 0.073 s | 0.084 s | 68.5x | 27 MiB |
| `ru.wav`, CPU | 0.009 s | 0.194 s | 0.084 s | 68.4x | 25 MiB |
| `ru.wav`, `.all` | 0.009 s | 0.075 s | 0.088 s | 65.4x | 29 MiB |
| `ru_long.wav`, ANE | 0.010 s | 0.074 s | 0.448 s | 67.0x | 56 MiB |

RTFx is calculated against valid audio duration and covers the host-side RNNT loop only. It is a spike measurement, not a product latency SLA. Footprint is `phys_footprint` sampled after decode and varies with Core ML cache state.

### 4.3 Language honesty

- **Product claim:** RU-focused only. This is the only language claim made by this report.
- The HF card declares `language: ru`; the upstream GigaAM v3 line is Russian-focused.
- The vocabulary contains Latin pieces because that is part of the model vocabulary, but this does not establish English or multilingual ASR capability.
- Auto-language detection is not part of this export. A future product descriptor must expose fixed RU routing and `supportsAutoLanguageDetect = false`.
- No AST/speech translation claim is made.

### 4.4 Chunking and fixed window

The harness explicitly caps input at 480,000 samples (30 s), creates the fixed `[1,64,3000]` feature input, computes valid frames from the source samples, and decodes only `ceil(validMelFrames / 4)` encoder frames.

The over-window probe used `ru_long.wav`:

- Source: 504,340 samples / 31.52 s.
- Processed: 480,000 samples / 30 s; the remaining 24,340 samples are not sent to the model.
- Features: 2,999 valid mel frames out of the fixed 3,000 columns.
- Encoder: all 750 frames valid for the capped 30 s window.
- Transcript ends at `... Ещё одно предложение для`, demonstrating first-window truncation rather than silently claiming full-file transcription.

**S7+ constraint:** product dictation must VAD-segment or otherwise chunk audio to <=30 s before this graph. It must not silently drop the tail. Each new segment must reset RNNT predictor state and repeat the true-length calculation. Padding size (`3000` or `750`) must never be used as the valid audio length for a shorter clip.

### 4.5 No Python

The GO evidence path is 100% native Swift + Core ML + Accelerate:

`WAV reader -> HTK log-mel -> Encoder.mlmodelc -> Predictor.mlmodelc + JointDecision.mlmodelc -> blank-greedy RNNT -> vocab.txt`

The harness has no Python, NeMo, PyTorch, NumPy, subprocess, or sidecar inference path. The product Sources were not changed and remain free of GigaAM production wiring.

### 4.6 Optional EN/other languages

Out of scope. No EN or other-language runtime run was used, and no multilingual GigaAM marketing/product claim is permitted by this spike.

## 5. Defects and constraints found

| ID | Finding | Impact |
|---|---|---|
| F1 | Encoder has a fixed `[1,64,3000]` input and no length input/output. | Host integration must calculate true valid encoder frames and avoid padded-tail decode. |
| F2 | Audio longer than 30 s is truncated by the spike window. | S7+ must VAD/chunk before inference and handle segment seams explicitly. |
| F3 | Selected README does not document the exact mel frontend constants. | Keep the upstream config cross-check and add a product regression fixture before wiring. |
| F4 | TTS proper noun `Болабол` became `Balable` in one clip. | No WER claim; product evaluation needs multi-speaker/domain RU audio. |
| F5 | No confidence/log-prob output is exposed by fused JointDecision. | Do not invent confidence UX from token ids; add a separate product quality policy if needed. |

None of these blocks the S6 spike verdict. F1/F2 are explicit S7+ integration constraints, F3/F4 limit the evidence claim, and F5 prevents over-promising quality metadata.

## 6. GO/NO-GO checklist

| Checklist item | Result | Evidence |
|---|---|---|
| 1. Environment | PASS | Section 1; native Apple Silicon harness |
| 2. Artifact audit | PASS | Section 2; pinned revision, sizes, hashes, metadata and candidate comparison |
| 3. Load without crash | PASS | Section 3; CPU, ANE, and `.all` loaded all three bundles |
| 4. Short RU audio ASR | **PASS** | Section 4.1; two non-empty sensible RU transcripts, one exact reference |
| 5. Latency / RAM | PASS | Section 4.2; measured encoder/RNNT timing and footprint |
| 6. Honest language list | PASS | Section 4.3; RU-focused only, no auto-detect or multilingual claim |
| 7. Chunking / window | PASS with constraint | Section 4.4; 31.52 s input capped at 30 s with true frame accounting |
| 8. No Python inference path | PASS | Section 4.5; Swift/Core ML/Accelerate-only harness and QA contract |
| 9. Optional EN/other | OUT OF SCOPE | Section 4.6; deliberately not claimed |
| 10. Verdict | **GO** | This section |

## 7. GO recommendation for S7+

1. Keep the candidate as `gigaam-v3-rnnt-coreml` only after the Human GO list confirms GigaAM for product integration.
2. Reproduce the exact mel frontend in the future native engine and keep a short RU golden fixture; do not copy a Python runtime or make Python a build/runtime dependency.
3. Enforce 16 kHz mono input, <=30 s VAD/chunk boundaries, true valid-frame accounting, RNNT blank id 1024, max-symbol protection, and state reset per segment.
4. Describe the capability as **GigaAM v3 Russian / RU-focused offline ASR**. Do not list English, multilingual, AST, auto-detect, or WER figures from this spike.
5. Add representative multi-speaker RU evaluation and a product-level long-audio seam test before using this candidate for a product quality decision.
6. Keep `scratch/gigaam-spike/` ignored. Do not add model/audio/bin blobs to Git.
7. Do not add catalog, descriptor, download, engine, settings, onboarding, HUD, or product `Sources` changes in S6. Those belong to S7+ after the Human gate.

## 8. Artifacts

| Path | Purpose |
|---|---|
| `docs/asr/gigaam-v3/COREML_SPIKE.md` | This report |
| `docs/asr/gigaam-v3/GigaAMCoreMLSpike.swift` | Native Swift/Core ML/Accelerate harness; no Package target |
| `scratch/gigaam-spike/models/` | Selected HF model bundle, vocab, and README; gitignored |
| `scratch/gigaam-spike/audio/` | `ru.wav`, `ru_short.wav`, and over-window `ru_long.wav`; gitignored |
| `scratch/gigaam-spike/bin/GigaAMCoreMLSpike` | Compiled harness; gitignored |
| `script/qa/check_s6_gigaam_spike.sh` | S6 report/harness/ignore/no-external-path contract |

## 9. Reproduction

```bash
# Build the native S6 harness.
xcrun swiftc -O -parse-as-library -o scratch/gigaam-spike/bin/GigaAMCoreMLSpike \
  docs/asr/gigaam-v3/GigaAMCoreMLSpike.swift

# RU short clip, ANE: exact non-empty transcript and blank termination.
scratch/gigaam-spike/bin/GigaAMCoreMLSpike scratch/gigaam-spike/audio/ru_short.wav \
  modelRoot=scratch/gigaam-spike/models compute=ane maxSymbols=10 maxTokens=512

# CPU and all compute selections: load/decode comparison.
scratch/gigaam-spike/bin/GigaAMCoreMLSpike scratch/gigaam-spike/audio/ru.wav \
  modelRoot=scratch/gigaam-spike/models compute=cpu maxSymbols=10 maxTokens=512
scratch/gigaam-spike/bin/GigaAMCoreMLSpike scratch/gigaam-spike/audio/ru.wav \
  modelRoot=scratch/gigaam-spike/models compute=all maxSymbols=10 maxTokens=512

# Over-window probe: 31.52 s source is capped at 480000 samples / 30 s.
scratch/gigaam-spike/bin/GigaAMCoreMLSpike scratch/gigaam-spike/audio/ru_long.wav \
  modelRoot=scratch/gigaam-spike/models compute=ane maxSymbols=10 maxTokens=512

# S6 structural contract.
bash script/qa/check_s6_gigaam_spike.sh
```

**S6 verdict: GO for `huggingfinger0/gigaam-v3-coreml` as a RU-focused native Core ML spike candidate; NO product integration in S6.**
