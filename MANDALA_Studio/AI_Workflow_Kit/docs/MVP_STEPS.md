# MVP Performance — пошаговый план для агентов

> **Источник истины для scope:** корневой [`implementation_plan.md`](../../implementation_plan.md)  
> **Этот файл:** нумерованные шаги для `STATE.yaml` → `current_step`  
> **Код только в:** `mandala-pro-studio/`  
> **Post-MVP (B1–B5) не трогать**, пока MVP не accepted.

## Роли (напоминание)

| Роль | Модель | Действие |
|------|--------|----------|
| Orchestrator | Grok / Antigravity | `STATE.yaml`, конфликты, next step |
| Implementation Engineer | **Hy3 / Hi3** | код только в `target_files` |
| Verification Engineer | **Gemini 3.5 Flash** | `FEEDBACK.md` + `review.status` |

---

## Шаги MVP

| `current_step` | Название | Цель |
|----------------|----------|------|
| **M0** | Perf baseline | Dev HUD + замер frame time «до» |
| **M1** | Hot-path React & input | refs, без React на pointerMove, decimation |
| **M2** | EffectLayer | smudge/blur после up = растр, без volatile re-play |
| **M3** | ROI / session WebGL | scissor/ROI + begin/stamp/end, без fullscreen thrash |
| **M4** | World / tiled bake | pan/zoom без full rebake |
| **MVP_DONE** | Приёмка | все gates M0 green |

---

## M0 — Perf baseline

### Цель
Появилась возможность **измерить** тормоза до оптимизаций. Без изменения поведения кистей.

### Требования
1. Dev-only оверлей (включается только в `import.meta.env.DEV` **или** `localStorage.mandalaPerfHud === '1'`):
   - FPS (скользящее окно ~1 с)
   - last frame ms (`drawAllStrokes` + `drawOverlay` если удобно разделить)
   - stroke count
   - optional: pan/zoom flag
2. Не ломать production build (HUD не в prod-бандле UI по умолчанию).
3. Минимальный helper (например `src/utils/PerfHud.ts` или внутри renderer) — без тяжёлых deps.
4. Документ `mandala-pro-studio/PERF_BASELINE.md` (короткий):
   - как включить HUD
   - таблица сценариев из implementation_plan (M0 gates) — заполнить **вручную** колонку «до» если замер возможен; иначе оставить TODO
5. `npm run build` проходит.

### Не делать
- Не рефакторить baker / shaders / refs (это M1+)
- Не менять визуал рисования

### target_files (ориентир)
- `mandala-pro-studio/src/utils/PerfHud.ts` (NEW) или эквивалент
- `mandala-pro-studio/src/components/CanvasRenderer.tsx` (тонкая интеграция замера)
- `mandala-pro-studio/PERF_BASELINE.md` (NEW)

### Done
- HUD виден в dev
- build clean
- baseline-файл создан

---

## M1 — Hot-path React & input

### Цель
Убрать React reconciliation из pointer/camera hot path; снизить число точек для effect-кистей.

### Требования
См. `implementation_plan.md` → **M1**. Кратко:
1. `currentPoints`, `isDrawing`, `hoverPoint` → `useRef` (+ минимум state если UI не требует)
2. `push` без spread-копии массива каждый move
3. pan/zoom через refs + `RenderScheduler`, без re-render на каждый pan-move
4. min-distance: smudge/stretch/blur 3–5 px; vector/airbrush 0.5–1.5 px
5. pointerDown effect: scratch только bbox, не full canvas
6. build clean; поведение кистей визуально то же

### Не делать
- EffectLayer, ROI shaders, world bake

### target_files (ориентир)
- `mandala-pro-studio/src/components/CanvasRenderer.tsx`
- при необходимости мелкие правки только связанных refs

### Done
- DevTools: нет 60 React re-renders/sec при рисовании
- decimation работает для smudge/blur

---

## M2 — EffectLayer

### Цель
Завершённые smudge/stretch/blur **не** переигрываются каждый кадр.

### Требования
См. `implementation_plan.md` → **M2**.  
Undo: dirty-region snapshot, depth default 20.

### Не делать
- multi-brush batch smudge
- world tiles (M4)

### target_files (ориентир)
- `mandala-pro-studio/src/utils/EffectLayer.ts` (NEW)
- `mandala-pro-studio/src/components/CanvasRenderer.tsx`
- `mandala-pro-studio/src/types.ts` (если нужен флаг rasterized)
- `mandala-pro-studio/src/App.tsx` (history, только если нужно для undo snapshot)

---

## M3 — ROI / session WebGL

### Цель
Live smudge/blur без fullscreen pass на каждый stamp.

### Требования
См. `implementation_plan.md` → **M3**.  
API: `beginStroke` / `stamp` / `endStroke`.  
**Запрещено:** multi-brush single pass для smudge.

### target_files (ориентир)
- `mandala-pro-studio/src/utils/SmudgeShader.ts`
- `mandala-pro-studio/src/utils/BlurShader.ts`
- `mandala-pro-studio/src/components/CanvasRenderer.tsx`
- `mandala-pro-studio/src/utils/EffectLayer.ts` (интеграция endStroke)

---

## M4 — World-space / tiled bake

### Цель
Pan/zoom без full rebake всех vector strokes.

### Требования
См. `implementation_plan.md` → **M4**.

### target_files (ориентир)
- `mandala-pro-studio/src/utils/StrokeBaker.ts`
- `mandala-pro-studio/src/components/CanvasRenderer.tsx`

---

## После каждого шага (Hy3)

1. Код только в `target_files` из `STATE.yaml`
2. `npm run build` в `mandala-pro-studio`
3. `implementation.status = waiting_review` в `STATE.yaml`
4. Сообщить человеку: «код готов, зови ревьюера»

## После каждого ревью (Gemini)

1. Заполнить `FEEDBACK.md` по `REVIEW_TEMPLATE.md`
2. `review.status = approved | changes_requested`
3. Сообщить человеку: «ревью готово, зови оркестратора»
