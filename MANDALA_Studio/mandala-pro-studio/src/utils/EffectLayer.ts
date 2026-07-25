/**
 * EffectLayer — offscreen буфер для завершённых effect-штрихов (smudge/stretch/blur).
 *
 * Буфер в МИРОВЫХ координатах (размер worldW×worldH × dpr).
 * Pan/zoom только в blit() — без перезапекания.
 *
 * Важно: регионы коммита НЕ должны оставаться полностью непрозрачными
 * (иначе прямоугольники фона #051424 перекрывают vector-тайлы → «кубы» и
 * «пропадание» картинки при zoom). После commit вырезаем фон в alpha=0.
 */

import { Stroke } from '../types';
import { isCacheableStroke } from './StrokeBaker';

export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

interface Snapshot {
  id: string;
  x: number;
  y: number;
  w: number;
  h: number;
  data: ImageData | null;
}

/** Фон холста MANDALA — пиксели «пустого» фона делаем прозрачными после commit. */
const BG_R = 0x05;
const BG_G = 0x14;
const BG_B = 0x24;
const BG_TOL = 6;

export class EffectLayer {
  private canvas: HTMLCanvasElement;
  private ctx: CanvasRenderingContext2D | null;

  private worldW = 0;
  private worldH = 0;
  private dpr = 1;
  private hasContent = false;

  private snapshots: Snapshot[] = [];
  private readonly maxSnapshots = 20;

  constructor() {
    this.canvas = document.createElement('canvas');
    this.ctx = this.canvas.getContext('2d', { willReadFrequently: true });
  }

  static isEffectStroke(s: Stroke): boolean {
    return !isCacheableStroke(s);
  }

  get hasPixels(): boolean {
    return this.hasContent;
  }

  /**
   * Подгоняет размер. Очищает ТОЛЬКО при реальной смене размера
   * (не на каждый pan/zoom — иначе «пропадание прогресса»).
   */
  ensureSize(width: number, height: number, dpr: number): void {
    const W = Math.max(1, Math.round(width * dpr));
    const H = Math.max(1, Math.round(height * dpr));
    if (this.canvas.width === W && this.canvas.height === H) {
      this.worldW = width;
      this.worldH = height;
      this.dpr = dpr;
      return;
    }
    this.canvas.width = W;
    this.canvas.height = H;
    this.worldW = width;
    this.worldH = height;
    this.dpr = dpr;
    this.clear();
    this.snapshots = [];
  }

  clear(): void {
    const ctx = this.ctx;
    if (!ctx) return;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    this.hasContent = false;
  }

  getCanvas(): HTMLCanvasElement {
    return this.canvas;
  }

  /**
   * Блит мирового буфера с камерой.
   * target-ctx: любой; мы сами ставим transform и restore.
   */
  blit(
    ctx: CanvasRenderingContext2D,
    dpr: number,
    zoom: number,
    pan: { x: number; y: number }
  ): void {
    if (!this.hasContent || this.canvas.width === 0 || this.canvas.height === 0) return;
    ctx.save();
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
    // world → CSS px → device px: scale(dpr) * T(pan) * scale(zoom)
    ctx.setTransform(dpr * zoom, 0, 0, dpr * zoom, dpr * pan.x, dpr * pan.y);
    // Буфер: device-пиксели мира (1 world unit = dpr buffer px)
    ctx.drawImage(
      this.canvas,
      0,
      0,
      this.canvas.width,
      this.canvas.height,
      0,
      0,
      this.worldW,
      this.worldH
    );
    ctx.restore();
  }

  /**
   * Копирует device-регион mainCanvas в мировые координаты буфера.
   * Затем вырезает фон (alpha=0), чтобы не перекрывать vector-тайлы прямоугольниками.
   */
  commitRegion(
    mainCanvas: HTMLCanvasElement,
    src: Rect,
    dpr: number,
    zoom: number,
    pan: { x: number; y: number }
  ): void {
    const ctx = this.ctx;
    if (!ctx) return;
    if (src.w <= 0 || src.h <= 0) return;

    // Device → world
    const xWorld = (src.x / dpr - pan.x) / zoom;
    const yWorld = (src.y / dpr - pan.y) / zoom;
    const wWorld = src.w / dpr / zoom;
    const hWorld = src.h / dpr / zoom;

    // Пишем в world-space: buffer_px = world * this.dpr (без pan/zoom)
    ctx.save();
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    ctx.imageSmoothingEnabled = true;
    ctx.drawImage(mainCanvas, src.x, src.y, src.w, src.h, xWorld, yWorld, wWorld, hWorld);
    ctx.restore();

    // Вырезать фон в alpha в затронутом регионе (buffer px)
    const bx = Math.max(0, Math.floor(xWorld * this.dpr));
    const by = Math.max(0, Math.floor(yWorld * this.dpr));
    const bw = Math.min(this.canvas.width - bx, Math.ceil(wWorld * this.dpr) + 1);
    const bh = Math.min(this.canvas.height - by, Math.ceil(hWorld * this.dpr) + 1);
    if (bw > 0 && bh > 0) {
      this.punchBackground(bx, by, bw, bh);
    }

    this.hasContent = true;
  }

  /** Сделать пиксели фона холста прозрачными (чтобы blit не клал «серые кубы»). */
  private punchBackground(x: number, y: number, w: number, h: number): void {
    const ctx = this.ctx;
    if (!ctx) return;
    let img: ImageData;
    try {
      img = ctx.getImageData(x, y, w, h);
    } catch {
      return;
    }
    const d = img.data;
    for (let i = 0; i < d.length; i += 4) {
      const dr = Math.abs(d[i] - BG_R);
      const dg = Math.abs(d[i + 1] - BG_G);
      const db = Math.abs(d[i + 2] - BG_B);
      if (dr <= BG_TOL && dg <= BG_TOL && db <= BG_TOL) {
        d[i + 3] = 0;
      }
    }
    ctx.putImageData(img, x, y);
  }

  pushSnapshot(id: string, worldRect: Rect): void {
    const ctx = this.ctx;
    if (!ctx) return;
    const px = {
      x: Math.floor(worldRect.x * this.dpr),
      y: Math.floor(worldRect.y * this.dpr),
      w: Math.ceil(worldRect.w * this.dpr),
      h: Math.ceil(worldRect.h * this.dpr)
    };
    const x = Math.max(0, px.x);
    const y = Math.max(0, px.y);
    const w = Math.min(this.canvas.width - x, px.w);
    const h = Math.min(this.canvas.height - y, px.h);
    if (w <= 0 || h <= 0) {
      this.snapshots.push({ id, x: 0, y: 0, w: 0, h: 0, data: null });
      return;
    }
    const data = ctx.getImageData(x, y, w, h);
    this.snapshots.push({ id, x, y, w, h, data });
    if (this.snapshots.length > this.maxSnapshots) {
      this.snapshots.shift();
    }
  }

  popAndRestore(): boolean {
    const ctx = this.ctx;
    if (!ctx) return false;
    while (this.snapshots.length > 0) {
      const s = this.snapshots.pop()!;
      if (s.data) {
        ctx.putImageData(s.data, s.x, s.y);
        this.hasContent = true;
        return true;
      }
    }
    return false;
  }

  resetSnapshots(): void {
    this.snapshots = [];
  }

  dispose(): void {
    this.canvas.width = 0;
    this.canvas.height = 0;
    this.snapshots = [];
    this.hasContent = false;
  }
}
