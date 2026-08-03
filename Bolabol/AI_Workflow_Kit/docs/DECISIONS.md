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

*Add new ADRs at the bottom; do not rewrite history — supersede with new ADR if needed.*
