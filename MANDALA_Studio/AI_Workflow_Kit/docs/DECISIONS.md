# Decision Log

## Template

### Step N
Status: IMPLEMENTED / APPROVED

Files:
- ...

Summary:
- ...

Reviewer Notes:
- ...

### Step M0 — Perf baseline
Status: APPROVED

Files:
- mandala-pro-studio/src/utils/PerfHud.ts
- mandala-pro-studio/src/components/CanvasRenderer.tsx
- mandala-pro-studio/PERF_BASELINE.md

Summary:
- Dev-only FPS / drawAll ms / overlay ms / stroke count HUD
- Opt-in via import.meta.env.DEV or localStorage.mandalaPerfHud === '1'
- dispose() for timers/DOM; measure-only, no brush/baker/shader changes

Reviewer Notes:
- Build OK (~660ms). No scope creep. Lightweight hot-path checks.

### Step M1 — Hot-path React & input
Status: APPROVED

Files:
- mandala-pro-studio/src/components/CanvasRenderer.tsx

Summary:
- currentPoints / isDrawing / hoverPoint / zoom / pan → useRef
- points via .push() (no spread); redraw via RenderScheduler
- min-distance: ~1px default, ~4px effect brushes, 8px dotting
- effect pointerDown: scratch bbox only (not full canvas)
- PerfHud (M0) preserved

Reviewer Notes:
- Build clean. No M2+ scope creep. Hot-path React overhead removed.

### Step M2 — EffectLayer rasterization
Status: APPROVED

Files:
- mandala-pro-studio/src/utils/EffectLayer.ts
- mandala-pro-studio/src/components/CanvasRenderer.tsx
- mandala-pro-studio/src/types.ts
- mandala-pro-studio/src/App.tsx
- mandala-pro-studio/src/utils/StrokeBaker.ts

Summary:
- Completed smudge/stretch/blur committed to EffectLayer; no per-frame WebGL re-play
- Dirty-region undo snapshots, depth 20
- World-ish buffer (dimensions × dpr); pan/zoom via blit transform
- Stroke.rasterized optional; baker still skips volatile types
- Known MVP limits documented in EffectLayer.ts (buffer size, layer visibility)

Reviewer Notes:
- vite build OK. No M3/M4 scope creep. EffectLayer.blit replaces N× full stroke re-apply.

### Step M3 — ROI / session WebGL
Status: APPROVED

Files:
- mandala-pro-studio/src/utils/SmudgeShader.ts
- mandala-pro-studio/src/utils/BlurShader.ts
- mandala-pro-studio/src/components/CanvasRenderer.tsx
- mandala-pro-studio/src/utils/EffectLayer.ts

Summary:
- Session API: beginStroke / stamp / endStroke on SmudgeShader + BlurShader
- gl.scissor ROI per stamp; GPU state lives across stamps; sequential replicas
- Live path integrated; endStroke commits dirty region to EffectLayer
- Canvas2D fallback keeps ROI scratch
- Multi-brush single-pass smudge NOT used (correct)

Reviewer Notes:
- npm run build OK. No M4 scope creep. Fullscreen-per-stamp bottleneck addressed via scissor.

### Step M4 — World-space / tiled bake
Status: APPROVED

Files:
- mandala-pro-studio/src/utils/StrokeBaker.ts
- mandala-pro-studio/src/components/CanvasRenderer.tsx

Summary:
- Tiled world-space cache (512×512, padding ~14px)
- pan/zoom uses drawVisibleTiles — no full rebake on camera change
- Incremental dirty tiles on add; full rebake on structural changes
- Content hash/strokeKey instead of length-only
- Composite: bg → tiles → EffectLayer → live (M0–M3 preserved)

Reviewer Notes:
- npm run build OK. No M3/Post-MVP scope creep.

### MVP_PERF track
Status: COMPLETE (M0–M4)

Delivered anti-lag stack:
- M0 PerfHud baseline
- M1 React hot-path refs + decimation
- M2 EffectLayer (no per-frame volatile re-play)
- M3 ROI session WebGL (scissor stamps)
- M4 World tiled bake (pan/zoom free)
