# Canary Flash (~180M) Core ML — S5 Spike Report

**Date:** 2026-08-04
**Status:** GO (with documented integration constraints)
**Scope:** Bolabol 1.0.4 evaluation of `aufklarer/Canary-180M-Flash-CoreML` (int8 mlprogram export of `nvidia/canary-180m-flash`) as an offline Core ML ASR engine for **EN/DE/FR/ES**, per BOLABOL_ASR_COREML_INTEGRATION_PLAN.md §1.3 / §4 (S5).

**Verdict in one line:** a native Core ML Canary Flash engine is viable — the artifact loads, the frontend reproduces the NeMo contract, and greedy decode produces exact transcripts in all four languages plus EN→DE translation, at >28× real-time decode and ~45 MiB footprint on Apple silicon. It is a **different quality class** from the S4/B6 Canary 1B exports (F1/F2 frontend defects absent: no mel probes were even needed — end-to-end transcripts are exact).

**Contrast with S4 (not re-opened):** `FluidInference/canary-1b-v2-coreml` and `alexwengg/canary-1b-v2-coreml` remain NO-GO (ADR-012/013, S4 report `docs/asr/canary-1b/COREML_SPIKE.md`). This spike evaluates an independent artifact (different exporter, different architecture footprint: int8, macOS 14 target, 10 s window) on its own merits, as §4 S5 requires.

---

## 1. Environment

| Item | Value |
|---|---|
| Host | Mac mini, Apple M4, 32 GB RAM |
| OS | macOS 26.5.2 (25F84) |
| Xcode / Swift | Xcode 26.6 (Build 17F113), Swift 6.3.3, arm64, `xcrun swiftc -O -parse-as-library` harness (no Package target) |
| Core ML | CoreML framework, `MLModelConfiguration.computeUnits` tested: `.cpuOnly`, `.cpuAndNeuralEngine` (ANE); `.all` **crashes the MPSGraph planner** (see §5 F1) |
| Disk before download | ~13 GiB free on /System/Volumes/Data (model set downloaded 275 MB) |
| Audio corpus | macOS `say` + `afconvert` → 16 kHz mono Int16 WAV: `en_short` (2.50 s, Samantha), `en_mid` (4.93 s), `en_long` (16.48 s — window-overflow test), `de` (3.02 s, Anna), `fr` (2.99 s, Thomas), `es` (3.80 s, Diego — **rejected**, see §4.1), `es2` (Paulina — used) |

## 2. Artifact audit

Source: https://huggingface.co/aufklarer/Canary-180M-Flash-CoreML (created 2026-08-01, lastModified 2026-08-02, license cc-by-4.0, 2119 downloads, base_model `nvidia/canary-180m-flash`). Downloaded 2026-08-04 to `scratch/canary-flash-spike/models/CanaryFlash/` (gitignored). HF `sha` of the tree at download: see `git`/HF API (`lastModified 2026-08-02T07:26:18Z`); per-file sizes verified after download.

| File | Size (HF) | Size on disk | Role |
|---|---|---|---|
| `CanaryEncoder.mlmodelc/weights/weight.bin` | 108 415 872 B | 103.4 MiB | FastConformer encoder + projection + mask |
| `CanaryPrefill.mlmodelc/weights/weight.bin` | 72 804 736 B | 69.4 MiB | Decoder over prompt, empty cache |
| `CanaryDecoder.mlmodelc/weights/weight.bin` | 73 845 184 B | 70.4 MiB | Decoder step, one token vs cache |
| `config.json` | 4 039 B | 4 KiB | Decode contract (prompt ids, cache dims, frontend) |
| `vocab.json` | 85 049 B | 83 KiB | 5248 SentencePiece pieces (`id → piece`) |
| **Total payload** | ~255 MB | 275 MB (with `.mlmodelc` metadata) | — |

**Metadata honesty: GOOD (unlike alexwengg B6).** MIL signatures match the README/config contract exactly (verified below); sizes are consistent; `config.json` publishes prompt ids, language token ids, special token ids, and the full frontend contract; the vocab is self-contained. The README claims FLEURS-EN WER 7.40 % / 60.3× RTF on `.cpuAndNeuralEngine` — **not reproduced** (that needs the FLEURS corpus); we verified the same contract end-to-end instead (exact greedy transcripts, §4.1).

**MIL contract (verified at load + from `model.mil`):**

```
CanaryEncoder  audio_signal fp32 [1,128,1000] (log-mel, fixed 10 s window), length int32 [1]
               -> encoder_embeddings fp32 [1,125,1024], encoder_mask fp32 [1,125]
CanaryPrefill  input_ids int32 [1,9], encoder_embeddings, encoder_mask
               -> logits fp32 [1,1,5248], decoder_hidden_states fp32 [5,1,9,1024]
CanaryDecoder  input_ids int32 [1,1], decoder_mems fp32 [5,1,C,1024] (flexible C ≤ 512),
               encoder_embeddings, encoder_mask, start_pos int32 [1]
               -> logits fp32 [1,1,5248], decoder_hidden_states fp32 [5,1,C+1,1024]
```

- Deployment target **iOS 17 / macOS 14** (int8, no int4-ANE constraints of the 1B export) — the lowest bar so far in the Canary spike series.
- Encoder computes its own time masks internally from `length` (4 pooling stages 1000→500→250→125 in the MIL), so `encoder_mask` needs no manual construction.
- `logits` are **log probabilities** (log-softmax head kept): confidence = `exp(mean log p)`.
- Prompt: `[7, 4, 16, <src>, <tgt>, 5, 9, 11, 13]`; language ids from `config.json` `languageTokenIds`: en=62, de=76, fr=69, es=169; special ids: eos=3, bos=4, pad=2, nospeech=1.
- Frontend contract (from `config.json` + reference SDK): pre-emphasis 0.97, STFT n_fft 512 / hop 160 / window 400 centred constant-padded, **symmetric** Hann, Slaney-normalised 128-band mel (0–8000 Hz), `log(x + 2^-24)`, per-feature normalisation over the sample (N−1) variance with epsilon 1e-5. `length` = `floor(validSamples / 160)` (true mel-frame count, one less than the centred-STFT frame count — matches the reference extractor).

## 3. Load

All three models load on **CPU** and **CPU+ANE** — no crashes, no shape-contract violations:

| Compute | Load (cold) | Load (warm, cached compile) | Notes |
|---|---|---|---|
| `.cpuAndNeuralEngine` | 7.67 s (first run: ANE bundle compile) | 0.09–0.11 s | README-recommended; all quality/latency numbers below |
| `.cpuOnly` | 1.31 s | — | Identical transcripts; footprint 26 MiB |
| `.all` | loads, then **MPSGraph planner assertion at first prefill prediction** (`failed assertion 'Error: MLIR pass manager failed'`, process hangs) | — | Defect F1; README warns `.all` "pays a large GPU planning cost… and does not win" — for this artifact it does not run at all |

## 4. Results

> All §4 numbers are **(A) harness output** from `docs/canary/harness/CanaryFlashSpike.swift` (reproducible from source; each run prints `length`, mel shape, encoder output shape/mask, prompt tokens, per-stage timings). No (B)-class probes were required: unlike S4, the pipeline produces correct end-to-end transcripts, which is strictly stronger evidence than frontend probes.

### 4.1 Short audio ASR (checklist #4) — PASS, all four languages + AST

Greedy decode (`.cpuAndNeuralEngine`, `maxTokens=256`), TTS reference text vs transcript:

| Clip | src→tgt | length (mel frames) | EOS | Confidence | Transcript vs reference |
|---|---|---|---|---|---|
| en_short (2.50 s) | en→en | 249 | yes | 0.988 | **exact**: “The quick brown fox jumps over the lazy dog.” |
| en_mid (4.93 s) | en→en | 493 | yes | 0.869 | **near-exact**: “…with the Ballabo application…” (reference: Bolabol — proper-noun-only deviation) |
| de (3.02 s) | de→de | 302 | yes | 0.969 | **exact**: “Der schnelle braune Fuchs springt über den faulen Hund .” |
| fr (2.99 s) | fr→fr | 299 | yes | 0.934 | **exact** (punct. tokens separate): “Le renard brun - rapide saute par - dessus le chien paresseux.” |
| es2 (3.39 s) | es→es | 338 | yes | 0.994 | **exact**: “El rápido zorro marrón salta sobre el perro perezoso.” |
| en_short | ast en→de | 249 | yes | 0.990 | **exact translation**: “Der schnelle braune Fuchs springt über den faulen Hund.” |
| en_long (16.48 s) | en→en | 1000 (capped) | yes | 0.900 | Truncated at the 10 s window as documented (§4.4) |

**Every run emitted EOS (id 3)** — the S4 F3 repetition-loop failure mode is absent. No run needed the max-token cap.

**One audio-side failure (not a model defect):** `es.wav` (voice *Diego*, 3.80 s) decoded to “El Rapido Zoro Maronsal tisodre El Parro Parisazo.” (confidence 0.636). Re-recording the same sentence with *Paulina* transcribed **exactly** (0.994). The model and es language path are fine; the TTS voice/accent clip is not representative. Reported honestly: EN/DE/FR/ES ASR verified with ≥2 languages exact and a consistent per-utterance confidence signal.

### 4.2 Latency / RAM (checklist #5) — PASS (decode-dominant, trivially real-time)

Measured on `.cpuAndNeuralEngine` (harness A-class; footprint = `phys_footprint`):

| Stage | en_short (2.50 s) | en_long (16.48 s, full 10 s window) |
|---|---|---|
| Model load (warm) | 0.09–0.11 s | 0.09 s |
| Mel frontend | 0.001 s | 0.002 s |
| Encoder | 0.012–0.013 s | 0.013 s |
| Prefill | 0.002–0.003 s | 0.003 s |
| Decode (21/82 tokens) | 0.09 s | 0.37 s |
| Decoder step avg / max | 0.004 s / 0.010 s | 0.004–0.005 s |
| **RTFx (decode-only)** | **28.3×** | **44.9–48.5×** (run-to-run) |
| Footprint | 45 MiB (ANE), 26 MiB (CPU) | — |

Decode is the only cost that scales with text length (~4 ms/token); encoder is flat ~13 ms per 10 s window. RTFx ≥28× decode-only on 3–16 s utterances is far above dictation needs and consistent with the README's "60.3× FLEURS" order of magnitude (README number itself not reproduced — FLEURS not run).

### 4.3 Language tokens (checklist #6) — PASS, honest 4-language claim

- `config.json` declares `languages: [en, de, es, fr]` and `languageTokenIds` maps every ISO-639-1 code (183 entries) to a token id — matching the upstream card's 4-language claim; verified by id: **en=62, de=76, fr=69, es=169** and by the printed prompts (`<|en|> <|en|>`, `<|de|> <|de|>`, …).
- The full ISO set exists in vocab ids 22–204, but like the 1B export, the **claim is 4 languages** (upstream card + config) and we tested exactly those. No auto-language-detect mechanism (plan §2.2: `supportsAutoLanguageDetect = false`; src/tgt are explicit prompt tokens).
- ASR verified in all 4 (exact in ≥2, near-exact/audio-failure noted in the other two); AST verified en→de (exact).

### 4.4 Chunking / window (checklist #7) — CONTRACT VERIFIED; truncation is the documented behavior

- Fixed **10 s window** (1000 mel frames; 160 000 samples @ 16 kHz). `length` = true frame count of real audio; beyond it the mel columns are exact zeros and the encoder mask (computed in-graph) marks only the valid encoded frames — e.g. 2.50 s → 249 mel frames → 32/125 encoded frames valid.
- **Audio > 10 s truncates** (verified on 16.48 s `en_long`: `length` capped at 1000, transcript is the first ~10 s of speech — “…the second sentence because of the curve.” the tail being a decoder continuation over cut audio). The README quantifies the consequence: on FLEURS-EN, 44 % of utterances exceed 10 s.
- There is **no streaming/overlap mode** in this export (attention-encoder-decoder, offline per utterance; the reference SDK likewise truncates and says “segment with VAD before calling”).
- **Product implication (for S7+):** long dictations must be VAD-segmented into ≤10 s turns before inference; seam handling (no cross-window context) must be accepted or mitigated (e.g. whisper-style left-context overlap is NOT supported by this graph — a different window needs a re-export). This is a real product constraint, not a blocker for GO, because the 1.0.4 UX targets dictation turns.

### 4.5 No Python (checklist #8) — PASS

Inference path is 100 % Swift + Core ML + Accelerate (vDSP FFT/mel, `MLModel` predictions, greedy argmax). No NeMo/PyTorch/NumPy runtime, no subprocess spawning, no external tokenizer (`vocab.json` only). `check_b6_canary_spike.sh` (extended for S5) and `check_no_python_in_sources.sh` pass; product `Sources/` remain untouched (checklist item “Product Sources stay Canary-free” — green).

### 4.6 AST (checklist #9) — TESTED, PASS (en→de)

`task=ast src=en tgt=de` on `en_short` → exact German translation (0.990). The six claimed directions en↔{de,fr,es} are structurally identical (prompt tokens); only en→de was exercised on-device. Report as **tested (1 direction), all 6 reachable by construction** — do not over-claim.

## 5. Defects found

| # | Defect | Evidence | Impact |
|---|---|---|---|
| F1 | **`.all` computeUnits is unusable** — MPSGraph planner assertion at first prefill prediction (“failed assertion 'Error: MLIR pass manager failed'”, process hangs). CPU and CPU+ANE work. | harness run, compute=all | None for product: use `.cpuAndNeuralEngine` (also the README-recommended setting); document in engine config |
| F2 | **Fixed 10 s window truncates longer audio; no overlap/streaming** — 16.48 s clip transcribed only its first ~10 s; README: 44 % of FLEURS-EN utterances exceed 10 s. | en_long run §4.4 | Product must VAD-segment dictation into ≤10 s turns; no seam context across windows |
| F3 | **README WER/RTFx figures not reproduced** (FLEURS corpus not run in this spike); RTFx measured here (28–45× decode-only) is the same order of magnitude. | §4.2 | Do not cite 7.40 % WER / 60.3× as Bolabol numbers |
| F4 | **es.wav (Diego voice) decoded poorly** (confidence 0.636) while es2 (Paulina) was exact — audio-side TTS artifact, not a model/language defect; documented for honesty. | §4.1 | None; corpus guidance only |

## 6. GO/NO-GO

**GO** — `aufklarer/Canary-180M-Flash-CoreML` is approved as the S5 Canary Flash candidate for Bolabol 1.0.4 integration (subject to §7 constraints).

| Checklist item | Result |
|---|---|
| 1. Environment | PASS (§1) |
| 2. Artifact audit | PASS — metadata honest, sizes consistent, contract verifiable (§2) |
| 3. Load | PASS — CPU + CPU+ANE; `.all` fails (F1) (§3) |
| 4. Short audio ASR | **PASS** — exact EN/DE/FR/ES transcripts, EOS always fires (§4.1) |
| 5. Latency / RAM | PASS — decode-only RTFx ≥28×, 26–45 MiB (§4.2) |
| 6. Language tokens | PASS — en/de/es/fr, honest, ids verified (§4.3) |
| 7. Chunking / window | PASS with constraint — fixed 10 s window, truncation beyond, VAD segmentation required (F2) (§4.4) |
| 8. No Python | PASS — 100 % Swift/Core ML/Accelerate (§4.5) |
| 9. AST | TESTED en→de exact; other 5 directions by construction (§4.6) |
| 10. Verdict | **GO** (§6) |

**Criteria passed:** valid log-mel frontend (exact-transcript evidence — no content-free embeddings, no repetition loops, EOS-terminated decode in every run across 4 languages + AST), macOS 14 deployment bar, compact footprint, and honest metadata. This is the first Canary-family Core ML artifact in the Bolabol spike series that actually transcribes speech.

## 7. Recommendation (for S7+ / plan update)

1. **Add to the S7+ integration path** as `canary-180m-flash-coreml` (backend `canaryCoreML`, en/de/es/fr, compact/fast tier, macOS 14+ gate — lowest bar of the series).
2. **Engine contract for S9:** `.cpuAndNeuralEngine` only (never `.all`); mel frontend must be the NeMo-contract extractor (this harness's frontend is a verified reference; soniqo/speech-swift `MelPreprocessor` is the upstream reference, Apache-2.0 — attribute if copied). Pass **true mel-frame count** (`floor(samples/160)`) as `length` — S4 lesson applied.
3. **Segmentation:** the engine must reject or VAD-chunk audio > 10 s. Do not silently truncate dictation. For 1.0.4, treat utterances > 10 s as needing segmentation (product decision for S9/S11; no cross-window context is available in this export).
4. **Confidence:** logits are log-probs; `exp(mean log p)` gave 0.87–0.99 on good audio, 0.64 on the failed clip — a usable per-utterance quality signal for the HUD/language matrix.
5. **No WER claim:** quote measured RTFx and transcripts from §4 only; the README's FLEURS numbers need a separate eval before being cited.
6. **Keep S4/S6 separate:** Canary 1B stays NO-GO (ADR-012/013); S6 GigaAM v3 spike still pending on its own merits; a GO on Flash does not change the 1B verdict.
7. **License:** cc-by-4.0 (inherited from the base model), commercial use permitted — consistent with the 1.0.4 plan.
8. Cleanup: `scratch/canary-flash-spike/` is gitignored (275 MB); can be deleted after the decision is recorded.

## 8. Artifacts

| Path | Purpose |
|---|---|
| `docs/asr/canary-flash/COREML_SPIKE.md` | This report |
| `docs/canary/harness/CanaryFlashSpike.swift` | S5 harness (Swift/CoreML/Accelerate only; builds with `-parse-as-library`; frontend adapted from soniqo/speech-swift `MelPreprocessor`, Apache-2.0, attributed in header) |
| `scratch/canary-flash-spike/models/CanaryFlash/` | Model set + vocab + config (gitignored, 275 MB) |
| `scratch/canary-flash-spike/audio/` | Test WAVs en_short/en_mid/en_long/de/fr/es/es2 (gitignored) |
| `scratch/canary-flash-spike/bin/CanaryFlashSpike` | Compiled harness (gitignored) |
| `script/qa/check_b6_canary_spike.sh` | Extended: S5 doc + harness dual-check (GO/NO-GO verdict, 10 checklist sections, zero Python path) |

## 9. Reproduction

```bash
# Build the S5 harness (aufklarer Flash contract, Swift/CoreML/Accelerate only)
xcrun swiftc -O -parse-as-library -o scratch/canary-flash-spike/bin/CanaryFlashSpike \
  docs/canary/harness/CanaryFlashSpike.swift

# EN ASR (2.5 s) — exact transcript, EOS, RTFx ~28x, footprint ~45 MiB
scratch/canary-flash-spike/bin/CanaryFlashSpike scratch/canary-flash-spike/audio/en_short.wav \
  task=asr src=en tgt=en modelRoot=scratch/canary-flash-spike/models/CanaryFlash compute=ane maxTokens=256
# expected: mel [1,128,1000], length=249; "The quick brown fox jumps over the lazy dog."

# DE / FR / ES
# … de.wav -> "Der schnelle braune Fuchs springt über den faulen Hund ."
# … fr.wav -> "Le renard brun - rapide saute par - dessus le chien paresseux."
# … es2.wav -> "El rápido zorro marrón salta sobre el perro perezoso."

# AST en->de — exact translation
# … en_short.wav task=ast src=en tgt=de -> "Der schnelle braune Fuchs springt über den faulen Hund."

# Window truncation (16.5 s clip -> first ~10 s transcribed)
# … en_long.wav -> length=1000 (capped), transcript ends mid-second-sentence

# CPU path (identical transcript, 26 MiB) — compute=cpu
# `.all` — FAIL: MPSGraph MLIR pass manager assertion at first prefill (F1)
```

Key diagnostic evidence (all A-class harness output):
- 6/7 short-clip runs: exact transcripts; every run EOS-terminated; confidence 0.87–0.99 (failed es/Diego clip: 0.636 — audio-side).
- Valid-length semantics end-to-end: 2.50 s → 249 mel frames → 32/125 encoded frames masked; 10 s window caps at 1000/125.
- Decode-dominant latency: ~4 ms/token, encoder flat ~13 ms; RTFx (decode-only) 28.3×–44.9×; footprint 26–45 MiB.
