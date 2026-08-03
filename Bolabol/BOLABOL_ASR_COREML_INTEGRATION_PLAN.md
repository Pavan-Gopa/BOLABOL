# Bolabol — план интеграции ASR (Core ML): GigaAM + Canary 1B + Canary Flash

| | |
|--|--|
| **Продукт** | Bolabol |
| **Версия train** | **1.0.4** (рабочее имя; маркетинг можно уточнить) |
| **Документ** | Единый master plan для оркестратора и агентов |
| **Статус** | К согласованию → затем workflow (Coder / Reviewer / Tester) |
| **Дата** | 2026-08-03 |

---

## 0. Резюме (1 страница)

### Цель

Встроить в Bolabol **три локальных ASR-модели на Core ML** (ANE), с полным UX: Local Models (каталог, download, presence), выбор engine, диктовка, Help/Settings/i18n, плюс **пересборка онбординга** (UI language / primary / additional без путаницы).

| Модель | Роль | Языки | Target artifact (старт) |
|--------|------|-------|-------------------------|
| **GigaAM v3 (RU)** | Лучший offline **русский** ASR | RU (EN слова внутри RU — по возможностям модели) | Core ML: `huggingfinger0/gigaam-v3-coreml` (spike); alt: `smkrv` / `vadimsuhanov` e2e-rnnt-coreml |
| **Canary 1B v2** | Большая multilingual ASR (+ AST где export позволяет) | ~25 EU + RU/UK (по capabilities после spike) | **Core ML:** `FluidInference/canary-1b-v2-coreml` + FluidAudio |
| **Canary Flash ~180M** | Компактная быстрая multilingual | **EN, DE, FR, ES** (ASR + AST en↔{de,fr,es}) | Upstream: `nvidia/canary-180m-flash`; Core ML: **найти/конверт** (mobius / FluidInference) — gate S2 |

### Runtime policy (жёстко)

| Разрешено для ASR | Запрещено для ASR |
|-------------------|-------------------|
| **Core ML** (ANE / GPU / CPU) | Python / NeMo / pip runtime |
| Swift native decode loops | MLX **для ASR** (MLX остаётся только **polish**) |
| FluidAudio, где SDK уже есть | ONNX Runtime, sidecars |

**Почему Core ML, не MLX:** polish уже на MLX/Metal; ASR на ANE через Core ML разгружает GPU/Metal и соответствует текущему Parakeet/WhisperKit path.

### Что не делаем в 1.0.4

- GigaAM **Multilingual** (у пользователя достаточно multi/EN путей)
- Интеграция **битого** `alexwengg/canary-1b-v2-coreml` (ADR-012 остаётся в силе)
- Canary через mlx-audio / Python
- Полировка через Canary (V1/V2 = MLX/cloud как сейчас)

### Термины UX (обязательно)

| Термин | Смысл | Не путать |
|--------|--------|-----------|
| **Язык интерфейса** | UI: меню, Help, onboarding copy | Язык речи |
| **Основной язык** | Primary — язык, на котором **обычно диктуют** | UI language |
| **Дополнительный язык** | Additional — второй язык для работы / Canary switch | **Не** «всегда target output» |

Copy: additional = «второй язык, с которым вы часто работаете»; **не** «целевой язык результата всегда».

---

## 1. Артефакты и research baseline

### 1.1. GigaAM (русскоязычная)

| | |
|--|--|
| Upstream | [ai-sage/GigaAM-v3](https://huggingface.co/ai-sage/GigaAM-v3) / [salute-developers/GigaAM](https://github.com/salute-developers/GigaAM) |
| Core ML (кандидаты) | [huggingfinger0/gigaam-v3-coreml](https://huggingface.co/huggingfinger0/gigaam-v3-coreml) — Encoder + Predictor + JointDecision `.mlmodelc`, int8, window ~30 s |
| | [smkrv/gigaam-v3-e2e-rnnt-coreml](https://huggingface.co/smkrv/gigaam-v3-e2e-rnnt-coreml) |
| | [vadimsuhanov/gigaam-v3-e2e-rnnt-coreml](https://huggingface.co/vadimsuhanov/gigaam-v3-e2e-rnnt-coreml) |
| MLX (fallback only) | al-bo / aystream GigaAM MLX — **не цель 1.0.4**, если Core ML GO |

**Product:** только **RU-focused** card (не Multilingual GigaAM).

### 1.2. Canary 1B v2 (большая)

| | |
|--|--|
| Upstream | [nvidia/canary-1b-v2](https://huggingface.co/nvidia/canary-1b-v2) |
| Core ML (primary) | [FluidInference/canary-1b-v2-coreml](https://huggingface.co/FluidInference/canary-1b-v2-coreml) — int4 ANE ~573 MB, 15 s window, FluidAudio `CanaryManager` |
| Rejected | alexwengg/canary-1b-v2-coreml — ADR-012 NO-GO |

**OS:** int4 требует **macOS 15+** (iOS 18+) — зафиксировать в UI/capability gate.

### 1.3. Canary Flash ~180M (маленькая, 4 языка)

| | |
|--|--|
| Upstream | [nvidia/canary-180m-flash](https://huggingface.co/nvidia/canary-180m-flash) (~182M params) |
| Языки | ASR: **EN, DE, FR, ES**; AST en↔{de,fr,es} |
| Core ML | **На момент plan:** публичный FluidInference Core ML **не** подтверждён как готовый HF-repo (в отличие от 1B). Путь: |
| | (A) найти community Core ML export; (B) **mobius** convert + validate; (C) spike harness Swift |
| MLX | не primary |

**Product name:** «Canary Flash (EN/DE/FR/ES)» — compact, fast, quality edge.

### 1.4. GO/NO-GO policy

Каждая модель: **отдельный spike** → `docs/asr/<model>/COREML_SPIKE.md` → GO или NO-GO.  
NO-GO → **не** показывать Download в production catalog (можно «Coming soon» только с явного Human OK).  
GO → catalog + download + engine + tests.

---

## 2. Архитектура (to-be)

```
Audio 16 kHz mono
    → TranscriptionEngine (protocol)
         ├─ WhisperKitTranscriptionEngine     (as-is)
         ├─ ParakeetTranscriptionEngine       (FluidAudio, as-is)
         ├─ CanaryCoreMLEngine                (FluidAudio CanaryManager / native)
         │     ├─ canary-1b-v2-coreml
         │     └─ canary-180m-flash-coreml
         └─ GigaAMCoreMLEngine                (Encoder+Predictor+Joint RNNT)
    → text → glossary → polish (MLX/cloud) → insert
```

### 2.1. Backend enum

```swift
// NativeBolabolCore
enum TranscriptionModelBackend {
  case whisperKitCoreML
  case fluidAudioCoreML      // Parakeet
  case canaryCoreML          // 1B and Flash share family
  case gigaAMCoreML          // RU RNNT
}
```

### 2.2. Capabilities (честность)

```swift
struct ASRModelCapabilities: Sendable {
  var supportsAutoLanguageDetect: Bool   // Whisper/Parakeet true; Canary/GigaAM false
  var supportedLanguageCodes: [String]   // after spike
  var supportsSpeechTranslation: Bool    // Canary AST if export+API
  var maxChunkSeconds: Double
  var minOSVersion: OperatingSystemVersion?
  var approxDownloadBytes: Int64
  var isRecommendedForPrimaryRU: Bool    // GigaAM
  var isRecommendedForEnDeFrEs: Bool     // Flash
}
```

### 2.3. Download / presence

- Root: SharedModelsRoot / `canary/1b-v2/`, `canary/180m-flash/`, `gigaam/v3-rnnt/`
- Complete-folder check (все required `.mlmodelc` + vocab)
- Resume download (как существующий HF / model install path)
- Disk warning for 1B (~0.5–2 GB depending quant)

### 2.4. Language routing

| Engine | Language UI |
|--------|-------------|
| Whisper / Parakeet | HUD **A** auto default |
| Canary 1B / Flash | **No A**; letter = primary ↔ additional (if both in supported set); else clamp + banner |
| GigaAM | Fixed **RU** (or source=ru); primary≠ru → soft banner «GigaAM optimized for Russian» |

---

## 3. UX / UI (полный)

### 3.1. Onboarding — пересборка шагов (обязательно)

**Проблема as-is:** язык UI и speech languages смешиваются / дублируются, мало пояснений; блок моделей не зависит от выбора языков.

**To-be order (фиксированный каркас + динамический блок моделей):**

| # | Screen ID | Title (EN intent) | Content |
|---|-----------|-------------------|---------|
| 0 | `uiLanguage` | **Interface language** | Только язык UI. Hint: «Language of menus and help.» Footer: change later in **Settings → General**. |
| 1 | `primarySpeech` | **Main dictation language** | Основной язык диктовки. Footer: change later in **Settings → Hotkey → Your Languages**. |
| 2 | `additionalSpeech` | **Additional working language** | Дополнительный + Same as primary. **Не** «always force output». Footer: same Settings path. |
| 3 | `localModels` | **Local transcription models** | **Три карточки**, порядок = f(primary, additional) — см. §3.5. Download optional; can skip. Footer: change later in **Settings → Local Models**. |
| 4+ | existing | Permissions / Modes / Glossary / Theme | Modes: A vs Canary/GigaAM letters |

**Правила:**

- Пикеры speech: `LanguagePickerOrder` (en → Europe → Asia).  
- UI language: `LanguagePickerOrder.uiLanguages` (System sentinel separate).  
- Не дублировать primary/additional на одном экране с UI language.  
- После finish: speech pair + optional selected model = store.  
- EN keys + 15 locales (reuse B5 process).  
- Блок моделей **пересчитывается** при смене primary/additional, если пользователь вернулся Back с экрана 3.

### 3.2. Settings

| Location | Controls |
|----------|----------|
| **General** | Interface language (only) |
| **Hotkey → Your Languages** | Primary + Additional + Same as primary + engine note |
| **Local Models** | Full catalog; **same ranking helper** optional sort «Recommended for you» on top |
| **Help** | Update bilingual + new models sections |

### 3.3. Local Models — карточки (Settings full catalog)

Единый pattern (как Whisper/Parakeet):

| Card | Subtitle | Size | Actions | Badges |
|------|----------|------|---------|--------|
| **GigaAM v3 (Russian)** | Offline RU ASR · Core ML | ~from spike | Download / Delete / Use | **RU recommended** |
| **Canary 1B v2** | Multilingual ASR · Core ML · ANE | ~573 MB int4 | Download / Delete / Use | Multilingual · macOS 15+ |
| **Canary Flash 180M** | EN · DE · FR · ES · Fast · Core ML | ~from spike | Download / Delete / Use | **Compact · 4 languages** |
| Parakeet / Whisper family | as-is | | | Large v3 / Turbo / … |

**States:** Not installed · Downloading (progress) · Ready · Failed (retry) · Unsupported OS (Canary 1B int4).

**Banners:**

- Canary selected + primary/additional outside supported set → clamp + explain.  
- GigaAM + primary ≠ ru → soft tip.  
- No auto language on Canary/GigaAM → link Help.

### 3.4. HUD

| Engine | Left control |
|--------|--------------|
| Whisper / Parakeet | **A** ↔ letter (existing) |
| Canary | Primary letter ↔ Additional letter (if both supported) |
| GigaAM | Letter **R** (or endonym rule) fixed RU; no fake A |

### 3.5. Onboarding Local Models — **динамический порядок 3 карточек** (product-critical)

Блок на экране `localModels` (и при желании «Recommended» strip в Settings) **напрямую зависит** от ответов на шагах primary + additional.

#### 3.5.1. Входные данные

```text
primaryCode: String      // e.g. "ru", "en", "hi"
additionalCode: String   // may equal primary
```

UI language **не** участвует в ranking ASR (только speech pair).

#### 3.5.2. Наборы кодов

| Set | Codes |
|-----|--------|
| `ruFocus` | `ru` |
| `canaryFlashLangs` | `en`, `de`, `fr`, `es` |
| «широкий multi» | primary **не** в `ruFocus` **и** **не** оба (primary, additional) ⊆ `canaryFlashLangs` — типично: `hi`+`en`, `zh`+`en`, `ar`+`fr`, `ja`+`en`, … |

#### 3.5.3. Правила приоритета (строго по порядку проверки)

**Правило R1 — русский в приоритете**  
Если `primaryCode == "ru"` **или** `additionalCode == "ru"`:

| Slot | Model | Why |
|------|--------|-----|
| **#1** | **GigaAM v3 (Russian)** | Лучший RU offline-сценарий |
| **#2** | Canary Flash 180M **или** Canary 1B (см. tie-break) | Второй язык / multi |
| **#3** | Whisper Large v3 **или** Turbo / Parakeet | Надёжный fallback |

Tie-break #2/#3 при R1:

- если additional ∈ canaryFlashLangs (и ≠ only-ru) → **#2 Canary Flash**, **#3 Whisper Large v3**  
- иначе (ru+ru, ru+hi, ru+zh, …) → **#2 Whisper Large v3**, **#3 Whisper Large v3 Turbo** (или Canary 1B если GO и Human prefers multi — default: Whisper pair)

**Правило R2 — компактный Canary (EN/DE/FR/ES)**  
Если R1 **не** сработал, и **оба** `primary` и `additional` ∈ `canaryFlashLangs`  
**(или** primary ∈ canaryFlashLangs **и** additional == primary):

| Slot | Model | Why |
|------|--------|-----|
| **#1** | **Canary Flash 180M** | Быстро, компактно, закрывает 4 языка |
| **#2** | Whisper Large v3 | Качество / auto |
| **#3** | Whisper Large v3 Turbo | Быстрее Large v3 |

**Правило R3 — мультиязычные / «прочие» сочетания**  
Во всех остальных случаях (пример: **hi + en**, zh+en, ar+de, …):

| Slot | Model | Why |
|------|--------|-----|
| **#1** | **Whisper Large v3** | Широкий multi, auto |
| **#2** | **Whisper Large v3 Turbo** | Тот же класс, быстрее |
| **#3** | Canary 1B **если GO**, иначе Parakeet TDT / Canary Flash | Третий вариант по наличию |

**Канонические примеры (unit tests must lock):**

| Primary | Additional | Top 3 (default) |
|---------|------------|-----------------|
| ru | en | 1 GigaAM · 2 Canary Flash · 3 Whisper Large v3 |
| ru | ru | 1 GigaAM · 2 Whisper Large v3 · 3 Whisper Large v3 Turbo |
| en | es | 1 Canary Flash · 2 Whisper Large v3 · 3 Whisper Large v3 Turbo |
| en | en | 1 Canary Flash · 2 Whisper Large v3 · 3 Whisper Large v3 Turbo |
| hi | en | 1 Whisper Large v3 · 2 Whisper Large v3 Turbo · 3 Canary 1B (if GO) else Parakeet |
| zh | en | same as R3 |
| de | fr | 1 Canary Flash · 2 Whisper Large v3 · 3 Whisper Large v3 Turbo |

#### 3.5.4. Реализация (Core)

```swift
// NativeBolabolCore — pure function, unit-tested
enum OnboardingModelRecommendation {
  static func topThree(
    primary: String,
    additional: String,
    available: [TranscriptionModelDescriptor] // only GO / shipped models
  ) -> [TranscriptionModelDescriptor]
}
```

- Если модель **NO-GO / not in catalog** — **выпадает** из списка, слоты сдвигаются (не показывать пустую карточку).  
- Всегда **ровно до 3** карточек (или меньше, если catalog thin).  
- Badge **Recommended** только на slot #1.  
- Subtitle slot #1: «Best match for your languages» (localized).  
- Download **не** обязателен на onboarding; выбор «Use» / «Download & use» / Skip → continue tour.  
- При Skip: default engine remains product default (не форсить GigaAM без install).

#### 3.5.5. Settings Local Models

- Полный каталог (все модели).  
- Optional section **«Recommended for you»** = тот же `topThree(primary, additional)` сверху.  
- Ручной выбор любой модели сохраняется.

#### 3.5.6. Copy (EN source keys)

- `onboardingModelsTitle` — Local transcription models  
- `onboardingModelsHint` — We ordered these based on your main and additional languages. Download one now or later in Settings.  
- `onboardingModelsRecommended` — Recommended for you  
- `onboardingModelsChangeLater` — You can change models anytime in **Settings → Local Models**.  
- Per-card badges: `badgeRecommendedRU`, `badgeCompactFourLang`, `badgeMultilingual`, …

### 3.6. Help

New/updated sections:

1. Your languages (primary / additional / not always output / Settings path) — refine.  
2. Local models: GigaAM vs Canary 1B vs Flash vs Whisper/Parakeet.  
3. When A disappears (Canary/GigaAM).  
4. OS requirements (Canary 1B int4).

---

## 4. Пошаговый plan (executable steps)

Имена для `STATE.yaml` / tags: `asr/pre-S0` … или `bolabol/pre-S0`.

### Track A — UX foundation (можно параллелить с spikes)

| Step | Goal | Exit |
|------|------|------|
| **S0** | Branch `feature/1.0.4-asr-coreml`, version train, kit STATE, this plan = SoT | Kit ready |
| **S1** | Onboarding: UI / primary / additional + footers «change later» | Clear 3 language steps; tests EN |
| **S1b** | **`OnboardingModelRecommendation.topThree`** pure ranking + unit tests (R1/R2/R3 matrix) | 100% table §3.5.3 green |
| **S1c** | Onboarding `localModels` screen: **3 dynamic cards** bound to ranking | Order follows primary/additional; Back recalculates |
| **S2** | Settings: labels + optional «Recommended for you» = same helper | No duplicate confusion |
| **S3** | AppText keys EN + 15 locales (onboarding models + language steps) | Localization tests green |

### Track B — Spikes (GO/NO-GO, sequential recommended)

| Step | Goal | Artifact | Exit |
|------|------|----------|------|
| **S4** | Spike **Canary 1B** FluidInference Core ML via FluidAudio | `docs/asr/canary-1b/COREML_SPIKE.md` | **GO/NO-GO** |
| **S5** | Spike **Canary Flash 180M** Core ML (find HF or convert mobius) | `docs/asr/canary-flash/COREML_SPIKE.md` | **GO/NO-GO** |
| **S6** | Spike **GigaAM v3 RU** Core ML | `docs/asr/gigaam-v3/COREML_SPIKE.md` | **GO/NO-GO** |

**Spike checklist (each):** load models · short audio ASR · latency/RAM · lang tokens · chunking · no Python · honest language list.

**Human gate after S4–S6:** which GO models ship in 1.0.4 UI.

### Track C — Product integration (only GO models)

| Step | Goal | Exit |
|------|------|------|
| **S7** | Backend enum + descriptors + capabilities + catalog entries | Models appear in data layer |
| **S8** | Download + presence + storage paths + progress UI | Install complete-folder works |
| **S9** | Engines: CanaryCoreMLEngine + GigaAMCoreMLEngine wired to TranscriptionEngineStore | Offline dictate produces text |
| **S10** | Local Models UI cards + banners + OS gates | Settings path complete |
| **S11** | HUD + session language matrix for Canary/GigaAM | M-matrix manual ready |
| **S12** | Wire ranking to Settings recommended strip + default-select hints | Same helper as onboarding |
| **S13** | Tests + `script/qa` (ranking matrix, no python, catalog, capabilities) | `swift test` + `run_all` green |
| **S14** | Help + RELEASE_NOTES + version string | Docs honest |
| **S15** | Test build `APP_VERSION=1.0.4` + smoke | Internal build ready |

### Dependency graph

```
S0
 ├─► S1 → S1b → S1c → S2 → S3  (UX languages + dynamic 3 model cards)
 └─► S4 → S5 → S6  (spikes; S5/S6 may parallel after S4 if agents available)
              │
              ▼ Human GO list (missing models drop out of topThree)
         S7 → S8 → S9 → S10 → S11 → S12 → S13 → S14 → S15
```

**Note:** S1b/S1c can ship with **existing** Whisper Large v3 / Turbo only; when S4–S6 GO, ranking automatically inserts GigaAM / Canary Flash / Canary 1B without UX rewrite.

---

## 5. Local Models — data model (product IDs)

| id | displayName | backend | languages | notes |
|----|-------------|---------|-----------|-------|
| `gigaam-v3-rnnt-coreml` | GigaAM v3 (Russian) | gigaAMCoreML | ru | Primary RU recommend |
| `canary-1b-v2-coreml` | Canary 1B v2 | canaryCoreML | from spike | Multilingual · large |
| `canary-180m-flash-coreml` | Canary Flash (EN/DE/FR/ES) | canaryCoreML | en, de, fr, es | Compact · fast |
| existing parakeet / whisper | … | … | … | unchanged |

---

## 6. Onboarding UX copy guidelines (EN source)

**Interface language**

- Title: Interface language  
- Body: Choose the language for Bolabol’s menus, settings, and help.  
- Footer: You can change this anytime in **Settings → General**.

**Main dictation language**

- Title: Main dictation language  
- Body: The language you usually speak when dictating.  
- Footer: You can change this later in **Settings → Hotkey → Your Languages**.

**Additional working language**

- Title: Additional language  
- Body: A second language you often work with. This is **not** “always force results into this language”. For Canary, it also drives the HUD language switch.  
- Control: Same as main language  
- Footer: Change anytime in **Settings → Hotkey → Your Languages**.

---

## 7. Тесты и QA

### Automated

- Catalog: three new IDs present only if GO  
- Download completeness per model  
- Capabilities: `supportsAuto == false` for Canary/GigaAM  
- HUD cycle primary↔additional for Canary  
- GigaAM forces RU / banner path  
- Onboarding step order + store persistence  
- **`OnboardingModelRecommendation.topThree` matrix** (all rows §3.5.3)  
- Ranking ignores UI language; uses primary+additional only  
- Missing/NO-GO models collapse slots  
- No Python in Sources  
- Localization × 15 for new keys  
- Archive format regressions  

### Manual

| ID | Scenario |
|----|----------|
| M1 | Onboarding: UI → primary → additional, clear copy |
| M1b | primary=ru → GigaAM **#1** among 3 cards |
| M1c | primary=en, additional=es → Canary Flash **#1** |
| M1d | primary=hi, additional=en → Whisper Large v3 **#1**, Turbo **#2** |
| M1e | Back from models, change primary, cards re-order |
| M2 | Settings path changes pair |
| M3 | Download GigaAM → dictate RU offline |
| M4 | Download Canary Flash → EN/DE/FR/ES |
| M5 | Download Canary 1B → multilingual |
| M6 | HUD Canary letters |
| M7 | Parakeet/Whisper still A |
| M8 | OS gate Canary 1B on older macOS |
| M9 | Polish still MLX after ASR |

---

## 8. Риски

| Risk | Mitigation |
|------|------------|
| Flash 180M **no** public Core ML yet | S5 convert via mobius or block ship |
| Canary 1B needs **macOS 15** | Capability gate + clear Settings text |
| GigaAM community Core ML quality | S6 strict GO/NO-GO |
| User confuses GigaAM with «GigaChat» | UI name **GigaAM**, never GigaChat |
| RAM: 1B + polish MLX | Optional unload polish while ASR |
| Scope creep Multilingual GigaAM | Explicitly out |

---

## 9. Definition of Done (1.0.4 ASR train)

- [ ] Onboarding: UI / primary / additional + «change later»  
- [ ] Onboarding **3 model cards** ordered by R1/R2/R3 (GigaAM / Flash / Whisper v3+Turbo)  
- [ ] Ranking unit tests + manual M1b–M1e  
- [ ] GigaAM RU in Local Models if S6 GO  
- [ ] Canary 1B in Local Models if S4 GO  
- [ ] Canary Flash EN/DE/FR/ES in Local Models if S5 GO  
- [ ] Download / presence / select / dictate offline for each GO model  
- [ ] Core ML only for new ASR; no Python; polish remains MLX  
- [ ] HUD/language rules per engine  
- [ ] Help + i18n × 15  
- [ ] Tests + QA green  
- [ ] Test build version string  

---

## 10. Workflow для агентов (после approve plan)

1. Адаптировать `AI_Workflow_Kit` STATE: `current_step: S0`, plan file = этот документ.  
2. Steps cards → `AI_Workflow_Kit/docs/ASR_COREML_STEPS.md` (S0–S15).  
3. Цикл: PRE → Kick Coder → graphify → Reviewer → Tester (gap-hunt) → POST → graphify.
4. После S4–S6: **Human** подтверждает GO list перед S7.  
5. Tags: `bolabol/pre-S*`, `bolabol/S*-done`.

---

## 11. Чеклист исполнения

```
[ ] S0  Train / kit / plan SoT
[ ] S1  Onboarding language steps (UI / primary / additional)
[ ] S1b Ranking pure function + unit tests (R1/R2/R3)
[ ] S1c Onboarding 3 dynamic model cards
[ ] S2  Settings labels + recommended strip
[ ] S3  i18n new keys × 15
[ ] S4  Spike Canary 1B FluidInference
[ ] S5  Spike Canary Flash 180M Core ML
[ ] S6  Spike GigaAM v3 RU Core ML
[ ] — Human GO list —
[ ] S7  Catalog + backends
[ ] S8  Download / presence
[ ] S9  Engines wiring
[ ] S10 Local Models UI
[ ] S11 HUD / session
[ ] S12 Wire ranking to Settings recommended
[ ] S13 Tests + QA
[ ] S14 Help + release notes
[ ] S15 Test build
```

---

## 12. Ссылки

| Resource | URL / path |
|----------|------------|
| FluidInference Canary 1B Core ML | https://huggingface.co/FluidInference/canary-1b-v2-coreml |
| NVIDIA Canary 180M Flash | https://huggingface.co/nvidia/canary-180m-flash |
| NVIDIA Canary 1B v2 | https://huggingface.co/nvidia/canary-1b-v2 |
| GigaAM v3 | https://huggingface.co/ai-sage/GigaAM-v3 |
| GigaAM Core ML (community) | https://huggingface.co/huggingfinger0/gigaam-v3-coreml |
| Prior NO-GO alexwengg | `docs/canary/COREML_SPIKE.md`, ADR-012 |
| FluidAudio SDK | already in Package.swift |

---

*Конец плана. Код не пишем, пока Human не утвердит plan и не откроет S0.*
