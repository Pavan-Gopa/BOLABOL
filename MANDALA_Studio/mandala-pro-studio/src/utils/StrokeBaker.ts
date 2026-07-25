/**
 * StrokeBaker — tiled, world-space кэш запечённых (baked) cacheable штрихов.
 *
 * M4 (World / tiled bake): устраняет full rebake ВСЕХ штрихов при pan/zoom.
 *   - Штрихи пекутся в МИРОВЫХ координатах (камера НЕ в bake-matrix).
 *   - Тайлы 512×512 (offscreen canvas на каждый тайл, ключ tx,ty).
 *   - Dirty-тайлы по bbox штриха (+ радиус кисти / glow spread) — padding для швов.
 *   - Pan/zoom: blit ТОЛЬКО visible тайлы через camera-transform (без rebake).
 *   - Add stroke: инкрементально перерисовываются только dirty-тайлы.
 *   - Full rebuild: clear/load/deep undo/смена видимости слоёв/симметрии/размеров.
 *   - Content identity: stroke-key (hash), НЕ только strokes.length.
 *
 * ВАЖНО: smudge/stretch/blur (VOLATILE) НЕ кэшируются — они в EffectLayer (M2),
 * либо живой WebGL-сессии (M3). Здесь только cacheable штрихи (vector/dotting/...).
 */

import { Stroke, DrawingLayer, BrushSettings } from '../types';

export type DrawFn = (
  ctx: CanvasRenderingContext2D,
  stroke: Stroke,
  cx: number,
  cy: number
) => void;

const VOLATILE_TYPES = new Set<BrushSettings['type']>(['smudge', 'stretch', 'blur']);

/** Штрих, который можно безопасно запечь (не сэмплирует основной холст). */
export function isCacheableStroke(s: Stroke): boolean {
  return !VOLATILE_TYPES.has(s.settings.type);
}

interface Tile {
  tx: number;
  ty: number;
  canvas: HTMLCanvasElement;
  ctx: CanvasRenderingContext2D | null;
}

const TILE = 512;
const PAD_PX = 14; // padding тайла в baked-пикселях (для semi-transparent швов)

export class StrokeBaker {
  private tiles = new Map<string, Tile>();

  // Разрешение сетки (baked-пиксели). Камера НЕ влияет.
  private bakeDpr = 1;
  private cols = 1;
  private rows = 1;
  private gridW = TILE;
  private gridH = TILE;

  // VRAM: предельный DPR для тайлов (как раньше maxBakeDpr).
  private readonly maxBakeDpr = 2;

  // Контент-идентичность (вместо strokes.length).
  private bakedFullSig = '';
  private bakedKeys: string[] | null = null;
  private dimSig = '';
  private layerVis = new Map<string, boolean>();

  /** Полностью ли кэш актуален (камера НЕ учитывается — pan/zoom бесплатны). */
  private isContentEqual(fullSig: string): boolean {
    return fullSig === this.bakedFullSig;
  }

  private layerSig(layers: DrawingLayer[]): string {
    return layers.map(l => `${l.id}:${l.visible ? 1 : 0}`).join('|');
  }

  private strokeKey(s: Stroke): string {
    const pts = s.points;
    let h = 0;
    const step = Math.max(1, Math.floor(pts.length / 8));
    for (let i = 0; i < pts.length; i += step) {
      h = (h * 31 + Math.round(pts[i].x * 100)) >>> 0;
      h = (h * 31 + Math.round(pts[i].y * 100)) >>> 0;
    }
    return [
      s.id || '',
      s.settings.type,
      s.settings.color,
      Math.round(s.settings.size * 100),
      Math.round(s.settings.opacity * 100),
      s.layerId || 'default',
      pts.length,
      h
    ].join(':');
  }

  private ensureGrid(dimensions: { width: number; height: number }, dpr: number): void {
    this.bakeDpr = Math.min(dpr, this.maxBakeDpr);
    this.cols = Math.max(1, Math.ceil((dimensions.width * this.bakeDpr) / TILE));
    this.rows = Math.max(1, Math.ceil((dimensions.height * this.bakeDpr) / TILE));
    this.gridW = this.cols * TILE;
    this.gridH = this.rows * TILE;
  }

  private clearAllTiles(): void {
    this.tiles.clear();
  }

  private getTile(tx: number, ty: number): Tile {
    const key = tx + ',' + ty;
    let t = this.tiles.get(key);
    if (!t) {
      const canvas = document.createElement('canvas');
      canvas.width = TILE;
      canvas.height = TILE;
      const ctx = canvas.getContext('2d');
      t = { tx, ty, canvas, ctx };
      this.tiles.set(key, t);
    }
    return t;
  }

  // Консервативный bbox штриха в baked-пикселях: радиальная симметрия вписана в
  // круг радиуса = max-удаление точки от центра. + brush radius / glow spread (padding).
  private strokeBBoxBaked(stroke: Stroke, cx: number, cy: number): { minX: number; minY: number; maxX: number; maxY: number } {
    const pts = stroke.points;
    let R = 0;
    for (const p of pts) {
      const d = Math.hypot(p.x - cx, p.y - cy);
      if (d > R) R = d;
    }
    const size = stroke.settings.size;
    const spread = (stroke.settings.type === 'glow' ? size * 1.5 : size * 0.5) + PAD_PX / this.bakeDpr;
    const pad = spread * this.bakeDpr;
    const cxb = cx * this.bakeDpr;
    const cyb = cy * this.bakeDpr;
    const Rb = R * this.bakeDpr + pad;
    const minX = Math.max(0, cxb - Rb);
    const minY = Math.max(0, cyb - Rb);
    const maxX = Math.min(this.gridW, cxb + Rb);
    const maxY = Math.min(this.gridH, cyb + Rb);
    return { minX, minY, maxX, maxY };
  }

  // Запечь один штрих в пересекающие его тайлы (поверх текущего содержимого тайла).
  private bakeStroke(stroke: Stroke, drawFn: DrawFn, cx: number, cy: number): void {
    if (this.layerVis.get(stroke.layerId || 'default') === false) return;
    if (!isCacheableStroke(stroke)) return;
    const bb = this.strokeBBoxBaked(stroke, cx, cy);
    const tx0 = Math.floor(bb.minX / TILE);
    const tx1 = Math.floor(bb.maxX / TILE);
    const ty0 = Math.floor(bb.minY / TILE);
    const ty1 = Math.floor(bb.maxY / TILE);
    for (let tx = tx0; tx <= tx1; tx++) {
      if (tx < 0 || tx >= this.cols) continue;
      for (let ty = ty0; ty <= ty1; ty++) {
        if (ty < 0 || ty >= this.rows) continue;
        const tile = this.getTile(tx, ty);
        const tctx = tile.ctx;
        if (!tctx) continue;
        // world -> tile-local baked px (канва тайла клиппует область за своими границами)
        tctx.setTransform(this.bakeDpr, 0, 0, this.bakeDpr, -tx * TILE, -ty * TILE);
        drawFn(tctx, stroke, cx, cy);
      }
    }
  }

  /** Полная перерисовка всех cacheable штрихов (undo/redo/clear/load/симметрия/видимость). */
  private rebake(
    strokes: Stroke[],
    layers: DrawingLayer[],
    drawFn: DrawFn,
    dimensions: { width: number; height: number }
  ): void {
    this.clearAllTiles();
    const cx = dimensions.width / 2;
    const cy = dimensions.height / 2;
    for (const layer of layers) {
      if (!layer.visible) continue;
      for (const s of strokes) {
        if ((s.layerId || 'default') !== layer.id) continue;
        this.bakeStroke(s, drawFn, cx, cy);
      }
    }
  }

  /**
   * Самостоятельно выбирает стратегию: nothing / incremental add / full rebake.
   * @param worldSignature сигнатура мира, влияющая на baked-контент (симметрия и т.п.)
   *        — НЕ содержит камеру (pan/zoom здесь не вызывает rebake).
   */
  sync(
    strokes: Stroke[],
    layers: DrawingLayer[],
    drawFn: DrawFn,
    dimensions: { width: number; height: number },
    dpr: number,
    worldSignature: string
  ): void {
    const dimSig = dimensions.width + 'x' + dimensions.height + '@' + dpr;
    if (dimSig !== this.dimSig) {
      this.dimSig = dimSig;
      this.ensureGrid(dimensions, dpr);
      this.clearAllTiles();
      this.bakedFullSig = '';
      this.bakedKeys = null;
    } else {
      this.ensureGrid(dimensions, dpr);
    }

    // Снимок видимости слоёв для фильтрации при bake.
    this.layerVis.clear();
    for (const l of layers) this.layerVis.set(l.id, l.visible);

    const contentSig = worldSignature + '#' + this.layerSig(layers);
    const keys = strokes.map(s => this.strokeKey(s));
    const fullSig = contentSig + '#' + keys.join('|');

    if (this.isContentEqual(fullSig)) return; // без изменений (в т.ч. при смене камеры)

    // Инкрементально: ровно один штрих добавлен в конец (append).
    if (
      this.bakedKeys &&
      this.bakedFullSig.startsWith(contentSig + '#') &&
      this.bakedKeys.length + 1 === keys.length
    ) {
      let appended = true;
      for (let i = 0; i < this.bakedKeys.length; i++) {
        if (this.bakedKeys[i] !== keys[i]) {
          appended = false;
          break;
        }
      }
      if (appended) {
        const last = strokes[strokes.length - 1];
        const cx = dimensions.width / 2;
        const cy = dimensions.height / 2;
        this.bakeStroke(last, drawFn, cx, cy);
        this.bakedKeys = keys;
        this.bakedFullSig = fullSig;
        return;
      }
    }

    // Иначе — полный rebake (undo/remove/modify/симметрия/видимость/load/resize).
    this.rebake(strokes, layers, drawFn, dimensions);
    this.bakedKeys = keys;
    this.bakedFullSig = fullSig;
  }

  /**
   * Нарисовать видимые тайлы на ctx с камерой (device-пиксели).
   * Pan/zoom здесь — БЕЗ rebake, только transform + drawImage visible тайлов.
   */
  drawVisibleTiles(
    ctx: CanvasRenderingContext2D,
    dpr: number,
    zoom: number,
    pan: { x: number; y: number }
  ): void {
    this.blit(ctx, dpr, zoom, pan, true);
  }

  /** Нарисовать ВСЕ тайлы (без culling) — для rebuild/export, где нужен полный кэш. */
  drawAllTiles(
    ctx: CanvasRenderingContext2D,
    dpr: number,
    zoom: number,
    pan: { x: number; y: number }
  ): void {
    this.blit(ctx, dpr, zoom, pan, false);
  }

  /** Число тайлов (для safety-rebuild, если кэш пуст при ненулевых strokes). */
  get tileCount(): number {
    return this.tiles.size;
  }

  private blit(
    ctx: CanvasRenderingContext2D,
    dpr: number,
    zoom: number,
    pan: { x: number; y: number },
    cull: boolean
  ): void {
    if (this.tiles.size === 0) return;
    // bake_px → device: scale = dpr*zoom/bakeDpr, origin = dpr*pan
    // world (x,y) baked at (x*bakeDpr, y*bakeDpr) → device dpr*(pan + zoom*world)
    const s = (dpr * zoom) / this.bakeDpr;
    const ox = dpr * pan.x;
    const oy = dpr * pan.y;
    const cw = ctx.canvas.width;
    const ch = ctx.canvas.height;

    ctx.save();
    ctx.setTransform(s, 0, 0, s, ox, oy);
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';

    for (const tile of this.tiles.values()) {
      const dx = tile.tx * TILE;
      const dy = tile.ty * TILE;
      if (cull) {
        const sx = ox + s * dx;
        const sy = oy + s * dy;
        const sw = s * TILE;
        const sh = s * TILE;
        // Небольшой запас, чтобы не отсекать тайлы на границе при дробном zoom
        if (sx + sw < -1 || sy + sh < -1 || sx > cw + 1 || sy > ch + 1) continue;
      }
      ctx.drawImage(tile.canvas, 0, 0, TILE, TILE, dx, dy, TILE, TILE);
    }
    ctx.restore();
  }

  /** Сброс (форсирует full rebake при следующем sync). */
  invalidate(): void {
    this.clearAllTiles();
    this.bakedFullSig = '';
    this.bakedKeys = null;
  }

  /** Очистить тайлы и сигнатуры. */
  clear(): void {
    this.clearAllTiles();
    this.bakedFullSig = '';
    this.bakedKeys = null;
  }

  dispose(): void {
    this.clearAllTiles();
  }
}
