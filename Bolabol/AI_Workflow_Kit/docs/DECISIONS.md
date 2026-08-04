# ADR Log — Bolabol

> Architecture Decision Records. Format: ADR-NNN — Title.  
> Product plan: `BOLABOL_1.0.3_IMPLEMENTATION_PLAN.md`.

---

## ADR-001 — Native-only ML runtime

**Status:** Accepted  
**Decision:** Runtime uses Core ML + MLX (polish worker) only. No Python, NeMo, PyTorch, ONNX Runtime, pip/venv sidecars.  
**Rationale:** Ship as notarized macOS app; no brittle Python stacks; Apple Silicon native path.

---

## ADR-002 — Product version line 1.0.3

**Status:** Accepted  
**Decision:** Marketing and default `APP_VERSION` for this train is **1.0.3** (not «1.3»).  
**Rationale:** Continuity after 1.0.2 notarized builds; clear patch train for bilingual + Canary.

---

## ADR-003 — Primary + additional speech languages (not «target always»)

**Status:** Accepted  
**Decision:** User model is **primary** (usual dictation language) + **additional** (second frequent language). UI/Help must not imply additional is always the output language.  
**Rationale:** Real bilingual users; avoids mis-setting auto engines and Canary AST.

---

## ADR-004 — Engine language behavior

**Status:** Accepted  
**Decision:**

| Engine | Language behavior |
|--------|-------------------|
| Parakeet / Whisper | Auto-detect by default (HUD **A**) |
| Canary | No auto; HUD **primary letter ↔ additional letter** as speech source |

**Rationale:** Canary needs explicit lang tokens; preserve existing auto UX for other engines.

---

## ADR-005 — Canary Core ML artifact

**Status:** Accepted (spike confirms capability)  
**Decision:** Integrate https://huggingface.co/alexwengg/canary-1b-v2-coreml as the only Canary package for 1.0.3. Language list = whatever spike verifies (honest UI).  
**Rationale:** Pre-exported Core ML; no in-app NeMo conversion.

---

## ADR-006 — Canary is ASR/AST only, not polish

**Status:** Accepted  
**Decision:** Canary produces speech text only. V1/V2 polish remains MLX/cloud after text.  
**Rationale:** Separate concerns; Canary not a polishing model.

---

## ADR-007 — Language picker order

**Status:** Accepted  
**Decision:** English first; then Europe alpha by English name (incl. ru, uk); then Asia/other (ar, zh, hi, ja, ko). System UI language separate.  
**Rationale:** Neutral “large product” ordering — not en→ru as artificial top-2.

---

## ADR-008 — Single master plan document

**Status:** Accepted  
**Decision:** `BOLABOL_1.0.3_IMPLEMENTATION_PLAN.md` is the only full plan. Spike log may live at `docs/canary/COREML_SPIKE.md` after B6. No parallel brief docs.  
**Rationale:** Agents must not drift across split plans.

---

## ADR-009 — Orchestrator hub workflow

**Status:** Accepted  
**Decision:** Multi-agent work uses `AI_Workflow_Kit` hub model: Orchestrator issues all kicks; workers are fresh terminals; only Orchestrator commits/tags/graphify.  
**Rationale:** Proven on DialGent / VaniScript / Torrentino kits; prevents context bleed and commit chaos in monorepo.

---

## ADR-010 — Monorepo scoped checkpoints

**Status:** Accepted  
**Decision:** Git root is `AI Projects/`; checkpoint script stages only `Bolabol/` paths; tags `bolabol/pre-B*`, `bolabol/B*-done`.  
**Rationale:** Avoid committing unrelated monorepo dirty trees (SmartScribe, DialGent, …).

---

## ADR-011 — Canary AST source/target MVP (1.0.3)

**Status:** Accepted (product rule for B9)  
**Decision:**

- HUD R↔E = **source** (speech language) toggles primary ↔ additional.  
- When AST enabled / force translate: target = the **other** of {primary, additional} when they differ; else ASR (source=target).  

**Rationale:** Plan §4.2; testable matrix.

---

---

## ADR-012 — Canary alexwengg Core ML NO-GO for Bolabol 1.0.3

**Status:** Accepted (B6 spike 2026-08-03)  
**Decision:** Do **not** integrate `https://huggingface.co/alexwengg/canary-1b-v2-coreml` into Bolabol product (catalog, engine, HUD Canary mode, download UX).  
**Evidence:** `docs/canary/COREML_SPIKE.md` — defects D1–D5 (metadata mismatch, fp16 length cap ~4.09 s, broken mel frontend, garbage encoded_lengths, degenerate decode). Review APPROVED; Tester qa_green (reproduced D3/D5; `check_b6_canary_spike.sh`).  
**1.0.3 ASR:** Keep WhisperKit / Parakeet / existing engines. Bilingual primary+additional (B1–B5) remains.  
**Steps B7–B10:** **Skipped / cancelled** for this train (product Canary path).  
**Future:** Revisit only with a **different** maintained Core ML export (e.g. FluidInference/FluidAudio Canary path) under the same hard rule: **no Python runtime**. Do not use MLX/PyTorch for in-app ASR.  
**Artifacts retained:** spike doc + harness under `docs/canary/` for audit; model weights stay gitignored under `scratch/canary-spike/` (human may delete ~1.8 GB after decision).

---

## ADR-013 — Canary 1B v2 FluidInference Core ML NO-GO (S4 spike)

**Status:** Accepted (S4 spike 2026-08-03/04; Reviewer re-review APPROVED; Tester qa_green 2026-08-04)
**Decision:** Do **not** integrate `https://huggingface.co/FluidInference/canary-1b-v2-coreml` (int4) into Bolabol 1.0.4 product (catalog, download UX, CanaryCoreMLEngine, Onboarding, HUD). Extends ADR-012: **both** known Canary 1B Core ML exports are NO-GO.
**Evidence:** `docs/asr/canary-1b/COREML_SPIKE.md` rev. 2 (authoritative) + fixed `docs/canary/harness/CanaryFluidSpike.swift` — S4 verdict **NO-GO** with F1–F6. Rev. 2 probe figures (supersede unauditable rev. 1): mel frontend fails frequency discrimination (1 kHz vs 4 kHz diffuse overlapping channels); valid-region exact-zero mel fraction **~0.67**; pearson(mel frame sums, envelope) **= 0.009** (preflight > 0.5); content-free embeddings cos(two EN) **= 0.97**, cos(EN, RU) **= 0.88**; decoder non-EOS loops on EN/FR/RU/AST with true `audio_length` semantics. F6: pinned FluidAudio 0.15.5 has no Canary API; upstream 2024 `canary` branch contract does not match this export. Reviewer re-reproduced short-clip lengths `39946 → 249 → 32` from fixed harness.
**Kept:** metadata.json honest and consistent with MIL; all 4 models load on CPU/ANE; language tokens 24–206 verified in vocab; zero Python inference path.
**1.0.4 ASR:** proceed with S5 (Canary Flash) and S6 (GigaAM v3 RU) spikes; Whisper/Parakeet remain shipping ASR.
**Future:** revisit Canary 1B only with a new export passing preflight: mel envelope correlation > 0.5 + sine frequency discrimination + non-looping EOS-terminated transcript; fix must land in the exporter (mobius mel path), not the app.

---

## ADR-014 — Canary Flash 180M Core ML GO candidate (S5 spike)

**Status:** Accepted as spike candidate (S5 2026-08-04; Reviewer APPROVED; Tester qa_green with runtime EN short EOS)
**Decision:** Record `https://huggingface.co/aufklarer/Canary-180M-Flash-CoreML` (int8 mlprogram of `nvidia/canary-180m-flash`) as a **GO spike candidate** for Bolabol 1.0.4 Canary Flash (EN/DE/FR/ES). **Do not** product-wire catalog/engine/UI until Human GO list after S4–S6 and steps S7+.
**Evidence:** `docs/asr/canary-flash/COREML_SPIKE.md` + `docs/canary/harness/CanaryFlashSpike.swift`; dual-check enforces `**Status:** GO`; product `check_no_canary_product` green; Tester runtime: exact EN short transcript, EOS true.
**Constraints for S7+:** use `.cpuAndNeuralEngine` (not `.all`); NeMo-aligned mel frontend + true length; audio > 10 s needs VAD segmentation; no unverified README WER; harden RTFx/confidence metrics before product UX.
**Contrast:** Canary 1B paths remain NO-GO (ADR-012, ADR-013).
**1.0.4 next:** complete S6 GigaAM spike, then Human GO list for which models enter S7+.



## ADR-015 — GigaAM v3 RU Core ML GO candidate (S6 spike)

**Status:** Accepted as spike candidate (S6 2026-08-04; Reviewer APPROVED with runtime; Tester qa_green)
**Decision:** Record `https://huggingface.co/huggingfinger0/gigaam-v3-coreml` as a **GO spike candidate** for Bolabol 1.0.4 **RU-focused** offline ASR only. **Do not** product-wire catalog/engine/UI/download until Human GO list after S4–S6 and steps S7+.
**Evidence:** `docs/asr/gigaam-v3/COREML_SPIKE.md` + `docs/asr/gigaam-v3/GigaAMCoreMLSpike.swift`; `script/qa/check_s6_gigaam_spike.sh` requires `**Status:** GO` + window/true-length invariants; product boundary green; Reviewer runtime exact RU short transcript.
**Constraints for S7+:** RU-only claim; 16 kHz mono; HTK log-mel frontend; VAD/chunk ≤30 s; per-segment predictor reset; decode only valid encoder frames; blank id 1024; no WER/EN/multilingual/AST/auto-detect claims from this spike; RTFx median protocol if published.
**Contrast:** Canary 1B NO-GO (ADR-012/013); Canary Flash GO candidate (ADR-014).
**1.0.4 next:** Human GO list → Track C S7+ for approved models only.

---

## ADR-016 — Canary 1B reopen via Bolabol-fixed Core ML package (S4b)

**Status:** Accepted (process) — 2026-08-04  
**Decision:** Canary 1B may re-enter the 1.0.4 train **only** as a **new** Bolabol-owned Core ML package that passes S4b preflight (`docs/asr/canary-1b/FIX_PLAN.md`). Hosting may be **Bolabol cloud / CDN** (not Hugging Face). ADR-012 and ADR-013 remain in force for the failed HF exports (`alexwengg`, `FluidInference/canary-1b-v2-coreml`).  
**Must fix first:** F1 mel frontend (exporter or Path B native NeMo mel); then re-validate F2/F3 (embeddings + EOS). App UI/download URL alone cannot clear NO-GO.  
**Product wiring:** only after S4b spike **GO** + Human inclusion on GO list + S7–S9 (custom engine; do not depend on FluidAudio unmerged `canary` branch).  
**Package:** versioned id e.g. `bolabol-canary-1b-v2-coreml-r1` + `MANIFEST.json` SHA-256 per file + LICENSE.  
**Rationale:** User wants large Canary; S4 proved HF int4 stack loads but does not ASR; Flash/GigaAM GO candidates do not replace a fixed 1B if export is repaired correctly.

---
*Add new ADRs at the bottom; do not rewrite history — supersede with new ADR if needed.*
