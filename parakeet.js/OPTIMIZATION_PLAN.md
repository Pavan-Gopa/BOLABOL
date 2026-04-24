# Parakeet.js – Performance Optimisation Plan

_Last updated: 2025-07-13_

---

## 1. Optimisations already in place

| Area | Change | Effect |
|------|--------|--------|
| Model download | • IndexedDB cache<br/>• Pre-fetch repo file list → skip non-existent `.data` files | zero 404s + faster cold load |
| Backend init | WASM configured with `numThreads = navigator.hardwareConcurrency`, `SIMD = true` | ≈2× speed-up on CPU fall-backs |
| Execution providers | `webgpu` for encoder, **forced `wasm` for decoder** (hybrid) | Decode step time ↓ ~7× |
| Session creation | Encoder session first → decoder after, avoiding double `initWasm()` race | stability + no “backend not available” errors |
| Graph-capture | Enabled for WASM sessions; auto fallback when unsupported | ~15 % faster second run when pure WASM |
| Timing | Always-on performance metrics returned from `transcribe()` and displayed in UI | Core feature for benchmarking & visibility |

## 2. Low-hanging fruit (<1 day each)

1. **Frame batching in decoder**  
   • Process 4–8 encoder frames per `_runCombinedStep` dispatch.  
   • Expected: Decode wall-time ↓ 3–4× with negligible quality drop.

2. **FP16 weights**  
   • Export encoder & decoder with half-precision initialisers.  
   • WASM/ SIMD handles FP16; WebGPU kernels halve VRAM traffic.  
   • Expected: Encode ↓ 20 %, memory ↓ 50 %.

3. **Pre-processing WebWorker**  
   • Move WAV → Float32 + resample into a dedicated worker to overlap with model load.

## 3. Medium effort (days-week)

1. **GPU pre-processor (WGSL)**  
   Implement STFT + Mel-filterbank directly in WebGPU; drop Nemo ONNX.  
   Savings: ~180 ms on 11 s clip.

2. **ORT WebGPU Graph-Capture**  
   Blocked by upstream issue (<https://github.com/microsoft/onnxruntime/issues/17232>).  
   Expected once fixed: Encode ↓ additional 15–20 %.

3. **INT8 path once WebGPU EP supports**  
   Re-enable `.int8.onnx` encoder for bandwidth-limited GPUs.

## 4. Long-term / Research

1. **Transformer decoder**  
   Replace LSTM stack with self-attention; enables single-pass GPU execution.

2. **Speculative streaming / pipelining**  
   Begin decoding mid-utterance; overlap encoder & decoder for <100 ms latency.

3. **Dynamic quantisation + Sparse kernels**  
   Exploit token sparsity in joint network for further speed-ups.

---

> Keep this file updated after each tuning session so we maintain a clear roadmap. 