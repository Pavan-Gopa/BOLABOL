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

---

## ADR-020 — S11 explicit Core ML session routing and 1B download failure policy

**Status:** Proposed for S11 runtime-blocker implementation

### Decision

S10 remains presentation-correct and `BLOCK-S10-001` remains closed, but feature
QA is blocked by a separate S11 runtime defect. S11 must introduce one
capability-aware **session plan** that binds the selected local model, backend,
operation, explicit ASR source, HUD representation, and eventual
`TranscriptionRequest`. Every local transcription entry point must use that
plan. The existing Whisper-oriented auto/target router must no longer be the
only route constructor for Canary or GigaAM.

The session plan is an ephemeral snapshot. It is computed from the active,
complete model descriptor, its `ASRModelCapabilities`, current OS, the user's
canonical primary/additional speech-language pair, and the explicitly requested
operation. It is not a new installation state and is not silently persisted.
For every Canary/GigaAM ASR request it produces a non-empty, non-`auto`
`forcedLanguageCode`; an invalid combination produces an unavailable session
with a truthful reason and **no engine call**.

Canary/GigaAM remain Core ML only. Whisper/Parakeet retain their current
auto-detect and HUD **A** behavior. No Python, NeMo runtime, PyTorch, ONNX, new
runtime dependency, S12 ranking behavior, or prohibited Canary 1B source is
introduced.

### A. Root-cause model

The live result is caused by an architectural disconnect, not by incomplete
Flash/GigaAM packages and not by an S10 card defect:

1. **Selected Local Model / backend.** `TranscriptionModelStore` persists
   `activeModelID`; `TranscriptionEngineStore.activeEngine` correctly maps the
   active descriptor backend to WhisperKit, Parakeet, `CanaryCoreMLEngine`, or
   `GigaAMCoreMLEngine`. The engine selection edge is present and is not the
   observed failure.
2. **Capabilities.** S7 descriptors correctly say
   `supportsAutoLanguageDetect == false`, Flash supports explicit
   `en/de/fr/es`, Path B 1B has an English-only verified ASR source projection,
   and GigaAM supports explicit `ru`. S10 consumes those capabilities for card,
   OS, source-projection, and activation presentation. The runtime router does
   not consume them.
3. **Legacy resolved language.** `TranscriptionModelSettings.languagePreference`
   defaults to `.auto`. `resolvedLanguageCode` falls back through legacy
   `LanguageSupport.defaultLanguageCode`; both new backends still carry the
   coarse `.multilingual`, whose default is `auto`. This API therefore returns
   `auto` even when the selected descriptor explicitly forbids auto detection.
4. **Hotkey override.** The current `ContentView` hotkey path goes further: for
   an ordinary hotkey session (`hotkeyTarget != nil`, target-language mode off)
   it assigns `languageCode = "auto"` unconditionally. It calls
   `TranscriptionLanguageRouter.route(resolvedLanguageCode:isMultilingualModel:
   forceTargetLanguage:)`, which only knows a language string and Whisper-style
   native-translation eligibility. It receives no model id, backend,
   capabilities, or primary/additional pair. By design, `auto` becomes
   `forcedLanguageCode == nil`.
5. **HUD/session UI.** `TranscriptionLanguageMode` models only Whisper's
   `.auto ↔ .target` semantics. `HotkeySessionOverlayManager` renders either
   **A** or a target-language letter, not an explicit ASR source. The current
   `isHUDLanguageControlEnabled` predicate is based on Gemini/Whisper native
   translation or polishing availability, not on ASR source capabilities. For
   a raw Canary/GigaAM session it disables the control and resets target mode,
   explaining the live `languageControlEnabled=false`; disabled state still
   does not supply the required explicit source.
6. **Request construction.** `ContentView` passes the legacy route fields into
   `RecordingTranscriptionWorkflow`, which constructs
   `TranscriptionRequest(forcedLanguageCode: nil, ...)`. The translation
   recording path uses the same router. `SidebarView` and
   `AudioPlaybackModalView` bypass that router but repeat the same defect with
   `resolvedLanguageCode == "auto" ? nil : languageCode` during re-transcription.
7. **Engine requirements.** Both new Core ML engines correctly reject a nil or
   unsupported explicit source. Canary documents that a HUD A/nil request is an
   error; GigaAM additionally rejects translation. The workflow catches the
   error and leaves the note's raw text empty; hotkey output then truthfully
   skips an empty string. Empty output is the downstream symptom, not proof that
   an auto request succeeded.

This distinguishes three independent facts:

- **S10 presentation correctness:** ADR-019 cards, capability notices, OS gate,
  real S8 actions/progress, non-mutating projection, and the accepted
  `BLOCK-S10-001` fix remain valid. S10 explicitly deferred HUD, session, and
  request routing to S11.
- **S11 missing runtime routing:** capabilities stop at Settings presentation;
  the actual session/request path is still Whisper-only and can emit nil/auto
  for engines that require an explicit source.
- **Canary 1B DNS/download blocker:** the 1B folder is empty because its Path B
  manifest request failed before any bytes with DNS `NoSuchRecord`,
  `NSURLErrorDomain` code `-1003`, `failed to connect 12:8`, and `0/0 bytes`.
  That network/configuration failure is separate from the route defect. It
  cannot be repaired by language routing or represented as installed.

The retained live log and observed folders are evidence for this decision only;
they are not product assets. The complete Flash and GigaAM layouts establish
that those two reproductions reached the routing boundary. The empty 1B folder
establishes that 1B did not reach its engine boundary.

### B. Explicit routing contract

#### Common request invariant

The route resolver receives a frozen active descriptor, the canonical
primary/additional pair, the requested operation, and availability/presence
facts. It returns either a valid session plan or a typed unavailable reason.
For `.canaryCoreML` and `.gigaAMCoreML`, a valid ASR plan must satisfy:

```text
forcedLanguageCode != nil
forcedLanguageCode is normalized, non-empty, and != "auto"
forcedLanguageCode is an allowed verified ASR source for this model/operation
translateToEnglish == false for ordinary ASR
```

The engine validators remain the final safety net. The router must prevent the
invalid call; it must not weaken a validator so nil/auto appears successful.

#### Whisper / Parakeet

- Preserve existing auto-detect behavior and HUD **A** behavior.
- Whisper retains its explicit recognition preference and its existing
  Whisper-only X→English translation semantics.
- Parakeet continues to auto-detect internally; a stale explicit Whisper
  preference must not become a restrictive Parakeet source hint.
- Existing `TranscriptionLanguageRouter` regression behavior remains available
  for these backends. Its auto result may remain
  `forcedLanguageCode == nil`; that result is never reused for Canary/GigaAM.

#### Canary Flash

Verified explicit ASR source set: **EN/DE/FR/ES**. Normalize and deduplicate the
configured primary/additional pair while preserving slot order. The first
surviving primary is the initial session source; otherwise the surviving
additional is initial. Only user-configured pair values may become Flash source
choices; do not manufacture another supported default.

| Configured pair case | Effective session behavior | HUD / request |
|---|---|---|
| Both supported and distinct | Choices are `[primary, additional]`; initial source is primary; a HUD tap switches only between those two. | Show the active explicit source letter; request always forces that source. Never show/send A. |
| Exactly one supported | Use the one surviving configured language, regardless of which slot supplied it. | Fixed explicit letter; no fake switch; force that code. |
| Neither supported | Session is unavailable for Flash. | Explain that Flash needs EN/DE/FR/ES in Primary or Additional; make no request. |
| Same-as-primary | Deduplicate to one explicit source. | Fixed letter; no duplicate toggle and no auto. |
| One missing/blank and the other supported | Treat the missing slot as absent and use the supported slot. | Fixed explicit route. |
| Both missing/blank | No configured source exists. | Unavailable; make no request. |
| Unsupported configured primary/additional, including defensive `auto` input | Exclude each unsupported value; then apply the one/none rules above. | Show the unsupported-combination reason when none survive; never silently substitute or rewrite. |

Pair evaluation is pure. It does not modify primary, additional,
`languagePreference`, active model, or installation state.

#### Canary 1B Path B

- The only verified ASR source is explicit **English**. A valid ASR request is
  `forcedLanguageCode = "en"` and `translateToEnglish = false`.
- English must survive the primary/additional projection. If neither configured
  slot is English, the ASR session is unavailable and tells the user to add
  English; it does not pretend that French is an ASR source and does not
  auto-select English behind the user's saved pair.
- **English → French speech translation is a narrow operation**, not French
  ASR and not a primary↔additional source toggle. An additional value of `fr`
  does not create a French source or an **F** source HUD state.
- The current request flag is named and implemented as
  `translateToEnglish`; it cannot honestly encode EN→FR and must not be
  repurposed. The runtime-blocker implementation may expose 1B English ASR as
  above. If it also exposes the verified translation operation, it must first
  add a typed operation/target contract whose only 1B translation route is
  source `en` → target `fr`, wire it through the workflow and engine, and add
  real runtime evidence. Until that distinct operation exists, EN→FR remains a
  truthful capability statement but no control may imply the operation ran.
- macOS 15+ and S8 complete-folder rules are prerequisites to session creation.
  Failure of either rule is unavailable, not a fallback model and not a fake
  ready state.
- The install source remains only the Bolabol-owned Path B package from the
  Bolabol CDN. FluidInference/alexwengg and the excluded smdesai preprocessor
  remain forbidden.

#### GigaAM

- Every valid session is explicit Russian ASR:
  `forcedLanguageCode = "ru"`, `translateToEnglish = false`.
- HUD shows a fixed Russian representation (**R**, following the existing Latin
  HUD-label rule), never **A** and never a second source.
- No primary/additional toggle is offered because the engine is RU-only. A
  configured additional language must not become a fake switch.
- If configured primary is not RU, keep ADR-019's clear, non-mutating user tip:
  the selected model transcribes Russian only and the session will use RU. This
  is a soft truth notice, not an implicit edit of primary/additional and not a
  claim that another configured language is supported.
- A translation request or a source other than RU is unavailable and must not
  reach the engine as a plausible success.

### C. Session/HUD state machine

#### Source of truth

At session start, create one immutable `TranscriptionSessionPlan` (name may
follow repository conventions) from:

```text
active complete model descriptor + backend + capabilities + model id
current OS availability
current primary/additional speech-language pair
explicit requested operation
legacy languagePreference only for the existing Whisper path
```

The plan owns the active source for that session, the permitted source choices,
the exact request fields, HUD presentation, and an unavailable reason when
invalid. `ContentView`, the workflow, and re-transcription entry points consume
the same resolver; no view reconstructs `auto ? nil : code` independently.

For a running hotkey session, the plan is the source of session language truth.
The model store and user settings remain sources for the **next** plan. This
prevents the HUD label, request, and engine descriptor from observing different
moments of mutable settings.

#### Persistence policy

- Capability clamping, session creation, HUD display, and a Canary HUD source
  tap never write `TranscriptionModelSettings.languagePreference`.
- `languagePreference` remains the existing persisted Whisper recognition
  preference and is written only by an explicit user action on the legacy
  Whisper/Parakeet-compatible Recognition Language control. It is not repaired
  on model activation and is not used as a Canary/GigaAM source fallback.
- When a Canary/GigaAM model is active, `HotkeySettingsView` presents the
  capability-derived current session source contract alongside the canonical
  Primary/Additional controls; it must not present Auto as a usable Core ML
  engine route. Editing Primary/Additional is an explicit user action through
  `GeneralSettingsStore`, not a router side effect.
- The existing persisted Whisper HUD target-mode preference must not be read as
  a Canary source choice. Canary source cycling is session-local. GigaAM/1B
  fixed displays do not persist a fake toggle state.
- No `clamped`, `fixedRU`, `readyForLanguage`, DNS-ready, or similar state is
  added to persisted model settings or installation state.

#### HUD behavior

The overlay needs a presentation state richer than current `.auto/.target`:
automatic, explicit-switchable source, explicit-fixed source, and unavailable.
Rendering and hit testing consume that state. A disabled explicit control still
renders its real source letter; `languageControlEnabled == false` must no longer
implicitly mean “render A”. Tooltips/accessibility text name the active source
and, for switchable Flash, the next source.

#### Transitions

| Event / guard | Next state | Request and HUD | Persistence |
|---|---|---|---|
| Begin Whisper/Parakeet session | Existing automatic/legacy route | Preserve HUD A and existing request semantics. | Existing explicit legacy settings only. |
| Begin Flash; two supported distinct pair values | Explicit-switchable, active primary | Force primary; show its letter. | None. |
| Tap Flash source control | Explicit-switchable, active other configured source | Rebuild only the pending session request fields; show other letter; never nil/auto. | None. |
| Begin Flash; exactly one supported value or same-as-primary | Explicit-fixed | Force sole source; fixed letter, no fake tap. | None. |
| Begin Flash; no supported configured value | Unavailable | Clear reason; do not record/invoke engine as a usable session. | None. |
| Begin 1B; macOS 15+, complete folder, English in pair | Explicit-fixed EN ASR | Force EN; fixed **E**. | None. |
| Begin 1B without English, on unsupported OS, or incomplete package | Unavailable with the specific language/OS/package reason | No request and no fallback. | Preserve real settings/state. |
| Begin GigaAM with complete folder | Explicit-fixed RU | Force RU; fixed **R**, even when primary is not RU; show soft RU-only notice. | None. |
| Model or pair changes while recording | Current plan remains frozen; next session uses new inputs | Current HUD/request stay consistent. If the frozen package is deleted/unavailable before invocation, fail truthfully; never switch engine silently. | Only the user's explicit settings action persists. |
| Session ends/cancels | Discard plan | Hide HUD; next session recomputes. | No session-language write. |
| DNS/download failure | Installation `.failed` for this attempt, package incomplete | Show bounded truthful error and Retry; no session plan for 1B. | Never mark downloaded/active. |

### D. Product implementation boundary

GraphiFy connects `ContentView` to `TranscriptionModelStore`,
`TranscriptionEngineStore`, `TranscriptionLanguageRouter`,
`RecordingTranscriptionWorkflow`, `TranscriptionRequest`, and
`HotkeySessionOverlayManager`; it connects the workflow request to both Core ML
engines. A second graph traversal connects the Path B descriptor/install source
to `TranscriptionModelStore.downloadBolabolCDNPackage`, Local Models Retry, and
complete-folder tests. The implementation therefore cannot be a HUD-only patch.

#### Mandatory product files

| File | Required S11/download responsibility |
|---|---|
| `Sources/NativeBolabolCore/Services/TranscriptionLanguageRouting.swift` | Add the pure backend/model/capability-aware session resolver and typed unavailable reasons while preserving the existing Whisper/Parakeet route contract. This is the single source for route/request/HUD projection. |
| `Sources/NativeBolabolCore/Models/TranscriptionLanguageMode.swift` | Replace or extend the two-state Whisper-only representation with automatic, explicit-switchable, explicit-fixed, and unavailable presentation semantics. It remains ephemeral unless an existing legacy value explicitly requires compatibility. |
| `Sources/NativeBolabol/Stores/TranscriptionModelStore.swift` | Supply the active descriptor, canonical speech pair, OS/presence facts to the resolver; remove all Core ML reliance on legacy `resolvedLanguageCode`; implement the truthful `-1003` classification, retry seam, and incomplete-artifact policy without weakening S8 SHA/storage semantics. |
| `Sources/NativeBolabol/Stores/TranscriptionEngineStore.swift` | Resolve an engine and its descriptor/runtime identity as one session binding so a mid-session model change cannot pair an old route with a new engine. Preserve existing engine caches and no-fallback behavior. |
| `Sources/NativeBolabolCore/Services/RecordingTranscriptionWorkflow.swift` | Accept/construct requests from the validated session plan rather than independent optional language fields; keep failure status honest. Ordinary Core ML ASR must never be able to lose its explicit source here. |
| `Sources/NativeBolabol/Views/ContentView.swift` | Replace both hotkey and translation-recording call sites, freeze the model/route at session start, drive the HUD from it, handle source taps, and remove the unconditional hotkey `"auto"` route for Canary/GigaAM. Whisper/Parakeet branches remain behaviorally unchanged. |
| `Sources/NativeBolabol/Views/SidebarView.swift` | Route re-transcription through the shared session resolver; remove its direct `auto → nil` construction. |
| `Sources/NativeBolabol/Views/AudioPlaybackModalView.swift` | Route modal re-transcription through the same resolver; remove its duplicate `auto → nil` construction. |
| `Sources/NativeBolabol/Services/HotkeySessionOverlayManager.swift` | Render the plan's actual source label and switchability independently of Whisper target mode; a fixed disabled explicit source must not render A. Keep all three HUD styles and hit-test behavior aligned. |
| `Sources/NativeBolabol/Views/Settings/HotkeySettingsView.swift` | Make the active model's session-language contract truthful: preserve existing Whisper/Parakeet Auto UI, show capability-derived explicit source behavior for Canary/GigaAM, and leave Primary/Additional and legacy preference unmodified unless the user edits their owning control. |
| `Sources/NativeBolabolCore/Models/TranscriptionModelDescriptor.swift` | Keep capabilities and source projections authoritative; accept only a Human-approved Path B CDN configuration correction. Do not add a guessed endpoint or alternate source. |
| `Sources/NativeBolabol/Views/Settings/LocalModelsSettingsView.swift` | Map the classified DNS/hostname failure to localized failed/Retry presentation while retaining real progress/Delete/action precedence from S8/S10. |
| `Sources/NativeBolabolCore/Services/AppText.swift` | Add localized unsupported-combination, fixed-source, unavailable-session, and DNS/hostname failure text for all supported UI locales; do not expose secrets or raw internal URLs. |

`Sources/NativeBolabolCore/Services/EngineProtocols.swift` is a mandatory edit
**only if** the Coder implements 1B EN→FR in the same S11 change: the request
must gain a typed speech-translation target rather than overloading
`translateToEnglish`. If this file is not changed, the S11 blocker scope is
English ASR only for 1B and no UI/control may claim to execute EN→FR.

The Canary/GigaAM engine decoding code is not the root-cause fix. Existing
explicit-language, OS, translation, missing-file, and empty-result guards stay
strict. `CanaryCoreMLEngine.swift`, `GigaAMCoreMLEngine.swift`, and
`WhisperKitTranscriptionEngine.swift` are edited only when required by an
approved typed operation contract; no frontend, compute-unit, chunking, state,
or decoding change is authorized by this ADR.

#### Mandatory tests

| File | Required evidence |
|---|---|
| `Tests/NativeBolabolCoreTests/TranscriptionLanguageRoutingTests.swift` | Backend route matrix, all Flash pair cases, fixed GigaAM RU, 1B English-only, typed unavailable reasons, and existing Whisper/Parakeet auto regressions. |
| `Tests/NativeBolabolCoreTests/S11SessionRoutingTests.swift` (new) | Session snapshot/state transitions, HUD projection/switchability, mid-session immutability, no persistence writes, and no request for unavailable model/language/OS/package combinations. |
| `Tests/NativeBolabolCoreTests/RecordingTranscriptionWorkflowTests.swift` | The exact plan request reaches the engine; every new Core ML ASR request is non-nil/non-auto; failures remain failures rather than empty success. |
| `Tests/NativeBolabolCoreTests/TranscriptionLanguageModeTests.swift` | Automatic versus switchable/fixed/unavailable presentation transitions and compatibility for existing A behavior. |
| `Tests/NativeBolabolCoreTests/TranscriptionModelSettingsTests.swift` | Capability routing and HUD taps do not rewrite primary/additional, `languagePreference`, active model, or installation state. |
| `Tests/NativeBolabolCoreTests/S9EngineEdgeCaseTests.swift` | Preserve engine rejection of nil/auto/unsupported sources, GigaAM translation rejection, 1B OS gate, and incomplete-folder behavior; add route-to-engine assertions without weakening S9. |
| `Tests/NativeBolabolCoreTests/S8DownloadContractTests.swift` | Injected `URLError(.cannotFindHost)` / `NSURLErrorDomain -1003`, no automatic fallback, truthful Retry state, no downloaded/active state, empty/unverified cleanup, verified-partial resume, manifest/SHA preservation, and prohibited-source absence. |
| `Tests/NativeBolabolCoreTests/SettingsLocalizationTests.swift` | All new session/DNS/error strings resolve in all supported locales with no raw key, empty value, secret, or prohibited source name. |
| `Tests/NativeBolabolCoreTests/S9RuntimeSmokeTests.swift` | Continue real explicit EN/RU engine smokes; add installed-root/session-plan coverage when the test seam can consume real installed folders without weakening scratch opt-in. |

#### Optional tests only if evidence proves a gap

- `EngineConstructionTests.swift`: extend only if the mandatory S9 edge tests do
  not already cover a changed engine/request API.
- `HUDLayoutAndComposerTests.swift`: extend only if the new shared HUD language
  presentation changes geometry/provider composition; source-state behavior
  belongs in `S11SessionRoutingTests`.
- `TranscriptionModelCatalogTests.swift` and `CoreMLEngineTests.swift`: edit only
  if the approved CDN configuration seam or capability projection changes their
  contract. They remain mandatory regression runs.
- Add focused `SidebarView`/`AudioPlaybackModalView` UI tests only if the shared
  resolver tests plus Reviewer call-site inspection cannot prove both direct
  re-transcription paths use the plan. Do not introduce a UI-test framework or
  dependency solely for this ADR.

#### Explicitly forbidden / out of scope

- `Package.swift`, `script/qa/**`, orchestration `STATE.yaml`, onboarding,
  release/version files, and S12 recommendation/ranking code.
- Any Python, NeMo runtime, PyTorch, ONNX, new runtime dependency, Apple Speech
  fallback, or silent fallback to a different local model.
- Any FluidInference/alexwengg/smdesai install fallback, endpoint, package tree,
  or user-facing source choice for Canary 1B.
- Changes to S9 frontend constants, compute units, chunk limits, true-length
  handling, RNNT/decoder state, SentencePiece, or engine smoke success criteria
  unless a separately reproduced engine defect is reviewed.
- New persisted fake session/availability/installation states; silent changes to
  primary/additional or `languagePreference`; French-ASR or broader 1B claims.
- QA-script remediation, S12 ranking, and broad Help/release work. Existing
  legacy QA allowlist debt remains a separate Tester/orchestrator item.

### E. Canary 1B DNS/download mitigation

`NSURLErrorDomain -1003` / `URLError.cannotFindHost` is a hostname-resolution
failure for the resolved Path B base configuration. It is not an HTTP status,
manifest parse result, checksum result, completed download, or evidence that an
alternate host should be tried.

Policy:

1. **Terminal current attempt.** A `-1003` manifest or file request ends that
   attempt immediately. Do not spin in an automatic retry loop: an immediate
   retry cannot repair an absent DNS record or wrong configured hostname.
2. **Truthful UI.** Map it to a bounded localized error such as “Bolabol could
   not resolve the model download host. Check DNS/network availability and try
   again.” Do not display Ready/Selected, `100%`, or a generic success. Do not
   print the full URL, credentials, query parameters, or secrets.
3. **User Retry.** Keep the real Retry action. A user-triggered Retry performs a
   fresh DNS/manifest request after configuration/connectivity may have changed.
   It may resume only files already verified against a successfully obtained
   Path B manifest; it never switches source.
4. **No prohibited fallback.** Failure must not try FluidInference,
   alexwengg, smdesai, Hugging Face search, a NeMo origin, or an invented mirror.
   If the approved Path B source is unavailable, 1B remains unavailable.
5. **Cleanup and resume.** If failure occurs before a trusted manifest is
   obtained, remove the newly created empty destination and any unverified temp
   manifest/file. If a trusted manifest was obtained, delete temp or
   SHA-mismatched files and retain only manifest-matching, SHA-verified completed
   files that S8 can safely resume. In every partial case the complete-folder
   predicate is false. Delete remains able to remove real partial files.
6. **S8 integrity remains authoritative.** Download completion requires every
   manifest entry, its expected size/SHA-256, the required Path B layout, and
   the normal complete-folder reconciliation. Network success alone is not
   model readiness; an empty folder is never readiness.

The live log proves DNS failure but does not prove whether the intended DNS
record is missing, the current distribution resolved the wrong base
configuration, or the deployment manifest path is unpublished. Therefore the
root cause must be corrected at the authoritative Bolabol CDN deployment and/or
its non-secret product configuration; it must not be guessed in source.

Before Coder changes a base URL or manifest mapping, Human/Orchestrator must
supply or confirm these validation inputs:

- the approved Path B CDN base configuration (no secret/token in source or
  feedback);
- package id `bolabol-canary-1b-v2-coreml-r1` and its published
  `MANIFEST.json` path contract;
- confirmation that DNS, TLS, and package hosting are deployed for the intended
  distribution environment.

Coder validates the supplied configuration without inventing an endpoint:

1. Resolve only the approved configured host and confirm DNS/TLS from the same
   network context used for the app.
2. Fetch `MANIFEST.json` using the supplied base configuration and known package
   id into a temporary path; validate JSON/package identity and never echo
   credentials. A development override such as `BOLABOL_CDN_BASE_URL` may be
   used for validation, but the shipped app must receive an approved,
   deterministic non-secret configuration rather than depending on an
   undeclared shell environment.
3. Exercise the real store download into an isolated model root; verify every
   manifest SHA and the complete-folder predicate before activation.
4. Repeat with an injected `cannotFindHost` failure and prove the truthful
   failed/Retry/no-fallback/cleanup behavior.

If the approved endpoint/configuration input is absent, Coder records that as a
required Human/deployment input and implements only the honest failure policy;
Coder must not fabricate a hostname. Orchestrator/Human then classifies 1B as a
known infrastructure blocker or withholds it from a release claim. It is never
classified as downloaded.

### F. Acceptance matrix and tests

| Area | Future Coder / Reviewer / Tester acceptance evidence |
|---|---|
| Route ownership | One session resolver consumes descriptor/backend/capabilities/pair/operation. No Canary/GigaAM entry point uses legacy `resolvedLanguageCode` or reconstructs `auto → nil`. Reviewer inspects `ContentView`, workflow, Sidebar, and audio modal call sites. |
| Whisper / Parakeet regression | Unit and live tests preserve Whisper/Parakeet auto detection and HUD A. Parakeet receives no stale restrictive hint; Whisper target-to-English behavior remains unchanged. |
| Flash pair matrix | Tests cover both supported distinct (and both HUD directions), primary-only supported, additional-only supported, neither supported, same-as-primary, primary blank, additional blank, both blank, and unsupported/`auto` defensive values. Every valid request forces EN/DE/FR/ES; invalid cases make no request. |
| No-auto Core ML invariant | Route, workflow spy-engine, and engine-edge tests assert non-nil/non-empty/non-`auto` for Flash, 1B, and GigaAM. Engine rejection of nil/auto remains green. |
| GigaAM fixed RU | Any valid session forces RU, shows fixed R, offers no secondary switch, rejects translation, and gives a clear non-mutating RU-only notice when primary is not RU. |
| Canary 1B | English in the pair yields fixed explicit EN ASR; no English yields unavailable. French never appears as ASR/HUD source. EN→FR is tested only if a distinct typed operation is implemented; no test may call `translateToEnglish` proof of EN→FR. macOS 15+ and complete-folder gates remain. |
| Session consistency | Tests freeze model/source at start, change model/pair mid-session, and prove current HUD/request remain aligned while the next session recomputes. Deletion/unavailability before invocation fails without fallback. No session transition mutates persisted language/model/install settings. |
| Unavailable paths | Missing/incomplete package, unsupported OS, unsupported pair, no active model, and deleted model produce distinct truthful failures and no engine call. Unsupported combinations cannot look successful. |
| Runtime smoke | With real files, Flash explicit language and GigaAM RU produce non-empty text; 1B explicit EN does so only after a real complete Path B install on macOS 15+. Existing S9 frontend/chunk/state smoke remains unchanged. |
| Live app manual matrix | Fresh built `Bolabol.app`: Flash EN/DE/FR/ES pair cases and HUD switch; GigaAM with primary RU and non-RU; 1B EN and no-EN pair; Whisper/Parakeet A; Sidebar/audio-modal re-transcription; mid-session pair/model change; missing/incomplete/unsupported-OS errors. Capture model id/backend, capability auto flag, session source mode, forced request language, and non-empty/failed result without secrets. |
| 1B DNS/retry/source safety | Injected `-1003` test and live approved-host test show failed/Retry, zero fake progress/readiness, cleanup rules, same-source retry, and no FI/alexwengg/smdesai/HF fallback. A corrected real download proves manifest/SHA/complete-folder before activation. |
| Full gates | Focused tests, full `swift test`, `run_all`, real runtime smoke, fresh build, and Human/Tester live reproduction are recorded. Static QA debt is reported honestly; no QA script is edited in this implementation. |

Future verification commands:

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"

swift test --filter TranscriptionLanguageRoutingTests
swift test --filter S11SessionRoutingTests
swift test --filter RecordingTranscriptionWorkflowTests
swift test --filter TranscriptionLanguageModeTests
swift test --filter TranscriptionModelSettingsTests
swift test --filter S8DownloadContractTests
swift test --filter S9EngineEdgeCaseTests
swift test --filter S9RuntimeSmokeTests
swift test
./script/qa/run_all.sh

# Requires the documented real scratch assets; does not replace live-app QA.
BOLABOL_S9_RUNTIME_SMOKE=1 swift test --filter S9RuntimeSmokeTests

# Builds and launches the fresh app used for the manual matrix.
./script/build_and_run.sh

# In a second shell, capture only Bolabol runtime routing/transcription evidence.
log stream --style compact --predicate \
  'subsystem == "com.pavan.NativeBolabol" AND (category == "hotkey" OR category == "transcription")'

# CDN validation only after Human supplies the approved non-secret base value.
: "${BOLABOL_CDN_BASE_URL:?Human-approved Path B CDN base URL is required}"
curl --fail --show-error --location \
  "${BOLABOL_CDN_BASE_URL%/}/bolabol-canary-1b-v2-coreml-r1/MANIFEST.json" \
  --output /tmp/bolabol-canary-1b-MANIFEST.json
plutil -lint /tmp/bolabol-canary-1b-MANIFEST.json
```

These commands are future acceptance instructions, not a success claim. No
runtime success is accepted without a fresh real `Bolabol.app` reproduction.

### G. Ordering and QA gate

**Yes: S10 feature QA remains blocked** in this order until all three gates are
handled:

1. S11 capability-aware runtime/session/request routing is implemented and
   independently reviewed, including all non-HUD entry points and no-auto
   assertions.
2. Canary 1B DNS/download mitigation is either corrected against a
   Human-approved live Path B CDN configuration and real package, or truthfully
   classified by Human/Orchestrator as an unresolved infrastructure/release
   blocker. Classification does not convert 1B to ready and does not permit a
   prohibited fallback or a green download claim.
3. Tester then runs the full feature QA/manual matrix on a fresh build,
   including real installed-model smoke and the truthful 1B failure/success
   path appropriate to gate 2.

Only after independent review and Tester evidence may the orchestrator decide
the S10/S11 completion status. The previous S10 approval does not prove runtime
success, and this ADR itself makes no such claim.
