# Blaboom 1.0.3 — единый план внедрения

| | |
|--|--|
| **Продукт** | Blaboom |
| **Версия** | **1.0.3** |
| **Документ** | Единственный полный план (агенту достаточно этого файла) |
| **Статус** | К исполнению |

---

## 0. Резюме (1 страница)

### Что делаем

В **Blaboom 1.0.3** внедряем:

1. **Двухъязычную модель пользователя** — **основной** и **дополнительный** язык (не «целевой результат всегда»).  
2. **Onboarding**, который сразу спрашивает оба языка и пишет их в Settings.  
3. **Обновление Help и Settings** + **локализация на все 15 UI-языков**.  
4. **Локальный Canary (Core ML only)** — ASR и speech translation (AST) без Python.  
5. **HUD-логику для Canary**: вместо **A** (auto) — буква основного языка; тап переключает **основной ↔ дополнительный** (например **R ↔ E**).

### Чего не делаем

- Python / NeMo / PyTorch в runtime  
- Полировка текста через Canary (V1/V2 = MLX/cloud)  
- Обещание «результат всегда на дополнительном языке»  
- Ломать auto-detect у Parakeet / Whisper (по умолчанию он **остаётся**)

### Термины (важно)

| Термин | Смысл | Не путать с |
|--------|--------|-------------|
| **Основной язык** | Родной / язык, на котором пользователь **обычно диктует** | Язык интерфейса |
| **Дополнительный язык** | Второй язык, которым пользователь **часто пользуется** (например EN при primary RU) | «Целевой язык результата всегда» |
| **Язык интерфейса** | Язык UI / Help / меню | Speech languages |

При **Canary** основной/дополнительный участвуют в speech-логике (source / alternate).  
При **Parakeet / Whisper** по умолчанию — **автоопределение языка**; пара языков — удобный default и база для Canary/HUD.

### Runtime

**Только native:** Core ML (Canary, WhisperKit, Parakeet) + MLX (polish).  
**Запрещено:** Python, sidecars, pip/venv, ONNX Runtime.

### Главный артефакт Canary

https://huggingface.co/alexwengg/canary-1b-v2-coreml  
(Core ML port of `nvidia/canary-1b-v2`)

### Порядок работ (обзор)

```
A. Foundation: store primary+additional, picker order, i18n keys
B. Onboarding + Settings + Help (full 15 locales)
C. Core ML spike Canary (go/no-go)
D. Canary engine + catalog + download
E. HUD R↔E + wiring dictation
F. Tests, QA, 1.0.3 test build
```

---

## 1. Что именно мы делаем и зачем

### 1.1. Двухъязычная модель пользователя

**Зачем.**  
Реальные пользователи живут в двух языках: «я диктую по-русски, но часто работаю с английским». Это не то же самое, что «всегда выдавай English».

**Что.**

- **Основной язык** — язык диктовок по умолчанию (пример: русский).  
- **Дополнительный язык** — второй привычный язык (пример: английский).  
  - У другого пользователя: primary Hindi, additional English.  
  - Или primary English, additional German / French / Chinese.  

**Почему не «целевой».**  
Слово «целевой» читается как «язык результата всегда». Это неверно:

- часто primary == output (просто транскрипция);  
- additional — **второй** язык для переключения и для Canary, а не жёсткий output;  
- auto-detect у Whisper/Parakeet по-прежнему определяет речь сам, когда Canary не выбран.

### 1.2. Onboarding

**Зачем.**  
Сейчас язык «результата/force» спрятан в Settings; Help мало кто читает.  
Нужно спросить **сразу** при первом запуске.

**Что спрашиваем (после языка интерфейса):**

1. **Основной язык** — «На каком языке вы обычно диктуете?»  
2. **Дополнительный язык** — «Какой второй язык вы обычно используете?»  
   - Опция: «Пока не нужен / тот же, что основной» (optional).  

Выбор **сразу сохраняется** в Settings (единый store).

### 1.3. Поведение движков

| Движок | Поведение языка |
|--------|-----------------|
| **Parakeet / Whisper** | **Auto-detect по умолчанию** (как сейчас, HUD **A**). Основной/дополнительный — defaults и для UI. |
| **Canary** | Auto **нет**. HUD: буква **основного** (R), тап → **дополнительный** (E), тап снова → R. В inference: source = активный HUD language; при AST target задаётся отдельно (см. §4). |

### 1.4. Canary (речь)

**Зачем.**  
Локальный ASR + speech translation на Apple Silicon, нативно.

**Что.**  
Core ML пакет: preprocessor + encoder + decoder + tokenizer/projection.  
**Не** text polish, **не** Python.

### 1.5. Help + i18n

**Зачем.**  
Новая модель (два языка + Canary + HUD R/E) требует объяснения; все UI-языки приложения (~15) должны получить onboarding, Settings и Help.

---

## 2. Ограничения

### 2.1. Runtime (обязательно)

| Разрешено | Запрещено |
|-----------|-----------|
| Core ML | Python, NeMo, PyTorch |
| MLX (только polish worker) | ONNX Runtime, pip/uv/venv |
| Swift / AVFoundation / Accelerate | Любой non-native ML sidecar |

Конвертация весов NeMo→Core ML — **вне** app (HF). В продукт — только `.mlmodelc` / assets.

### 2.2. Версия

- Маркетинг: **1.0.3**  
- Default build: `APP_VERSION=1.0.3`  
- Не называть линию «1.3»

### 2.3. Non-goals 1.0.3

- Результат «всегда на дополнительном языке»  
- Canary text→text (⌥1/⌥2)  
- Canary polishing  
- Удаление Parakeet/Whisper  
- Python fallback если Core ML слаб  

---

## 3. Продуктовая модель: основной и дополнительный язык

### 3.1. Определения

**Основной (primary / recording language)**  
Язык, на котором пользователь **обычно говорит** в диктовках.  
Примеры: русский, хинди, английский.

**Дополнительный (additional / secondary language)**  
Второй язык, которым пользователь **регулярно пользуется** (чтение, ответы, иногда диктовка/перевод).  
**Не** означает «всегда печатать результат на нём».

**Язык интерфейса (UI language)**  
Отдельный выбор: язык меню, Help, onboarding.

### 3.2. Примеры пар

| Primary | Additional | Типичный пользователь |
|---------|------------|------------------------|
| ru | en | Русскоязычный, часто EN |
| hi | en | Hindi + English |
| en | de | English native, German as second |
| en | zh | English + Chinese |
| de | en | German + English |

### 3.3. Где хранится

Единый source of truth (новый или расширенный settings blob), например:

```swift
struct UserSpeechLanguages: Codable {
    var primaryLanguageCode: String    // "ru", "en", ...
    var additionalLanguageCode: String // "en", "de", ...; may equal primary
}
```

- Onboarding пишет сюда.  
- Settings читает/пишет сюда же.  
- Hotkey session / Canary / HUD читают отсюда.  
- Legacy поля (transcription language, glossary author, auto-translation) — **мигрировать/зеркалить** один релиз, затем canonical = эта пара.

### 3.4. Defaults

| Ситуация | Primary | Additional |
|----------|---------|------------|
| Свежий install | map system locale if known, else `en` | `en` if primary ≠ en, else `en` (same) or second common |
| «Дополнительный не нужен» | user primary | = primary |
| Migration from old installs | best-effort from old prefs | en or old force-target |

---

## 4. Поведение движков и HUD

### 4.1. Parakeet / Whisper / Gemini (default path)

- **Автоопределение языка речи** остаётся (HUD **A** когда mode = auto).  
- Primary/additional **не отключают** auto.  
- Primary может влиять на: defaults glossary, onboarding, future hints.  
- Additional — для быстрого switch (если product later) и для перехода на Canary без переспрашивания.

### 4.2. Canary (отдельная двухъязычная логика)

Canary **не умеет** auto language task selection — нужны явные lang tokens.

**HUD left control при Canary:**

| Состояние | Label | Смысл |
|-----------|-------|--------|
| Active = primary | **R** (если primary = Russian) | Диктую на основном |
| After tap | **E** (если additional = English) | Диктую / режим с дополнительным |
| Tap again | **R** | Обратно на основной |
| **A** | Не показывается активным | Auto недоступен |

Цикл: **primary letter ↔ additional letter** (только если additional ≠ primary; иначе только primary letter).

**Inference (Canary):**

- `activeSpeechLanguage` = язык, выбранный на HUD (primary или additional).  
- Для **ASR**: `source = target = activeSpeechLanguage`.  
- Для **speech translation (AST)**: product decision — MVP 1.0.3:  
  - **Рекомендация:** source = activeSpeechLanguage, target = the other of {primary, additional} if different, **или** явный «output» later.  
  - Минимальный MVP, согласованный с UX «R↔E = на каком языке говорю»:  
    - R/E переключает **язык речи (source)**;  
    - AST (перевод в другой язык) — отдельный mode (force translate / target) **или** «если active = primary и user wants EN out» через Settings «prefer translation into additional when recording primary» — **optional later**.  

**Уточнение MVP для 1.0.3 (зафиксировать в реализации):**

1. **HUD R↔E** = переключение **языка диктовки (source)** между primary и additional.  
2. **Output language for AST** (если source≠desired output):  
   - v1: if user enables «speech translation» / force output to the *other* language of the pair when they differ;  
   - simplest coherent rule:  
     - source = HUD language (primary or additional);  
     - target = additional if source == primary && primary ≠ additional, else primary if source == additional, else source (ASR).  

Это даёт: «говорю по-русски (R) → могу получить EN (additional)»; «говорю по-английски (E) → могу получить RU (primary)».  
Если оба одинаковы → всегда ASR.

*(При реализации — unit tests на эту матрицу.)*

### 4.3. Полировка

V1/V2 всегда MLX/cloud **после** текста. Canary не участвует.

---

## 5. Порядок языков в списках (пикеры)

### 5.1. Проблема

Порядок **English → Russian** как top-2 выглядит нарочито. Нужен нейтральный, «крупный продукт».

### 5.2. Практика

English first (app default), затем региональные группы / алфавит English names; endonym в отображении (Deutsch, Русский, 中文).

### 5.3. Canonical order UI (15 языков)

**1. English** (`en`)

**2. Europe** (alpha by English name):  
French (`fr`), German (`de`), Italian (`it`), Polish (`pl`), Portuguese (`pt`), **Russian (`ru`)**, Spanish (`es`), Turkish (`tr`), **Ukrainian (`uk`)**

**3. Asia & other** (alpha):  
Arabic (`ar`), Chinese (`zh`), Hindi (`hi`), Japanese (`ja`), Korean (`ko`)

`System` — отдельно (верх или низ списка UI language), не между en и fr.

### 5.4. Реализация

```swift
// NativeBlaboomCore
enum LanguagePickerOrder {
  static let uiLanguages: [UILanguagePreference] // not raw allCases order
  static let speechLanguages: [SpeechLanguage]   // for primary/additional
}
```

- Onboarding UI language step: `LanguagePickerOrder.uiLanguages`  
- Primary / additional pickers: same regional principle  
- Unit tests: `en` first; `ru` not index 1; `ru` before `zh`  

---

## 6. Onboarding (детально)

### 6.1. Порядок шагов (to-be)

| # | Шаг | Содержание |
|---|-----|------------|
| 1 | Welcome + **язык интерфейса** | Как сейчас; список по `LanguagePickerOrder` |
| 2 | **Основной язык** | «На каком языке вы обычно диктуете?» |
| 3 | **Дополнительный язык** | «Какой второй язык вы часто используете?» + «Тот же, что основной» |
| 4 | How to transcribe / models | Как сейчас |
| 5 | Permissions | Как сейчас |
| 6 | Modes / HUD | **Обновить copy:** A у auto-engines; у Canary — буквы primary/additional |
| 7 | Glossary | Prefill author language from primary |
| 8 | Theme / finish | Как сейчас |

### 6.2. Поведение

- Выбор primary → store + (optional) glossary author.  
- Выбор additional → store; **сразу** видно в Settings.  
- Не называть additional «целевым» / «target result language» в UI copy.  

### 6.3. Файлы

- `OnboardingView.swift` — steps  
- `AppText` — keys  
- `LanguagePickerOrder`  
- Tests: onboarding* localization  

---

## 7. Settings

### 7.1. Явные пункты

| Пункт UI | Store field |
|----------|-------------|
| Primary / recording language | `primaryLanguageCode` |
| Additional language | `additionalLanguageCode` |
| Optional: «Same as primary» | sets additional = primary |

**Путь:** Settings → Hotkey (и/или General), **не** только Help.

### 7.2. Copy guidelines

- **Не:** «Target language for all output»  
- **Да:** «Additional language you often use (second language)»  
- Hint: для Canary переключение на HUD; для Whisper/Parakeet auto-detect по умолчанию  

### 7.3. Canary filter

При активном Canary — списки primary/additional сужаются до supported languages модели (после spike).

---

## 8. Help (обязательное обновление)

### 8.1. Новый раздел «Два языка» / «Your languages»

Обязательное содержание:

1. **Зачем два языка** — основной и **дополнительный** (не «всегда результат на втором»).  
2. **Основной** — язык диктовок.  
3. **Дополнительный** — второй привычный язык.  
4. **Onboarding** — где спросили; как изменить в Settings.  
5. **Settings path** — точный путь.  
6. **Parakeet / Whisper** — auto-detect (A), пара языков как defaults.  
7. **Canary** — нет A; буква primary; tap → additional; обратно.  
8. **Полировка** — отдельно (MLX/cloud).  

### 8.2. Обновить существующие ключи

`helpLang*`, `helpHUDLeftA`, `helpHUDLeftLetter`, `helpHUDControlLanguage`, modes body — согласовать с новой моделью.

### 8.3. HelpSettingsView

Вставить секцию в логичном месте (после HUD / Language).

### 8.4. Внешние материалы

- `docs/RELEASE_NOTES.md` — 1.0.3 bullets  
- `README.md` — кратко  
- Не плодить отдельные «plan.md»  

---

## 9. Локализация (все 15 UI-языков)

### 9.1. Список

en, ru, es, de, fr, it, pt, zh, ja, ko, ar, hi, uk, tr, pl  

### 9.2. Поверхности

| Поверхность | Что переводить |
|-------------|----------------|
| Onboarding | primary/additional steps, hints, same-as-primary |
| Settings | labels, hints, section titles, Canary banners |
| Help | весь §8 + updates helpLang/HUD |
| Errors / toasts | unsupported pair, clamp, Canary no auto |

### 9.3. Процесс

1. EN source strings  
2. `AppTextKey`  
3. Все 15 maps в `AppText.swift`  
4. Tests: no raw-key fallback  
5. Positional format if multi-arg (`%1$@`)  
6. RTL spot-check (ar)  

### 9.4. Черновик ключей

**Onboarding:**  
`onboardingPrimaryLanguageTitle/Hint/Body`,  
`onboardingAdditionalLanguageTitle/Hint/Body`,  
`onboardingAdditionalSameAsPrimary`, …

**Settings:**  
`primaryLanguage`, `primaryLanguageHint`,  
`additionalLanguage`, `additionalLanguageHint`,  
`additionalSameAsPrimary`, `languagePairSectionTitle`,  
`canaryAutoLanguageUnavailable`, …

**Help:**  
`helpBilingualTitle`, `helpBilingualIntro`, `helpBilingualPrimary`,  
`helpBilingualAdditional`, `helpBilingualNotAlwaysOutput`,  
`helpBilingualWhere`, `helpBilingualOnboarding`, `helpBilingualSettingsPath`,  
`helpBilingualCanary`, `helpBilingualHUD`, `helpBilingualAutoEngines`,  
`helpBilingualPolishNote`, …

---

## 10. Canary Core ML — технический план

### 10.1. Артефакт

| | |
|--|--|
| HF | https://huggingface.co/alexwengg/canary-1b-v2-coreml |
| Upstream | nvidia/canary-1b-v2 |
| Состав | preprocessor, encoder, decoder, projection, tokenizer |
| ~Size | ~5.8 GB on HF |
| Window | ~14 s context → Swift chunking for long audio |
| Lang tokens in export | verify; may be EN/DE/FR/ES first — document after spike |

### 10.2. Архитектура

```
Audio → 16 kHz mono
     → CanaryCoreMLEngine (Swift, TranscriptionEngine)
          preprocessor / encoder / decoder (Core ML)
          projection + tokenizer (native)
     → text
     → glossary → optional MLX/cloud polish → insert
```

### 10.3. Изменения в коде (as-is → to-be)

**As-is:**

- `TranscriptionBackend`: localWhisper | geminiCloud  
- Model backends: whisperKitCoreML | fluidAudioCoreML  
- `TranscriptionRequest`: forcedLanguageCode, translateToEnglish  
- Engine store: Whisper / Parakeet only  

**To-be:**

- `TranscriptionModelDescriptor.Backend.canaryCoreML`  
- Request: `sourceLanguageCode`, `targetLanguageCode` (Canary); keep legacy fields for Whisper  
- `CanaryCapabilities` (langs, no auto, no polish)  
- `CanaryCoreMLEngine` + loader + chunker + prompt tokens  
- `TranscriptionEngineStore` factory branch  
- Download/presence under SharedModelsRoot `canary/…`  

### 10.4. Capabilities (product honesty)

После spike зафиксировать реальный список языков Core ML-порта.  
UI и Help не обещают 25 langs, пока не подтверждено.

### 10.5. Optional later

Canary Flash ~180M **только** при наличии Core ML export (те же native rules).

---

## 11. Пошаговый план работ (единый)

Каждый шаг: **что → зачем → файлы/задачи → критерий выхода**.

---

### Шаг 0 — Версия и ветка

**Что:** `feature/1.0.3`, `APP_VERSION=1.0.3`.  
**Зачем:** единый train.  
**Критерий:** docs/scripts на 1.0.3; этот plan — единственный master plan.

---

### Шаг 1 — Language pair store + picker order

**Что:**

- `UserSpeechLanguages` / `LanguagePairSettings` (primary + additional)  
- Migration from old prefs  
- `LanguagePickerOrder` (en → Europe → Asia)  

**Зачем:** foundation для onboarding/settings/HUD/Canary.  

**Файлы:** Core models, store, tests order + migration.  

**Критерий:** unit tests green; order invariants.

---

### Шаг 2 — Onboarding primary + additional

**Что:** два шага (или один экран с двумя блоками) после UI language; persist.  

**Зачем:** не заставлять искать Settings.  

**Файлы:** `OnboardingView.swift`, AppText EN (full i18n step 6).  

**Критерий:** fresh tour writes both fields; no en-ru top-2 in lists.

---

### Шаг 3 — Settings UI

**Что:** явные Primary + Additional; sync с store; hints.  

**Зачем:** изменение после onboarding.  

**Критерий:** Settings == onboarding values; copy не говорит «target always».

---

### Шаг 4 — Help (EN first, full structure)

**Что:** раздел §8 + updates helpLang/HUD.  

**Зачем:** обязательная документация фичи.  

**Критерий:** EN Help complete in HelpSettingsView.

---

### Шаг 5 — i18n на 15 языков

**Что:** все новые + обновлённые Help/Settings/onboarding keys × 15.  

**Зачем:** product requirement.  

**Критерий:** localization tests no raw-key fallback.

---

### Шаг 6 — Canary Core ML spike (go/no-go)

**Что:** load mlmodelc, ASR EN, AST pair, lang token audit, metrics → `docs/canary/COREML_SPIKE.md` (единственный технический spike-log, не «ещё один plan»).  

**Зачем:** без GO нельзя обещать engine.  

**Критерий:** GO/NO-GO written; no Python.

---

### Шаг 7 — Catalog, presence, download

**Что:** Canary model in catalog; complete-folder check; download UI.  

**Критерий:** install detects complete package.

---

### Шаг 8 — CanaryCoreMLEngine

**Что:** full Swift inference, chunking, errors.  

**Критерий:** offline dictate text on device.

---

### Шаг 9 — Wire dictation + HUD Canary logic

**Что:**

- Session: primary/additional  
- Canary: HUD R↔E (primary↔additional)  
- Non-Canary: keep A/auto  
- Request source/target per §4.2  
- Glossary + polish after text  

**Критерий:** manual M-matrix below.

---

### Шаг 10 — Local Models UI + banners

**Что:** Canary card; auto unavailable banner when Canary selected.  

**Критерий:** settings path complete.

---

### Шаг 11 — QA suite + scripts

**Что:** unit + `script/qa` native-only + bilingual keys + catalog.  

**Критерий:** `swift test` + `run_all.sh` green.

---

### Шаг 12 — Test build 1.0.3

**Что:** `APP_VERSION=1.0.3 ./script/build_and_run.sh`; smoke.  
Notarize — когда product-ready (не блокер first internal).  

**Критерий:** smoke list pass.

---

## 12. Матрицы тестов

### 12.1. Automated

| Test |
|------|
| Language pair migration |
| Picker order: en first; ru not #2; europe before asia |
| All new onboarding/settings/help keys × 15 langs |
| Canary capabilities.supportsAuto == false |
| HUD cycle primary↔additional |
| ASR vs AST routing from primary/additional/active |
| Archive stats format regression (tr/ja/ko/hi) |
| No Python imports in Sources |

### 12.2. Manual

| ID | Scenario | Expected |
|----|----------|----------|
| M1 | Onboarding | Asked primary + **additional** (wording not «target output always») |
| M2 | Additional → Settings | Same values |
| M3 | Parakeet | A / auto works |
| M4 | Canary | No A; letter = primary; tap → additional letter |
| M5 | Canary dictate primary | Works offline |
| M6 | Canary switch to additional | Source follows HUD |
| M7 | V1/V2 | Polish MLX/cloud |
| M8 | UI Turkish | No crash |
| M9 | Language list order | en … europe … asia; not en, ru first |
| M10 | Help | Explains primary/additional/Canary/Settings |

---

## 13. Риски

| Risk | Mitigation |
|------|------------|
| Путаница «additional = always output» | Copy + Help § «not always output» |
| Core ML incomplete langs | Spike; honest UI list |
| 14s window | Chunker |
| Dual legacy settings | One canonical store |
| i18n volume | Step 5 dedicated; tests gate |
| RAM Canary + MLX | Optional unload polish |

---

## 14. Definition of Done (1.0.3)

- [ ] Primary + **additional** (не «target always») в store, onboarding, Settings  
- [ ] Onboarding order: UI lang → primary → additional → rest  
- [ ] Picker order: English → Europe (incl. ru/uk) → Asia/other  
- [ ] Help: bilingual system + Settings path + Canary HUD + auto engines  
- [ ] All related strings on **15 UI languages**  
- [ ] Canary Core ML path native-only (or documented NO-GO)  
- [ ] Parakeet/Whisper auto preserved by default  
- [ ] Canary HUD: primary letter ↔ additional letter  
- [ ] Tests + QA green  
- [ ] Version string 1.0.3  
- [ ] **Единый plan-документ** = этот файл  

---

## 15. Оценка трудозатрат (ориентир)

| Блок | Дни |
|------|-----|
| Store + order + tests | 1–2 |
| Onboarding + Settings | 3–5 |
| Help EN + structure | 1–2 |
| i18n × 15 | 3–5 |
| Canary spike | 3–7 |
| Engine + download | 5–10 |
| HUD + wiring | 2–3 |
| QA + build | 2–3 |
| **Total** | **~20–37 person-days** |

---

## 16. Чеклист исполнения

```
[ ] 0  Version 1.0.3 + branch
[ ] 1  UserSpeechLanguages store + LanguagePickerOrder + tests
[ ] 2  Onboarding primary + additional
[ ] 3  Settings primary + additional
[ ] 4  Help bilingual section (EN) + updates
[ ] 5  Localize all new/updated strings × 15 languages
[ ] 6  Canary Core ML spike → COREML_SPIKE.md (GO/NO-GO)
[ ] 7  Catalog + presence + download
[ ] 8  CanaryCoreMLEngine
[ ] 9  Dictation wiring + HUD R↔E
[ ] 10 Local Models UI + banners
[ ] 11 Automated tests + QA scripts
[ ] 12 1.0.3 test build + manual matrix
```

---

## 17. Ссылки

| Resource | Location |
|----------|----------|
| Core ML Canary | https://huggingface.co/alexwengg/canary-1b-v2-coreml |
| Upstream | https://huggingface.co/nvidia/canary-1b-v2 |
| **This plan (only master plan)** | `BLABOOM_1.0.3_IMPLEMENTATION_PLAN.md` |
| Spike log (after step 6) | `docs/canary/COREML_SPIKE.md` (создать при spike) |

---

*Конец единого плана Blaboom 1.0.3. Отдельные brief/summary documents не используются.*
