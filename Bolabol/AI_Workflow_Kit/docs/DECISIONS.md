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


## ADR-017 — Canary 1B Path B package GO candidate (S4b)

**Status:** Accepted as spike/package candidate (S4b 2026-08-04; Reviewer APPROVED with runtime; Tester qa_green)
**Decision:** Record Bolabol-owned package **`bolabol-canary-1b-v2-coreml-r1`** (Path B: native NeMo-aligned mel + smdesai encoder / cross-KV / stateful decoder; **no** Core ML preprocessor) as a **GO candidate** for offline Canary 1B on Apple Silicon. Hosting target: **Bolabol CDN/cloud**, not re-host of failed HF trees. **Do not** product-wire catalog/engine/UI until Human GO list + S7–S9.
**Evidence:** `docs/asr/canary-1b/BOLABOL_COREML_SPIKE.md`; harness `docs/canary/harness/CanarySmdesaiSpike.swift`; `script/qa/check_s4b_canary_fix.sh` + VERIFY package SHA 19/19; Reviewer reproduced EN ASR + EN→FR AST EOS; Tester runtime reproduced EN short.
**Still NO-GO (unchanged):** FluidInference + alexwengg 1B Core ML full packages including their preprocessors (ADR-012/013). smdesai **preprocessor** alone also fails mel preflight and is excluded from the package.
**S7+ constraints:** custom adapter (not FluidAudio canary branch); macOS 15+ MLState; exact Path B frontend constants; true valid lengths; ≤15 s VAD chunks; fresh decoder state per segment; native SentencePiece from `canary_spe.model`; verified claims only EN ASR / EN→FR AST until re-gated.
**1.0.4 next:** Human GO list may include Path B 1B alongside Flash (ADR-014) and GigaAM RU (ADR-015).


## ADR-018 — Human GO list for Track C (S7+)

**Status:** Accepted 2026-08-04 (Human decision in Orchestrator session)  
**Decision:** Product integration (S7→S15) **ships data/engine/UI paths** for these spike-green models only:

| Product id (plan §5) | Source / package | Backend family | Languages (honest) |
|----------------------|------------------|----------------|--------------------|
| `canary-180m-flash-coreml` | aufklarer/Canary-180M-Flash-CoreML (S5, ADR-014) | `canaryCoreML` | en, de, fr, es (+ AST per S5 verified scope) |
| `gigaam-v3-rnnt-coreml` | huggingfinger0/gigaam-v3-coreml (S6, ADR-015) | `gigaAMCoreML` | **ru only** |
| `canary-1b-v2-coreml` | **Bolabol Path B** package `bolabol-canary-1b-v2-coreml-r1` (S4b, ADR-017) — **CDN, not HF FI/alexwengg** | `canaryCoreML` | EN ASR + EN→FR AST verified; expand only after re-gate |

**Explicitly excluded from product catalog:**  
- FluidInference / alexwengg Canary 1B full Core ML trees (ADR-012/013 remain NO-GO)  
- smdesai Core ML preprocessor (failed mel; Path B uses native mel only)

**S7 scope note:** Data layer (backends, descriptors, capabilities, catalog) first; download (S8) and engines (S9) follow.  
**QA:** `check_no_canary_product.sh` (ADR-012 zero product surface) is **superseded for GO catalog entries** starting S7 — replace/narrow so GO model IDs + backend cases are allowed; still forbid engine modules / Package targets until S9, and forbid re-introducing NO-GO HF packages as download sources.

**Rationale:** Human: «GO list: Flash + GigaAM + 1B Path B — всё spike-green».

---

## ADR-019 — S10 Local Models UI capability and banner contract

**Status:** Proposed for S10 implementation

### Decision

S10 completes the **Settings → Local Models** path for the three ADR-018 GO
models, using the already-shipped S7 catalog/capabilities, S8
download/presence/progress state, and S9 engines. It adds only card
presentation, capability-derived availability, truthful language notices, and
the Canary 1B macOS gate. It does not create a persisted UI state, alter the
catalog/install sources, reimplement downloads or engines, or wire a HUD or
session language matrix.

The only S10 model cards introduced or materially changed are the ADR-018 GO
cards:

| Model id | Exact title | Exact EN subtitle | Required badges | Install source that may be represented |
|---|---|---|---|---|
| `canary-180m-flash-coreml` | **Canary Flash (EN/DE/FR/ES)** | **Fast offline ASR for English, German, French, and Spanish · Core ML/ANE.** | **Compact · 4 languages**; **No auto-detect**; existing runtime badge **Canary · Core ML/ANE** | GO Flash package only; never present the NeMo origin as an install choice. |
| `gigaam-v3-rnnt-coreml` | **GigaAM v3 (Russian)** | **Offline Russian ASR · Core ML/ANE. Russian only; no automatic language detection.** | **Russian only**; **No auto-detect**; existing runtime badge **GigaAM · Core ML/ANE** | `huggingfinger0/gigaam-v3-coreml` only. |
| `canary-1b-v2-coreml` | **Canary 1B v2** | **Verified English ASR and English → French speech translation · Core ML/ANE.** | **macOS 15+**; **No auto-detect**; existing runtime badge **Canary · Core ML/ANE** | Bolabol-owned Path B package `bolabol-canary-1b-v2-coreml-r1` from the Bolabol CDN only. |

The Canary 1B card must never offer, name, link to, or imply an alternative
FluidInference/alexwengg Canary 1B tree or an smdesai preprocessor. The three
new ASR paths remain Core ML only: no Python, NeMo runtime, PyTorch, or ONNX
runtime can be introduced by card copy, controls, dependencies, or actions.

### Rationale

ADR-018 accepts exactly Flash, GigaAM RU, and Canary 1B Path B for the 1.0.4
train. S7 already exposes their real `ASRModelCapabilities`; S8 already owns
the installation lifecycle and complete-folder checks; S9 already owns the
runtime hard gate. The former `LanguageSupport` enum is deliberately too
coarse for these models: GigaAM and 1B currently carry `.multilingual`, whose
legacy default is `auto`, even though neither accepts automatic language
detection. FEEDBACK S7 NB-4 therefore makes `capabilities` mandatory for new
backend presentation and decisions.

The 1B generic capability token list includes `en` and `fr`, but it does not
encode operation direction. ADR-017/018 are narrower and authoritative for
user-facing claims: **English ASR** and **English → French speech
translation** only. S10 must use the capability object for auto-detect, min
OS, package size, and language-token bounds, while applying this accepted
ADR-018 operation scope as a narrowing constraint. It must not infer French
ASR, arbitrary translation directions, or broader multilingual support from
`supportsSpeechTranslation == true`.

### Exact S10 boundaries

#### In scope

1. `LocalModelsSettingsView` presentation for the three GO cards, including
   exact subtitles/badges above, real installation actions, language notices,
   and the computed macOS availability gate.
2. A single capability/OS predicate usable by the view and store action path.
   It is computed from `ASRModelCapabilities.minOSVersion` and the current
   `ProcessInfo` OS version; it is **not** saved in
   `TranscriptionModelSettings` and is not an installation-state enum case.
3. Synchronous action guards so an unsupported OS cannot start/retry the 1B
   download or activate/use it through the Settings path. Existing complete
   local files remain removable.
4. Capability-derived banner/copy logic and full 15-locale `AppText` maps.
5. Focused unit/policy, localization, and regression verification defined
   below.

#### Explicitly deferred to S11 — HUD/session matrix

- HUD **A** versus explicit language letters, source-letter cycling, fixed RU
  HUD behavior, and all session/request routing.
- Writing a session's explicit source language to
  `TranscriptionModelSettings.languagePreference`, including any interaction
  with `TranscriptionLanguageRouter` or `ContentView`.
- Any change to `HotkeySessionOverlayManager`, `HotkeySettingsView`,
  `TranscriptionLanguageRouting`, `ContentView`, the two S9 engines, or their
  runtime smoke semantics.

S10 may state what a later Canary session will be limited to, but it must not
pretend that the HUD matrix has been implemented. In particular, it must not
silently rewrite the user's primary/additional pair or turn `auto` into an
implicit Canary/GigaAM route.

#### Explicitly deferred to S12 — Settings recommendation/ranking wiring

- Changes to `OnboardingModelRecommendation`, its table, ordering, or any
  recommendation/ranking persistence.
- New Settings recommendation behaviour. The existing S2 recommended section
  and its current `topThree(primary, additional)` rendering remain unchanged;
  S10 must neither duplicate ranking logic in a card nor re-order the catalog.

#### Out of scope entirely for S10

- Rewriting S7 descriptors/catalog IDs/capabilities, S8 sources/download/
  storage/presence/progress implementation, or S9 engines.
- Onboarding cards, cloud/Gemini behaviour, polish MLX paths, package/dependency
  changes, release notes, or Help content expansion (S14 owns Help content).
- Any product source/install choice for excluded FluidInference/alexwengg 1B
  packages or the smdesai preprocessor.
- Any new `unsupportedOS`, `clamped`, `readyForLanguage`, or similar persisted
  `TranscriptionModelInstallationState` case. Presentation may only derive
  from real store state, real folder presence, capabilities, and current OS.

### UX card and real-state contract

All cards stay in the existing full catalog and retain the existing card
interaction pattern. `Whisper` and `Parakeet` titles, subtitles, badges,
`languageSupport` display, download/delete/use controls, selected behavior,
and HUD A/auto behavior are unchanged. The S10 capability-specific rendering
applies only to the three GO IDs above; it must not change the legacy cards.

For the GO cards, the language label is formatted from the supported codes in
`capabilities` (using existing speech-language display conventions), never
from `model.languageSupport.displayName`. The 1B exact subtitle is the
ADR-018 narrowing rule above, not a generic claim inferred from its legacy
`.multilingual` field or translation boolean.

| Visible card state | Real source | Required action/presentation |
|---|---|---|
| **Not installed** | `TranscriptionModelStore.installationState(for:) == .notDownloaded` after `reconcileModelStates()` | Show **Download** when OS-compatible. Preserve the existing large-download confirmation for 1B, but localize all of its title, message, confirmation, and cancel copy. |
| **Downloading** | Real `.downloading(progressFraction:)` from `TranscriptionModelSettings.installationStates`; duplicate work remains prevented by `downloadingModelIDs` | Show existing real progress indicator and percentage/indeterminate label. Do not add a synthetic cancel, ready, or retry state. |
| **Ready** | `.downloaded(localURL:)` **and** `hasLocalFiles(for:)`/`activeDownloadedModel()` resolves a complete folder | Show **Use**, or **Selected** only when this is the real active downloaded model and the OS gate is met. Keep **Delete**. |
| **Failed** | Real `.failed(errorMessage)` from the store | Show **Retry** and the real bounded error message. Do not replace it with a fabricated reason. Existing residual files may still be deleted. |
| **Incomplete/missing folder** | Existing S8/S9 `completeLocalURL(for:)`/GO required-assets check fails; `reconcileModelStates()` removes stale downloaded/failed state | Do not show Ready, Selected, or Use. Render the resulting real **Not installed** state; no new “corrupt” product state. |
| **Unsupported OS** | `capabilities.minOSVersion != nil` and current `ASRModelCapabilities.OSVersion < minOSVersion` | This is a computed presentation/action gate, not a persisted install state. It has visual/action precedence over the rows above. |

For the only current OS-gated model, Canary 1B, the card remains visible on
older macOS and reads: **“Requires macOS 15 or later. This Mac can’t download
or use this model.”** It keeps its exact capabilities and any existing local
files visible enough to permit **Delete**, but it must disable or omit
**Download**, **Retry**, and **Use**. It must not say “available”, become a
hidden catalog gap, fall back to another runtime, or relabel an installed
folder as ready/selected. Flash and GigaAM have no `minOSVersion` gate unless a
future capability value says otherwise; S10 must not hard-code a model-ID OS
exception in the view.

### Banner, clamp, and language-truth contract

#### Truth sources and precedence

1. The only model inventory is ADR-018's three GO IDs plus the existing
   catalog. Excluded sources cannot appear.
2. `ASRModelCapabilities` is the product truth for `minOSVersion`,
   `supportsAutoLanguageDetect`, supported explicit language-token bounds,
   download size, and backend/runtime presentation. `languageSupport` is not a
   truth source for any new backend language label, auto-detect decision,
   banner, or clamp.
3. ADR-017/018 narrow Canary 1B user-visible operation claims to English ASR
   and English → French speech translation. This narrows, but never expands,
   the descriptor capability bounds.
4. S8 real installation state/presence and the current OS decide whether an
   action can execute. A banner never fabricates installation success or an
   engine fallback.

#### Canary clamp

“Clamp” has one precise S10 meaning: it computes the **non-persisted set of
explicit source-language choices available to the selected Canary model from
the user's configured primary/additional pair**. It does **not** change either
saved field, does not change the UI language, does not choose a translation
outcome, and does not write a session language (the latter is S11).

For a normalized, de-duplicated ordered pair `[primary, additional]`, derive:

```text
effectiveCanarySourceChoices = configuredPair ∩ verifiedASRSourceChoices
```

- Flash `verifiedASRSourceChoices` is its capability list: `en`, `de`, `fr`,
  `es`.
- Canary 1B's verified ASR source choice is `en`. The accepted `en → fr`
  speech-translation claim is a fixed verified operation; it does not turn
  `fr` into a French-ASR claim or a second generic ASR source choice.

If exactly one configured member survives, the card shows a clamp warning:
**“This Canary model can use [supported language] from your primary and
additional languages. [unsupported language] is not supported for this model.
 Your language settings were not changed.”** Use remains available once the
model is otherwise Ready/OS-compatible; S11 will consume the explicit session
choice. If both members survive, no clamp warning is needed. If neither
member survives (including nil/blank/missing inputs in a policy test), show a
hard language block: **“This Canary model needs a supported primary or
additional language. Choose one in Settings → Hotkey → Your Languages.”** The
card remains downloadable/deleteable but **Use** is disabled/not offered until
the stored pair supplies a supported explicit source. No fallback language is
invented.

When `primary == additional`, de-duplicate before the intersection: a
supported single language is a valid one-choice result and does not create a
false two-language switch. A supported primary with an unsupported additional
clamps only the available model-specific choice set; an unsupported primary
with a supported additional exposes only that supported additional choice.
The persisted pair remains exactly as the user configured it in both cases.

#### GigaAM tip and no-auto notice

GigaAM has no Canary-style automatic pair replacement. Whenever
`primary != "ru"`, show the soft tip: **“GigaAM is optimized for Russian.
It recognizes Russian only and does not change your primary or additional
languages. Choose Russian explicitly in Settings → Hotkey → Transcription
Language before dictating.”** This remains a soft tip even if additional is
`ru`; it must never silently replace primary with Russian, rewrite additional,
or claim automatic detection.

Every Canary or GigaAM card also presents the informational no-auto notice:
**“Automatic language detection is not available for this model. See
Settings → Help → Language modes.”** The Help destination already exists.
S10 only provides this truthful path/copy; it does not add a Help view feature
or HUD implementation.

The categories are deliberately distinct:

| Category | Trigger | Behaviour |
|---|---|---|
| **Hard block** | Canary 1B current OS below `minOSVersion`; or selected Canary has no configured supported explicit source | OS: block download/retry/use. Language: block use only. Preserve the card and real files/state. |
| **Clamp warning** | Selected Canary has one supported configured source and one unsupported configured member | Expose only the surviving non-persisted source choice; explain exactly what was excluded and that saved languages are unchanged. |
| **Soft tip** | GigaAM primary is not `ru` | Give the Russian-only/manual-selection guidance; do not alter selection or language fields. |
| **Informational notice** | Any Canary/GigaAM card because capability says no auto-detect | State no automatic detection and provide the existing Help path. |

All new copy must call the two values **primary** and **additional**. UI copy
must not use or translate the phrases “target always output”, “target output”,
or “always output”, and must not imply that additional is an output promise.

### Recommended future S10 target files

These are the proposed Coder scope, derived from the GraphiFy links from
`LocalModelsSettingsView` to `TranscriptionModelStore`,
`TranscriptionModelDescriptor`/`ASRModelCapabilities`,
`TranscriptionModelSettings`, and the existing settings/capability test
surfaces. Exact changes are limited to the following.

#### Mandatory product files

| File | Why it is an S10 target |
|---|---|
| `Sources/NativeBolabol/Views/Settings/LocalModelsSettingsView.swift` | Owns catalog card rows, real installation actions/progress, current selected presentation, and the existing S2 full-catalog/recommended rendering. Add only GO-specific capability labels, computed state precedence, action disabling, banners, and localized large-download alert. Keep Whisper/Parakeet branch and recommendation grouping unchanged. |
| `Sources/NativeBolabol/Stores/TranscriptionModelStore.swift` | Owns the real installation state, reconciliation, download/retry, `hasLocalFiles`, and activation path used by this view. Add only a testable capability/OS availability query plus guards for Settings-initiated download/retry/activation. It must continue to use S8's existing source, progress, SHA/presence, and storage implementations without modification. |
| `Sources/NativeBolabolCore/Models/TranscriptionModelDescriptor.swift` | Home of `ASRModelCapabilities` and `OSVersion`. Add only pure, non-persisting capability predicates/projections needed to compare current OS and evaluate explicit supported source codes. Do not change GO IDs, capabilities payloads, catalog order, source mapping, storage paths, legacy `LanguageSupport`, or download metadata. |
| `Sources/NativeBolabolCore/Services/AppText.swift` | Add all card/badge/state/banner/OS-gate/no-auto/help-path/large-download strings as `AppTextKey`s with non-empty maps for all 15 concrete locales. The exact 1B verified scope and primary/additional terminology must live in localized copy, not raw Swift strings. |

The core predicate/projection may be a minimal extension in
`TranscriptionModelDescriptor.swift`; it must be pure input/output logic over
descriptor capabilities, primary/additional codes, and supplied OS version.
It must not become a new persisted `TranscriptionModelSettings` field or an
invented installation state.

#### Mandatory test files

| File | Why it is an S10 target |
|---|---|
| `Tests/NativeBolabolCoreTests/CoreMLEngineTests.swift` | Extend the existing capability contract tests with simulated below-minimum/equal/above-minimum OS comparisons and capability-based language/no-auto assertions. The test must demonstrate that `.multilingual` is not read for GigaAM/1B S10 decisions. |
| `Tests/NativeBolabolCoreTests/SettingsLocalizationTests.swift` | Add an explicit S10 Local Models key set and assert all 15 locales resolve non-empty/non-raw/non-English fallback values, retain primary/additional terminology, include the Help path, and exclude prohibited output-promise wording. |
| `Tests/NativeBolabolCoreTests/TranscriptionModelSettingsTests.swift` | Add regression coverage that computed S10 clamp/OS presentation does not mutate `primary`/`additional`, `languagePreference`, installation state, or active model merely by rendering/evaluating availability. |
| `Tests/NativeBolabolCoreTests/S9EngineEdgeCaseTests.swift` | Retain/extend only if needed to prove S10's store gate does not weaken S9's real unsupported-OS and incomplete-folder rejection. It is a regression seam, not a place to reimplement S10 UI policy. |

`Tests/NativeBolabolCoreTests/TranscriptionModelCatalogTests.swift`,
`S8DownloadContractTests.swift`, and `S9RuntimeSmokeTests.swift` are mandatory
regression reads/runs, but are **not** expected S10 edit targets unless a
focused test proves an actual contract gap. In particular, do not weaken their
GO source, no-NO-GO-source, storage, complete-folder, or runtime smoke guards.

#### No S10 QA-script change

No `script/qa/**` change is required or authorized for this card. Existing QA
already protects the allowed GO surface and runtime boundary; unit/localization
tests provide the S10-specific contract. A proposed new QA guard is justified
only by a newly demonstrated static gap and must be separately approved, not
added as speculative scope.

### Acceptance matrix and Definition of Done

| Area | Coder/Reviewer/Tester acceptance evidence |
|---|---|
| GO inventory and source safety | Exactly Flash, GigaAM RU, and Bolabol CDN Path B 1B receive S10-specific cards. No FluidInference/alexwengg 1B or smdesai preprocessor appears as text/source/action. Existing catalog/source tests remain green. |
| Exact cards | The three titles, subtitles, badges, runtime badge, and actions match this ADR. 1B claims only English ASR plus English → French speech translation; GigaAM is Russian only; Flash names only EN/DE/FR/ES. |
| Installation states | Deterministic fixtures/manual checks cover not installed, downloading with known and nil progress, ready/use, selected real complete model, failed/retry/error, and incomplete folder reconciliation. No synthetic state exists. |
| OS gate | Simulated OS `< 15.0`, `15.0`, and later values prove the capability predicate. On `< 15.0`, 1B stays visible, says macOS 15+, cannot download/retry/use, and can delete local files; Flash/GigaAM remain ungated. S9 engine OS rejection remains green. |
| Capability language contract | Tests cover Flash `(en, es)` (no clamp), `(en, ru)` and `(ru, es)` (one surviving explicit source), `(ru, uk)` (hard language block), same-as-primary, and nil/empty defensive inputs. They cover 1B English-only verified ASR source projection, its English → French operation wording, no French-ASR claim, and no auto-detect. They cover GigaAM RU-only/no-auto truth independently of legacy `.multilingual`. |
| Clamp / soft tip | Clamp never writes primary/additional, UI language, language preference, installation state, or active model. GigaAM primary `!= ru` yields only the soft Russian tip; it never auto-replaces either language. No-auto notice supplies `Settings → Help → Language modes` for every Canary/GigaAM card. |
| Existing behaviour | Existing Whisper/Parakeet cards, S2 recommended/remaining partition, download/use/delete flows, and HUD A/auto behavior are unchanged. Existing catalog snapshot and S8/S9 presence/runtime tests remain green. |
| Localization | Every new `AppTextKey` has all 15 concrete locale maps, no raw-key/empty/silent English fallback, primary/additional wording remains distinct where applicable, and no prohibited output-promise terminology appears. No new visible English literals remain in the card/alert/banner path. |
| Scope discipline | Diff contains only mandatory S10 product/test/i18n files (plus worker feedback if requested by the orchestrator). It contains no engine, catalog payload, onboarding, HUD/session, ranking, Package.swift, QA-script, STATE, checkpoint, commit, or push change. |

Future Coder verification commands:

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"
swift test --filter CoreMLCapabilitiesTests
swift test --filter CapabilitiesContractTests
swift test --filter S10
swift test
./script/qa/run_all.sh
./script/build_and_run.sh

# Required only when the documented scratch assets are present; preserves S9
# real-runtime confidence without making S10 depend on a fake fixture.
BOLABOL_S9_RUNTIME_SMOKE=1 swift test --filter S9RuntimeSmokeTests

git diff --check -- \
  Sources/NativeBolabol/Views/Settings/LocalModelsSettingsView.swift \
  Sources/NativeBolabol/Stores/TranscriptionModelStore.swift \
  Sources/NativeBolabolCore/Models/TranscriptionModelDescriptor.swift \
  Sources/NativeBolabolCore/Services/AppText.swift \
  Tests/NativeBolabolCoreTests/CoreMLEngineTests.swift \
  Tests/NativeBolabolCoreTests/SettingsLocalizationTests.swift \
  Tests/NativeBolabolCoreTests/TranscriptionModelSettingsTests.swift \
  Tests/NativeBolabolCoreTests/S9EngineEdgeCaseTests.swift
```

### Risks / open questions

None block S10 design. The only apparent ambiguity—Canary 1B's generic `en`/
`fr` token list versus its narrower verified operation—is resolved here by the
accepted ADR-017/018 scope: never claim French ASR or a broader AST matrix.
Expanding any 1B language or translation claim requires a new spike/re-gate
and a superseding ADR; it is not an S10 UI decision.

---
*Add new ADRs at the bottom; do not rewrite history — supersede with new ADR if needed.*
