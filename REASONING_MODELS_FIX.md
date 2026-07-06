# Fix: reasoning models (Qwopus/Opus) leaking thinking into polishing

> ⚠️ **THESE ARE SOURCE EDITS. They do nothing until you rebuild.**
> The running app is still the OLD binary, so every screenshot will look identical
> until you run `swift build` (or rebuild in Xcode) on your Mac. This is the #1
> reason "it still shows reasoning".

## Problem
With Qwen instruct models polishing works. With **Qwopus** (a Qwen fine-tune of Opus-style
reasoning) the result shows the model's English chain-of-thought ("The user wants me to… Analysis:…
Checking for duplicates:"). With the 6/8-bit 9B build it also produces CJK gibberish.

## Root cause (from the code)
1. Qwopus is a reasoning model: it writes its analysis as **plain text** (no `<think>` tags).
2. The MLX worker tries to disable thinking three ways — a "do NOT include your thinking" suffix,
   a `<|think_off|>` prefix, and `additionalContext: enable_thinking=false`. This particular
   fine-tune **ignores all three** (its chat template doesn't read them).
3. The model spends its whole token budget reasoning and is **cut off before the final text**.
4. `ModelOutputSanitizer` finds no final answer and returns `""`.
5. `main.swift` did `sanitized.isEmpty ? rawOutput : sanitized` → it printed the **raw reasoning**.

The CJK gibberish at 6/8-bit is quantization-level degeneration into the Qwen CJK token space,
amplified by sampling. It is **not** a temperature problem — temperature is already hard-wired to
`0.1` in the worker (it is not exposed in Settings).

## Changes made

### A — `Sources/NativeSmartScribePolishWorker/main.swift`
When the sanitizer returns empty, **throw a clear error** instead of dumping the raw chain-of-thought.
The user now sees an actionable message ("model returned only its reasoning… try a non-reasoning
instruct model, or increase the token limit") rather than a wall of English reasoning.

### D — `Sources/NativeSmartScribeCore/Services/ModelOutputSanitizer.swift`
- Added reasoning section labels (`Analysis:`, `Checking for…`, `Input text:`) to the
  chain-of-thought preamble detection.
- The "last paragraph" extractor now **rejects** paragraphs that start with those labels, so a
  truncated reasoning dump resolves to empty (→ error from change A) instead of returning a stray
  reasoning fragment. A genuine final-answer paragraph is still kept.
- Tests added in `Tests/NativeSmartScribeCoreTests/ModelOutputSanitizerTests.swift`:
  - truncated Qwopus screenshot → `""`
  - reasoning + final answer paragraph → returns the answer
  - explicit `Cleaned text:` delimiter → returns the answer

### E — reasoning-model warning
- `Sources/NativeSmartScribeCore/Models/PolishingModelDescriptor.swift`: new computed
  `isReasoningModel` (detects qwopus/gemopus/opus/reasoning, or qwen+think).
- `Sources/NativeSmartScribe/Views/Settings/PolishingSettingsView.swift`: shows an orange warning
  on reasoning-model cards recommending a non-reasoning instruct model.
- Tests in `Tests/NativeSmartScribeCoreTests/PolishingModelReasoningTests.swift`.
- NOTE: the warning string is hardcoded English; localize via `generalSettingsStore.text(...)` if
  desired.

## Direct answers
- **Lower the temperature in the app?** It is not in Settings; it is `0.1` in the worker. Lowering
  it will **not** stop a reasoning model from reasoning, and only marginally helps the gibberish.
- **Other models — as good or better?** Yes. For this short, deterministic polishing task a
  **non-reasoning instruct** model (e.g. a Qwen2.5-Instruct MLX build) is faster and will not leak
  thinking. Reasoning models can be made to work but are a worse fit here.

### B + C — make Qwopus actually finish (added) — `Sources/NativeSmartScribePolishWorker/main.swift`
Diagnosis refinement from the second screenshot: Qwopus's chat template **hard-starts** a `<think>`
block, so `enable_thinking=false` / `<|think_off|>` are ignored. The model then reasons until it
hits the **2048-token cap**, gets cut off before closing `</think>`, and never emits the answer.

- **C (main lever):** `generationTokenLimit` is now reasoning-aware — reasoning models get up to
  **8192** tokens (was capped at 2048) so they can finish thinking *and* produce the final text,
  which the sanitizer then extracts (everything after `</think>` / after the reasoning). Reasoning
  models also run **greedy (temperature 0)** to curb CJK-token drift on quantised builds.
- **B (cheap bonus):** append `/no_think` to the user prompt for Qwen3-family reasoning models.
  Harmless if unrecognised.

Honest expectation: C is the change most likely to make Qwopus usable. But this is a **custom
fine-tune** — if it is trained to always reason and its quant is unstable (the 8-bit/9B CJK
gibberish), it may still be unreliable. The robust path remains a non-reasoning instruct model
(your Qwen3.5-4B already works perfectly).

## Build & test (must run on macOS — MLX is Apple-only, cannot build in this Linux session)
```bash
cd NativeSmartScribe
swift build
swift test            # runs the new sanitizer + reasoning-model tests
```
The sanitizer/descriptor changes are pure-Swift and unit-tested. The worker change needs a real
MLX run on Apple Silicon to confirm the end-to-end error path.
