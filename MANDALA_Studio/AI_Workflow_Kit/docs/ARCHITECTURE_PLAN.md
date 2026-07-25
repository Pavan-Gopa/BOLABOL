This document is the single source of truth.

# MANDALA Pro Studio — План оптимизации производительности

> **Цель:** Устранить тормоза при сложных мандалах и smear/blur кистях.
> **Стратегия:** Фаза 1 (оптимизация Canvas 2D) + Фаза 2 (WebGL шейдеры для smudge/blur).
> **Стек остаётся:** React 19 + TypeScript + Vite + Tailwind v4 + Canvas 2D API.

---

## Текущая архитектура и узкие места

```
Узкое место #1: drawAllStrokes() перерисовывает ВСЕ штрихи при каждом изменении
Узкое место #2: vector brush — stroke() на каждый сегмент (lineTo+stroke в цикле)
Узкое место #3: smudge/blur/stretch — updateScratchCanvas копирует ВЕСЬ холст перед каждым шагом
Узкое место #4: snapping — O(n) перебор всех guide points при каждом движении мыши
Узкое место #5: history — Stroke[][] полные копии (квадратичная память)
Узкое место #6: нет RAF-батчинга — множественные re-render'ы за кадр
Узкое место #7: математика направляющих дублирована 4 раза
Узкое место #8: airbrush — Math.random() density раз на точку (density = size*1.5)
Узкое место #9: DPR удваивает размеры холста (4x пикселей)
```

> Пример масштаба: 50 штрихов × 24 сегмента × mirror = **2,400 `drawSegment()` вызовов на кадр**.

---

## ФАЗА 1: Оптимизация Canvas 2D

### Модуль 1: `src/utils/RenderScheduler.ts`

**Проблема:** Сейчас `drawAllStrokes` и `drawOverlay` вызываются из `useEffect` напрямую. При движении мыши `setCurrentPoints` → React re-render → `useEffect` → `drawAllStrokes` + `drawOverlay`. Если за один кадр меняются `currentPoints`, `hoverPoint` и `pan` — это до 3× рендеров.

**Решение:** Планировщик с dirty-флагами на `requestAnimationFrame`.

```typescript
export class RenderScheduler {
  private rafId: number | null = null;
  private dirtyLayers: Set<() => void> = new Set();

  // Регистрирует функцию отрисовки, помечает её как "грязную"
  schedule(drawFn: () => void): void;

  // Запускает все dirty-функции в одном RAF
  private flush(): void;

  // Принудительный синхронный рендер (для экспорта)
  flushNow(): void;

  // Отмена всех запланированных рендеров
  cancel(): void;
}
```

**Алгоритм:**
1. `schedule(fn)` добавляет `fn` в `Set<() => void>` и вызывает `requestAnimationFrame(flush)` если ещё не запланировано
2. `flush()` вызывает все dirty-функции, очищает set, сбрасывает `rafId`
3. Несколько `schedule()` за один кадр → один RAF → один набор вызовов

**Интеграция в CanvasRenderer.tsx:**
```typescript
const scheduler = useRef(new RenderScheduler());
useEffect(() => {
  scheduler.current.schedule(drawAllStrokes);
  scheduler.current.schedule(drawOverlay);

  // Добавлена очистка (cleanup) при размонтировании
  return () => scheduler.current.cancel();
}, [strokes, zoom, pan, dimensions, currentPoints, /* ... */]);
```

**Ожидаемый эффект:** Устранение множественных рендеров за кадр. При быстром движении мыши пропускаются промежуточные состояния.

---

### Модуль 2: `src/utils/StrokeBaker.ts`

**Проблема:** При 50 штрихах × 24 сегмента × mirror = 2,400 `drawSegment()` вызовов на каждый кадр. 99% этих штрихов не меняются между кадрами.

**Решение:** OffscreenCanvas (или обычный `<canvas>`) для "запекания" завершённых штрихов.

```typescript
export class StrokeBaker {
  private bakedCanvas: HTMLCanvasElement;
  private bakedCtx: CanvasRenderingContext2D;
  private bakedStrokeCount: number = 0;
  private bakedStrokeHashes: string[] = [];

  // Проверяет, нужно ли перерисовать кэш
  isStale(strokes: Stroke[], layers: DrawingLayer[]): boolean;

  // Полная перерисовка кэша (undo/redo/clear/load)
  rebake(
    strokes: Stroke[],
    layers: DrawingLayer[],
    drawFn: (ctx, stroke, cx, cy) => void,
    dimensions: { width: number; height: number },
    dpr: number, zoom: number, pan: { x: number; y: number }
  ): void;

  // Инкрементальное добавление одного нового штриха
  addStroke(stroke: Stroke, drawFn: (ctx, stroke, cx, cy) => void, cx: number, cy: number): void;

  // Получить запечённый canvas для blit на основной
  getCanvas(): HTMLCanvasElement;

  // Сброс (при изменении слоёв, видимости, zoom/pan)
  invalidate(): void;
}
```

**Алгоритм:**
1. При нормальном рисовании: `addStroke()` — рисует только новый штрих поверх кэша
2. При undo/redo/clear/load: `rebake()` — полная перерисовка
3. При изменении zoom/pan: `invalidate()` + `rebake()` (матрица камеры меняется)
4. При изменении видимости слоёв: `rebake()`

> **ВНИМАНИЕ (VRAM):** Если DPR >= 2, размер offscreen-холста значительно увеличивается. Необходимо следить за потреблением видеопамяти и при превышении лимитов снижать DPR для `bakedCanvas`.

**Стратегия инвалидации при zoom/pan:**
- Pan: не перерисовывать кэш, а сместить `drawImage` координаты. Кэш рисуется в "мировых" координатах, камера применяется при blit.
- Zoom: тот же подход — кэш в мировых координатах, zoom через `drawImage` с масштабированием.
- Альтернатива (проще): кэш в экранных координатах, инвалидация+rebake при zoom/pan.

**Интеграция:**
```typescript
const baker = strokeBakerRef.current;
if (baker.isStale(strokes, drawingLayers)) {
  baker.rebake(strokes, drawingLayers, drawSymmetric, dimensions, dpr, zoom, pan);
} else if (newStrokeAdded) {
  baker.addStroke(newStroke, drawSymmetric, cx, cy);
}
ctx.drawImage(baker.getCanvas(), 0, 0);

// Только активный штрих поверх
if (isDrawing && currentPoints.length > 0) {
  drawSymmetric(ctx, tempStroke, cx, cy);
}
```

**Ожидаемый эффект:** Вместо 2,400 `drawSegment()` — один `drawImage()` + рендер 1 активного штриха. **100-1000× ускорение** при большом количестве штрихов.

---

### Модуль 3: `src/utils/PathBatcher.ts`

**Проблема:** Текущий vector brush (CanvasRenderer.tsx:564-577):
```typescript
for (let i = 1; i < points.length; i++) {
  ctx.lineWidth = settings.size * pres;
  ctx.lineTo(p.x, p.y);
  ctx.stroke();           // <-- дорогой вызов!
  ctx.beginPath();
  ctx.moveTo(p.x, p.y);
}
```
Каждый `stroke()` — отдельный GPU draw call. Штрих из 200 точек = 200 draw calls × 24 сегмента × mirror = 9,600 draw calls.

**Решение:** Batch в один Path2D. Для pressure-varying толщины — сегментировать на группы по уровням (округление до N уровней).

```typescript
export class PathBatcher {
  // Создаёт один Path2D из массива точек
  static buildPath(points: Point[]): Path2D;

  // Создаёт несколько Path2D по уровням толщины (pressure-sensitive)
  static buildPressureBatchedPaths(
    points: Point[],
    baseSize: number,
    buckets: number = 8
  ): { path: Path2D; width: number }[];

  // Для sketch brush — множественные офсеты в одном Path2D
  static buildSketchPath(points: Point[], offsets: {dx:number,dy:number,w:number}[]): Path2D[];
}
```

**Алгоритм pressure-batching:**
1. Толщина для каждой точки: `width = baseSize * pressure`
2. Округление до одного из 8 уровней (buckets)
3. Группировка последовательных точек с одинаковым уровнем
4. Для каждой группы — один `Path2D` с `lineTo`
5. Рисуем 8 путей вместо 200 отдельных `stroke()` вызовов

**Интеграция в drawSegment:**
```typescript
if (settings.type === 'vector') {
  const paths = PathBatcher.buildPressureBatchedPaths(points, settings.size);
  paths.forEach(({ path, width }) => {
    ctx.lineWidth = width;
    ctx.stroke(path);  // один draw call на bucket
  });
}
```

**Ожидаемый эффект:** 200 draw calls → 8 draw calls на штрих. 25× уменьшение GPU вызовов для vector brush.

---

### Модуль 4: `src/utils/SpatialHash.ts`

**Проблема:** `getCanvasPoint()` (CanvasRenderer.tsx:1026-1048) перебирает ВСЕ guide points линейно. Если cache содержит 5,000 точек — каждое движение мыши = 5,000 distance вычислений.

**Решение:** Grid-based spatial hash.

```typescript
export class SpatialHash {
  private grid: Map<string, Point[]>;
  private cellSize: number;

  constructor(cellSize: number = 20);

  // Построение индекса
  build(points: Point[]): void;

  // Возвращает точки в соседних ячейках (обычно 0-10)
  query(x: number, y: number): Point[];

  // Точки в радиусе r
  queryRadius(x: number, y: number, r: number): Point[];

  // Ближайшая точка
  nearest(x: number, y: number): { point: Point; distance: number } | null;

  clear(): void;
}
```

**Алгоритм:**
1. `cellSize` = ~20px
2. Ключ ячейки: `Math.floor(x/cellSize), Math.floor(y/cellSize)`
3. `query(x, y)` — проверяет 3×3 ячейки вокруг точки
4. `nearest(x, y)` — query + поиск минимума среди ~10 точек вместо 5,000

**Интеграция:**
```typescript
const snapHashRef = useRef<SpatialHash>(new SpatialHash(20));
useEffect(() => {
  const allPoints: Point[] = [];
  Object.values(guidePointsCache).forEach(pts => allPoints.push(...pts));
  snapHashRef.current.build(allPoints);
}, [guidePointsCache]);

// В getCanvasPoint:
const nearest = snapHashRef.current.nearest(x, y);
if (nearest && nearest.distance < bestDist) {
  bestDist = nearest.distance;
  bestSnapPoint = nearest.point;
}
```

**Ожидаемый эффект:** O(5,000) → O(10) при каждом движении мыши. 500× ускорение snapping.

---

### Модуль 5: `src/utils/guides.ts`

**Проблема:** Математика направляющих дублирована в 4 местах:
1. `guidePointsCache` в CanvasRenderer.tsx (snapping)
2. `drawGuides` в CanvasRenderer.tsx (рендеринг)
3. `drawTemplatePreview` в Templates.tsx (preview)
4. `handleHiResExport` в Workspace.tsx (экспорт)

Каждая копия ~200 строк тригонометрии.

**Решение:** Единый модуль с чистыми функциями.

```typescript
// Вычисление точек для каждого типа
export function computeSpirographPoints(cx, cy, maxRadius, settings): Point[];
export function computeSuperellipsePoints(...): Point[];
export function computeMaurerRosePoints(...): Point[];
export function computeRosePetalsPoints(...): Point[];
export function computeLissajousPoints(...): Point[];
export function computeCardioidPoints(...): Point[];
export function computeSpiralPoints(...): Point[];
export function computeGridRays(...): Point[];
export function computeRings(...): Point[];

// Все активные направляющие
export function computeAllGuides(cx, cy, maxRadius, settings): { [key: string]: Point[] };

// Рендеринг
export function renderGuides(ctx, cx, cy, maxRadius, settings, zoom): void;
export function renderGuidesForExport(ctx, cx, cy, maxRadius, settings): void;
```

**Ожидаемый эффект:** DRY, поддержка в одном месте, возможность кэширования Path2D.

---

### Рефакторинг `CanvasRenderer.tsx`

**Изменения:**
1. Импорт новых модулей
2. Замена useEffect-рендеров на RenderScheduler
3. PathBatcher в drawSegment (vector brush)
4. SpatialHash в getCanvasPoint
5. Bbox-optimized scratch canvas для smudge/blur (временный, до WebGL):
```typescript
function updateScratchBbox(
  srcCanvas: HTMLCanvasElement,
  bbox: { x: number; y: number; w: number; h: number }
): void {
  const scratch = scratchCanvasRef.current;
  scratch.width = bbox.w;
  scratch.height = bbox.h;
  const sCtx = scratch.getContext('2d');
  sCtx.clearRect(0, 0, bbox.w, bbox.h);
  sCtx.drawImage(srcCanvas, bbox.x, bbox.y, bbox.w, bbox.h, 0, 0, bbox.w, bbox.h);
}
```

---

### Модуль 6: History delta в `App.tsx`

**Проблема:**
```typescript
const [history, setHistory] = useState<Stroke[][]>([[]]);
// 50 штрихов × 20 undo steps = 1,000 копий Stroke
```

**Решение:** Delta-based history.

```typescript
type HistoryAction =
  | { type: 'add'; stroke: Stroke }
  | { type: 'remove'; strokeId: string }
  | { type: 'clear'; previousStrokes: Stroke[] }
  | { type: 'load'; strokes: Stroke[] };

const [history, setHistory] = useState<HistoryAction[]>([]);
const [historyStep, setHistoryStep] = useState(-1);

const addStroke = (stroke: Stroke) => {
  const newHistory = history.slice(0, historyStep + 1);
  newHistory.push({ type: 'add', stroke });
  setHistory(newHistory);
  setHistoryStep(newHistory.length - 1);
  setStrokes(prev => [...prev, stroke]);
};

const undo = () => {
  if (historyStep < 0) return;
  const replayed = replayHistory(history.slice(0, historyStep));
  setStrokes(replayed);
  setHistoryStep(historyStep - 1);
};
```

**Ожидаемый эффект:** Память O(strokes × undo_depth) → O(undo_depth).

---

## ФАЗА 2: WebGL шейдеры для smudge/blur/stretch

### Модуль 7: `src/utils/SmudgeShader.ts`

**Проблема:** Текущий smudge (CanvasRenderer.tsx:665-729):
1. `updateScratchCanvas(canvas)` — копирует ВЕСЬ холст (W×H×4 байта)
2. Для каждой точки пути (× steps per segment): `clip()` + `drawImage(scratch)` + `restore()`
3. × segments (до 128) × mirror = катастрофа

**Решение:** WebGL2 fragment shader.

```typescript
export class SmudgeShader {
  private gl: WebGL2RenderingContext;
  private program: WebGLProgram;
  private framebuffer: WebGLFramebuffer;
  private texture: WebGLTexture;
  private outputTexture: WebGLTexture;

  constructor(canvas: HTMLCanvasElement);

  applySmudge(
    sourceCanvas: HTMLCanvasElement,
    points: Point[],
    brushSize: number,
    opacity: number,
    smudgeStrength: number
  ): HTMLCanvasElement;

  dispose(): void;
}
```

**Shader (GLSL):**
```glsl
#version 300 es
precision highp float;

uniform sampler2D u_source;
uniform vec2 u_resolution;
uniform vec2 u_pointPrev;
uniform vec2 u_pointCurr;
uniform float u_brushRadius;
uniform float u_strength;

out vec4 fragColor;

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec2 pos = gl_FragCoord.xy;

  float dist = distance(pos, u_pointCurr);
  if (dist > u_brushRadius) {
    fragColor = texture(u_source, uv);
    return;
  }

  vec2 dir = normalize(u_pointCurr - u_pointPrev);
  vec2 sampleOffset = dir * (u_brushRadius * 0.3) * u_strength;
  vec2 sampleUV = uv + sampleOffset / u_resolution;

  float mask = 1.0 - smoothstep(0.0, u_brushRadius, dist);
  mask = pow(mask, 2.0);

  vec4 original = texture(u_source, uv);
  vec4 sampled = texture(u_source, sampleUV);

  fragColor = mix(original, sampled, mask * u_strength);
}
```

**Алгоритм рендеринга:**
1. Загрузить canvas как текстуру (`texImage2D`)
2. Для каждой точки пути: uniforms (`u_pointPrev`, `u_pointCurr`, `u_brushRadius`, `u_strength`) + `drawArrays` (fullscreen quad) + ping-pong swap
3. Результат → обратно в Canvas 2D через `drawImage`

---

### Модуль 8: `src/utils/BlurShader.ts`

**Проблема:** Текущий blur (CanvasRenderer.tsx:779-835) использует `ctx.filter = 'blur(Xpx)'` — CPU-операция, применяемая per-step.

**Решение:** Two-pass Gaussian blur shader (horizontal + vertical).

```typescript
export class BlurShader {
  private gl: WebGL2RenderingContext;
  private hProgram: WebGLProgram;
  private vProgram: WebGLProgram;
  private pingPong: [WebGLTexture, WebGLTexture];

  constructor(canvas: HTMLCanvasElement);

  applyBlur(
    sourceCanvas: HTMLCanvasElement,
    points: Point[],
    brushSize: number,
    blurRadius: number,
    opacity: number
  ): HTMLCanvasElement;
}
```

**Shader (horizontal pass):**
```glsl
#version 300 es
precision highp float;

uniform sampler2D u_source;
uniform vec2 u_resolution;
uniform float u_blurRadius;
uniform vec2 u_brushCenter;
uniform float u_brushSize;
uniform float u_opacity;

out vec4 fragColor;

const float weights[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec2 texelSize = 1.0 / u_resolution;

  float dist = distance(gl_FragCoord.xy, u_brushCenter);
  float mask = 1.0 - smoothstep(0.0, u_brushSize, dist);
  mask = pow(mask, 2.0) * u_opacity;

  vec4 result = texture(u_source, uv) * weights[0];
  for (int i = 1; i < 5; i++) {
    result += texture(u_source, uv + vec2(float(i) * u_blurRadius, 0.0) * texelSize) * weights[i];
    result += texture(u_source, uv - vec2(float(i) * u_blurRadius, 0.0) * texelSize) * weights[i];
  }

  vec4 original = texture(u_source, uv);
  fragColor = mix(original, result, mask);
}
```

---

### Интеграция WebGL слоя в CanvasRenderer

**Архитектура слоёв:**
```
┌─────────────────────────────────────────┐
│  Overlay Canvas (Canvas 2D)              │
│  - Guides (renderGuides)                │
│  - Active stroke preview                │
│  - Brush cursor ring                    │
├─────────────────────────────────────────┤
│  WebGL Canvas (WebGL2) — под overlay     │
│  - Smudge/blur/stretch рендеринг         │
│  - Только когда активна соответствующая   │
│    кисть                                │
├─────────────────────────────────────────┤
│  Main Canvas (Canvas 2D)                 │
│  - Baked strokes (StrokeBaker)           │
│  - Vector/dotting/glow/и т.д.           │
└─────────────────────────────────────────┘
```

**Логика переключения:**
```typescript
const isWebGLSupported = checkWebGLSupport(); // Фоллбэк

if (isWebGLSupported && (brushSettings.type === 'smudge' || brushSettings.type === 'stretch')) {
  ctx.drawImage(baker.getCanvas(), 0, 0);
  const smudged = smudgeShader.applySmudge(mainCanvas, currentPoints, brushSize, opacity, strength);
  ctx.drawImage(smudged, 0, 0);
} else if (isWebGLSupported && brushSettings.type === 'blur') {
  // аналогично через BlurShader
} else {
  // Фоллбэк на Canvas 2D
  ctx.drawImage(baker.getCanvas(), 0, 0);
  if (isDrawing) drawSymmetric(ctx, tempStroke, cx, cy);
}
```

---

## Порядок реализации

```
Шаг 1: guides.ts (вынос математики)           — 1 час
Шаг 2: RenderScheduler.ts                     — 30 мин
Шаг 3: PathBatcher.ts                         — 30 мин
Шаг 4: SpatialHash.ts                         — 30 мин
Шаг 5: StrokeBaker.ts                         — 1 час
Шаг 6: Рефакторинг CanvasRenderer.tsx         — 2 часа
Шаг 7: App.tsx history delta                   — 30 мин
  -- ПРОВЕРКА BUILD + ТЕСТ --
Шаг 8: SmudgeShader.ts                        — 2 часа
Шаг 9: BlurShader.ts                          — 1 час
Шаг 10: Интеграция WebGL в CanvasRenderer     — 1 час
  -- ФИНАЛЬНАЯ ПРОВЕРКА BUILD + ТЕСТ --
```

---

## Что останется без изменений

- Вся UI часть (Workspace, TopNav, Gallery, Settings, Templates)
- SoundEngine.ts, AiGemini.ts, types.ts (возможно +`id` в Stroke)
- index.css, Tailwind конфигурация
- Концепция, UX, визуальный стиль

---

## Риски и митигация

| Риск | Митигация |
|------|-----------|
| StrokeBaker инвалидация при pan/zoom | Мировые координаты для кэша, camera transform при blit |
| WebGL не поддерживается | Fallback на Canvas 2D (bbox-оптимизированный) |
| OffscreenCanvas не везде | Обычный `document.createElement('canvas')` |
| Memory leak от WebGL textures | `dispose()` в useEffect cleanup |

---

*План создан на основе анализа `mandala-pro-studio/src`.*
