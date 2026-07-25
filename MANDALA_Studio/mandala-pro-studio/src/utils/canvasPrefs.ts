/**
 * Пользовательские настройки холста, HUD и камеры (localStorage).
 */

export type HudCorner = 'tl' | 'tr' | 'bl' | 'br';

export interface CanvasPrefs {
  /** Режим фона: цвет или «без холста» (в редакторе — чёрный, экспорт — alpha). */
  canvasMode: 'color' | 'transparent';
  /** Цвет холста при mode=color */
  canvasColor: string;
  /** При экспорте всегда прозрачный фон (даже если в редакторе цветной). */
  exportTransparent: boolean;
  /** Показывать Perf HUD */
  hudEnabled: boolean;
  hudCorner: HudCorner;
  /** 0…1 */
  hudOpacity: number;
}

const KEY = 'mandalaCanvasPrefs';

const DEFAULTS: CanvasPrefs = {
  canvasMode: 'color',
  canvasColor: '#051424',
  exportTransparent: false,
  hudEnabled: true,
  hudCorner: 'tl',
  hudOpacity: 0.85
};

export function loadCanvasPrefs(): CanvasPrefs {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return { ...DEFAULTS };
    const parsed = JSON.parse(raw) as Partial<CanvasPrefs>;
    return {
      ...DEFAULTS,
      ...parsed,
      hudOpacity: Math.min(1, Math.max(0.05, Number(parsed.hudOpacity ?? DEFAULTS.hudOpacity))),
      canvasColor: typeof parsed.canvasColor === 'string' ? parsed.canvasColor : DEFAULTS.canvasColor
    };
  } catch {
    return { ...DEFAULTS };
  }
}

export function saveCanvasPrefs(prefs: CanvasPrefs): void {
  localStorage.setItem(KEY, JSON.stringify(prefs));
  window.dispatchEvent(new CustomEvent('mandala-prefs-changed', { detail: prefs }));
}

export function updateCanvasPrefs(partial: Partial<CanvasPrefs>): CanvasPrefs {
  const next = { ...loadCanvasPrefs(), ...partial };
  saveCanvasPrefs(next);
  return next;
}

/** Цвет заливки в Workspace (визуальный редактор). */
export function workspaceFillColor(prefs: CanvasPrefs): string {
  if (prefs.canvasMode === 'transparent') return '#000000';
  return prefs.canvasColor || DEFAULTS.canvasColor;
}

/** Нужен ли прозрачный фон при экспорте. */
export function exportIsTransparent(prefs: CanvasPrefs): boolean {
  return prefs.canvasMode === 'transparent' || prefs.exportTransparent;
}

/** Общие лимиты zoom для Workspace и Templates. */
export const CAMERA_ZOOM_MIN = 0.015;
export const CAMERA_ZOOM_MAX = 120;
