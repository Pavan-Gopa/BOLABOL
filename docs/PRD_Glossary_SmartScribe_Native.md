# PRD: Глоссарий для NativeSmartScribe — Swift-порт нативного VaniScript

| Поле | Значение |
|---|---|
| Продукт | NativeSmartScribe (Swift/SwiftUI, Apple Silicon) |
| Фича | Глоссарий — детерминированная автокоррекция терминов |
| Версия документа | 4.0 — только нативный Swift, без Electron/JS |
| Дата | 2026-07-01 |
| Автор | Pavan (при участии Стратегического Партнёра) |
| Источник истины | **`VaniScriptAppleSilicon` → `VaniScriptCore`** (нативный Swift) |
| Целевой код | `NativeSmartScribe/Sources/NativeSmartScribeCore` |

> **Принцип.** Только Swift под Apple Silicon. Никаких `.ts/.tsx`, никакого Electron, никакого дублирования логики на двух языках. Эталон — уже работающий **нативный** глоссарий VaniScript, а не его Electron-двойник.

---

## 1. TL;DR

В `VaniScriptAppleSilicon` глоссарий уже реализован нативно и работает. Задача — перенести ту же систему в `NativeSmartScribe`: модель `GlossaryEntry`, движок `GlossaryTextRewriter`, стартовый набор `StarterGlossary`, добавление по правому клику (`GlossaryDraftModal`) и применение в конвейере (как в `NativeProcessingPipeline`). Механика — детерминированная замена вариантов на каноническую форму: длинные варианты раньше коротких, границы слова по Unicode, регистронезависимо, **без fuzzy, без влияния на движок распознавания, без LLM**.

Текущий `GlossaryStore.swift` в NativeSmartScribe построен по отклонённой трёхслойной модели (bias + llm + агрессивный fuzzy) и в конвейер не подключён — его надо заменить на порт `GlossaryTextRewriter`.

---

## 2. Эталон: нативный глоссарий VaniScript (Swift)

Всё нижеперечисленное существует и работает в `VaniScriptAppleSilicon`. `[высокая]`

### 2.1. Модель — `VaniScriptCore/AppSettings.swift:127`
```swift
public struct GlossaryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var variants: [String]        // частые ошибочные написания
    public var source: String            // верная форма (транслитерация/оригинал)
    public var translation: String       // перевод (может быть пустым)
    public var category: String?
    public var translations: [String: String]
    public var remember: Bool
    public var createdAt: String
    public var updatedAt: String
}
```
Глоссарий хранится в `AppSettings.glossary: [GlossaryEntry]`.

### 2.2. Движок — `VaniScriptCore/GlossaryTextRewriter.swift`
Чистый `enum` без состояния. Ключевое:
- `apply(to text: String, entries:, target: .source | .translation) -> Result{text, count}`.
- Для записи: `replacement` = trimmed `source`/`translation`; пусто → пропуск. `variants` = `entry.variants` + противоположное поле, dedup, без пустых и без равных `replacement`.
- Сортировка вариантов по длине **убыв.** (длинные/многословные раньше).
- Быстрый гейт `localizedCaseInsensitiveContains` перед regex.
- Паттерн `(?<![\p{L}\p{N}_]) <escaped> (?![\p{L}\p{N}_])`, опции `.caseInsensitive`; замена шаблоном `replacement`.
- **Кэш скомпилированных `NSRegularExpression`** под `NSLock` (потокобезопасно).
- Перегрузка `apply(to cues: [TranscriptCue], …)` — построчная замена в субтитр-репликах с пересчётом таймингов слов.
- **Нет** нечёткого сопоставления, **нет** bias, **нет** LLM.

### 2.3. Стартовый набор — `VaniScriptCore/StarterGlossary.swift`
Встроенный корпус терминов (source/translation/category/variants), загружается по умолчанию.

### 2.4. Интеграция — `Services/NativeProcessingPipeline.swift:834–856`
```swift
let textResult = GlossaryTextRewriter.apply(to: text, entries: settings.glossary, target: .source)
let cueResult = GlossaryTextRewriter.apply(to: cues, entries: settings.glossary, target: .source)
// … перевод:
let cueResult = GlossaryTextRewriter.apply(to: cues, entries: settings.glossary, target: .translation)
let textResult = GlossaryTextRewriter.apply(to: text, entries: settings.glossary, target: .translation)
```
Плюс применение на уровне чанков в `WorkflowStore.swift:3043–3136`.

### 2.5. Правый клик — `Views/ReviewWorkspaceView.swift`
- `beginGlossaryDraft(selectedText:side:)` → `GlossaryDraftModal` → `saveGlossaryDraft`.
- Сохранение: `store.addGlossaryVariants(...)` (добавить вариант к существующей записи) или `store.createGlossaryEntryFromReview(...)` (создать запись). `side ∈ {source, translation}`.
- Категории берутся из существующих записей (`glossaryCategories`).

### 2.6. Настройки — вкладка `glossary`
Отдельная вкладка в `SettingsTab.swift` / `SettingsView.swift`.

---

## 3. Что не так в текущем NativeSmartScribe

`NativeSmartScribeCore/Stores/GlossaryStore.swift` и `Models/GlossarySettings.swift` реализуют **отклонённую** модель: `[высокая]`
- `initialPrompt()` — bias-слой (влияние на распознавание). **Удалить.**
- `GlossarySettings.layers.llm` — LLM-слой. **Удалить.**
- `applyRulesCorrection` с always-on **fuzzy** (Levenshtein по каждому слову ≥4 симв., порог 0.82). **Удалить** — в VaniScript fuzzy нет, это источник ложных замен.
- Границы слова `\b` вместо Unicode-lookaround. **Заменить** на паттерн из `GlossaryTextRewriter`.
- Модель `GlossaryTerm` (одноязычная `canonical`) вместо `GlossaryEntry`. **Заменить.**
- Оба метода (`initialPrompt`, `applyRulesCorrection`) **нигде не вызываются** — фича не подключена.

Сохранить из текущего кода: CRUD, персист в `Application Support/NativeSmartScribe/glossary.json`, импорт/экспорт JSON/CSV (адаптировать под `GlossaryEntry`).

---

## 4. Как переносим (без дублирования логики)

Два варианта — выбрать один (см. §9, решение 1):

- **Вариант A (рекомендую) — общий Swift-модуль.** Вынести `GlossaryEntry` + `GlossaryTextRewriter` + `StarterGlossary` в отдельный Swift-пакет (напр. `GlossaryKit`), от которого зависят и `VaniScriptCore`, и `NativeSmartScribeCore`. Единый источник истины, ноль дублирования — прямой ответ на «не дублировать скрипты».
- **Вариант B — аккуратный порт.** Скопировать три самодостаточных файла в `NativeSmartScribeCore`. Проще и без связности между приложениями, но две копии для сопровождения.

В обоих вариантах — **чистый Swift**, ноль JS/TS, ноль внешних модулей.

---

## 5. Цели и не-цели

### Цели
1. Поведенческий паритет с нативным глоссарием VaniScript (`GlossaryTextRewriter`).
2. Устранить ручную правку повторяющихся ошибок распознавания терминов.
3. Отдельная вкладка «Глоссарий» + добавление по правому клику из результата.
4. Локально, офлайн, быстро, нативно под Apple Silicon.

### Не-цели
- ❌ Любые ссылки на Electron/JS-версию и её `.ts/.tsx`.
- ❌ bias / `initialPrompt` / влияние на WhisperKit / Apple Speech.
- ❌ LLM-слой для коррекции.
- ❌ Fuzzy (Levenshtein) — в эталоне его нет.
- ❌ Ollama, whisper.cpp, любые доп. модули.
- ❌ Проектные словари (только глобальный `settings.glossary`).

---

## 6. Интеграция в NativeSmartScribe

Применять после распознавания, до показа/сохранения; движки распознавания не трогать.

- **A. Транскрипция.** В `RecordingTranscriptionWorkflow` результат Apple Speech / WhisperKit → `GlossaryTextRewriter.apply(to: text, entries: glossary, target: .source)` → показ/persist в `SmartScribeNote`.
- **B. Перевод.** В пути перевода (`TranslationModalView`/сервис) → `apply(..., target: .translation)`.
- Гейт: `guard settings.enabled` — при выключенном глоссарии поведение неизменно.
- Никаких изменений в `WhisperKitTranscriptionEngine` / `AppleSpeechTranscriptionEngine`.

---

## 7. UX

### 7.1. Правый клик (порт `ReviewWorkspaceView`)
- Контекстное меню на выделенном тексте заметки (`SelectableTextView`/`NoteDetailView`): «Добавить в глоссарий».
- Открывается `GlossaryDraftModal`: выделение → как вариант; поле «Верная форма» (source), опц. «Перевод»; выбор/создание категории.
- Сохранение: добавить вариант к существующей записи или создать новую (порт `createGlossaryEntryFromReview` / `addGlossaryVariants`).
- После сохранения — немедленный повторный `apply` по текущему тексту (мгновенное исправление).

### 7.2. Вкладка «Глоссарий»
- Список записей: source · translation · варианты · категория; поиск, фильтр по категории, сортировка.
- CRUD, объединение записей, тумблер «Использовать глоссарий».
- Импорт/экспорт JSON/CSV (адаптировать под `GlossaryEntry`).
- Стиль — существующие компоненты NativeSmartScribe.

---

## 8. Нефункциональные требования

- **NFR-1. Скорость.** Кэш скомпилированных regex (как в эталоне) + гейт `localizedCaseInsensitiveContains`; проход — O(длина текста × варианты), незаметно на реальных заметках.
- **NFR-2. Локальность.** `Application Support/NativeSmartScribe/glossary.json`; офлайн; без сети.
- **NFR-3. Автономность.** Чистый Swift + `NSRegularExpression`; ноль зависимостей от Ollama/whisper.cpp/JS.
- **NFR-4. Apple Silicon.** Штатные Foundation/ICU-операции.
- **NFR-5. Надёжность.** Детерминизм + Unicode-границы + longest-first, без fuzzy → ложные замены ≈ 0.
- **NFR-6. Совместимость.** Пустой/выключенный глоссарий не меняет поведение; версия схемы в контейнере.

---

## 9. Открытые решения

1. **Общий модуль (A) или порт (B)?** Рекомендую A (`GlossaryKit`) — единый источник истины, нет дублирования.
2. **Судьба текущего `GlossaryStore.swift`:** переписать под `GlossaryEntry`/`GlossaryTextRewriter` или удалить и завести заново от эталона? Рекомендую переписать, сохранив CRUD/персист/импорт-экспорт.
3. **Cue-level замена.** Нужна ли в NativeSmartScribe построчная замена по субтитр-репликам (перегрузка для `[TranscriptCue]`), или достаточно замены по плоскому тексту? Зависит от того, есть ли в NativeSmartScribe караоке-реплики.

---

## 10. Этапы

**P0 — Ядро (Swift).** Решить A/B. Перенести `GlossaryEntry` + `GlossaryTextRewriter` + `StarterGlossary`. Удалить из NativeSmartScribe bias/llm/fuzzy.

**P1 — Интеграция и UX.** Применение в конвейере (точки A и B). Правый клик + `GlossaryDraftModal` + мгновенный повторный проход. Вкладка «Глоссарий».

**P2 — Полировка.** Стартовый глоссарий. Импорт/экспорт под `GlossaryEntry`. Тест-паритет: перенести `Tests/VaniScriptCoreTests/GlossaryTextRewriterTests.swift` в `NativeSmartScribeCoreTests`.

---

## 11. История версий (для контекста)

- v1.0 — трёхслойная модель (bias `initial_prompt` + rules + LLM). **Отклонена**, но попала в текущий Swift-скелет NativeSmartScribe.
- v2.0 — верно свела к детерминированной замене, но ошиблась платформой (Electron/localStorage).
- v3.0 — опиралась на Electron-эталон (`.ts`). **Не то:** дублирование логики на JS.
- v4.0 (эта) — эталон и цель полностью нативные Swift: порт/шеринг `GlossaryTextRewriter` из `VaniScriptAppleSilicon` в `NativeSmartScribe`. Один язык, один источник истины.
