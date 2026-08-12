# Canary 1B v2 (FluidInference Core ML) — S4 Spike Report

**Date:** 2026-08-03 (rev. 2 — harness valid-length fix + re-run, S4 fix attempt 1)
**Status:** NO-GO
**Scope:** Bolabol 1.0.4 evaluation of `FluidInference/canary-1b-v2-coreml` (int4 ANE export) as an offline Core ML ASR engine, per BOLABOL_ASR_COREML_INTEGRATION_PLAN.md §1.2 / §4 (S4).
**Supersedes:** B6 spike (`docs/canary/COREML_SPIKE.md`, alexwengg artifact, ADR-012) — a different artifact, evaluated with the same rigor; outcome is the same: the mel frontend is broken.

**Evidence provenance (rev. 2):** all §4 numbers below are split into two classes.
- **(A) harness runs** — `docs/canary/harness/CanaryFluidSpike.swift` (reproducible from source; every run prints `audio_length`, `processed_length`, `encoder_length` and the encoder-mask summary). Rev. 2 fixed the valid-length semantics: `audio_length` is the true valid sample count of the current window after `offset` (padded zero samples are never counted), so short clips no longer masquerade as 15 s.
- **(B) probe scripts** — disposable Swift diagnostics regenerated for rev. 2 with the same correct-length semantics (sources retained at `/tmp/canary_melprobe_fix.swift`, `/tmp/canary_encprobe_fix2.swift`; binaries `/tmp/canary_melprobe_fix`, `/tmp/canary_encprobe_fix2`). The rev. 1 probe numbers quoted in F1/F2 (§5) were produced by binaries whose sources were not retained and whose length semantics could not be audited; they are superseded by rev. 2 numbers. Conclusion is unchanged and now consistent.

---

## 1. Environment

| Item | Value |
|---|---|
| Host | Mac mini, Apple M4, 32 GB RAM |
| OS | macOS 26.5.2 (25F84) — satisfies the int4 deployment target (ios18 / macOS 15+) |
| Xcode / Swift | Xcode 26.6 (Build 17F113), Swift 6.3.3, arm64 |
| Core ML | CoreML framework, `MLModelConfiguration.computeUnits` tested: `.all`, `.cpuAndNeuralEngine` (ANE), `.cpuOnly` |
| Free disk before download | ~14 GiB on /System/Volumes/Data |
| FluidAudio | 0.15.5 pinned in Package.swift (no Canary API on `main`; see §6 F6) |
| Audio corpus | macOS `say` + `afconvert` → 16 kHz mono Int16 WAV: en_short (2.50 s), en_fresh (4.01 s), en (7.86 s), en_long (23.54 s), fr_short (4.20 s), ru (6.33 s), fr (5.27 s) |

## 2. Artifact audit

Source: https://huggingface.co/FluidInference/canary-1b-v2-coreml (sha `75c1b53…`, lastModified 2026-06-17, license cc-by-4.0, gated=false).

| File | Size on disk | Role |
|---|---|---|
| `Preprocessor.mlmodelc` (model.mil + weight.bin 0.9 MB) | ~2.0 MB | waveform `[1,240000]` → mel `[1,128,1501]`, fp32, `func main<ios17>` |
| `EncoderInt4.mlmodelc` (weight.bin 424.7 MiB) | ~445 MB | mel → `[1,1024,188]`, int4, `func main<ios18>` |
| `DecoderInt4.mlmodelc` (weight.bin 81.4 MiB) | ~85 MB | AR transformer → `[1,256,1024]`, int4, `func main<ios18>` |
| `Projection.mlmodelc` (weight.bin 32.0 MiB) | ~34 MB | hidden `[1,1024]` → logits `[1,16384]`, fp16, `func main<ios17>` |
| `vocab.json` | 0.3 MB | 16384 SentencePiece pieces (`id → piece`) |
| `metadata.json` | — | shapes, `eos=3 pad=2 bos=4`, 15 s / 240000 samples / 256 decoder steps |

**Metadata honesty: GOOD (unlike alexwengg).** `metadata.json` matches the MIL program signatures exactly (shapes, dtypes, deployment targets); no fp32-spec-vs-fp16-executable contradiction. Total int4 payload ≈ 541 MB on disk vs README claim ~573 MB — consistent. README claims WER ~2.1 % (LibriSpeech test-clean) and RTFx ~7x, and states fp16 export is byte-identical to NeMo greedy — **none of these could be reproduced** because the frontend defect (§5) blocks any meaningful decode.

**Repo file layout note:** the README/`metadata.json` describe the *intended* contract; the actual MIL matches. `projection_weights.npz` (64 MB, Python reference) was **not** downloaded — the projection path uses `Projection.mlmodelc` (native Core ML), no Python needed.

## 3. Load

All four models load and run on CPU, ANE, and `.all` — no crashes, no shape contract violations:

| Model | Inputs (MIL) | Outputs |
|---|---|---|
| Preprocessor | `audio_signal` fp32 `[1,240000]`, `audio_length` int32 `[1]` | `processed` fp32 `[1,128,1501]`, `processed_length` int32 `[1]` |
| EncoderInt4 | `features` fp32 `[1,128,1501]`, `features_length` int32 `[1]` | `encoder` fp32 `[1,1024,188]`, `encoder_length` int32 `[1]` |
| DecoderInt4 | `input_ids` int32 `[1,256]`, `decoder_mask` fp32 `[1,256]`, `encoder_embeddings` fp32 `[1,188,1024]`, `encoder_mask` fp32 `[1,188]` | `decoder` fp32 `[1,256,1024]` |
| Projection | `hidden` fp32 `[1,1024]` | `logits` fp32 `[1,16384]` |

Prompt contract verified in vocab: `[7,4,16,<src>,<tgt>,5,9,11,13]` (`<|startofcontext|><|startoftranscript|><|emo:undefined|>…<|nodiarize|>`).

## 4. Results

> Rev. 2 note: §4.1–§4.4 and §4.6 numbers are (A) harness output from the fixed harness; F1/F2 diagnostics in §5 are (B) regenerated probe output. Both use correct `audio_length` semantics. The rev. 1 report's "leading-silence offset unlocks 2–4 words of LM-prior fluency" (§4.1 old table) was an artifact of the length bug (the full padded window was passed as valid); with corrected lengths the offset only changes chunk placement, and no run recovers LM-prior text.

### 4.1 Short audio ASR (checklist #4) — FAIL on every language and configuration

Greedy decode (harness `CanaryFluidSpike.swift`, fixed valid-length semantics) was re-run across the corpus with {compute=cpu, ane} × {encMask=derived, all} × {window offset 0 / 120000 / −20000} × {maxTokens 40–60} — 11 runs (table below; ANE/isolate/mask variants in §4.2/§4.6/§5 F3). **Every run produced a repetition loop and never emitted EOS (id 3).**

| Clip (duration on disk) | src→tgt | audio_length (valid) | processed_length | encoder_length | mask (valid/T) | Best output observed |
|---|---|---|---|---|---|---|
| en_short (2.50 s) | en→en | 39 946 | 249 | 32 | 32/188 | `sa sa sa sa …` (60 tok, no EOS) |
| en_short, offset=120000 | en→en | 39 946 | 249 | 32 | 32/188 | `sa sa sa sa …` (no EOS) |
| en_fresh (4.01 s) | en→en | 64 095 | 400 | 50 | 50/188 | `AW sa sa sa …` (no EOS) |
| en_fresh, offset=120000 | en→en | 64 095 | 400 | 50 | 50/188 | `AW sa sa sa …` (no EOS) |
| en_fresh, offset=−20000 (mid-clip) | en→en | 44 095 | 275 | 35 | 35/188 | `sa sa sa …` (no EOS) |
| en (7.86 s) | en→en | 125 767 | 786 | 99 | 99/188 | `Awls, awls, awls …` (no EOS) |
| en_long (23.54 s → 15 s window) | en→en | 240 000 | 1500 | 188 | 188/188 | `Mhm. Mhm. Mhm. …` (no EOS) |
| fr_short (4.20 s) | fr→fr | 67 206 | 420 | 53 | 53/188 | `l'h l'h l'h …` (no EOS) |
| ru (6.33 s) | ru→ru | 101 239 | 632 | 79 | 79/188 | `Там, в котом, в котом, в кварта …` (no EOS) |
| en_short, encMask=all | en→en | 39 946 | 249 | 32 | — | `Si si si …` (no EOS) |

All 10 runs above + the ANE/AST/isolate runs (below) reproduce the same failure: repetition loops, EOS never emitted, no language or configuration yields a transcript. `en_short` with `encMask=all` yields `Si si si …` — mask mode changes loop token, not termination. The offset matrix (0/120000/160000/200054/−20000) changes only where the chunk sits; content never follows audio.

### 4.2 Latency / RAM (checklist #5) — measured, but meaningless for quality since the pipeline is broken

Measured on `en_short` (2.5 s valid, 60-token greedy cap; harness A-class):

| Stage | CPU | ANE |
|---|---|---|
| Model load (first) | 4.35 s | 0.16–0.23 s (ANE bundle compiled lazily at first inference) |
| Preprocessor | 0.004–0.008 s | 0.004–0.007 s |
| Encoder | 0.25–0.64 s (warm 0.25–0.58) | 3.73 s first inference (ANE compile), 0.27 s warm |
| Decoder loop (60 tokens, full 256-seq recompute, no KV cache) | 1.7–2.6 s | 1.9–2.8 s |
| Footprint | 297–322 MiB | 154 MiB |
| Decode RTFx (loop-limited) | 0.6–3.4x (short clips), 7.8x on 15 s window | 0.9–1.3x |

Notes: the ANE path engages (encoder 0.27 s warm vs 0.25–0.58 s CPU; footprint 154 vs 297–322 MiB). README's "RTFx ~7x" is only approached on the fully-padded 15 s window (7.8x measured on `en_long`), and that run is degenerate — RTFx is not a quality figure here and must not be quoted as a product expectation.

### 4.3 Language tokens (checklist #6) — vocab-level PASS, capability claim UNVERIFIED

- Full ISO-639-1 token set present at ids 24–206 (183 tokens, `vocab.json`); the 25-language set claimed by upstream `nvidia/canary-1b-v2` verified by token id: en=64, fr=71, de=78, es=171, bg=46, hr=58, cs=59, da=60, nl=62, et=66, fi=70, el=79, hu=89, it=99, lv=117, lt=120, mt=127, pl=150, pt=151, ro=154, sk=167, sl=168, sv=175, ru=157, uk=192.
- The HF card lists only **en/de/es/fr** — the only claim that can be asserted from the artifact itself.
- No auto-language-detect token mechanism (consistent with plan §2.2: Canary `supportsAutoLanguageDetect = false`; src/tgt are explicit prompt tokens).

### 4.4 Chunking / window (checklist #7) — structurally verified, behaviorally BLOCKED

- Fixed 15 s window: `[1,240000]` samples; audio > 15 s truncates (en_long 23.54 s fed as first 15 s → `audio_length=240000`).
- **Valid-length contract verified end-to-end (A-class).** The fixed harness passes the true valid sample count to `Preprocessor.audio_length`; `processed_length` and `encoder_length` now track real audio:
  - 2.50 s → `audio_length=39946`, `processed_length=249`, `encoder_length=32` (= `ceil(249/8)`)
  - 4.01 s → `processed_length=400`, `encoder_length=50`
  - 4.20 s (fr) → `processed_length=420`, `encoder_length=53`
  - 6.33 s (ru) → `processed_length=632`, `encoder_length=79`
  - 15 s window → `processed_length=1500`, `encoder_length=188` (all 188 frames valid)
  - Mid-clip chunk (offset=−20000, skip 1.25 s) → `processed_length=275`, `encoder_length=35` for 2.76 s valid audio
  - The encoder mask output is consistent: derived mode marks exactly `encoder_length` frames valid and zeroes the rest (e.g. 32/188, 53/188, 188/188).
- The declared output shape is `[1,128,1501]`, but the largest `processed_length` actually produced is **1500** (not 1501) — full-window runs and the rev. 2 probes agree. This is a minor contract nuance, not a defect.
- Beyond the valid length the mel is padded with exact zeros (probe: pad-region exact-zero fraction 0.87).
- FluidAudio's own streaming design (upstream `canary` branch, 2024): 10 s left context + 2 s chunk + 2 s right context; not applicable here — the pinned 0.15.5 has no Canary API and the branch's CanaryManager does not match this export (§6 F6). A long-audio chunk strategy was not validated (frontend blocks any content decode).

### 4.5 No Python (checklist #8) — PASS

Inference path in the harness is 100 % Swift + Core ML + Accelerate: preprocessor → encoder → transpose → decoder greedy loop → Projection.mlmodelc → argmax → SentencePiece join. No NeMo/PyTorch/NumPy runtime, no subprocess spawning. `projection_weights.npz` deliberately not downloaded.

### 4.6 AST (checklist #9) — ATTEMPTED, FAILS (degenerate)

`task=ast src=en tgt=fr` produced `sa sa sa sa …` (60 tokens, no EOS). Language direction tokens are consumed correctly (prompt prints `<|en|> <|fr|>`), but with the broken frontend no speech content reaches the decoder. AST is not claimed by the FluidInference card; upstream model supports AST — untestable in this state.

## 5. Defects found

> Rev. 2: F1/F2 evidence rows are (B) probe output regenerated with correct `audio_length` semantics; F3/F4 are (A) harness output. Rev. 1 probe numbers (73 % zeros, pearson 0.151, cos 0.923/0.731/0.706) came from disposable binaries whose length semantics were not auditable and are superseded by the numbers below; the defect conclusions are unchanged or strengthened.

| # | Defect | Evidence |
|---|---|---|
| F1 | **Mel frontend is broken (no frequency discrimination, no envelope tracking).** Sine-tone probe (2.5 s, true `audio_length=40000`): a 1 kHz tone and a 4 kHz tone activate a diffuse, nearly overlapping channel set (77 vs 71 active channels, 66 in common, all small magnitudes) — a healthy 128-band mel would excite a narrow 1–3-channel band around the tone frequency (≈ch 24 vs ≈ch 66). 67 % of valid-region mel values are exactly `0.0` (pad region 87 %); pearson(model mel frame sums, audio envelope) = **0.009** (preflight threshold > 0.5). | `canary_melprobe_fix` (B) + harness A-class |
| F2 | **Encoder output is content-free (energy-aware but not content-aware).** Mean-pooled valid-frame embeddings: cos(two different EN utterances) = **0.97**, cos(EN, RU) = **0.88** — different utterances/languages produce near-identical embeddings, so the int4 encoder does not extract speech content from the broken mel. cos(speech, silence) = 0.28, cos(silence, white noise) = 0.26 — the encoder only tracks signal presence, not content. | `canary_encprobe_fix2` (B) |
| F3 | **Decoder never terminates: repetition loops without EOS on every input/language/config** — rev. 2 re-run across EN/FR/RU/AST, offsets 0/120000/−20000, encMask derived/all, compute cpu/ane, maxTokens 40–60 (11 runs, §4.1) plus the rev. 1 matrix (offsets 160000/200054, maxTokens 60–150). Isolate experiment (embeddings zeroed, disposable harness variant): the loop persists (`Their, their, their …`, no EOS) — the repetition is not solely an artifact of the broken embeddings; the decoder-side termination failure compounds F1/F2. (Rev. 1 isolate claim "zeroed embeddings → no loops" is **not reproducible** and is superseded.) | harness runs (A) |
| F4 | **README performance/quality claims not reproducible** (RTFx ~7x claimed; only approached on the fully-padded 15 s window — 7.8x measured on `en_long` — and that run is degenerate; WER 2.1 % impossible to verify without working ASR). | harness timings (A) |
| F5 | **Cross-artifact consistency:** the defect class is identical to alexwengg B6 D4 (mel confined to low channels, no frequency discrimination) — two independent exporters produce the same broken audio frontend. | B6 report + this spike |

## 6. GO/NO-GO

**NO-GO.**

| Checklist item | Result |
|---|---|
| 1. Environment | PASS (documented §1) |
| 2. Artifact audit | PASS — metadata honest, sizes consistent (§2) |
| 3. Load | PASS — all 4 models load on CPU/ANE/all (§3) |
| 4. Short audio ASR | **FAIL** — no language yields a transcript; EOS never fires (§4.1) |
| 5. Latency / RAM | Measured but non-representative (§4.2) |
| 6. Language tokens | PASS at vocab level; 25-language capability **not** verifiable (§4.3) |
| 7. Chunking / window | Window contract verified; behavior blocked by F1 (§4.4) |
| 8. No Python | PASS (§4.5) |
| 9. AST | **FAIL** — degenerate (§4.6) |
| 10. Verdict | **NO-GO** |

**Criteria failed:** production ASR requires a valid log-mel frontend, content-bearing encoder embeddings, and EOS-terminated greedy decode. F1–F3 fail all three. The artifacts load and run, the model plumbing (prompt, masks, projection) is sound, and the valid-length contract is correct (rev. 2 verified end-to-end), but the audio pipeline does not carry speech information — the same conclusion as the B6 spike, on the advertised primary artifact.

### Additional structural finding (F6 — integration surface)

FluidAudio 0.15.5 (pinned in Package.swift) exposes **no Canary API** on `main`; CanaryManager exists only on an unmerged 2024 `canary` branch whose contract (14 s window, `audio_features`/`encoder_output`/`hidden_states` I/O names, fp16 embeddings, int32 masks, 128 decoder seq, `projection_weights.bin` + `tokenizer.json` layout) **does not match** the current FluidInference repo export (15 s, `processed`/`encoder`/`decoder` names, fp32 masks, 256 seq, `Projection.mlmodelc` + `vocab.json`). Even a GO would have required a custom adapter, not a drop-in `CanaryManager.load(precision:)` as the README suggests.

## 7. Recommendation (for S7+ / plan update)

1. **Do not** add `canary-1b-v2-coreml` to the production catalog, download UI, engines, or Onboarding cards. Extend the ADR-012 invariant: **both** alexwengg and FluidInference Canary 1B Core ML exports are NO-GO for Bolabol.
2. **Do not** upgrade FluidAudio to the unmaintained `canary` branch; its CanaryManager does not match the current export and the branch is not a release path.
3. Keep 1.0.4 ASR options open via the other spikes: **S5 Canary Flash 180M** (independent converter/artifact — evaluate on its own merits) and **S6 GigaAM v3 RU** (RU-focused product path). Whisper/Parakeet remain the shipping ASR.
4. Revisit Canary 1B Core ML only with a **new export** that passes a minimal preflight: (a) mel envelope correlation > 0.5 and sine-frequency discrimination across the 128-band range; (b) non-looping EOS-terminated EN + second-language transcript. The fix must live in the exporter (mobius `convert-coreml.py` mel path), not in the app.
5. Keep the honest capability stance: card languages en/de/es/fr only; no 25-language claim until a GO artifact exists.
6. Delete `scratch/canary-spike/fi-models` (566 MB) once the decision is recorded (gitignored).

## 8. Artifacts

| Path | Purpose |
|---|---|
| `docs/asr/canary-1b/COREML_SPIKE.md` | This report |
| `docs/canary/harness/CanaryFluidSpike.swift` | S4 harness (Swift/CoreML only; builds with `-parse-as-library`; rev. 2: true valid-length semantics for `audio_length`, offset support, length/mask logging) |
| `docs/canary/harness/CanarySpike.swift` | B6 harness (retained, untouched) |
| `scratch/canary-spike/fi-models/` | FluidInference model set + vocab (gitignored, 566 MB) |
| `scratch/canary-spike/audio/` | Test WAVs incl. new `en_fresh.wav`, `en_long.wav`, `ru.wav` (gitignored) |
| `scratch/canary-spike/bin/CanaryFluidSpike` | Compiled harness (gitignored) |
| `/tmp/CanaryFluidSpike` | Rev. 2 compiled harness (correct-length builds) |
| `/tmp/canary_melprobe_fix.swift`, `/tmp/canary_melprobe_fix` | Rev. 2 mel-frontend probe (F1; correct `audio_length`) |
| `/tmp/canary_encprobe_fix2.swift`, `/tmp/canary_encprobe_fix2` | Rev. 2 embedding probe (F2; valid-frame pooling) |
| `/tmp/CanaryFluidSpike_iso*` | Rev. 2 isolate variant (zeroed embeddings, F3) |
| Rev. 1 disposable probes (`/tmp/canary_sine, canary_melstats, canary_envcorr, canary_cos, canary_iso, …`) | Superseded — sources not retained, length semantics unauditable; numbers replaced by rev. 2 probes |

## 9. Reproduction

```bash
# Build the S4 harness (FluidInference contract, rev. 2 valid-length semantics)
xcrun swiftc -O -parse-as-library -o scratch/canary-spike/bin/CanaryFluidSpike \
  docs/canary/harness/CanaryFluidSpike.swift

# EN ASR (2.5 s) — prints true lengths, then a repetition loop, no EOS
scratch/canary-spike/bin/CanaryFluidSpike scratch/canary-spike/audio/en_short.wav \
  task=asr src=en tgt=en modelRoot=scratch/canary-spike/fi-models compute=cpu maxTokens=60
# expected: audio_length(valid)=39946; processed_length=249; encoder_length=32;
#           encoder mask derived (valid 32/188, zeroed 156); transcript "sa sa sa …"; EOS: false

# Leading-silence chunk (offset=120000): same lengths, same loop ("sa sa sa …")
scratch/canary-spike/bin/CanaryFluidSpike scratch/canary-spike/audio/en_short.wav \
  task=asr src=en tgt=en modelRoot=scratch/canary-spike/fi-models compute=cpu maxTokens=60 offset=120000

# Mid-clip chunk (offset<0 skips the first 1.25 s): valid=44095, mel=275, enc=35
scratch/canary-spike/bin/CanaryFluidSpike scratch/canary-spike/audio/en_fresh.wav \
  task=asr src=en tgt=en modelRoot=scratch/canary-spike/fi-models compute=cpu maxTokens=40 offset=-20000

# Second language (RU, 6.33 s): mel=632, enc=79, loop "Там, в котом, …", no EOS
scratch/canary-spike/bin/CanaryFluidSpike scratch/canary-spike/audio/ru.wav \
  task=asr src=ru tgt=ru modelRoot=scratch/canary-spike/fi-models compute=cpu maxTokens=60

# AST probe — degenerate ("sa sa sa …", no EOS)
scratch/canary-spike/bin/CanaryFluidSpike scratch/canary-spike/audio/en_short.wav \
  task=ast src=en tgt=fr modelRoot=scratch/canary-spike/fi-models compute=cpu maxTokens=60

# ANE path (warm): footprint 154 MiB, encoder 0.27 s
scratch/canary-spike/bin/CanaryFluidSpike scratch/canary-spike/audio/en_short.wav \
  task=asr src=en tgt=en modelRoot=scratch/canary-spike/fi-models compute=ane maxTokens=60

# Rev. 2 diagnostic probes (B-class; sources retained in /tmp, correct lengths):
xcrun swiftc -O -parse-as-library -o /tmp/canary_melprobe_fix /tmp/canary_melprobe_fix.swift
/tmp/canary_melprobe_fix scratch/canary-spike/fi-models
#  -> 1 kHz vs 4 kHz: 77 vs 71 active channels (66 overlap), no narrow-band discrimination;
#     valid-region exact-zero fraction 0.67; pearson(mel, envelope)=0.009
xcrun swiftc -O -parse-as-library -o /tmp/canary_encprobe_fix2 /tmp/canary_encprobe_fix2.swift
/tmp/canary_encprobe_fix2 scratch/canary-spike/fi-models scratch/canary-spike/audio/en_short.wav \
  scratch/canary-spike/audio/en_fresh.wav scratch/canary-spike/audio/ru.wav
#  -> cos(en_short, en_fresh)=0.97; cos(en_short, ru)=0.88; cos(speech, silence)=0.28
```

Key diagnostic evidence (rev. 2, correct valid-length semantics):
- **Mel broken (B):** 1 kHz vs 4 kHz sine → diffuse overlapping channel profiles (77/71 active, 66 overlap); 67 % exact-zero valid-region mel values; pearson(mel, envelope) = 0.009.
- **Encoder content-free (B):** cos(two different EN utterances) = 0.97 > cos(EN, RU) = 0.88 — embeddings do not carry content; they only track signal presence (cos(speech, silence) = 0.28).
- **Decoder loop (A):** `sa sa …` / `l'h l'h …` / `Там, в котом, …` / `Mhm. Mhm. …` — EOS (id 3) never emitted in any of the 11 rev. 2 harness runs (5 languages/AST × compute/offset/mask configs), and persists with zeroed embeddings (`Their, their …`).
