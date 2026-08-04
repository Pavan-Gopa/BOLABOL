# S4b P0 Triage Notes

Date: 2026-08-04

## Public options

The Hugging Face Core ML survey returned the three relevant 1B-v2 trees:

- `FluidInference/canary-1b-v2-coreml`: S4 / ADR-013 NO-GO.
- `alexwengg/canary-1b-v2-coreml`: B6 / ADR-012 NO-GO.
- `smdesai/canary-1b-v2-coreml`: revision `300285867b1757efddab01980c6be9b519bf68fd`, no model card.

`FluidInference/canary-speech-translation-coreml` is not an independent
weight tree. Its published benchmark claims use the FluidInference 1B weights
through FluidAudio.

## smdesai artifact

Downloaded under `scratch/canary-1b-fix/smdesai/` (gitignored). The tree is
approximately 1.8 GiB and contains:

- `canary_preprocessor.mlmodelc`: raw audio -> `[1,128,1501]` mel.
- `canary_encoder.mlmodelc`: mel + `mel_length` -> `[1,188,1024]` states.
- `canary_cross_kv.mlmodelc`: encoder states -> cross-attention K/V.
- `canary_decoder_kv.mlmodelc`: macOS 15 stateful single-token decoder.
- `canary_spe.model`: tokenizer asset.

All four models load on CPU and with `.cpuAndNeuralEngine`; the latter emits a
local ANE bundle recompilation warning but completes the probe. The Core ML
preprocessor fails S4b mel preflight (`top3 overlap=2`, envelope correlation
`0.019`, valid-region exact-zero fraction `0.671`). It is not included in the
Bolabol package.

The native Path B frontend produces healthy 1 kHz/4 kHz separation and
envelope correlation `0.701` / `0.683` on the two EN clips. The same encoder,
cross-KV, and decoder then produce EOS-terminated EN ASR and EN->FR AST.

## FluidAudio

The pinned `FluidAudio` 0.15.5 checkout contains no Canary API. The public
`canary` branch has `CanaryManager`/`CanaryModels`, but `CanaryManager` invokes
the Core ML preprocessor and expects a different legacy contract. It is not a
native-mel Path B implementation and is not a release dependency.

Conclusion: do not re-host FluidInference or alexwengg unchanged. Use the
smdesai encoder/KV components only as inputs to the Bolabol-owned Path B
package, with the frontend contract frozen in `FRONTEND.md`.
