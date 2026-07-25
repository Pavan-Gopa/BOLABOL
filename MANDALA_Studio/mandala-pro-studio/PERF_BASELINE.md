# PERF_BASELINE — M0 (Perf baseline HUD)

Dev-only performance overlay for MANDALA Studio. **Measure-only** — it does not
change drawing, brush, baker, or shader behaviour. This is the "до" (before)
baseline that later MVP steps (M1–M4) will be compared against.

## How to enable the HUD

The HUD is **off by default** in production UI. It appears only when one of:

1. **Dev server** — `npm run dev` (Vite `import.meta.env.DEV` is `true`).
2. **Forced anywhere** — set `localStorage.mandalaPerfHud = '1'` in the browser
   console, then reload. Works in production builds too.
   - Turn off with `localStorage.removeItem('mandalaPerfHud')` + reload.

When active, a fixed monospace panel appears in the top-left corner showing:

| Field        | Meaning                                                        |
|--------------|----------------------------------------------------------------|
| `FPS`        | Frames/sec over a sliding ~1 s window (main canvas redraws).   |
| `drawAll ms` | Duration of the last `drawAllStrokes` pass (cache + composite + volatile re-draw). |
| `overlay ms` | Duration of the last `drawOverlay` pass (preview stroke + guides + cursor ring). |
| `strokes`    | Current `strokes.length`.                                      |
| `pan/zoom`   | `active` for ~800 ms after a wheel/pan interaction, else `idle`. |

The singleton is also reachable from the console as `window.mandalaPerfHud`
(in DEV only) if you need to inspect it.

## What to measure

1. Open the app with the HUD enabled.
2. Reproduce a scenario from the table below.
3. Read `FPS`, `drawAll ms`, `overlay ms`, and `strokes` while interacting /
   while idle-panning. The `drawAll ms` value is the closest observable proxy
   for the plan's p95 frame budget.

> Note: this baseline reports **per-frame last-pass ms**, not a p95 percentile.
> To get p95, observe `drawAll ms` across many interactions and take the 95th
> percentile of the high values. The HUD is the "до" harness; a scripted
> harness (synthetic strokes + frame budget) is post-MVP (P10/#6).

## Scenario table (MVP gates)

Synthetic scene recipe: `segments = 12` + `mirror` on, then draw the listed
stroke counts. Budgets come from `implementation_plan.md` → M0. Fill the "до"
column manually after measuring in this build; leave `TODO` if not yet measured.

| # | Сценарий (MVP gate)                         | Budget (p95) | До (measured) |
|---|---------------------------------------------|--------------|---------------|
| S1 | Pan/zoom, 500 vector strokes                | < 16 ms      | TODO          |
| S2 | Live vector stroke, 24 replicas             | < 12 ms      | TODO          |
| S3 | Live smudge, 24 replicas, size ≤ 40         | < 16 ms      | TODO          |
| S4 | After 20 smudge strokes, idle pan           | < 16 ms      | TODO          |
| S5 | Blur live + opacity 30%, 24 replicas        | < 16 ms      | TODO          |

## Suggested synthetic scenes

- **Vector load:** 100 then 500 vector strokes, `segments = 12` + mirror.
- **Effect load:** 10 then 20 smudge strokes (S4), then idle-pan.
- **Live stress:** hold a single stroke (vector / smudge / blur) while watching
  `drawAll ms` and `overlay ms`.

## Notes / limitations

- HUD draws on a separate DOM overlay → it adds negligible cost and never
  touches the canvas content.
- `drawAll ms` includes the baker sync + volatile re-draw of **all** smudge/blur
  strokes every frame (this is exactly the cost M2/M4 aim to remove — see P4/P1).
- Production build stays clean: no overlay is created unless DEV or the
  `localStorage` flag is set.
