/**
 * guides.ts — единый источник математики направляющих мандалы.
 *
 * Ранее одна и та же тригонометрия была продублирована в 4 местах
 * (CanvasRenderer: кэш снаппинга + рендеринг, Templates: preview,
 * Workspace: экспорт). Теперь вся геометрия вычисляется здесь,
 * остальные модули вызывают готовые функции.
 */
import { Point, TemplateSettings } from '../types';

// ---------------------------------------------------------------------------
// Adaptive rail / guide colors — always contrast against canvas background
// ---------------------------------------------------------------------------

export type GuideLayerId =
  | 'grid'
  | 'rings'
  | 'petals'
  | 'spiral'
  | 'lissajous'
  | 'cardioid'
  | 'spirograph'
  | 'superellipse'
  | 'maurer'
  | 'center';

export interface GuidePalette {
  grid: string;
  rings: string;
  petals: string;
  spiral: string;
  lissajous: string;
  cardioid: string;
  spirograph: string;
  superellipse: string;
  maurer: string;
  center: string;
}

function parseHexRgb(hex: string): { r: number; g: number; b: number } | null {
  const h = (hex || '').trim();
  const m6 = /^#?([0-9a-f]{6})$/i.exec(h);
  if (m6) {
    const n = parseInt(m6[1], 16);
    return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
  }
  const m3 = /^#?([0-9a-f]{3})$/i.exec(h);
  if (m3) {
    const s = m3[1];
    return {
      r: parseInt(s[0] + s[0], 16),
      g: parseInt(s[1] + s[1], 16),
      b: parseInt(s[2] + s[2], 16)
    };
  }
  return null;
}

function relLum(r: number, g: number, b: number): number {
  const lin = [r, g, b].map(c => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2];
}

function rgbToHsl(r: number, g: number, b: number): { h: number; s: number; l: number } {
  r /= 255;
  g /= 255;
  b /= 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  if (max === min) return { h: 0, s: 0, l };
  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  let h = 0;
  switch (max) {
    case r:
      h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
      break;
    case g:
      h = ((b - r) / d + 2) / 6;
      break;
    default:
      h = ((r - g) / d + 4) / 6;
  }
  return { h: h * 360, s, l };
}

function hueDist(a: number, b: number): number {
  const d = Math.abs(a - b) % 360;
  return d > 180 ? 360 - d : d;
}

function hslToRgba(h: number, s: number, l: number, a: number): string {
  const hh = ((h % 360) + 360) % 360;
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const x = c * (1 - Math.abs(((hh / 60) % 2) - 1));
  const m = l - c / 2;
  let rp = 0,
    gp = 0,
    bp = 0;
  if (hh < 60) [rp, gp, bp] = [c, x, 0];
  else if (hh < 120) [rp, gp, bp] = [x, c, 0];
  else if (hh < 180) [rp, gp, bp] = [0, c, x];
  else if (hh < 240) [rp, gp, bp] = [0, x, c];
  else if (hh < 300) [rp, gp, bp] = [x, 0, c];
  else [rp, gp, bp] = [c, 0, x];
  const R = Math.round((rp + m) * 255);
  const G = Math.round((gp + m) * 255);
  const B = Math.round((bp + m) * 255);
  return `rgba(${R}, ${G}, ${B}, ${a})`;
}

/** Identity hues for formula rails (distinct “channels”). */
const LAYER_HUE: Record<Exclude<GuideLayerId, 'grid' | 'rings' | 'center'>, number> = {
  petals: 330,
  spiral: 145,
  lissajous: 275,
  cardioid: 45,
  spirograph: 185,
  superellipse: 18,
  maurer: 295
};

/**
 * Build a high-contrast guide palette for a canvas background.
 * Structural rails (grid/rings) go light-on-dark or dark-on-light;
 * formula rails keep identity hues but shift away from bg and flip lightness.
 */
export function getGuidePalette(bgHex: string): GuidePalette {
  const rgb = parseHexRgb(bgHex) || { r: 5, g: 20, b: 36 };
  const L = relLum(rgb.r, rgb.g, rgb.b);
  const bgHsl = rgbToHsl(rgb.r, rgb.g, rgb.b);
  const darkBg = L < 0.42;

  // Structural lattice — pure luminance contrast, slightly tinted
  const grid = darkBg
    ? 'rgba(255, 255, 255, 0.38)'
    : 'rgba(28, 22, 18, 0.42)';
  const rings = darkBg
    ? 'rgba(170, 215, 255, 0.40)'
    : 'rgba(35, 70, 110, 0.44)';

  const formula = (baseHue: number, alphaDark: number, alphaLight: number): string => {
    let h = baseHue;
    // Push hue away if background is chromatic and similar
    if (bgHsl.s > 0.12 && hueDist(h, bgHsl.h) < 36) {
      h = (h + 55) % 360;
    }
    // Lightness opposite of bg; higher saturation on light canvases for “Eye” contrast
    const s = darkBg ? 0.78 : 0.82;
    const l = darkBg ? 0.72 : 0.36;
    const a = darkBg ? alphaDark : alphaLight;
    return hslToRgba(h, s, l, a);
  };

  return {
    grid,
    rings,
    petals: formula(LAYER_HUE.petals, 0.55, 0.62),
    spiral: formula(LAYER_HUE.spiral, 0.52, 0.60),
    lissajous: formula(LAYER_HUE.lissajous, 0.55, 0.62),
    cardioid: formula(LAYER_HUE.cardioid, 0.55, 0.62),
    spirograph: formula(LAYER_HUE.spirograph, 0.55, 0.62),
    superellipse: formula(LAYER_HUE.superellipse, 0.55, 0.62),
    maurer: formula(LAYER_HUE.maurer, 0.58, 0.64),
    center: darkBg
      ? hslToRgba((bgHsl.h + 180) % 360, 0.75, 0.72, 1)
      : hslToRgba((bgHsl.h + 180) % 360, 0.8, 0.32, 1)
  };
}

// ---------------------------------------------------------------------------
// Pure curve point generators (world / screen coords).
// `step` — шаг интегрирования; значения по умолчанию совпадают с кэшем
// снаппинга (грубее), рендеринг передаёт более мелкий шаг для плавности.
// ---------------------------------------------------------------------------

export function computeSpirographPoints(
  cx: number, cy: number, maxRadius: number, settings: TemplateSettings
): Point[] {
  const pts: Point[] = [];
  const R = (settings.spiroR / 100) * maxRadius * 0.6;
  const rVal = (settings.spiro_r / 100) * maxRadius * 0.3;
  const d = (settings.spiroD / 100) * maxRadius * 0.4;
  const isEpi = settings.spiroType === 'epi';
  const rotLimit = Math.PI * 2 * (settings.spiroRotations || 10);

  for (let theta = 0; theta <= rotLimit; theta += 0.015) {
    let x: number, y: number;
    if (isEpi) {
      x = cx + (R + rVal) * Math.cos(theta) - d * Math.cos(((R + rVal) / rVal) * theta);
      y = cy + (R + rVal) * Math.sin(theta) - d * Math.sin(((R + rVal) / rVal) * theta);
    } else {
      x = cx + (R - rVal) * Math.cos(theta) + d * Math.cos(((R - rVal) / rVal) * theta);
      y = cy + (R - rVal) * Math.sin(theta) + d * Math.sin(((R - rVal) / rVal) * theta);
    }
    pts.push({ x, y });
  }
  return pts;
}

export function computeSuperellipsePoints(
  cx: number, cy: number, maxRadius: number, settings: TemplateSettings
): Point[] {
  const pts: Point[] = [];
  const n = settings.superellipseN;
  const a = (settings.superellipseA / 100) * maxRadius;
  const b = (settings.superellipseB / 100) * maxRadius;
  const baseRotation = (settings.rotation * Math.PI) / 180;

  for (let theta = 0; theta <= Math.PI * 2 + 0.05; theta += 0.01) {
    const cosT = Math.cos(theta);
    const sinT = Math.sin(theta);
    const xSign = Math.sign(cosT);
    const ySign = Math.sign(sinT);
    const xVal = a * xSign * Math.pow(Math.abs(cosT), 2 / n);
    const yVal = b * ySign * Math.pow(Math.abs(sinT), 2 / n);

    const rotX = cx + xVal * Math.cos(baseRotation) - yVal * Math.sin(baseRotation);
    const rotY = cy + xVal * Math.sin(baseRotation) + yVal * Math.cos(baseRotation);

    pts.push({ x: rotX, y: rotY });
  }
  return pts;
}

export function computeMaurerRosePoints(
  cx: number, cy: number, maxRadius: number, settings: TemplateSettings
): Point[] {
  const pts: Point[] = [];
  const n = settings.maurerN;
  const d = settings.maurerD;
  const a = maxRadius * 0.8;
  const baseRotation = (settings.rotation * Math.PI) / 180;

  for (let i = 0; i <= 360; i++) {
    const k = i * d;
    const r = a * Math.sin((n * k * Math.PI) / 180);
    const theta = (k * Math.PI) / 180 + baseRotation;
    const x = cx + r * Math.cos(theta);
    const y = cy + r * Math.sin(theta);
    pts.push({ x, y });
  }
  return pts;
}

export function computeRosePetalsPoints(
  cx: number, cy: number, maxRadius: number, settings: TemplateSettings, step = 0.015
): Point[] {
  const pts: Point[] = [];
  const a = (settings.petalLength / 100) * maxRadius;
  const k = settings.petalFrequency;
  const baseRotation = (settings.rotation * Math.PI) / 180;

  for (let theta = 0; theta < 2 * Math.PI; theta += step) {
    const r = a * Math.cos(k * theta);
    const x = cx + r * Math.cos(theta + baseRotation);
    const y = cy + r * Math.sin(theta + baseRotation);
    pts.push({ x, y });
  }
  return pts;
}

export function computeLissajousPoints(
  cx: number, cy: number, maxRadius: number, settings: TemplateSettings, step = 0.03
): Point[] {
  const pts: Point[] = [];
  const phaseRad = (settings.lissPhase * Math.PI) / 180;
  const rx = maxRadius * 0.75;
  const ry = maxRadius * 0.75;
  const baseRotation = (settings.rotation * Math.PI) / 180;

  for (let i = 0; i < settings.segments; i++) {
    const startAngle = baseRotation + (i * 2 * Math.PI) / settings.segments;
    for (let theta = 0; theta <= 2 * Math.PI + 0.02; theta += step) {
      const lx = rx * Math.cos(settings.lissFreqX * theta + phaseRad);
      const ly = ry * Math.sin(settings.lissFreqY * theta);
      const x = cx + lx * Math.cos(startAngle) - ly * Math.sin(startAngle);
      const y = cy + lx * Math.sin(startAngle) + ly * Math.cos(startAngle);
      pts.push({ x, y });
    }
  }
  return pts;
}

export function computeCardioidPoints(
  cx: number, cy: number, maxRadius: number, settings: TemplateSettings, step = 0.03
): Point[] {
  const pts: Point[] = [];
  const baseRotation = (settings.rotation * Math.PI) / 180;
  const a = (settings.cardioidA / 100) * maxRadius * 0.5;
  const b = (settings.cardioidB / 100) * maxRadius * 0.5;

  for (let i = 0; i < settings.segments; i++) {
    const startAngle = baseRotation + (i * 2 * Math.PI) / settings.segments;
    for (let theta = 0; theta <= 2 * Math.PI + 0.02; theta += step) {
      const rVal = a + b * Math.cos(theta);
      const x = cx + rVal * Math.cos(theta + startAngle);
      const y = cy + rVal * Math.sin(theta + startAngle);
      pts.push({ x, y });
    }
  }
  return pts;
}

export function computeSpiralPoints(
  cx: number, cy: number, maxRadius: number, settings: TemplateSettings, step = 0.04
): Point[] {
  const pts: Point[] = [];
  const b = settings.spiralGrowth / 10;
  const a = settings.spiralScale || 15;
  const baseRotation = (settings.rotation * Math.PI) / 180;
  const arms = settings.spiralArms || 3;

  for (let i = 0; i < arms; i++) {
    const startAngle = baseRotation + (i * 2 * Math.PI) / arms;
    for (let theta = 0; theta < Math.PI * 20; theta += step) {
      const r = a * Math.exp(b * theta);
      if (r > maxRadius * 1.5) break;
      const x = cx + r * Math.cos(theta + startAngle);
      const y = cy + r * Math.sin(theta + startAngle);
      pts.push({ x, y });
    }
  }
  return pts;
}

/**
 * Вычисляет все активные (enable'd) кривые-направляющие для снаппинга.
 * Ключи совпадают с оригинальным `guidePointsCache` в CanvasRenderer.
 */
export function computeAllGuides(
  cx: number, cy: number, maxRadius: number, settings: TemplateSettings
): { [key: string]: Point[] } {
  const cache: { [key: string]: Point[] } = {};

  if (settings.showSpirograph) cache['spirograph'] = computeSpirographPoints(cx, cy, maxRadius, settings);
  if (settings.showSuperellipse) cache['superellipse'] = computeSuperellipsePoints(cx, cy, maxRadius, settings);
  if (settings.showMaurer) cache['maurer'] = computeMaurerRosePoints(cx, cy, maxRadius, settings);
  if (settings.showPetals && settings.petalLength > 0) cache['petals'] = computeRosePetalsPoints(cx, cy, maxRadius, settings);
  if (settings.showLissajous) cache['lissajous'] = computeLissajousPoints(cx, cy, maxRadius, settings);
  if (settings.showCardioid) cache['cardioid'] = computeCardioidPoints(cx, cy, maxRadius, settings);
  if (settings.showSpiral && settings.spiralGrowth > 0) cache['spiral'] = computeSpiralPoints(cx, cy, maxRadius, settings);

  return cache;
}

// ---------------------------------------------------------------------------
// Рендеринг направляющих на 2D-контекст.
// ---------------------------------------------------------------------------

function drawPolyline(ctx: CanvasRenderingContext2D, pts: Point[], closePath = false): void {
  if (pts.length === 0) return;
  ctx.beginPath();
  ctx.moveTo(pts[0].x, pts[0].y);
  for (let i = 1; i < pts.length; i++) {
    ctx.lineTo(pts[i].x, pts[i].y);
  }
  if (closePath) ctx.closePath();
  ctx.stroke();
}

/**
 * Render guide rails on a 2D context (Workspace overlay / Templates / export).
 * @param bgColor canvas fill — palette is contrast-adapted to this color
 * @param zoom scale for line widths (1 for export)
 * @param drawCenter optional origin marker
 */
export function renderGuides(
  ctx: CanvasRenderingContext2D,
  cx: number,
  cy: number,
  maxRadius: number,
  settings: TemplateSettings,
  zoom: number,
  bgColor = '#051424',
  options?: { drawCenter?: boolean; rayLength?: number }
): void {
  const palette = getGuidePalette(bgColor);
  const z = Math.max(0.001, zoom);
  const rayLen = options?.rayLength ?? maxRadius * 2;

  ctx.save();
  ctx.lineCap = 'round';

  const layers = settings.guideLayerOrder || [
    'grid',
    'rings',
    'petals',
    'spiral',
    'lissajous',
    'cardioid',
    'spirograph',
    'superellipse',
    'maurer'
  ];

  layers.forEach(layer => {
    if (layer === 'grid' && settings.showGridLines) {
      ctx.strokeStyle = palette.grid;
      ctx.lineWidth = 1.15 / z;
      const angleStep = (Math.PI * 2) / settings.segments;
      const baseRotation = (settings.rotation * Math.PI) / 180;
      for (let i = 0; i < settings.segments; i++) {
        const angle = baseRotation + i * angleStep;
        ctx.beginPath();
        ctx.moveTo(cx, cy);
        ctx.lineTo(cx + Math.cos(angle) * rayLen, cy + Math.sin(angle) * rayLen);
        ctx.stroke();
      }
    } else if (layer === 'rings' && settings.showRings) {
      ctx.strokeStyle = palette.rings;
      ctx.lineWidth = 1.15 / z;
      const amp = (settings.ringModulationAmp || 0) / 100;
      const freq = settings.ringModulationFreq || 4;
      for (let j = 1; j <= settings.layers; j++) {
        const baseR = (j * maxRadius) / settings.layers;
        const pts: Point[] = [];
        for (let theta = 0; theta <= Math.PI * 2 + 0.02; theta += 0.01) {
          const modR = baseR * (1 + amp * Math.cos(freq * theta));
          pts.push({ x: cx + modR * Math.cos(theta), y: cy + modR * Math.sin(theta) });
        }
        drawPolyline(ctx, pts);
      }
    } else if (layer === 'petals' && settings.showPetals && settings.petalLength > 0) {
      ctx.strokeStyle = palette.petals;
      ctx.lineWidth = 1.65 / z;
      drawPolyline(ctx, computeRosePetalsPoints(cx, cy, maxRadius, settings, 0.005), true);
    } else if (layer === 'spiral' && settings.showSpiral && settings.spiralGrowth > 0) {
      ctx.strokeStyle = palette.spiral;
      ctx.lineWidth = 1.65 / z;
      drawPolyline(ctx, computeSpiralPoints(cx, cy, maxRadius, settings, 0.02));
    } else if (layer === 'lissajous' && settings.showLissajous) {
      ctx.strokeStyle = palette.lissajous;
      ctx.lineWidth = 1.65 / z;
      drawPolyline(ctx, computeLissajousPoints(cx, cy, maxRadius, settings, 0.01));
    } else if (layer === 'cardioid' && settings.showCardioid) {
      ctx.strokeStyle = palette.cardioid;
      ctx.lineWidth = 1.65 / z;
      drawPolyline(ctx, computeCardioidPoints(cx, cy, maxRadius, settings, 0.015), true);
    } else if (layer === 'spirograph' && settings.showSpirograph) {
      ctx.strokeStyle = palette.spirograph;
      ctx.lineWidth = 1.65 / z;
      drawPolyline(ctx, computeSpirographPoints(cx, cy, maxRadius, settings));
    } else if (layer === 'superellipse' && settings.showSuperellipse) {
      ctx.strokeStyle = palette.superellipse;
      ctx.lineWidth = 1.65 / z;
      drawPolyline(ctx, computeSuperellipsePoints(cx, cy, maxRadius, settings), true);
    } else if (layer === 'maurer' && settings.showMaurer) {
      ctx.strokeStyle = palette.maurer;
      ctx.lineWidth = 1.25 / z;
      drawPolyline(ctx, computeMaurerRosePoints(cx, cy, maxRadius, settings));
    }
  });

  if (options?.drawCenter) {
    ctx.fillStyle = palette.center;
    ctx.beginPath();
    ctx.arc(cx, cy, Math.max(2.5, 3.5 / z), 0, Math.PI * 2);
    ctx.fill();
  }

  ctx.restore();
}

/** High-res export guides (same adaptive palette as live view). */
export function renderGuidesForExport(
  ctx: CanvasRenderingContext2D,
  cx: number,
  cy: number,
  maxRadius: number,
  settings: TemplateSettings,
  bgColor = '#051424'
): void {
  renderGuides(ctx, cx, cy, maxRadius, settings, 1, bgColor, {
    drawCenter: false,
    rayLength: maxRadius * 2
  });
}
