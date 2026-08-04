# Canary 1B v2 Core ML — Bolabol S4b Spike Report

**Date:** 2026-08-04  
**Step:** S4b  
**Status:** GO  
**Scope:** New Bolabol-owned Path B package candidate for offline macOS Core ML.  
**Not product approval:** S7+ adapter, catalog, download UI, and engine wiring remain out of scope.

## 1. Result

S4b is **GO for `bolabol-canary-1b-v2-coreml-r1` as a spike/package
candidate**. The package is not a re-host of either failed Hugging Face
preprocessor export. It uses the smdesai encoder and KV decoder components
with a Bolabol-native NeMo-aligned mel frontend.

The smdesai Core ML preprocessor is explicitly excluded. It fails the same
frontend gate as the FluidInference artifact. The selected Path B frontend
passes frequency discrimination and envelope correlation, and the complete
native Core ML pipeline passes EN ASR and EN->FR AST EOS checks.

The existing ADR-012 and ADR-013 decisions remain unchanged for
`alexwengg/canary-1b-v2-coreml` and `FluidInference/canary-1b-v2-coreml`.

## 2. P0 Triage

### Public options

The 2026-08-04 Hugging Face Core ML search returned these relevant 1B-v2
trees:

| Candidate | P0 result | S4b disposition |
|---|---|---|
| `FluidInference/canary-1b-v2-coreml` | S4 / ADR-013 NO-GO: broken mel and non-EOS raw decode | Do not re-host |
| `alexwengg/canary-1b-v2-coreml` | B6 / ADR-012 NO-GO: same defect class | Do not re-host |
| `smdesai/canary-1b-v2-coreml` | New KV layout; Core ML preprocessor fails; encoder/KV works with Path B | Use only as a component source |

`FluidInference/canary-speech-translation-coreml` is not an independent
weight tree. Its benchmark documentation uses the FluidInference 1B weights
through FluidAudio.

### smdesai spike

Source revision:
`300285867b1757efddab01980c6be9b519bf68fd`.

Downloaded to `scratch/canary-1b-fix/smdesai/` (gitignored, approximately
1.8 GiB). The layout is:

| Component | Contract observed |
|---|---|
| `canary_preprocessor.mlmodelc` | `audio_signal [1,240000]` + `audio_length` -> `mel [1,128,1501]` + `mel_length` |
| `canary_encoder.mlmodelc` | `mel` + `mel_length` -> `enc_states [1,188,1024]` + `encoder_length` |
| `canary_cross_kv.mlmodelc` | `enc_states [1,188,1024]` -> `enc_k`/`enc_v [8,1,8,188,128]` |
| `canary_decoder_kv.mlmodelc` | `token [1,1]`, `pos`, `self_mask`, cross K/V; macOS 15 `MLState`; `log_probs [1,1,16384]` |
| `canary_spe.model` | SentencePiece tokenizer asset |

All four Core ML models loaded on CPU. The same harness also completed with
`.cpuAndNeuralEngine`; the local runtime printed an E5 ANE bundle recompilation
warning but did not fail inference. This is recorded as a runtime warning,
not as a performance claim.

The exported Core ML preprocessor failed:

| Probe | Result | Gate |
|---|---:|---:|
| 1 kHz vs 4 kHz top-three overlap | `2`, profiles not separated | Fail |
| EN short mel/envelope Pearson | `0.019` | Fail, required `> 0.5` |
| EN short valid-region exact-zero fraction | `0.671` | Fail, pathological |

The Core ML preprocessor is therefore not part of the GO package. A CPU run
could produce the language-model-prior sentence for the short clip, but that
does not clear the mel gate and is not accepted as independent evidence for
the exported frontend.

### FluidAudio analysis

- The pinned `FluidAudio` `0.15.5` checkout in `.build/checkouts/FluidAudio`
  contains no `CanaryManager` or `CanaryModels` API.
- The public `canary` branch does contain those types, but
  `CanaryManager` loads and invokes a Core ML preprocessor (`audio_signal` ->
  `audio_features`); it does not implement native mel Path B.
- That branch uses a legacy 14-second / 128-token / projection-weight
  contract and is not the current smdesai 15-second stateful KV contract.
- The branch is not a pinned release dependency and is not used in the
  package.

FluidAudio therefore supplies no new Path B evidence. FluidInference and
alexwengg remain NO-GO as-is.

## 3. Path Chosen

**Path B: native Swift/Accelerate mel + Core ML encoder/KV decoder.**

The frontend is implemented in `CanarySmdesaiSpike.swift` and frozen in the
package's `FRONTEND.md`:

- 16 kHz mono Float32, maximum 240,000 valid samples / 15 seconds.
- Pre-emphasis `0.97`.
- Reflect-centered STFT, 512-point FFT, 400-sample symmetric Hann window,
  160-sample hop.
- 128-band Slaney area-normalized mel bank, 0-8 kHz, power spectrum.
- `log(x + 2^-24)` and per-feature sample normalization with `N - 1` variance
  and `1e-5` epsilon.
- Valid frames `min(floor(validSamples / 160) + 1, 1501)`; padded columns are
  zero and never counted as valid.

The Core ML preprocessor remains loaded and measured by the harness as a
negative control, but it is never fed to the packaged encoder. The selected
native mel tensor is fed directly to the smdesai encoder. Cross-attention K/V
is computed once per window, and the decoder uses a fresh `MLState` for each
independent segment.

## 4. Preflight Evidence

Environment: Apple M4, macOS 26.5.2, arm64, Xcode 26.6 / Swift 6.3.3. The
stateful decoder requires macOS 15 or newer.

### Mel

| Input | Valid samples | Mel frames | Native top channels | Result |
|---|---:|---:|---|---|
| 1 kHz sine | 40,000 | 251 | `[30, 52, 64]` | separated |
| 4 kHz sine | 40,000 | 251 | `[109, 110, 108]` | separated |
| `en_short.wav` | 39,946 | 250 | envelope Pearson `0.701` | PASS |
| `en_fresh.wav` | 64,095 | 401 | envelope Pearson `0.683` | PASS |

The native 1 kHz/4 kHz top-three overlap was `0`; native valid-region exact
zero fraction was `0.000` on both EN clips. The native mel gate is green.
The harness emitted `MEL_PREFLIGHT: PASS` for both native runs.

### ASR / AST

| Clip / task | True audio length | Mel length | Encoder length | Output | EOS |
|---|---:|---:|---:|---|---|
| `en_short.wav`, ASR `en->en` | 39,946 | 250 | 32/188 | `The quick brown fox jumps over the lazy dog.` | true |
| `en_fresh.wav`, ASR `en->en` | 64,095 | 401 | 51/188 | sensible EN: `The quick brown fox jumps over the lazy dog while the weather is nice today.` | true |
| `en_short.wav`, AST `en->fr` | 39,946 | 250 | 32/188 | `Le renard brun saute par-dessus le chien paresseux.` | true |

The decoder stopped before the token cap on all three Path B runs. No
repetition tail was detected. Only EN ASR and EN->FR AST are verified in this
step; no 25-language capability claim is made.

### Platform and policy

| Gate | Result |
|---|---|
| CPU Core ML | PASS; all four components load and run |
| `.cpuAndNeuralEngine` | PASS at harness level; local ANE bundle recompilation warning recorded |
| Valid length | PASS; fixed 240,000 buffer is never used as valid audio length |
| No external runtime | PASS; Swift + Core ML + Accelerate only |
| Minimum OS | macOS 15.0 because decoder uses `MLState` |
| Product boundary | PASS; no `Sources/`, `Package.swift`, catalog, engine, UI, or download wiring |

## 5. Package

Local package root:

```text
scratch/canary-1b-fix/package/bolabol-canary-1b-v2-coreml-r1/
```

Contents:

```text
MANIFEST.json
LICENSE.txt
FRONTEND.md
metadata.json
canary_encoder.mlmodelc/
canary_cross_kv.mlmodelc/
canary_decoder_kv.mlmodelc/
canary_spe.model
```

The package deliberately does **not** contain
`canary_preprocessor.mlmodelc`.

Manifest summary:

| Field | Value |
|---|---|
| package ID | `bolabol-canary-1b-v2-coreml-r1` |
| frontend | `native-nemo-mel` |
| model family | `canary-1b-v2` |
| minimum macOS | `15.0` |
| listed files | 19 |
| package size | approximately 1.8 GiB |
| MANIFEST SHA-256 | `3a258e36b6a71b95e538656569c455a76c302cd7ca69724b3a7075f0f20202a5` |

`docs/asr/canary-1b/fix/package_manifest.sh` generates the inventory. The
S4b run verified every listed file's SHA-256 and byte size successfully.

Human CDN upload checklist:

1. Upload the folder as an immutable object at a new `r1` path; never
   overwrite this package ID.
2. Suggested manifest URL:
   `https://<cdn-host>/bolabol/models/canary-1b-v2/r1/MANIFEST.json`.
3. Upload each listed path under the same base URL, preserving the `.mlmodelc`
   directory trees.
4. Verify the downloaded manifest and every file hash on the CDN host before
   giving S7 a URL.
5. Do not upload the failed FluidInference or alexwengg preprocessor trees as
   an alternate or fallback package.

## 6. Reproduction

Build the standalone probe:

```bash
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx15.0 \
  -o scratch/canary-1b-fix/bin/CanarySmdesaiSpike \
  docs/canary/harness/CanarySmdesaiSpike.swift
```

Run Path B EN ASR:

```bash
scratch/canary-1b-fix/bin/CanarySmdesaiSpike \
  scratch/canary-spike/audio/en_short.wav \
  modelRoot=scratch/canary-1b-fix/smdesai \
  vocabPath=scratch/canary-spike/fi-models/vocab.json \
  frontend=native task=asr src=en tgt=en compute=cpu maxTokens=50
```

Run the second EN clip:

```bash
scratch/canary-1b-fix/bin/CanarySmdesaiSpike \
  scratch/canary-spike/audio/en_fresh.wav \
  modelRoot=scratch/canary-1b-fix/smdesai \
  vocabPath=scratch/canary-spike/fi-models/vocab.json \
  frontend=native task=asr src=en tgt=en compute=cpu maxTokens=50
```

Run the AST probe:

```bash
scratch/canary-1b-fix/bin/CanarySmdesaiSpike \
  scratch/canary-spike/audio/en_short.wav \
  modelRoot=scratch/canary-1b-fix/smdesai \
  vocabPath=scratch/canary-spike/fi-models/vocab.json \
  frontend=native task=ast src=en tgt=fr compute=cpu maxTokens=50
```

Run the ANE contract probe:

```bash
scratch/canary-1b-fix/bin/CanarySmdesaiSpike \
  scratch/canary-spike/audio/en_short.wav \
  modelRoot=scratch/canary-1b-fix/smdesai \
  vocabPath=scratch/canary-spike/fi-models/vocab.json \
  frontend=native task=asr src=en tgt=en compute=ane maxTokens=30
```

The `vocab.json` argument is only a diagnostic id-to-piece map inherited from
the existing ignored S4 corpus. The hosted package carries
`canary_spe.model`; a product adapter must use a native SentencePiece
implementation and must not add an external runtime.

## 7. S7+ Constraints

- Add a custom Bolabol adapter; do not depend on the unmerged FluidAudio
  `canary` branch or `CanaryManager`.
- Gate the package at macOS 15.0 and verify stateful Core ML behavior on the
  shipping Apple Silicon matrix.
- Reuse the exact Path B frontend constants and pass true valid sample/mel/
  encoder lengths. Never pass the padded 15-second buffer as valid audio.
- Segment/VAD audio into windows no longer than 15 seconds and create a fresh
  decoder `MLState` per segment.
- Decode only valid encoder frames, stop on EOS id `3`, cap generation, and
  guard against repeated-token loops.
- Implement native SentencePiece decoding from the packaged
  `canary_spe.model`; do not use the diagnostic `vocab.json` as a product
  dependency.
- Claim only the verified EN ASR and EN->FR AST directions until additional
  language runs pass the same gate.
- Keep product Canary-free until Human GO-list approval and S7-S9. No catalog,
  downloader, settings card, HUD mode, or production engine is part of S4b.
