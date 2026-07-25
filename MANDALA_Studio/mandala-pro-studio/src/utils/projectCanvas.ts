import { Stroke } from '../types';

/**
 * Fixed drawing world (CSS/world units). Strokes live here.
 * Large enough to feel “infinite” for normal use — never auto-grows on stroke.
 * Bake buffer is capped separately (WorldScene MAX_WORLD_DEVICE_PX).
 */
export const DRAW_WORLD_SIZE = 8192;

/** Export / project quality presets (not the drawable world size). */
export const CANVAS_SIZE_PRESETS = [
  { label: '1024²', size: 1024 },
  { label: '1536²', size: 1536 },
  { label: '2048² HD', size: 2048 },
  { label: '3072²', size: 3072 },
  { label: '4096² 4K', size: 4096 },
  { label: '6144²', size: 6144 },
  { label: '8192² 8K', size: 8192 }
] as const;

/** Default export quality (world is always DRAW_WORLD_SIZE). */
export const DEFAULT_CANVAS_SIZE = 2048;
export const MIN_CANVAS_SIZE = 256;
export const MAX_CANVAS_SIZE = 16384;

export function clampCanvasSize(n: number): number {
  let s = Math.round(Number(n) || DEFAULT_CANVAS_SIZE);
  s = Math.max(MIN_CANVAS_SIZE, Math.min(MAX_CANVAS_SIZE, s));
  if (s % 2 !== 0) s += 1;
  return s;
}

/**
 * Пересчёт штрихов при смене разрешения (масштаб вокруг центра).
 * size кисти тоже масштабируется, чтобы визуальный вес сохранился.
 */
export function rescaleProjectStrokes(
  strokes: Stroke[],
  oldSize: number,
  newSize: number
): Stroke[] {
  if (oldSize <= 0 || newSize <= 0 || oldSize === newSize) return strokes;
  const s = newSize / oldSize;
  const oCx = oldSize / 2;
  const oCy = oldSize / 2;
  const nCx = newSize / 2;
  const nCy = newSize / 2;

  return strokes.map(stroke => ({
    ...stroke,
    settings: {
      ...stroke.settings,
      size: Math.max(0.5, stroke.settings.size * s)
    },
    points: stroke.points.map(p => ({
      ...p,
      x: (p.x - oCx) * s + nCx,
      y: (p.y - oCy) * s + nCy
    }))
  }));
}

export function formatCanvasSize(size: number): string {
  return `${size}×${size}`;
}

/**
 * Expand seed points by mandala dihedral replicas (segments × optional mirror).
 * Replicas can leave the square even when the drawn path is inside.
 */
export function expandPointsForSymmetry(
  points: { x: number; y: number }[],
  opts: { segments: number; mirror: boolean; rotation: number; cx: number; cy: number }
): { x: number; y: number }[] {
  if (!points.length) return points;
  const segs = Math.max(1, Math.round(opts.segments) || 1);
  const angleStep = (Math.PI * 2) / segs;
  const base = (opts.rotation * Math.PI) / 180;
  const { cx, cy } = opts;
  const out: { x: number; y: number }[] = [];

  for (let i = 0; i < points.length; i++) {
    const p = points[i];
    const dx = p.x - cx;
    const dy = p.y - cy;
    for (let s = 0; s < segs; s++) {
      const a = base + s * angleStep;
      const cos = Math.cos(a);
      const sin = Math.sin(a);
      const rx = dx * cos - dy * sin;
      const ry = dx * sin + dy * cos;
      out.push({ x: cx + rx, y: cy + ry });
      if (opts.mirror) {
        // mirror across local Y after rotation (same as drawSymmetric scale(-1,1) at center)
        out.push({ x: cx - rx, y: cy + ry });
      }
    }
  }
  return out;
}

/**
 * If stroke points (or brush halo / symmetry replicas) leave the square world [0, size]²,
 * return a larger even size so content fits after center-preserving rescale.
 * Returns `currentSize` when everything already fits.
 */
export function requiredCanvasSizeForPoints(
  points: { x: number; y: number }[],
  currentSize: number,
  brushRadius = 0
): number {
  const size = clampCanvasSize(currentSize);
  if (!points.length) return size;

  const pad = Math.max(12, brushRadius + 6);
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (let i = 0; i < points.length; i++) {
    const p = points[i];
    if (p.x < minX) minX = p.x;
    if (p.y < minY) minY = p.y;
    if (p.x > maxX) maxX = p.x;
    if (p.y > maxY) maxY = p.y;
  }

  // Fits inside padded square?
  if (minX >= pad && minY >= pad && maxX <= size - pad && maxY <= size - pad) {
    return size;
  }

  const cx = size / 2;
  const cy = size / 2;
  // L∞ distance from center covers square bounds
  let maxAbs = size / 2;
  for (let i = 0; i < points.length; i++) {
    const p = points[i];
    maxAbs = Math.max(maxAbs, Math.abs(p.x - cx), Math.abs(p.y - cy));
  }
  maxAbs += pad;

  let needed = Math.ceil(maxAbs * 2);
  // Grow in 256px steps to avoid micro-resizes every stroke
  needed = Math.ceil(needed / 256) * 256;
  return clampCanvasSize(Math.max(size, needed));
}

export type ContentFitSymmetry = {
  segments: number;
  mirror: boolean;
  rotation: number;
};

/**
 * Tight square size that fits all strokes (incl. mandala replicas) from center.
 * Can grow or shrink vs `currentSize`. Empty project → keep current size.
 * @param marginRatio extra padding as fraction of content radius (default 12%)
 */
/**
 * Content axis-aligned bounds in draw-world coordinates (incl. symmetry + brush pad).
 */
export function contentBoundsInWorld(
  strokes: Stroke[],
  worldSize: number,
  symmetry: ContentFitSymmetry
): { minX: number; minY: number; maxX: number; maxY: number } | null {
  if (!strokes.length) return null;
  const cx = worldSize / 2;
  const cy = worldSize / 2;
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  let maxBrushR = 0;

  for (let i = 0; i < strokes.length; i++) {
    const stroke = strokes[i];
    maxBrushR = Math.max(maxBrushR, (stroke.settings?.size ?? 0) / 2);
    const orbit = expandPointsForSymmetry(stroke.points, {
      segments: symmetry.segments,
      mirror: symmetry.mirror,
      rotation: symmetry.rotation,
      cx,
      cy
    });
    for (let j = 0; j < orbit.length; j++) {
      const p = orbit[j];
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
  }
  if (!Number.isFinite(minX)) return null;
  const pad = Math.max(16, maxBrushR);
  return {
    minX: minX - pad,
    minY: minY - pad,
    maxX: maxX + pad,
    maxY: maxY + pad
  };
}

/**
 * Camera pan/zoom so all content fits in the viewport (no world/quality resize).
 */
export function cameraFitToContent(
  strokes: Stroke[],
  symmetry: ContentFitSymmetry,
  worldSize: number,
  viewW: number,
  viewH: number,
  marginRatio = 0.1,
  zoomMin = 0.015,
  zoomMax = 120
): { zoom: number; pan: { x: number; y: number } } | null {
  const b = contentBoundsInWorld(strokes, worldSize, symmetry);
  if (!b || viewW <= 0 || viewH <= 0) return null;

  const bw = Math.max(32, b.maxX - b.minX);
  const bh = Math.max(32, b.maxY - b.minY);
  const contentCx = (b.minX + b.maxX) / 2;
  const contentCy = (b.minY + b.maxY) / 2;
  const scale = (1 - marginRatio) * Math.min(viewW / bw, viewH / bh);
  const zoom = Math.min(zoomMax, Math.max(zoomMin, scale));
  return {
    zoom,
    pan: {
      x: viewW / 2 - zoom * contentCx,
      y: viewH / 2 - zoom * contentCy
    }
  };
}

/**
 * Old projects: strokes lived in 0..canvasSize. Map into fixed DRAW_WORLD (center-preserving translate).
 */
export function migrateStrokesToDrawWorld(
  strokes: Stroke[],
  previousWorldSize: number,
  drawWorldSize: number = DRAW_WORLD_SIZE
): Stroke[] {
  if (!strokes.length || previousWorldSize === drawWorldSize) return strokes;
  const dx = (drawWorldSize - previousWorldSize) / 2;
  const dy = dx;
  return strokes.map(s => ({
    ...s,
    points: s.points.map(p => ({
      ...p,
      x: p.x + dx,
      y: p.y + dy
    }))
  }));
}
