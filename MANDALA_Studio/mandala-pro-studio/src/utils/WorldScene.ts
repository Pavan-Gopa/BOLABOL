/**
 * WorldScene — world-space растр сцены.
 *
 * - pan/zoom: только blit (буфер не трогаем)
 * - обычное рисование: incremental append одного штриха (плавно, без full rebake)
 * - undo/clear/load/resize: full rebuild в back-buffer, swap — без мигания пустым кадром
 *
 * Мир ВСЕГДА квадратный и больше viewport: мандала не должна «срезаться»
 * прямоугольником окна (типичный баг: wide screen → clip top/bottom).
 */

/**
 * Interactive bake cap (one side, device px).
 * 2048² was still too heavy with smudge×symmetry full-frame copies.
 * 1536² ≈ 9MB — keeps UI responsive; world units stay DRAW_WORLD_SIZE.
 */
const MAX_WORLD_DEVICE_PX = 1536;

/** Eco / quality multiplier applied on top of the device cap. */
let PROJECT_BAKE_DPR = 1;

/** 1 = full quality; 0.55 ≈ Eco Mode (меньше VRAM / быстрее bake). */
export function setWorldBakeQuality(scale: number): void {
  PROJECT_BAKE_DPR = Math.max(0.2, Math.min(1, scale));
}

export function getWorldBakeQuality(): number {
  return PROJECT_BAKE_DPR;
}

export interface MandalaWorld {
  /** Drawable world side (fixed DRAW_WORLD_SIZE — not export quality). */
  size: number;
  cx: number;
  cy: number;
  /** pan at zoom=1 so world center is viewport center */
  defaultPan: { x: number; y: number };
}

/**
 * World = fixed large square for drawing. Viewport is only a camera.
 * `drawWorldSize` is independent of export quality (canvasSize).
 */
export function getMandalaWorld(
  viewW: number,
  viewH: number,
  drawWorldSize: number
): MandalaWorld {
  let size = Math.max(256, Math.round(drawWorldSize) || 8192);
  if (size % 2 !== 0) size += 1;
  return {
    size,
    cx: size / 2,
    cy: size / 2,
    defaultPan: {
      x: viewW / 2 - size / 2,
      y: viewH / 2 - size / 2
    }
  };
}

export class WorldScene {
  /** То, что показываем (blit). */
  private display: HTMLCanvasElement;
  private displayCtx: CanvasRenderingContext2D | null;

  /** Рабочий буфер для full rebuild (потом swap). */
  private work: HTMLCanvasElement;
  private workCtx: CanvasRenderingContext2D | null;

  private worldW = 0;
  private worldH = 0;
  private dpr = 1;
  private contentSig = '';

  /** Сколько штрихов уже запечено инкрементально (для append detection). */
  private bakedStrokeCount = 0;
  private structureSig = '';
  /** Цвет заливки мира (редактор). */
  private bgColor = '#051424';

  /**
   * Snapshots of the bake buffer after each committed stroke count.
   * Undo (stroke count ↓) restores a snap instead of full rebuild — keeps Ctrl+Z snappy.
   */
  private undoSnaps: {
    strokeCount: number;
    structureSig: string;
    contentSig: string;
    canvas: HTMLCanvasElement;
  }[] = [];
  private readonly maxUndoSnaps = 32;

  constructor() {
    this.display = document.createElement('canvas');
    this.work = document.createElement('canvas');
    this.displayCtx = this.display.getContext('2d');
    this.workCtx = this.work.getContext('2d');
  }

  private clearUndoSnaps(): void {
    this.undoSnaps.length = 0;
  }

  /** Capture current display as an undo point (call after successful bake). */
  private pushUndoSnap(): void {
    if (!this.displayCtx || this.display.width <= 0 || this.contentSig === '') return;
    // Drop snaps with higher/equal count (new branch after undo+draw)
    this.undoSnaps = this.undoSnaps.filter(s => s.strokeCount < this.bakedStrokeCount);

    const c = document.createElement('canvas');
    c.width = this.display.width;
    c.height = this.display.height;
    const ctx = c.getContext('2d');
    if (!ctx) return;
    ctx.drawImage(this.display, 0, 0);
    this.undoSnaps.push({
      strokeCount: this.bakedStrokeCount,
      structureSig: this.structureSig,
      contentSig: this.contentSig,
      canvas: c
    });
    while (this.undoSnaps.length > this.maxUndoSnaps) {
      this.undoSnaps.shift();
    }
  }

  /**
   * Fast path for Ctrl+Z: restore bake buffer for a previous stroke count.
   * Returns true if restored (no full rebuild needed).
   */
  tryRestoreUndo(
    targetStrokeCount: number,
    structureSig: string,
    contentSig: string
  ): boolean {
    if (targetStrokeCount > this.bakedStrokeCount) return false;
    if (this.structureSig !== structureSig && structureSig !== '') {
      // structure may still match snap
    }
    // Prefer exact contentSig; else match count + structure
    let idx = -1;
    for (let i = this.undoSnaps.length - 1; i >= 0; i--) {
      const s = this.undoSnaps[i];
      if (s.contentSig === contentSig && s.structureSig === structureSig) {
        idx = i;
        break;
      }
    }
    if (idx < 0) {
      for (let i = this.undoSnaps.length - 1; i >= 0; i--) {
        const s = this.undoSnaps[i];
        if (s.strokeCount === targetStrokeCount && s.structureSig === structureSig) {
          idx = i;
          break;
        }
      }
    }
    if (idx < 0) return false;

    const snap = this.undoSnaps[idx];
    if (snap.canvas.width !== this.display.width || snap.canvas.height !== this.display.height) {
      // Buffer size changed — snaps invalid
      this.clearUndoSnaps();
      return false;
    }
    const ctx = this.displayCtx;
    if (!ctx) return false;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, this.display.width, this.display.height);
    ctx.drawImage(snap.canvas, 0, 0);
    this.contentSig = snap.contentSig;
    this.bakedStrokeCount = snap.strokeCount;
    this.structureSig = snap.structureSig;
    // Drop newer snaps
    this.undoSnaps = this.undoSnaps.slice(0, idx + 1);
    return true;
  }

  setBackgroundColor(color: string): void {
    this.bgColor = color || '#051424';
  }

  get width(): number {
    return this.worldW;
  }
  get height(): number {
    return this.worldH;
  }
  get devicePixelRatio(): number {
    return this.dpr;
  }
  get strokeCount(): number {
    return this.bakedStrokeCount;
  }
  getStructureSig(): string {
    return this.structureSig;
  }

  /** Diagnostics for hang hunting */
  getBakeStats(): {
    worldW: number;
    worldH: number;
    bakeDpr: number;
    bufferW: number;
    bufferH: number;
    megapixels: number;
    bakedStrokes: number;
  } {
    const bufferW = this.display.width;
    const bufferH = this.display.height;
    return {
      worldW: this.worldW,
      worldH: this.worldH,
      bakeDpr: this.dpr,
      bufferW,
      bufferH,
      megapixels: +((bufferW * bufferH) / 1e6).toFixed(2),
      bakedStrokes: this.bakedStrokeCount
    };
  }

  getCanvas(): HTMLCanvasElement {
    return this.display;
  }

  isCurrent(sig: string): boolean {
    return sig === this.contentSig && this.display.width > 0;
  }

  /**
   * Качество bake = project px (1:1). Если size > MAX_WORLD_DEVICE_PX — даунскейл буфера.
   * Параметр screenDpr не раздувает мир (Retina только для blit на экран).
   */
  private bakeDprOf(_screenDpr: number, worldSide?: number): number {
    const side = worldSide ?? Math.max(this.worldW, this.worldH, 1);
    const byCap = MAX_WORLD_DEVICE_PX / side;
    return Math.max(0.05, Math.min(PROJECT_BAKE_DPR, byCap));
  }

  private ensureCanvas(
    canvas: HTMLCanvasElement,
    worldW: number,
    worldH: number,
    dpr: number
  ): boolean {
    const bd = this.bakeDprOf(dpr, Math.max(worldW, worldH));
    const W = Math.max(1, Math.round(worldW * bd));
    const H = Math.max(1, Math.round(worldH * bd));
    const resized = canvas.width !== W || canvas.height !== H;
    if (resized) {
      canvas.width = W;
      canvas.height = H;
      // Snapshots no longer match buffer size
      if (canvas === this.display || canvas === this.work) {
        this.clearUndoSnaps();
      }
    }
    return resized;
  }

  private fillBg(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, w, h);
    ctx.fillStyle = this.bgColor;
    ctx.fillRect(0, 0, w, h);
  }

  private setWorldTransform(ctx: CanvasRenderingContext2D): void {
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
  }

  /**
   * Подготовить back-buffer к полной пересборке.
   * Display не трогаем — пока идёт bake, blit показывает старую картинку.
   */
  beginRebuild(worldW: number, worldH: number, dpr: number): CanvasRenderingContext2D | null {
    this.worldW = worldW;
    this.worldH = worldH;
    const bd = this.bakeDprOf(dpr, Math.max(worldW, worldH));
    this.dpr = bd;
    this.ensureCanvas(this.work, worldW, worldH, dpr);
    this.ensureCanvas(this.display, worldW, worldH, dpr);

    const ctx = this.workCtx;
    if (!ctx) return null;
    this.fillBg(ctx, this.work.width, this.work.height);
    this.setWorldTransform(ctx);
    return ctx;
  }

  /** Buffer side after last ensure (device px). */
  get bufferSide(): number {
    return this.display.width;
  }

  /** Закончить full rebuild: swap work → display (атомарно для пользователя). */
  endRebuild(sig: string, strokeCount: number, structureSig: string): void {
    // Swap buffers
    const tmpC = this.display;
    const tmpCtx = this.displayCtx;
    this.display = this.work;
    this.displayCtx = this.workCtx;
    this.work = tmpC;
    this.workCtx = tmpCtx;

    this.contentSig = sig;
    this.bakedStrokeCount = strokeCount;
    this.structureSig = structureSig;
    // Fresh baseline for undo stack
    this.clearUndoSnaps();
    this.pushUndoSnap();
  }

  /**
   * Подготовить display к incremental append (без clear).
   * Возвращает world-space ctx или null, если размер не готов.
   */
  beginAppend(worldW: number, worldH: number, dpr: number): CanvasRenderingContext2D | null {
    this.worldW = worldW;
    this.worldH = worldH;
    const bd = this.bakeDprOf(dpr, Math.max(worldW, worldH));
    this.dpr = bd;
    const resized = this.ensureCanvas(this.display, worldW, worldH, dpr);

    const ctx = this.displayCtx;
    if (!ctx) return null;

    if (resized || this.display.width === 0) {
      // Первый кадр / resize — нужен full rebuild, не append
      return null;
    }

    this.setWorldTransform(ctx);
    return ctx;
  }

  endAppend(sig: string, strokeCount: number, structureSig: string): void {
    this.contentSig = sig;
    this.bakedStrokeCount = strokeCount;
    this.structureSig = structureSig;
    this.pushUndoSnap();
  }

  /** Можно ли дописать ровно один новый штрих поверх (append-only). */
  canAppendOne(
    structureSig: string,
    newStrokeCount: number
  ): boolean {
    return (
      this.display.width > 0 &&
      this.contentSig !== '' &&
      this.structureSig === structureSig &&
      newStrokeCount === this.bakedStrokeCount + 1
    );
  }

  invalidate(): void {
    this.contentSig = '';
    this.bakedStrokeCount = 0;
    this.structureSig = '';
    this.clearUndoSnaps();
  }

  /**
   * Blit display → screen с камерой.
   * device = dpr * (pan + zoom * world)
   */
  blitTo(
    screenCtx: CanvasRenderingContext2D,
    screenW: number,
    screenH: number,
    dpr: number,
    zoom: number,
    pan: { x: number; y: number }
  ): void {
    screenCtx.setTransform(1, 0, 0, 1, 0, 0);
    screenCtx.clearRect(0, 0, screenW, screenH);
    screenCtx.fillStyle = this.bgColor;
    screenCtx.fillRect(0, 0, screenW, screenH);

    if (this.display.width === 0 || this.display.height === 0) return;

    screenCtx.save();
    screenCtx.imageSmoothingEnabled = true;
    screenCtx.imageSmoothingQuality = 'high';
    screenCtx.setTransform(dpr * zoom, 0, 0, dpr * zoom, dpr * pan.x, dpr * pan.y);
    screenCtx.drawImage(
      this.display,
      0,
      0,
      this.display.width,
      this.display.height,
      0,
      0,
      this.worldW,
      this.worldH
    );
    screenCtx.restore();
  }

  /**
   * Квадратный экспорт: вырезать регион мира (world CSS units) в outSize×outSize px.
   * Всегда квадрат — независимо от формы viewport.
   */
  /**
   * @param bg — цвет фона, или `null` для полностью прозрачного PNG (alpha).
   */
  exportSquare(
    outCtx: CanvasRenderingContext2D,
    outSize: number,
    worldCenterX: number,
    worldCenterY: number,
    worldSide: number,
    bg: string | null = '#051424'
  ): void {
    outCtx.setTransform(1, 0, 0, 1, 0, 0);
    outCtx.clearRect(0, 0, outSize, outSize);
    if (bg) {
      outCtx.fillStyle = bg;
      outCtx.fillRect(0, 0, outSize, outSize);
    }

    if (this.display.width === 0 || this.display.height === 0 || worldSide <= 0) return;

    const half = worldSide / 2;
    const srcX = (worldCenterX - half) * this.dpr;
    const srcY = (worldCenterY - half) * this.dpr;
    const srcS = worldSide * this.dpr;

    outCtx.imageSmoothingEnabled = true;
    outCtx.imageSmoothingQuality = 'high';
    outCtx.drawImage(
      this.display,
      srcX,
      srcY,
      srcS,
      srcS,
      0,
      0,
      outSize,
      outSize
    );

    // Fallback transparent path only (HQ export avoids this):
    // punch near-bg pixels — can nibble anti-aliased stroke edges.
    if (bg === null) {
      this.punchColorToAlpha(outCtx, outSize, outSize, this.bgColor, 3);
    }
  }

  private punchColorToAlpha(
    ctx: CanvasRenderingContext2D,
    w: number,
    h: number,
    hex: string,
    tol = 3
  ): void {
    const m = /^#?([0-9a-f]{6})$/i.exec(hex.trim());
    if (!m) return;
    const n = parseInt(m[1], 16);
    const tr = (n >> 16) & 255;
    const tg = (n >> 8) & 255;
    const tb = n & 255;
    let img: ImageData;
    try {
      img = ctx.getImageData(0, 0, w, h);
    } catch {
      return;
    }
    const d = img.data;
    for (let i = 0; i < d.length; i += 4) {
      if (
        Math.abs(d[i] - tr) <= tol &&
        Math.abs(d[i + 1] - tg) <= tol &&
        Math.abs(d[i + 2] - tb) <= tol
      ) {
        d[i + 3] = 0;
      }
    }
    ctx.putImageData(img, 0, 0);
  }

  dispose(): void {
    this.display.width = 0;
    this.display.height = 0;
    this.work.width = 0;
    this.work.height = 0;
    this.contentSig = '';
    this.bakedStrokeCount = 0;
    this.structureSig = '';
  }
}

/** Состояние камеры/мира для экспорт-модалки (выставляется CanvasRenderer). */
export interface MandalaExportSnapshot {
  worldScene: WorldScene;
  viewW: number;
  viewH: number;
  pan: { x: number; y: number };
  zoom: number;
  worldSize: number;
  cx: number;
  cy: number;
  /** Радиус решётки в world units (как в Workspace) */
  latticeRadius: number;
}

/**
 * Квадратный кадр из текущего viewport:
 * вписанный квадрат в окно → область мира под ним.
 */
export function squareCropFromView(
  viewW: number,
  viewH: number,
  pan: { x: number; y: number },
  zoom: number
): { centerX: number; centerY: number; side: number } {
  const z = Math.max(0.0001, zoom);
  const screenSide = Math.min(viewW, viewH);
  const side = screenSide / z;
  const screenX0 = (viewW - screenSide) / 2;
  const screenY0 = (viewH - screenSide) / 2;
  const worldX0 = (screenX0 - pan.x) / z;
  const worldY0 = (screenY0 - pan.y) / z;
  return {
    centerX: worldX0 + side / 2,
    centerY: worldY0 + side / 2,
    side
  };
}
