/**
 * Performance HUD — только над областью холста (Workspace / Templates).
 * Host = div между side panels; position absolute в углах host.
 * Gallery / Settings: detach() — HUD не показывается.
 */

import { loadCanvasPrefs, HudCorner, CanvasPrefs } from './canvasPrefs';

const INSET = '10px';

const CORNER_STYLE: Record<HudCorner, Partial<CSSStyleDeclaration>> = {
  tl: { top: INSET, left: INSET, right: 'auto', bottom: 'auto' },
  tr: { top: INSET, right: INSET, left: 'auto', bottom: 'auto' },
  bl: { bottom: INSET, left: INSET, right: 'auto', top: 'auto' },
  br: { bottom: INSET, right: INSET, left: 'auto', top: 'auto' }
};

class PerfHudImpl {
  private el: HTMLDivElement | null = null;
  private host: HTMLElement | null = null;
  private rows: Record<string, HTMLSpanElement> = {};
  private timer: ReturnType<typeof setInterval> | null = null;

  private wantVisible = true;
  private corner: HudCorner = 'tl';
  private opacity = 0.85;

  private frameCount = 0;
  private lastFpsStamp = 0;
  private fps = 0;
  private drawAllMs = 0;
  private drawOverlayMs = 0;
  private strokeCount = 0;
  private panZoom = false;
  private panZoomTimer: ReturnType<typeof setTimeout> | null = null;
  /** Не обновлять DOM, если статус pz не сменился (меньше лишних перерисовок). */
  private lastPzLabel = '';

  constructor() {
    if (typeof window === 'undefined') return;
    const prefs = loadCanvasPrefs();
    this.wantVisible = prefs.hudEnabled !== false;
    this.corner = prefs.hudCorner || 'tl';
    this.opacity = prefs.hudOpacity ?? 0.85;

    window.addEventListener('mandala-prefs-changed', ((e: CustomEvent<CanvasPrefs>) => {
      this.applyPrefs(e.detail || loadCanvasPrefs());
    }) as EventListener);
  }

  /** true если HUD должен показывать метрики (prefs + привязан к host). */
  get enabled(): boolean {
    return this.wantVisible && !!this.host && !!this.el;
  }

  /**
   * Привязать к зоне холста (между панелями).
   * Workspace и Templates передают свой host.
   */
  attach(host: HTMLElement | null): void {
    if (!host) {
      this.detach();
      return;
    }
    // Убрать любые старые HUD
    document.querySelectorAll('#mandala-perf-hud').forEach(n => n.remove());
    this.el = null;

    this.host = host;
    const cs = getComputedStyle(host);
    if (cs.position === 'static') host.style.position = 'relative';

    if (this.wantVisible) this.mount();
  }

  /** Снять HUD (Gallery, Settings, unmount). */
  detach(): void {
    this.el?.remove();
    this.el = null;
    this.host = null;
    this.rows = {};
  }

  applyPrefs(prefs: CanvasPrefs): void {
    this.wantVisible = prefs.hudEnabled !== false;
    this.corner = prefs.hudCorner || 'tl';
    this.opacity = typeof prefs.hudOpacity === 'number' ? prefs.hudOpacity : 0.85;

    if (!this.host) return;

    if (this.wantVisible) {
      if (!this.el) this.mount();
      else this.applyLayout();
      if (this.el) this.el.style.display = 'block';
    } else if (this.el) {
      this.el.style.display = 'none';
    }
  }

  private mount(): void {
    if (!this.host || typeof document === 'undefined') return;

    document.querySelectorAll('#mandala-perf-hud').forEach(n => n.remove());

    const el = document.createElement('div');
    el.id = 'mandala-perf-hud';
    Object.assign(el.style, {
      position: 'absolute',
      zIndex: '5',
      padding: '6px 8px',
      font: '11px/1.4 ui-monospace, SFMono-Regular, Menlo, monospace',
      borderRadius: '8px',
      pointerEvents: 'none',
      whiteSpace: 'pre',
      boxSizing: 'border-box',
      maxWidth: 'min(220px, calc(100% - 20px))'
    } as CSSStyleDeclaration);

    const fields: [string, string][] = [
      ['fps', 'FPS'],
      ['drawAll', 'drawAll ms'],
      ['drawOverlay', 'overlay ms'],
      ['strokes', 'strokes'],
      ['pz', 'pan/zoom']
    ];
    for (const [key, label] of fields) {
      const line = document.createElement('div');
      line.style.display = 'flex';
      line.style.justifyContent = 'space-between';
      line.style.gap = '10px';
      const name = document.createElement('span');
      name.className = 'hud-label';
      name.textContent = label;
      name.style.flex = '0 0 auto';
      const val = document.createElement('span');
      val.className = 'hud-val';
      val.textContent = '—';
      // Fixed value width — HUD doesn't jump idle ↔ active
      val.style.display = 'inline-block';
      val.style.minWidth = '7ch';
      val.style.textAlign = 'right';
      val.style.fontVariantNumeric = 'tabular-nums';
      line.appendChild(name);
      line.appendChild(val);
      this.rows[key] = val;
      el.appendChild(line);
    }

    this.host.appendChild(el);
    this.el = el;
    this.lastFpsStamp = performance.now();
    if (!this.timer) this.timer = setInterval(() => this.tick(), 250);
    this.applyLayout();
  }

  private applyLayout(): void {
    if (!this.el) return;
    Object.assign(this.el.style, {
      top: 'auto',
      right: 'auto',
      bottom: 'auto',
      left: 'auto',
      ...CORNER_STYLE[this.corner]
    });
    // Whole-widget opacity (prefs slider); colors come from theme CSS (#mandala-perf-hud)
    const a = Math.min(1, Math.max(0.12, this.opacity));
    this.el.style.opacity = String(a);
  }

  frame(): void {
    if (!this.wantVisible || !this.el) return;
    this.frameCount++;
  }

  recordDrawAll(ms: number, strokeCount: number): void {
    if (!this.wantVisible || !this.el) return;
    this.drawAllMs = ms;
    this.strokeCount = strokeCount;
  }

  recordDrawOverlay(ms: number): void {
    if (!this.wantVisible || !this.el) return;
    this.drawOverlayMs = ms;
  }

  markPanZoom(): void {
    if (!this.wantVisible || !this.el) return;
    this.panZoom = true;
    if (this.panZoomTimer) clearTimeout(this.panZoomTimer);
    // Дольше держим «active», чтобы не мигало idle на каждом RAF/кадре
    this.panZoomTimer = setTimeout(() => {
      this.panZoom = false;
    }, 1600);
  }

  private tick(): void {
    if (!this.el || !this.wantVisible) return;
    const now = performance.now();
    const dt = now - this.lastFpsStamp;
    if (dt > 0) this.fps = (this.frameCount * 1000) / dt;
    this.frameCount = 0;
    this.lastFpsStamp = now;

    if (this.rows.fps) this.rows.fps.textContent = this.fps.toFixed(0).padStart(3, ' ');
    if (this.rows.drawAll) this.rows.drawAll.textContent = this.drawAllMs.toFixed(2).padStart(6, ' ');
    if (this.rows.drawOverlay) this.rows.drawOverlay.textContent = this.drawOverlayMs.toFixed(2).padStart(6, ' ');
    if (this.rows.strokes) this.rows.strokes.textContent = String(this.strokeCount).padStart(5, ' ');
    // Одинаковая длина: "active" / "idle  " — без скачка ширины
    const pz = this.panZoom ? 'active' : 'idle  ';
    if (this.rows.pz && pz !== this.lastPzLabel) {
      this.rows.pz.textContent = pz;
      this.lastPzLabel = pz;
    }
  }
}

export const perfHud = new PerfHudImpl();

if (typeof window !== 'undefined') {
  (window as any).mandalaPerfHud = perfHud;
}
