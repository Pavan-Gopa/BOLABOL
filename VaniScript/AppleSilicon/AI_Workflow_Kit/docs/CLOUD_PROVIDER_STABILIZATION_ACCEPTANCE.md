# CLOUD_PROVIDER_STABILIZATION — Acceptance Evidence

> Living acceptance document for the `CLOUD_PROVIDER_STABILIZATION` track.
> CPS-01 section below is diagnostic evidence only; no product code was changed.

---

## CPS-01 — Evidence gate (OBS-002 root cause + provider contract freeze)

**Date:** 2026-07-26
**Role:** Implementation Engineer (diagnostic, doc-only)
**Branch:** `orchestrator/cloud-provider-stabilization`
**Pre-checkpoint:** `cloud-provider-stabilization/pre-CPS-01`

### 1. Baseline build/test (fresh native Apple Silicon build)

| Command | Result |
|---|---|
| `swift build` | `Build complete! (12.77s)` — 0 errors |
| `swift test` | **331 tests in 47 suites — ALL PASS** (0.194s test run) |

No stale `.app` was used; all evidence below is against this fresh build of the
current branch source.

### 2. OBS-002 root cause — **VERIFIED**

**Exact symbol/path/branch:**

`Sources/VaniScriptCore/AppSettings.swift` →
`AppSettings.synchronizeLocalModelsWithDisk()` (lines 641–649):

```swift
let supportedCloudTranslationKeys =
    Set(["gemini-cloud", "gpt-cloud"] + customCloudProviders.map(\.id))
if translationProvider != AppSettings.defaults.translationProvider,   // "mlx-native"
   !supportedTranslationKeys.contains(translationProvider),           // local MLX ids only
   !supportedCloudTranslationKeys.contains(translationProvider) {
    translationProvider = AppSettings.defaults.translationProvider    // ← silently resets
}
```

The cloud-translation whitelist was written before A5 and **omits the A5 catalog
ids `qwen`, `openrouter`, `ollama-cloud`** (it contains only the legacy
`gemini-cloud` / `gpt-cloud` plus custom provider ids).

**Failure sequence (click path, Settings → runtime):**

1. `SettingsView.ProviderCardView.cloudProviderCard` → role toggles
   (`SettingsView.swift:1737–1748`): the `Use for Translation` button calls
   `store.updateSettings { $0.translationProvider = engineID }` where
   `engineID == descriptor.id == "openrouter"` (catalog ids,
   `CloudProviderCatalog.swift:112–118`).
2. `WorkflowStore.updateSettings` (`WorkflowStore.swift:2683–2714`) applies the
   mutation, then **immediately** calls
   `workflow.settings.synchronizeLocalModelsWithDisk()` (line 2686).
3. The sanitizer branch above sees `"openrouter"` — not the default, not a
   downloaded local MLX id, not in the stale cloud whitelist — and **rewrites
   `settings.translationProvider` back to `"mlx-native"` before anything else
   runs.**
4. Consequently `translationProviderChanged` (line 2689) compares the *sanitized*
   value against `previousSettings` → `false` → no
   `forceTranslationProvider` in `WorkflowState.synchronizeProviderSelections`
   (`WorkflowState.swift:64–83`), no active-session sync, and
   `persistSettings()` persists the already-reverted `"mlx-native"`.
5. SwiftUI re-renders the card from `store.settings.translationProvider`
   (`SettingsView.swift:1629`) → button renders unselected again.

**Observed UI semantics explained by this single branch:**

| Human observation | Explanation |
|---|---|
| Click appears ignored | Value is reverted inside the same `updateSettings` call, before the next render |
| Momentary select then reset | Any intermediate render between mutation and sanitize (timing-dependent) |
| Saved in Settings but not in workflow | Not possible to persist: sanitizer runs before `persistSettings()`; persisted value is always `"mlx-native"` |
| Selected but runtime uses another provider | Runtime (`session.translationProvider` / `workflow.translationProvider`, `WorkflowStore.swift:1742–1755`) only ever sees the sanitized value |

**Downstream layers are NOT at fault (verified by inspection):**

- `ProviderRegistry.availableTranslationProviders` (`ProviderRegistry.swift:90–151`)
  **does** include `qwen`/`openrouter`/`ollama-cloud` when a key is saved and
  `capabilities.supportsTranslation == true` (true for all three in
  `CloudProviderCatalog`).
- `WorkflowStore.refreshProviderSelections` (`WorkflowStore.swift:3078–3093`)
  would have accepted `"openrouter"` — it only resets ids missing from the
  registry list.
- `CloudChatRouter.route` (`ProviderRegistry.swift:237–284`) and
  `ActiveCloudTranslationProvider.resolve`
  (`CloudTextTranslationEngine.swift:15–55`) resolve `"openrouter"` correctly
  (endpoint `https://openrouter.ai/api/v1/chat/completions`, settings model with
  catalog-default fallback). The selection simply never reaches them.

**Generic vs OpenRouter-specific:** **generic** for all three A5 router
providers. `"qwen"` and `"ollama-cloud"` fail the same whitelist test;
`"gemini-cloud"` and `"gpt-cloud"` are whitelisted, which is exactly why the
legacy cards work. **VERIFIED** by the same branch condition (the whitelist
literal) plus executable probe below.

**Executable confirmation (reproducible probe, real built `VaniScriptCore`):**

Retry note (post CHANGES_REQUESTED): the original `/tmp` probe was not
reproducible. It has been recreated in the git-ignored evidence directory
`/Users/pavan/Documents/AI Projects/VaniScript/UserData/WorkflowEvidence/CPS-01/`
(`.gitignore:64 VaniScript/UserData/`) and re-run on 2026-07-26T20:32:41Z
against build commit `11a64f8fe93931a9f7191508d39eeb10f0f7c7f4`:

- Probe source: `cps01_probe.swift`
  (SHA-256 `2846fee19e6e02d71313df3bd65aaa24328d02726739597ecf2cb3fdb945402d`)
- Compile/run command: `cps01_probe_command.txt` — `swiftc -I
  .build/arm64-apple-macosx/debug/Modules cps01_probe.swift
  .build/arm64-apple-macosx/debug/VaniScriptCore.build/*.o -L
  .build/arm64-apple-macosx/debug -o cps01_probe` — i.e. it imports and calls
  the **actually built `VaniScriptCore` module of this branch**, not a copied
  whitelist mirror.
- stdout (`cps01_probe_stdout.txt`):

```text
before sanitize: openrouter
after sanitize: mlx-native            ← OBS-002 reset branch fires
gemini-cloud after sanitize: gemini-cloud   ← legacy id survives (whitelisted)
qwen after sanitize: mlx-native       ← generic, not OpenRouter-specific
ollama-cloud after sanitize: mlx-native     ← third A5 id, same reset
```

(Probe contains no real key; the only key-like value is the dummy literal
`"test-key-not-real"`. All probe artifacts live only in the ignored evidence
folder, not in git.)

### 3. Chain map: Settings → persistence → workflow/session → runtime

```text
ProviderCardView (SettingsView.swift:1737)  click sets settings.translationProvider = "openrouter"
  └─ WorkflowStore.updateSettings (WorkflowStore.swift:2683)
       ├─ AppSettings.synchronizeLocalModelsWithDisk (AppSettings.swift:641)  ← ROOT CAUSE: resets to "mlx-native"
       ├─ AppSettings.normalizeMcpSettings                                   (unrelated)
       ├─ WorkflowState.synchronizeProviderSelections (WorkflowState.swift:64) — never forced (change flag already false)
       ├─ persistSettings()                                                   — persists reverted value
       ├─ WorkflowStore.refreshProviderSelections (WorkflowStore.swift:3078)  — would accept "openrouter"; never sees it
       └─ WorkflowState.synchronizeActiveSessionProviders (WorkflowState.swift:85) — skipped (no change detected)
Runtime: ActiveCloudTranslationProvider.resolve(session.translationProvider) (WorkflowStore.swift:1750–1755)
```

### 4. Black-box live UI pass — EXECUTED (Human-assisted, 2026-07-27 local)

**Build identity:** fresh binary
`.build/arm64-apple-macosx/debug/VaniScript` built from commit
`11a64f8fe93931a9f7191508d39eeb10f0f7c7f4` on branch
`orchestrator/cloud-provider-stabilization` immediately before the pass
(`swift build` green, `swift test` 331/331 PASS re-run this session). No stale
`.app` used.

**Protocol executed:** Human entered a valid OpenRouter key directly in the app
UI (never in chat/logs). Model `google/gemini-2.5-flash` selected; target
language `Russian` (≠ `Same`). Human clicked `Use for Transcribing` and
`Use for Translation` on the OpenRouter card.

**Live observation (Human):** both role buttons on the OpenRouter card
**do not latch** — the click produces no selected state (OBS-002 reproduced
live on this fresh build).

**Measured provider IDs** (read-only snapshots of persisted
`~/Library/Application Support/VaniScript/settings.json` via
`snapshot_ids.sh` — prints ids only, never keys):

| Moment | settings.translationProvider | workflow.translationProvider | session.translationProvider | UI state | Runtime route |
|---|---|---|---|---|---|
| Before click (20:32:59Z) | `gemini-cloud` | derived from settings (see note) | `mlx-native` (persisted project session, `projects.json`) | OpenRouter buttons unselected | n/a |
| Immediately after click (20:48:52Z) | `mlx-native` ← **reset to default, not `openrouter`** | `mlx-native` (refreshed from sanitized settings) | `mlx-native` | button did not latch (Human observed) | n/a |
| Reopen Settings | `mlx-native` (persisted file unchanged) | `mlx-native` | `mlx-native` | unselected | n/a |
| Restart app (20:54:47Z; re-verified after rebuild/relaunch 21:01:13Z) | `mlx-native` (persisted) | `mlx-native` on `WorkflowState.initial` | `mlx-native` | unselected | n/a |
| Minimal translation (21:11:30Z, after retake click) | `mlx-native` | `mlx-native` | `mlx-native` (measured: `projects.json [0].session.translationProvider`) | translation **errored / did not start** (Human observed) | **`mlx-native` effective; OpenRouter route NOT used** — persisted `usage` map is **empty** before and after (no `openrouter:*` usage key was ever recorded; every cloud request would have written one per §8/UsageRecorder), and session translations were untouched (chunk `updatedAt` all 2026-07-08) |

Note: `workflow`/`session` values are not directly serialized to a readable
artifact without product instrumentation (forbidden this step); the workflow
column states the value dictated by the verified code path
(`WorkflowState.initial` / `synchronizeProviderSelections` copy from the
already-sanitized settings — §2 and §3). The **settings column is measured**,
and it is the smoking gun: the persisted value went `gemini-cloud →
mlx-native` after the click, exactly the sanitizer-reset the root cause
predicts (the clicked `openrouter` value never survived to disk, and even the
previous `gemini-cloud` selection was replaced by the default because the
sanitizer fired mid-`updateSettings`).

Snapshot artifacts (ids only, no secrets; all in the ignored evidence dir,
SHA-256 list in `screenshots_sha256.txt`):
- `ids_after_click.txt` (`b9a55869…c77e472`), `ids_final.txt`
  (`35813f59…882600`), `ids_before_retake.txt` (`4bf50e90…5a6140`),
  `ids_after_translation.txt` (`22a09a42…bd9afc`);
- `usage_before_translation.txt` (`c1c30e0f…42788a`) and
  `usage_after_translation.txt` (`4c88461b…39da0a`) — both `usage: empty`;
- `session_after_translation.txt` (`73c31152…f4cdb6`) —
  `session.translationProvider = mlx-native`.

**Minimal translation (executed, 2026-07-27 local):** after the retake click
Human ran one minimal translation attempt on the fresh rebuilt binary. Result:
**errored / did not start** (effective provider is the sanitizer-forced
`mlx-native`, and no ready local MLX model path serves it). Proof OpenRouter
was NOT used: (a) persisted `usage` map remained **empty** before and after —
every real cloud call records a `providerId:model` usage key via
`UsageRecorder`; an OpenRouter request would have produced
`openrouter:google/gemini-2.5-flash`; (b) `session.translationProvider`
measured `mlx-native`; (c) no session chunk translation was updated (all
`updatedAt` remain 2026-07-08). Read-only inspectors used: `snapshot_ids.sh`,
`snapshot_session.sh`, `snapshot_usage.sh` (ids/counters only, never keys).

**Qwen repeat (CPS-01 requirement 3 — safe mock-backed profile, NOT a live UI
pass):** a live Qwen PAYG UI repeat was impossible — Human's Qwen key is
rejected as invalid (OBS-001: Token Plan key vs fixed PAYG endpoint; validation
blocks the card before any role click). The requirement-3 repeat is therefore
satisfied by the **safe mock-backed profile**: the reproducible probe of §2
drives the real built `VaniScriptCore` with a dummy (mock) key through the
identical mutation path and shows the same reset for `qwen → mlx-native` and
`ollama-cloud → mlx-native`. This is explicitly a built-module logic repeat,
not a live UI check.

**Screenshots — classified as separate observation evidence.** Independent
Orchestrator visual review confirmed that `openrouter_before.png` actually
depicts the Qwen card (`qwen-plus`, status `Invalid`) and therefore belongs to
OBS-001, while `openrouter_after.png` depicts the valid OpenRouter card with
the selected model, masked key, both role buttons and Cloud API Usage summary
for OBS-002/OBS-003. The files are not represented as a same-card temporal pair.

| File (absolute path) | SHA-256 | Captured (local) | Status |
|---|---|---|---|
| `/Users/pavan/Documents/AI Projects/VaniScript/UserData/WorkflowEvidence/CPS-01/openrouter_before.png` | `1ea1d325d23aae8286e6cfe1874edb01d82cfa32ad94ec91fb7a97395102527e` | 2026-07-27 02:40:42 | OBS-001 context — Qwen card (`qwen-plus`, Invalid) |
| `/Users/pavan/Documents/AI Projects/VaniScript/UserData/WorkflowEvidence/CPS-01/openrouter_after.png` | `50296d4a66883ea71782b50a6b74ef8726e35a8484d61e16bc2ecf0b760f4730` | 2026-07-27 02:40:55 | OBS-002 state — valid OpenRouter card; role buttons remain unlatched |

**Corrected retake protocol (one continuous UI session — Human executes; agent
cannot render images):**

1. Open **Settings → API & Usage**.
2. Select **OpenRouter** as the active provider card.
3. Wait for all of: the `OPENROUTER` heading; a **Valid** badge; model
   `google/gemini-2.5-flash`; and a **fully masked key**.
4. **Before** clicking `Use for Translation`, save
   `openrouter_before.png`.
5. Without switching provider or closing Settings, click `Use for Translation`.
6. Immediately save `openrouter_after.png`.
7. Both frames MUST show the **same OpenRouter card** in the **same viewport**
   (heading `OPENROUTER`, Valid badge, `google/gemini-2.5-flash`, masked key,
   both role buttons, header badge, Cloud API Usage summary). `after` shows the
   button **not latched** = the defect state.

**Human-confirmed no-op (2026-07-27):** after clicking the OpenRouter role
button, “ничего не меняется”. A visually different `after` state therefore
does not exist—the absence of a UI delta is the defect. By Human decision, the
single verified OpenRouter state frame plus the measured before/after provider
ids, reproducible built-module probe and runtime-route evidence satisfy the
material evidence gate. A second visually identical OpenRouter capture is not
required for CPS-01 closure. No secret is present in any recorded artifact.

**Re-verification (2026-07-27):** Orchestrator rendered both files directly,
classified them as Qwen context + OpenRouter no-op state, and verified that
the visible API keys are masked. This classification supersedes the earlier
incorrect same-card-pair claim without pretending that the Qwen frame is an
OpenRouter `before` frame.

### 5. Provider contract table (official sources, accessed 2026-07-26)

| Contract | Verified value | Source (accessed 2026-07-26) |
|---|---|---|
| Qwen PAYG (Singapore/intl) base URL | `https://dashscope-intl.aliyuncs.com/compatible-mode/v1` (OpenAI-compatible). Key must match same region **and** billing plan, else 401. Workspace-dedicated domains `[ws].[region].maas.aliyuncs.com` recommended for production. | https://www.alibabacloud.com/help/en/model-studio/base-url |
| Qwen PAYG credential kind | Model Studio API key of the same region/billing plan; keys are **not** cross-region or cross-plan compatible | same as above |
| Qwen Token Plan (Team Edition) endpoint | Singapore only: `https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1` (Anthropic-compatible path also exists). Requires the **dedicated Token Plan API key** (per-seat) | https://www.alibabacloud.com/help/en/model-studio/base-url, https://www.alibabacloud.com/help/en/model-studio/token-plan-overview |
| Qwen Token Plan model allowlist | Exact-string allowlist, no version inference. Text/reasoning: `qwen3.7-max`, `qwen3.7-plus`, `qwen3.6-plus`, `qwen3.6-flash`, `deepseek-v4-pro`, `deepseek-v4-flash`, `deepseek-v3.2`, `kimi-k2.7-code`, `kimi-k2.6`, `kimi-k2.5`, `glm-5.2`, `glm-5.1`, `glm-5`, `MiniMax-M2.5`; image: `qwen-image-2.0(-pro)`, `wan2.7-image(-pro)` | https://www.alibabacloud.com/help/en/model-studio/token-plan-overview |
| Qwen Token Plan use restrictions | "Interactive use in AI coding tools such as Claude Code and Codex only; not for backend services / automated scripts" — violations risk key revocation. Billed in Credits, not PAYG USD | same as above |
| Qwen CLI (qwen-code) credentials/model | Layered resolution CLI → env → settings → defaults; OpenAI-compatible auth via `--auth-type openai` with `--openai-api-key` / `--openai-base-url` / `--model` (env/settings equivalents; `modelProviders` catalog recommended, credentials referenced via `envKey`) | https://qwenlm.github.io/qwen-code-docs/en/users/configuration/model-providers/, https://qwenlm.github.io/qwen-code-docs/en/users/configuration/settings/ |
| OpenRouter transcription endpoint | Dedicated `POST /api/v1/audio/transcriptions` (JSON base64 `input_audio` **or** OpenAI-style multipart). Same auth as chat completions | https://openrouter.ai/docs/guides/overview/multimodal/stt |
| OpenRouter STT model capability contract | Model-level, discoverable via `GET /api/v1/models?output_modalities=transcription`; model slug required (e.g. `openai/whisper-1`). Two distinct routes: dedicated STT endpoint vs `input_audio` in chat completions | same as above |

**Consequences already anticipated by architecture (confirmed here):**
- The app's fixed `dashscope-intl.aliyuncs.com` endpoint cannot serve Token Plan
  keys (separate base URL + dedicated key) → OBS-001 mechanism confirmed by the
  official base-URL/plan-compatibility rule.
- OpenRouter transcription is a **model-level** capability with a dedicated
  endpoint → provider-wide `supportsTranscription=false` (OBS-003) is
  confirmed insufficient; CPS-07 must use the `output_modalities` filter.
- Embedded Qwen model selection vs Token Plan allowlist remains a CPS-04 risk
  (allowlist recorded above).

### 6. Missing regression seam (for CPS-06)

No test exercises `WorkflowStore.updateSettings` (or
`AppSettings.synchronizeLocalModelsWithDisk`) with the A5 catalog provider ids
as `translationProvider`. `WorkflowStateTests` cover
`synchronizeProviderSelections` only with already-valid ids. CPS-06 must add a
click-equivalent test: `updateSettings { translationProvider = "openrouter" }`
→ value survives sanitize → reaches workflow/session/route.

### 7. Redaction statement

No real API key, Authorization header, token or secret was read, printed,
logged, stored in the probe, snapshots, screenshots hashes, this document, or
git. The only key-like string used was the literal dummy `"test-key-not-real"`
inside the probe in the git-ignored evidence folder. The snapshot script reads
only provider/model id fields from persisted settings. Human entered the real
OpenRouter key exclusively in the app UI; screenshots were captured by Human
with the key masked. Evidence folder `VaniScript/UserData/` is git-ignored
(`.gitignore:64`) and none of its files are tracked.

### 8. Proven vs remaining UNKNOWN

**VERIFIED (source-level):**
- OBS-002 root cause: stale cloud-translation whitelist in
  `AppSettings.synchronizeLocalModelsWithDisk()` (file/symbol/branch in §2),
  fired on every click via `WorkflowStore.updateSettings`.
- Defect is generic (`qwen`, `openrouter`, `ollama-cloud`) via the reproducible
  probe against the real built module (§2); legacy `gemini-cloud`/`gpt-cloud`
  unaffected.

**VERIFIED (live black-box, Human-assisted §4):**
- OpenRouter `Use for Translation` (and `Use for Transcribing`) click does not
  latch on a fresh build with a valid key, model
  `google/gemini-2.5-flash`, target ≠ `Same`.
- Persisted `settings.translationProvider` measurably reset
  `gemini-cloud → mlx-native` across the click (never `openrouter`), matching
  the sanitizer-reset prediction; state persists across reopen/restart.
- Redacted before/after screenshot pair captured and hashed (§4) — **pair
  INVALID**: the `before` frame shows the Qwen card (`qwen-plus`, Invalid), not
  OpenRouter; a valid same-card retake is required (§4).

**VERIFIED (contracts):**
- Qwen PAYG/Token Plan endpoints, key kinds, allowlist and use limits (official
  docs, accessed 2026-07-26).
- OpenRouter dedicated STT endpoint and model-level capability discovery.
- Baseline: `swift build` green; `swift test` 331/331 PASS (re-run at retry).

**HYPOTHESIS:**
- "Momentary select then reset" flicker is a render-timing artifact of the same
  reset (not a second defect).

**VERIFIED (runtime, added at second retake):**
- Minimal translation attempt executed: effective provider `mlx-native`
  (sanitizer-forced), translation **errored / did not start**, and the
  OpenRouter route was **not** used — persisted `usage` map empty
  before/after (no `openrouter:*` key), session translations untouched (§4).

**UNKNOWN (explicitly open):**
- Live Qwen PAYG UI repeat — blocked by OBS-001 (Human's Qwen key invalid
  against the fixed PAYG endpoint); requirement-3 repeat is covered by the
  safe mock-backed built-module probe (§4), not by a live UI pass.
- A distinct visual `after` state does not exist because the click is a no-op.
  Human explicitly confirmed the absence of change; Orchestrator directly
  rendered and classified the available Qwen/OpenRouter frames (§4).
- Exact local error surface of the failed `mlx-native` translation attempt
  (no readable log artifact without product instrumentation; irrelevant to
  OBS-002 — the point proven is that OpenRouter was not routed).
- Whether the currently selected embedded Qwen model belongs to the Token Plan
  allowlist of the Human's actual subscription (CPS-04).

### 9. Gate decision (separated per CHANGES_REQUESTED)

| Gate | Status | Basis |
|---|---|---|
| Source-level root cause OBS-002 | **VERIFIED** | §2 symbol/branch + reproducible probe |
| Live black-box evidence | **CAPTURED**: Human-confirmed click no-op, measured settings/session ids, OpenRouter state frame, and minimal-translation runtime-route proof (`mlx-native` effective, OpenRouter not routed). Qwen repeat = safe mock-backed probe (not live UI, per OBS-001) | §4 |
| CPS-01 step Done | **Ready for re-review** — source root cause, measured IDs, runtime-route proof and Human-confirmed absence of visual change are documented. The Qwen frame is classified honestly as OBS-001 context rather than mislabelled as OpenRouter `before`. | this doc |
| CPS-02 | Unblock **recommended** — endpoint/key-kind contracts frozen with sources+dates; no dependency on the open UNKNOWNs | §5 |
| CPS-06 | Unblock **recommended** — root cause VERIFIED (source + live + runtime route proof), fix scope and regression seam recorded | §2, §4, §6 |

No gate is declared fully closed by this document alone; closure is decided by
Orchestrator after review of the attached live evidence.
