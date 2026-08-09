# LOCAL_ASR_COREML — Acceptance / Smoke Skeleton

> **Status:** DESIGN SKELETON — NOT RUN.  
> Заполняется фактическими командами/evidence на `LASR-08`; финализируется doc-only на `LASR-09`.  
> Scope: Apple Silicon; exactly Parakeet TDT 0.6B v3, Canary Flash 180M, Canary 1B v2.

## 1. Gate policy

- Один блокирующий FAIL/NOT RUN по любой из трёх моделей означает общий статус **NOT ACCEPTED**.
- Unit/fixture tests не заменяют real package download + offline transcription smoke.
- Нельзя использовать Python/NeMo/ONNX/MLX как скрытый ASR fallback.
- Не коммитить model weights, package archives, API keys, private Drive tokens or unredacted user paths.
- Evidence хранится вне repo или в approved ignored evidence root; в документе фиксируются redacted path, SHA-256, environment and command.

## 2. Environment record

| Item | Actual value |
|---|---|
| Date/time | NOT RECORDED |
| Build commit/tag | NOT RECORDED |
| Host / Apple Silicon chip / RAM | NOT RECORDED |
| macOS version | NOT RECORDED |
| Swift/Xcode | NOT RECORDED |
| App build command/result | NOT RUN |
| Test command/result/counts | NOT RUN |
| SharedModelsRoot | REDACTED / NOT RECORDED |
| Network state during inference | NOT RECORDED |

## 3. Release-source record

| Model | Source/revision | Package/layout integrity | Status |
|---|---|---|---|
| `parakeet-tdt-06b-v3` | FluidAudio `0.15.5`, v3/int8; HF attribution `FluidInference/parakeet-tdt-0.6b-v3-coreml` | SDK layout/presence evidence NOT RECORDED | NOT RUN |
| `canary-180m-flash-coreml` | `aufklarer/Canary-180M-Flash-CoreML`; immutable revision NOT RECORDED | Required file/hash evidence NOT RECORDED | NOT RUN |
| `canary-1b-v2-coreml` | Human Drive direct URL or configured base URL NOT SUPPLIED | package ID/layout/bytes/archive SHA-256/per-file manifest NOT SUPPLIED | BLOCKED ON HUMAN INPUT |

Private/full Drive URL may be recorded in release configuration/evidence, not pasted here if it contains an access token. Record a redacted locator and digest.

## 4. Automated contract checklist

### Catalog / migration

- [ ] Exactly the three new model IDs exist; no fourth new ASR model.
- [ ] Existing WhisperKit and MLX settings decode/round-trip without path/provider reset.
- [ ] `LocalModelRuntime`/storage raw values are migration-safe.
- [ ] Parakeet supports auto; both Canary entries reject auto.
- [ ] Canary Flash languages equal `en/de/fr/es`.
- [ ] Canary 1B languages equal the catalog 25 including `ru/uk`.
- [ ] Canary 1B minimum OS equals macOS 15.0.

### Install / presence / integrity

- [ ] HF paths reject absolute/empty/`..` traversal.
- [ ] HF revision is immutable; no floating layout assumption.
- [ ] Remote package rejects wrong archive SHA-256.
- [ ] Remote package rejects HTML/login/Drive confirmation content.
- [ ] Extraction rejects traversal and symlink escape.
- [ ] Missing/extra/wrong-hash required file cannot become Ready.
- [ ] Failed replacement preserves prior verified install.
- [ ] Cancellation removes untrusted staging.
- [ ] Insufficient disk fails before destructive replacement.
- [ ] Delete cannot escape the descriptor-owned SharedModelsRoot child.
- [ ] Scan/Locate/reconcile/provider lookup use the same completeness policy.

### Engines / routing

- [ ] Parakeet engine uses FluidAudio v3/int8 and fresh decoder state.
- [ ] Multichannel preparation selects loudest physical channel before 16 kHz mono conversion.
- [ ] Canary uses `.cpuAndNeuralEngine`; no `.all`.
- [ ] Flash internal windows are ≤10 s.
- [ ] 1B internal windows are ≤15 s with fresh `MLState` per window.
- [ ] Canary rejects missing/auto/unsupported source before model work.
- [ ] Canary has no AST/speech-translation path.
- [ ] Unknown/unready local ID fails explicitly; no Whisper fallback.
- [ ] Batch, current-chunk and live-dictation entry points use descriptor routing.
- [ ] Outer VaniScript chunk boundaries persist across Canary internal windowing.
- [ ] Source glossary applies exactly once, then existing translation path runs.
- [ ] Previous ASR engine unloads on model/path switch.
- [ ] Canary 1B is released before local MLX translation residency.

### UI / accessibility

- [ ] Exactly three new cards appear with source, size, languages, runtime and state.
- [ ] Download/Retry/Locate/Use/Delete reflect persisted install state.
- [ ] Canary 1B card stays visible but disabled on macOS 14 with macOS 15+ explanation.
- [ ] Parakeet source picker includes `auto`.
- [ ] Canary source picker excludes `auto` and filters to supported explicit languages.
- [ ] Initialize is blocked with actionable copy for invalid Canary source.
- [ ] VoiceOver labels expose model/runtime/state/action/OS requirement.

## 5. Build and test evidence

```text
Command: swift build
Result: NOT RUN

Command: swift test
Result: NOT RUN
Suites/tests/failures: NOT RECORDED

Command: QA runner from QA manifest
Result: NOT RUN
PASS/FAIL counts: NOT RECORDED
```

Required static QA assertions:

- [ ] no `bolabolCDN` / `cdn.bolabol.app` / Bolabol package ID in VaniScript product code;
- [ ] no Python/NeMo/ONNX/MLX ASR route;
- [ ] no `.all` compute configuration in Canary engine;
- [ ] no tracked model archive/weights;
- [ ] new catalog IDs set equals the three in-scope IDs.

## 6. Real-model smoke matrix

### P1 — Parakeet download/select/auto/offline ASR

**Preconditions:** clean Parakeet destination; network available only for user-initiated download; source language `auto`.

1. Open Settings → Models.
2. Download `parakeet-tdt-06b-v3`; record progress and final canonical path/presence (path redacted).
3. Select Use; verify provider persists after Settings reopen/app restart.
4. Transcribe representative ≥60 s audio containing at least two supported languages or one Russian/English sample.
5. Disable network before inference repeat; confirm same route and non-empty transcript.

- [ ] Download reaches Ready only with complete FluidAudio layout.
- [ ] `auto` is accepted.
- [ ] Offline inference produces non-empty source text.
- [ ] Engine identity/log evidence is Parakeet, not WhisperKit/cloud.
- [ ] Result/evidence: NOT RUN.

### C1 — Canary Flash explicit-source/offline ASR

**Preconditions:** clean Flash destination; source fixture(s) EN and one of DE/FR/ES.

1. Download from pinned `aufklarer/Canary-180M-Flash-CoreML` revision.
2. Select Use; verify source choices are exactly EN/DE/FR/ES and no Auto.
3. Transcribe EN with source `en`.
4. Transcribe one non-EN supported fixture with matching explicit code.
5. Disable network and repeat one inference.

- [ ] Required Flash layout is complete before Ready.
- [ ] Both supported-language transcripts are non-empty and plausible.
- [ ] No AST/target-language behavior is exposed.
- [ ] Engine identity/log evidence is Canary Flash.
- [ ] Result/evidence: NOT RUN.

### C2 — Canary 1B remote package/explicit RU or UK/offline ASR

**Preconditions:** macOS 15+; Human release metadata frozen; enough free disk for archive + staging + installed package.

1. Download using direct Drive URL or configured base URL.
2. Record redirect/content-type/archive-size/hash/manifest verification without exposing private URL tokens.
3. Select Use; choose explicit `ru` or `uk`.
4. Transcribe representative matching-language audio longer than 15 s.
5. Disable network and repeat inference.

- [ ] Package reaches Ready only after archive + per-file integrity checks.
- [ ] Source list contains catalog 25 and no Auto.
- [ ] Multi-window transcript is ordered and non-empty.
- [ ] Engine identity/log evidence is Canary 1B Path B.
- [ ] No network request occurs during inference.
- [ ] Result/evidence: BLOCKED / NOT RUN.

## 7. Negative smoke

| ID | Scenario | Expected | Actual |
|---|---|---|---|
| N1 | Canary source = `auto` | Start blocked; explicit-source message; no model load | NOT RUN |
| N2 | Flash source = `ru` | Unsupported-language block; no silent `en` fallback | NOT RUN |
| N3 | Canary 1B on macOS 14 | Download/Use disabled; engine cannot load | NOT RUN |
| N4 | Truncated/corrupt 1B archive | SHA/size failure; staging removed; not Ready | NOT RUN |
| N5 | Drive returns HTML/login/confirmation page | Content error; retry guidance; not extracted | NOT RUN |
| N6 | 1B manifest missing required decoder/model | Completeness failure; not Ready | NOT RUN |
| N7 | Package contains `../`, absolute path or escaping symlink | Install rejected; no write outside staging | NOT RUN |
| N8 | Model/path switched mid-session | Immutable route for active operation or explicit cancellation; no mixed engine | NOT RUN |
| N9 | Unknown local provider ID | Explicit unavailable; no Whisper/cloud fallback | NOT RUN |
| N10 | Download cancelled | Partial staging removed or safely resumable per contract; not Ready | NOT RUN |

## 8. Regression smoke

- [ ] Existing WhisperKit model downloads/locates/selects/transcribes.
- [ ] Cloud transcription still routes and records usage.
- [ ] Local MLX translation runs after local ASR.
- [ ] Source glossary is applied once.
- [ ] Existing projects/settings reopen without provider/path reset.
- [ ] MCP `list_providers`/selection reports the same readiness policy as UI.
- [ ] Result/evidence: NOT RUN.

## 9. Residency/performance record

Record facts for each model on the same host; do not set universal performance promises from one machine.

| Model | Load time | Peak resident memory | RTF/elapsed | ASR→MLX overlap | Result |
|---|---:|---:|---:|---|---|
| Parakeet | NOT RECORDED | NOT RECORDED | NOT RECORDED | NOT RECORDED | NOT RUN |
| Canary Flash | NOT RECORDED | NOT RECORDED | NOT RECORDED | NOT RECORDED | NOT RUN |
| Canary 1B | NOT RECORDED | NOT RECORDED | NOT RECORDED | NOT RECORDED | NOT RUN |

Required observations:

- [ ] only one local ASR engine resident after model switch;
- [ ] Canary 1B not prewarmed at launch;
- [ ] Canary 1B released before local MLX translation load;
- [ ] no crash/ANE allocation failure on representative long input.

## 10. UI evidence

Required screenshots/recording, with user paths/URLs/tokens redacted:

1. Three new model cards in Not installed/Ready states.
2. Canary 1B Unsupported OS state on macOS 14 (real host or controlled availability seam clearly labeled).
3. Parakeet source picker with Auto.
4. Canary Flash picker with four explicit languages and no Auto.
5. Canary 1B explicit RU/UK selection on macOS 15+.
6. Failed corrupt/expired package state with actionable copy.

Evidence paths/hashes: NOT RECORDED.

## 11. Final status

| Gate | Status |
|---|---|
| Human Canary 1B package input | BLOCKED |
| Build/tests | NOT RUN |
| QA static | NOT RUN |
| Parakeet real smoke | NOT RUN |
| Canary Flash real smoke | NOT RUN |
| Canary 1B real smoke | BLOCKED / NOT RUN |
| Negative/regression smoke | NOT RUN |
| UI/accessibility evidence | NOT RUN |
| Independent Verification | NOT RUN |

**Overall:** `DESIGN SKELETON — NOT ACCEPTED / NOT RUN`.
