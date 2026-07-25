# Оптимизация производительности MANDALA Studio

> **Цель:** 60 FPS при 500+ мазках, 12–24 сегментах симметрии, smudge/blur/stretch, полупрозрачных и «тяжёлых» кистях.  
> **Стек:** React 19 + TypeScript + Vite + Canvas 2D + точечный WebGL2 для sample-based кистей.  
> **Документ:** расширенная ревизия плана Claude 4.6 (анализ кодовой базы `mandala-pro-studio`, 2026-07-12).  
> **Статус плана:** **MVP — основной трек реализации** (4 фазы). Post-MVP — backlog после приёмки MVP.  
> **Исполнение:** оркестрация через `AI_Workflow_Kit/docs/` — Grok = Orchestrator, **Hy3 = coder**, **Gemini 3.5 Flash = reviewer**.  
> **Карточки шагов для агентов:** [`AI_Workflow_Kit/docs/MVP_STEPS.md`](AI_Workflow_Kit/docs/MVP_STEPS.md) · **STATE:** [`AI_Workflow_Kit/docs/AI/STATE.yaml`](AI_Workflow_Kit/docs/AI/STATE.yaml)

---

## MVP — основной план (делаем это)

Четыре фазы ниже — **единственный обязательный scope** до «не тормозит с кистями и эффектами».  
Baseline (M0) короткий и входит в MVP как ворота «до/после».

| # | Фаза | Что даёт | Закрывает проблемы |
|---|------|----------|-------------------|
| **M0** | Perf baseline | Цифры до/после, HUD FPS | — |
| **M1** | Hot-path React & input | Нулевой React pressure, меньше точек | P5, P8, часть P10 |
| **M2** | Effect stroke rasterization | Завершённый smudge/blur = пиксели, не пересчёт | **P4** |
| **M3** | ROI / session WebGL | Live smudge/blur без fullscreen GPU | **P2, P3** |
| **M4** | World-space / tiled bake | Много линий + pan/zoom free | **P1**, semi-transparent seams |

```text
M0 baseline → M1 input refs → M2 EffectLayer → M3 ROI WebGL → M4 world tiles → ✅ MVP done
                                                              ↓
                                                    Post-MVP backlog (по необходимости)
```

**Критерий готовности MVP:** все budget-сценарии из M0 проходят; smudge/blur/stretch + vector + pan/zoom ощущаются плавными при 12+ mirror и 100+ мазках.

**Вне MVP (не блокируют релиз anti-lag):** incremental live buffer, airbrush/glow batching, RDP simplify, adaptive quality, Web Worker.

---

## Что уже сделано (база)

Часть оптимизаций из `ARCHITECTURE_PLAN.md` **уже в коде**. План ниже не повторяет их «с нуля», а устраняет оставшиеся bottlenecks.

| Модуль | Статус | Ограничение |
|--------|--------|-------------|
| `RenderScheduler` | ✅ | Не спасает от тяжёлой работы *внутри* одного кадра |
| `StrokeBaker` | ⚠️ частично | Bake **в экранных координатах** → full rebake на pan/zoom |
| `PathBatcher` | ✅ vector | Airbrush / rainbow / sketch / glow ещё не батчатся |
| `SpatialHash` | ✅ | — |
| `guides.ts` | ✅ | — |
| Delta-history | ✅ | Undo всё равно триггерит rebake |
| `SmudgeShader` / `BlurShader` | ⚠️ интегрированы | Fullscreen ping-pong + CPU↔GPU upload/download |
| Scratch bbox | ⚠️ | Помогает Canvas2D fallback; WebGL всё равно full-res |

---

## Диагноз: корневые причины торможения

### 🔴 P1 — Full rebake при pan/zoom (КРИТИЧЕСКАЯ)

[`StrokeBaker.sync()`](mandala-pro-studio/src/utils/StrokeBaker.ts) сравнивает `zoom/pan` с запечёнными и при любом pan/zoom вызывает `rebake()` всех cacheable-штрихов.

```169:188:mandala-pro-studio/src/utils/StrokeBaker.ts
    const camChanged =
      zoom !== this.bakedZoom ||
      pan.x !== this.bakedPanX ||
      pan.y !== this.bakedPanY || ...;
    // → rebake() = полная перерисовка ВСЕХ штрихов
```

**Решение:** bake в **мировых** координатах (или тайлах мира); камера только при `drawImage` / transform.

---

### 🔴 P2 — WebGL smudge/blur: O(replicas × points) fullscreen passes (КРИТИЧЕСКАЯ)

[`SmudgeShader.applySmudge`](mandala-pro-studio/src/utils/SmudgeShader.ts) для **каждой** пары точек **каждой** симметричной реплики:

1. `viewport(0,0,W,H)` — full screen  
2. `drawArrays` ping-pong  
3. В конце: `drawImage(glCanvas → outCanvas)` + `drawImage` на main  

Пример: 12 сегментов + mirror = 24 пути, 50 точек → **~1176 full-screen passes**. Blur ещё ×2 (H+V).

**Решение:** локальный ROI (scissor / brush-sized FBO) + **не переигрывать** завершённые effect-штрихи (растровый bake).

> ⚠️ **Ошибка исходного плана:** «batch all brush centers в один multi-brush pass» **некорректен для smudge/stretch**.  
> Smudge **последователен**: каждый штамп сэмплирует результат предыдущего. Один независимый multi-stamp pass изменит визуал.  
> Параллелить можно только **непересекающиеся** симметричные ROI (осторожно у центра). Blur чуть свободнее, но live-stroke всё равно sequential.

---

### 🔴 P3 — CPU↔GPU thrashing каждый сегмент

Каждый `applySmudge` / `applyBlur`:

1. `texImage2D` (Canvas2D → GPU) — upload  
2. N fullscreen passes  
3. `drawImage(gl → 2D out)` — readback  
4. `drawImage(out → main)`  

На live-path это уже на **каждый pointerMove-сегмент** × все реплики внутри одного вызова шейдера.

**Решение:** держать working buffer на GPU (или один shared WebGL canvas); upload только dirty ROI; readback только при snapshot/export.

---

### 🔴 P4 — Volatile-штрихи пересчитываются каждый кадр (КРИТИЧЕСКАЯ для «после рисования»)

В `drawAllStrokes()`:

```730:739:mandala-pro-studio/src/components/CanvasRenderer.tsx
    const volatileStrokes = strokes.filter(s => !isCacheableStroke(s));
    // ... для каждого: updateScratchBbox + drawSymmetric (полный WebGL re-run)
```

Даже 5–10 завершённых smudge/blur → каждый pan/zoom/resize = полный re-apply всех effect-штрихов.  
Live-рисование smudge **инкрементально** (хорошо), но после `pointerUp` штрих попадает в `strokes` и становится «дорогим навсегда».

**Решение:** при `pointerUp` **запечь результат в растр** (effect layer / snapshot). Хранить vector points только для undo metadata, не для re-render.

---

### 🟡 P5 — React state в hot path pointerMove

```1035:1036:mandala-pro-studio/src/components/CanvasRenderer.tsx
    const newPoints = [...currentPoints, point];
    setCurrentPoints(newPoints);
```

~60 spreads + 60 React re-renders/сек + `useEffect` → schedule overlay.  
Плюс `setHoverPoint` на каждое движение даже без рисования.

**Решение:** `useRef` + `scheduler.schedule`; React state только для UI chrome.

---

### 🟡 P6 — Live non-volatile stroke перерисовывается целиком каждый кадр

Overlay каждый кадр делает `drawSymmetric` **всех** `currentPoints`, а не только нового сегмента. Длинный штрих (500+ точек) × 24 реплики → лаг **во время** рисования растёт линейно.

**Решение:** incremental live layer: дорисовывать только новый сегмент (или перепекать preview-stroke canvas).

---

### 🟡 P7 — Тяжёлые кисти без батчинга

| Кисть | Проблема |
|-------|----------|
| Airbrush | `density = size*1.5` отдельных `arc+fill` × точки × реплики |
| Rainbow | `stroke()` на каждый сегмент |
| Glow | `shadowBlur` (очень дорого в Canvas2D) |
| Sketch | 5 path strokes (частично PathBatcher, но не в hot path sketch) |
| Dotting | fill per point (приемлемо при threshold 8px) |

---

### 🟡 P8 — Нет decimation для smudge/blur

Dotting: min distance 8px. Smudge/blur: **каждая** pointer-точка → WebGL. На планшете 120–240 Hz = лишние сотни passes.

---

### 🟡 P9 — Полупрозрачность / blend (качество + скорость)

Исходный план почти не покрывает:

- Bake + scale при zoom ломает **субпиксельную** полупрозрачность (двойной coverage, fringe).
- `globalAlpha` + overlapping stamps = darkening; world-space tile edges = seams.
- Eraser (`destination-out`) и bleach (`color`) требуют корректного layer compositing, не «одного bitmap всего мира» без учёта blend.

**Решение:** premultiplied alpha в bake; тайлы с padding; eraser/bleach как отдельные операции на layer buffer; при zoom-out — LOD downsample **после** bake, не re-stroke.

---

### 🟡 P10 — Прочие gaps, которых не было в плане Claude

1. **Нет simplification точек** после `pointerUp` (RDP/min-distance) → раздувание JSON, memory, rebake.  
2. **`StrokeBaker` identity** проверяет только `strokes.length`, не содержимое — хрупко при replace/load edge cases.  
3. **Symmetry paths** пересоздаются (`map`/`getSymmetricPaths`) на каждый draw — аллокации в hot path.  
4. **Glow `shadowBlur`** не упомянут — один из самых дорогих Canvas2D path.  
5. **Нет adaptive quality** (DPR/LOD/decimation) при drop below 55 FPS.  
6. **Нет perf harness** (synthetic strokes + frame budget) → регрессии незаметны.  
7. **Worker bake** раньше camera-independent bake / effect-rasterize — преждевременно (только post-MVP).  
8. **Undo volatile:** нужен stack растровых snapshots или layer versioning, иначе undo = expensive rebake.  
9. **Pan state** тоже через `useState` → React reconcile на каждый pan-move (отдельно от baker).  
10. **Scratch на pointerDown** копирует **весь** canvas (`w: mainCanvas.width`) — лишний full copy при старте effect-кисти.

---

## Целевая архитектура рендера

```
┌─────────────────────────────────────────────────────────────┐
│  Presentation (camera: pan/zoom/DPR)                        │
│  ctx.setTransform → drawImage layers / tiles                │
└─────────────────────────────────────────────────────────────┘
        ▲                 ▲                    ▲
┌───────────────┐  ┌──────────────┐  ┌─────────────────────┐
│ VectorBake    │  │ EffectLayer  │  │ LiveStroke          │
│ world tiles   │  │ raster       │  │ incremental only    │
│ cacheable     │  │ smudge/blur  │  │ preview / overlay   │
│ brushes       │  │ stretch bake │  │                     │
└───────────────┘  └──────────────┘  └─────────────────────┘
        ▲                 ▲
   Stroke[] (vector)   Bitmap snapshots (+ meta for undo)
```

**Принципы:**

1. **Камера никогда не инвалидирует bake** (кроме resize мира / export).  
2. **Sample-based кисти** после завершения = **пиксели**, не переигрываемый vector.  
3. **Live path** рисует только delta (новый сегмент).  
4. **React вне hot path** pointer/camera.  
5. **WebGL** работает в ROI, без full-canvas readback на каждый stamp.

---

## MVP — детализация фаз (в порядке реализации)

### M0 — Perf baseline *(ворота MVP)*

Без цифр нельзя доказать «не тормозит». Делается **первым**, переизмеряется после M1–M4.

#### [NEW] dev HUD + короткий harness

1. Синтетические сцены: 100 / 500 vector strokes; 10 / 20 smudge; segments=12 + mirror.  
2. Метрики p95 (3 сек): `drawAllStrokes`, `drawOverlay`, pointerMove, pan/zoom.  
3. Dev HUD: FPS, stroke count, last frame ms.  

| Сценарий (MVP gate) | Budget |
|---------------------|--------|
| Pan/zoom, 500 vector strokes | p95 &lt; 16 ms |
| Live vector stroke, 24 replicas | p95 &lt; 12 ms |
| Live smudge, 24 replicas, size≤40 | p95 &lt; 16 ms |
| После 20 smudge strokes, idle pan | p95 &lt; 16 ms |
| Blur live + opacity 30%, 24 replicas | p95 &lt; 16 ms |

---

### M1 — Hot-path React & input *(MVP #1)*

**Зачем в MVP:** убирает React/GC из каждого pointerMove; уменьшает число WebGL stamps ещё до ROI.

#### [MODIFY] `CanvasRenderer.tsx`

1. `currentPoints`, `isDrawing`, `hoverPoint` → **`useRef`**.  
2. `pointsRef.current.push(point)` — без `[...spread]`.  
3. `zoom` / `pan` / `isPanning` → refs; camera → `scheduler.schedule` **без** React re-render (UI zoom % — отдельный throttled state, если нужен).  
4. Min-distance:  
   - smudge / stretch / blur: **3–5 px** (world)  
   - vector / airbrush: **0.5–1.5 px**  
5. `pointerdown` effect-кисти: scratch **только bbox кисти**, не full canvas.  
6. Опционально в MVP: `getCoalescedEvents()` для pen.

**Done when:** при рисовании нет React re-render на каждый move; DevTools Components не мигает 60 раз/сек.

**Эффект:** −60 React renders/sec, меньше GC, стабильнее input latency.

---

### M2 — Effect stroke rasterization *(MVP #2)*

**Зачем в MVP:** без этого 20 smudge = 20 полных WebGL re-run на каждый pan. Главный долг «после рисования».

#### [NEW] `EffectLayer.ts`

1. Offscreen buffer (world-space предпочтительно, чтобы жить с M4).  
2. Live smudge/blur/stretch: инкрементально в effect buffer (или main → commit в buffer на up).  
3. **На pointerUp:** результат остаётся на слое; stroke **не** попадает в volatile re-draw list.  
4. Metadata: `rasterized: true` / effect snapshot ref; vector points — только undo meta (опционально).  
5. **Undo (MVP-минимум):** snapshot dirty region effect layer **до** штриха; restore on undo.  
   - Depth по умолчанию: **20** effect snapshots (достаточно; см. Open Questions).  
6. `drawAllStrokes` **запрещено** делать `for each volatile: applyWebGL(full stroke)`.

#### [MODIFY] `CanvasRenderer.tsx`, `StrokeBaker.ts`, `types.ts` / history

- Убрать volatile re-play loop.  
- `isCacheableStroke` / composit: `bg → vectorBake → effectLayer → live`.  
- History action для effect: dirty tiles / ImageData patch.

**Done when:** 20 completed smudge + pan/zoom ≈ cost пустого pan (нет WebGL re-apply).

**Эффект:** завершённые effects бесплатны при повторном кадре.

---

### M3 — ROI / session WebGL *(MVP #3)*

**Зачем в MVP:** live smudge/blur сейчас = fullscreen × replicas × points. M2 чинит «после», M3 — «во время».

#### [MODIFY] `SmudgeShader.ts`, `BlurShader.ts`

**Обязательно в MVP:**

1. `SCISSOR_TEST` по brush bbox (+ margin) **или** brush-local FBO `~2r+padding`.  
2. Upload dirty ROI (`texSubImage2D`), не весь canvas.  
3. Session API на один жест:  
   - `beginStroke(source)`  
   - `stamp(prev, curr)` × N (sequential — **не** multi-brush batch)  
   - `endStroke()` → один commit в EffectLayer  
4. Убрать per-stamp full readback: readback/blit **в конце stamp batch кадра** или на `endStroke`.  
5. GPU state живёт между moves одного stroke (не create/teardown каждый move).

**Запрещено в MVP:**

- multi-brush single pass для smudge (ломает физику)  
- fullscreen pass «на весь штрих» без stamp order  

**Canvas2D fallback (MVP):** ROI scratch + step `max(1, dist / (radius*0.35))`.

**Done when:** live smudge/blur при 24 replicas, size≤40 — p95 &lt; 16 ms.

**Эффект:** GPU ≈ O(brushPixels × stamps), не O(screen × stamps).

---

### M4 — World-space / tiled bake *(MVP #4)*

**Зачем в MVP:** 100–500+ линий + pan/zoom сейчас = full rebake. Без M4 «много линий» останется медленным.

#### [MODIFY] `StrokeBaker.ts`

1. Bake cacheable strokes **в мировых координатах** (камера не в bake matrix).  
2. **Tiled cache 512×512**, padding **8–16 px** (semi-transparent seams).  
3. Dirty tiles by stroke bbox (+ brush radius / glow spread).  
4. Pan/zoom: blit **только visible tiles** через camera transform.  
5. Add stroke → incremental dirty tiles; full rebuild: undo deep / clear / load / layer visibility / symmetry change.  
6. Content identity: stroke id list / hash, **не только** `length`.  
7. Premultiplied-friendly compositing.

#### [MODIFY] `CanvasRenderer.tsx`

```text
clear → fill bg
     → setTransform(camera)
     → baker.drawVisibleTiles(ctx)
     → effectLayer.draw(ctx)
     → live preview (current stroke)
```

**Не** передавать zoom/pan в baker как причину rebake.

**Done when:** 500 vector strokes, pan/zoom p95 &lt; 16 ms; add one stroke ≠ full scene rebuild.

**Эффект:** pan/zoom ≈ free при большом числе линий.

---

## Порядок выполнения MVP (фиксированный)

| Шаг | Фаза | Зависит от | Можно параллелить? |
|-----|------|------------|-------------------|
| 1 | **M0** Baseline | — | — |
| 2 | **M1** Input refs + decimation | M0 (желательно) | Да, почти изолированно |
| 3 | **M2** EffectLayer | M1 (удобнее) | После M1 |
| 4 | **M3** ROI WebGL | M2 (session → commit в layer) | Слабо; лучше сразу после M2 |
| 5 | **M4** World/tiled bake | M1; стыкуется с M2 world buffer | После M2 или параллельно с M3, если EffectLayer уже world-space |
| 6 | **Приёмка MVP** | M0–M4 | Повторный прогон budgets |

**Почему M2 перед M3:**  
сначала перестать **копить** дорогие volatile strokes, потом ускорять live path.  
**Почему M4 последним в MVP:**  
effect path (M2+M3) — боль «кисти/эффекты»; bake — боль «много линий». Оба в MVP, но effects важнее для заявленной цели.

**Definition of Done (весь MVP):**

- [ ] `npm run build` clean  
- [ ] Все 5 budget-сценариев M0 green  
- [ ] 20 smudge + pan — без re-WebGL  
- [ ] Live smudge/blur 24 replicas — без fullscreen thrash  
- [ ] 500 strokes pan/zoom — без full rebake  
- [ ] Undo effect stroke — корректные пиксели  
- [ ] Visual QA: center smudge, opacity 30%, tile borders  

---

## Post-MVP backlog *(не блокирует anti-lag)*

Делать **только после** приёмки MVP, по приоритету боли.  
(Префикс **B** = backlog; не путать с проблемами **P1–P10** в диагнозе.)

### B1 — Incremental live stroke

`LiveStrokeBuffer`: только last segment; длина штриха не растёт в цене кадра. Закрывает проблему **P6**.

### B2 — Brush draw-call batching

Airbrush sprite / density cap; rainbow hue buckets; glow без per-frame `shadowBlur`; sketch PathBatcher. Закрывает **P7**.

### B3 — Geometry hygiene

RDP / min-distance simplify на pointerUp; cap points; pool symmetric transforms.

### B4 — Adaptive quality

Если frame &gt; 18 ms: ↑ decimation, ↓ bake DPR / airbrush density, LOD tiles; UI остаётся живым.

### B5 — Web Worker bake

OffscreenCanvas worker для tile rebake / export. **Только после** M2+M4. ROI ниже MVP-фаз.

---

## Что исправлено относительно плана Claude 4.6

| Было | Стало |
|------|-------|
| Multi-brush single pass для smudge | Запрещено; sequential stamps + ROI (**M3**) |
| Узкий VolatileStrokeCache | `EffectLayer` + undo snapshots (**M2**) — **в MVP** |
| Worker в основном треке | Post-MVP **B5** |
| MVP «опциональный быстрый старт» | **MVP = основной план** (M1–M4) |
| Порядок размыт | Фиксированный: M0→M1→M2→M3→M4 |
| Почти нет semi-transparent | Tile padding + premultiplied в **M4** |
| Нет метрик | **M0** обязателен |
| Tiled bake вскользь | Явная dirty/visible tile model в **M4** |

---

## Риски MVP и решения

| Риск | Митигация |
|------|-----------|
| World bake + zoom ≠ pixel-perfect | Accept subpixel; QA 100%/200%; export 1:1 world |
| Effect snapshot memory | Dirty tiles only; undo depth **20** |
| Undo after effect bake | Snapshot before stroke в history action (**M2**) |
| Visual change smudge after ROI | Сравнить ROI vs full на 2–3 golden strokes (**M3**) |
| M3 до world-space EffectLayer | В M2 сразу world buffer → проще M4 |
| Export hi-res effects | Scale effect layer или offline re-apply (post-MVP ok) |
| Scope creep (airbrush/worker) | Жёстко: не в MVP, только backlog |

---

## Open Questions *(не блокируют старт MVP)*

Defaults, если нет ответа:

1. **Undo depth effect snapshots** — default **20**.  
2. **Export smudge 4×** — default: scale effect layer (не re-sim).  
3. **Buffer per DrawingLayer?** — default MVP: **один** EffectLayer (+ filter by layer id later).  
4. **Visual diffs world bake** — принимаем лёгкие subpixel отличия.

---

## Verification Plan

### Automated

```bash
cd "/Users/pavan/Documents/AI Projects/MANDALA_Studio/mandala-pro-studio" && npm run build
```

- TypeScript clean  
- После M0: budgets на synthetic scenes (повтор после M4)

### Manual (приёмка MVP)

1. **500 vector strokes** — pan/zoom 60 FPS (**M4**)  
2. **Smudge 30 с** continuous, 12+ mirror — нет growth lag (**M1+M3**)  
3. **20 completed smudge** — pan free (**M2**)  
4. **Blur + opacity 30%** — без full-frame freezes (**M3**)  
5. **Undo/redo** effect stroke — пиксели ок (**M2**)  
6. Chrome Performance: long tasks &gt; 50 ms = fail  

### Visual QA (MVP)

- Semi-transparent strokes at tile borders (**M4**)  
- Smudge near mandala center (overlapping replicas) (**M3**)  
- Eraser over baked content  

### Post-MVP only

- Airbrush size 50 stress (**B2**)  
- Long vector 1000 pts constant cost (**B1**)  
- Glow без halo artifacts (**B2**)  

---

## Краткий вывод

**Основной план = MVP: M0 → M1 → M2 → M3 → M4.**

| MVP-фаза | Одной фразой |
|----------|----------------|
| **M1** Input refs + decimation | React и лишние точки — вон из hot path |
| **M2** EffectLayer | Smudge/blur после штриха = растр |
| **M3** ROI WebGL | Live effects без fullscreen GPU |
| **M4** World tiles | Много линий + pan/zoom free |

План Claude верно нашёл боли; MVP **вшивает** исправления в обязательный трек и **не** размазывает anti-lag на worker/airbrush/adaptive.

Без **M2+M3** smudge/blur останутся медленными даже после world bake.  
Без **M4** «много линий» останется медленным даже после быстрых effects.  
Все четыре — **вместе** — и есть ответ на «чтобы вообще не тормозило».
)