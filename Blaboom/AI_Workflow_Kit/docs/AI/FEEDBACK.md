# FEEDBACK — Blaboom 1.0.3

> Workers fill sections on handoff. Orchestrator reads this every «статус».

---

## Meta

| Field | Value |
|-------|--------|
| Step | B6 |
| Actor | reviewer |
| Timestamp | 2026-08-03 |
| RESULT | `approved` |

---

## §1 — Build / commands (Coder)

Commands run and outcomes:

```bash
cd "/Users/pavan/Documents/AI Projects/Blaboom"

# Build spike harness
xcrun swiftc -O -parse-as-library -o scratch/canary-spike/bin/CanarySpike docs/canary/harness/CanarySpike.swift

# Spike harness test runs (short audio < 4.09 s cap)
scratch/canary-spike/bin/CanarySpike scratch/canary-spike/audio/en_short.wav task=asr src=en tgt=en modelRoot=scratch/canary-spike/models
scratch/canary-spike/bin/CanarySpike scratch/canary-spike/audio/en_short.wav task=ast src=en tgt=fr modelRoot=scratch/canary-spike/models

# Suite verification
swift test       # ✔ 470 tests in 4 suites passed
```

No `git commit` / `git push`.

---

## §2 — Step compliance (Coder)

- [x] Spike evaluation performed using native Swift harness (`docs/canary/harness/CanarySpike.swift`).
- [x] SPIKE document written: `docs/canary/COREML_SPIKE.md` with explicit NO-GO decision based on defects D1–D5:
  - D1: `metadata.json` describes fp32 spec-8 export; executable model is fp16 iOS-17 export.
  - D2: **fp16 length overflow caps usable audio at ~4.09 s** (>65504 samples → inf → garbage `features_length`).
  - D3: `encoded_lengths` output is bit-reinterpreted garbage (4992 for 250 mel frames).
  - D4: **Mel frontend is broken** (linear-Hz filterbank instead of log-mel, channels 36–127 zeroed out, non-zero output floor on silence, pad region garbage).
  - D5: **Decoder emits degenerate loops, never real transcript content** due to corrupted mel input features.
- [x] NO product Canary integration added (no changes under `Sources/` or app target; spike code isolated under `docs/canary/` and `scratch/`).
- [x] Recommendation documented: Do not use `alexwengg/canary-1b-v2-coreml`. Keep WhisperKit for Blaboom 1.0.3 ASR, or consider FluidInference/FluidAudio Canary manager if Canary model support is required in future releases.
- [x] Model artifacts gitignored under `scratch/canary-spike/`.
- [x] `swift test` GREEN — 470/470.
- [x] No Python runtime path used for harness or evaluation.
- [x] No `git commit` / `git push`.

---

## §3 — Invariants (Coder)

- ZERO Python dependency: spike execution, model loading, log-mel frontend testing, and SentencePiece token decoding implemented purely in native Swift/CoreML/Accelerate.
- Main package integrity preserved: 0 edits to `Sources/**`, main test suite passes 470/470.
- GO/NO-GO status strictly grounded in empirical evidence (defects D1–D5).
- Model files stored in gitignored local scratch directory (`scratch/canary-spike/models/`).

---

## §4 — Comments / structure (Coder)

- `docs/canary/COREML_SPIKE.md`: complete evaluation report documenting environment, artifact audit, steps performed, detailed defect analysis (D1–D5), GO/NO-GO verdict, recommendation, artifacts table, and reproduction commands.
- `docs/canary/harness/CanarySpike.swift`: Swift harness implementing preprocessor -> encoder -> decoder -> projection pipeline using CoreML, Accelerate (cblas_sgemv), and vDSP.

---

## §5 — Reviewer findings (Reviewer)

### Decision: `[APPROVED]`

#### Checklist Audit
1. **Scope Isolation:** Verified. `git status --short -- docs/canary Sources` confirms changes are isolated entirely within `docs/canary/`. Zero modifications made under `Sources/` or product app targets.
2. **Spike Documentation Rigor:** Verified. `docs/canary/COREML_SPIKE.md` provides environment specs, artifact audit, step-by-step methodologies, defect table (D1–D5), explicit NO-GO verdict, and clear recommendations.
3. **Defect Analysis Coherence:** Verified. Defects D1–D5 are technically sound, detailed, and empirically supported:
   - D1: Executable CoreML model is fp16 iOS-17 export, contradicting `metadata.json` (fp32 spec-8).
   - D2: fp16 scalar overflow (`length` / `audio_lengths` > 65504 samples → inf) caps usable audio at ~4.09 seconds.
   - D3: `encoded_lengths` output produces bit-reinterpretation garbage (4992 for 250 mel frames).
   - D4: Preprocessor Mel frontend is corrupt (linear-Hz filterbank, zeroed channels 36–127, non-zero silence floor, pad region garbage).
   - D5: Decoder emits fluent but repetitive hallucinated token loops without EOS due to broken input features.
4. **Zero Python Path:** Verified. `docs/canary/harness/CanarySpike.swift` is 100% native Swift using `Accelerate`, `CoreML`, and `Foundation`. No Python invocations or dependencies.
5. **Architectural Recommendation Honesty:** Verified. Recommends avoiding `alexwengg/canary-1b-v2-coreml`, retaining production WhisperKit engine for Blaboom 1.0.3, and noting official `FluidInference`/`FluidAudio` Canary manager as potential future options.
6. **Main Suite Health:** Verified. `swift test` executed clean with 470/470 tests passing across 4 test suites.
7. **Language Claims Integrity:** Verified. Token vocabulary audit accurately maps ISO-639-1 tokens without inflating capabilities or creating false product promises.

#### Summary
The B6 Canary Core ML spike evaluation is approved with high confidence. The NO-GO recommendation is fully justified by empirical evidence.

---

## §6 — QA summary (Tester)

### Decision: `[qa_green]`

#### Checklist Audit
1. **Full suite:** `swift test` → `✔ Test run with 470 tests in 4 suites passed` (matches ~470 expectation; 470 at B5 baseline, no delta — spike is docs-only).
2. **QA gate:** `./script/qa/run_all.sh` → `Passed: 16  Failed: 0` (15 pre-existing scripts + NEW `check_b6_canary_spike.sh`).
3. **Sources isolation:** `git status --short -- Sources Tests` empty; `git diff --stat -- Sources` empty. Only "canary" hits under `Sources/**` are pre-existing B4 i18n copy strings (`helpBilingualCanary` etc. in `AppText.swift` surfaced via `HelpSettingsView.swift`) — help text about a future engine, zero Core ML/engine code. No product Canary integration.
4. **COREML_SPIKE.md contents:** exists; `Status: NO-GO`; defect table D1–D5 with evidence; zero-Python pipeline (native Swift/CoreML/Accelerate harness, `swiftc -O -parse-as-library`, no Package target); Recommendation section present (do not integrate `alexwengg/canary-1b-v2-coreml`; keep WhisperKit; FluidInference/FluidAudio or mlx as alternatives).
5. **Zero Python path:** `CanarySpike.swift` greps clean for `python3`/`python`/`pip`/`pip3`/`nemo`/`Process(`/`executableURL`/`launchPath`/`/usr/bin/env`; the only "Python" token is the header comment "pure Swift, no Python"; imports = Accelerate/CoreML/Foundation only. Enforced permanently by new script (comment-only allowance).
6. **Harness rebuild + ASR run (models were present):** `scratch/canary-spike/models/` exists → harness rebuilt (`xcrun swiftc -O -parse-as-library`), `en_short.wav` (2.50 s < 4.09 s cap) ran: 250 mel frames, `encoded_lengths_out=4992` (D3 reproduced), transcript = 119-token degenerate loop "To the other, to the other, …" without EOS (D5 reproduced). NO-GO verdict independently reproduces on re-run.

#### New tests added
- `script/qa/check_b6_canary_spike.sh` — structural contracts: `docs/canary/COREML_SPIKE.md` exists + `/NO-GO/i` + D1–D5 + Recommendation; `docs/canary/harness/CanarySpike.swift` exists + zero-Python-invocation grep. Wired into `run_all.sh` automatically (glob `check_*.sh`). No Swift test added — the spike has no product code surface to unit-test.

#### Findings / issues
- No bugs opened. `bugs_open: 0`. Tester made no product changes and no `git commit`/`git push`.
- Minor (non-blocking) observation: `scratch/canary-spike/models` (1.8 GB) remains on disk; COREML_SPIKE.md §6 recommends deleting after decision recording — deletion decision belongs to the Orchestrator, not the tester.

---

## Handoff line (all)

> Готово. Вернись к оркестратору и скажи «статус».
