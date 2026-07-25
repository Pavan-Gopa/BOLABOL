/**
 * App-level prefs: theme, accent color, render quality (localStorage).
 * UI language is English-only for now (future: Settings → Language).
 */

export type AppTheme = 'midnight' | 'night' | 'day' | 'latte';
export type RenderQuality = 'high' | 'eco';

export interface AppSettings {
  theme: AppTheme;
  /** Accent used across chrome (buttons, icons, focus). Hex #rrggbb */
  accent: string;
  renderQuality: RenderQuality;
}

const KEY = 'mandalaAppSettings';

export const THEME_OPTIONS: {
  id: AppTheme;
  label: string;
  blurb: string;
  defaultAccent: string;
  preview: { bg: string; panel: string; accent: string };
}[] = [
  {
    id: 'midnight',
    label: 'Midnight Aura',
    blurb: 'Deep ocean teal — classic studio dark',
    defaultAccent: '#44e2cd',
    preview: { bg: '#051424', panel: '#0d1c2d', accent: '#44e2cd' }
  },
  {
    id: 'night',
    label: 'Night Violet',
    blurb: 'Purple void for late-night sessions',
    defaultAccent: '#c4b5fd',
    preview: { bg: '#0a0614', panel: '#16102a', accent: '#c4b5fd' }
  },
  {
    id: 'latte',
    label: 'Café Latte',
    blurb: 'Warm sepia / champagne — soft on the eyes',
    defaultAccent: '#a67c52',
    preview: { bg: '#f0e6d8', panel: '#e4d5c2', accent: '#a67c52' }
  },
  {
    id: 'day',
    label: 'Daylight Glass',
    blurb: 'Bright airy UI for daytime work',
    // Richer teal — more saturated / slightly deeper than soft mint for “Eye” contrast
    defaultAccent: '#0a6f68',
    preview: { bg: '#e8eef6', panel: '#ffffff', accent: '#0a6f68' }
  }
];

const ACCENT_PRESETS = [
  '#44e2cd',
  '#c4b5fd',
  '#a67c52',
  '#0a6f68',
  '#f472b6',
  '#38bdf8',
  '#fbbf24',
  '#f87171',
  '#a3e635',
  '#e879f9'
];

export { ACCENT_PRESETS };

const DEFAULTS: AppSettings = {
  theme: 'midnight',
  accent: '#44e2cd',
  renderQuality: 'high'
};

function isTheme(v: unknown): v is AppTheme {
  return v === 'midnight' || v === 'night' || v === 'day' || v === 'latte';
}

function normalizeHex(hex: string | undefined, fallback: string): string {
  if (!hex || typeof hex !== 'string') return fallback;
  const h = hex.trim();
  if (/^#[0-9a-fA-F]{6}$/.test(h)) return h.toLowerCase();
  if (/^#[0-9a-fA-F]{3}$/.test(h)) {
    const r = h[1],
      g = h[2],
      b = h[3];
    return `#${r}${r}${g}${g}${b}${b}`.toLowerCase();
  }
  return fallback;
}

export function themeDefaultAccent(theme: AppTheme): string {
  return THEME_OPTIONS.find(t => t.id === theme)?.defaultAccent ?? DEFAULTS.accent;
}

export function loadAppSettings(): AppSettings {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return { ...DEFAULTS };
    const parsed = JSON.parse(raw) as Partial<AppSettings> & { theme?: string };
    // migrate old 'night' etc.; ignore unknown
    const theme = isTheme(parsed.theme) ? parsed.theme : DEFAULTS.theme;
    const renderQuality =
      parsed.renderQuality === 'high' || parsed.renderQuality === 'eco'
        ? parsed.renderQuality
        : DEFAULTS.renderQuality;
    const accent = normalizeHex(parsed.accent, themeDefaultAccent(theme));
    return { theme, accent, renderQuality };
  } catch {
    return { ...DEFAULTS };
  }
}

export function saveAppSettings(settings: AppSettings): void {
  localStorage.setItem(KEY, JSON.stringify(settings));
  window.dispatchEvent(new CustomEvent('mandala-app-settings', { detail: settings }));
}

export function updateAppSettings(partial: Partial<AppSettings>): AppSettings {
  const next = { ...loadAppSettings(), ...partial };
  if (partial.theme && partial.accent === undefined) {
    // Switching theme adopts that theme's default accent (user can override after)
    next.accent = themeDefaultAccent(partial.theme);
  }
  if (partial.accent) {
    next.accent = normalizeHex(partial.accent, next.accent);
  }
  saveAppSettings(next);
  return next;
}

function hexToRgb(hex: string): { r: number; g: number; b: number } {
  const n = parseInt(hex.slice(1), 16);
  return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
}

function relativeLuminance(hex: string): number {
  const { r, g, b } = hexToRgb(hex);
  const lin = [r, g, b].map(c => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2];
}

function onAccentColor(accent: string): string {
  return relativeLuminance(accent) > 0.45 ? '#0f172a' : '#f8fafc';
}

function mixHex(hex: string, toward: string, t: number): string {
  const a = hexToRgb(hex);
  const b = hexToRgb(toward);
  const m = (x: number, y: number) => Math.round(x + (y - x) * t);
  const r = m(a.r, b.r)
    .toString(16)
    .padStart(2, '0');
  const g = m(a.g, b.g)
    .toString(16)
    .padStart(2, '0');
  const bl = m(a.b, b.b)
    .toString(16)
    .padStart(2, '0');
  return `#${r}${g}${bl}`;
}

/** Apply theme + accent CSS tokens on <html>. */
export function applyAppearance(settings?: AppSettings): void {
  const s = settings ?? loadAppSettings();
  const root = document.documentElement;
  root.dataset.theme = s.theme;

  const accent = normalizeHex(s.accent, themeDefaultAccent(s.theme));
  const { r, g, b } = hexToRgb(accent);
  root.style.setProperty('--color-secondary', accent);
  root.style.setProperty('--color-secondary-container', mixHex(accent, '#ffffff', 0.25));
  root.style.setProperty('--color-on-secondary', onAccentColor(accent));
  root.style.setProperty('--secondary-rgb', `${r}, ${g}, ${b}`);

  // Body overscroll flash color
  if (s.theme === 'day') {
    document.body.style.backgroundColor = '#e8eef6';
  } else if (s.theme === 'latte') {
    document.body.style.backgroundColor = '#e8dcc8';
  } else if (s.theme === 'night') {
    document.body.style.backgroundColor = '#06040e';
  } else {
    document.body.style.backgroundColor = '#000000';
  }
}

/** @deprecated use applyAppearance */
export function applyTheme(theme: AppTheme): void {
  const s = loadAppSettings();
  applyAppearance({ ...s, theme });
}

/** Bake quality multiplier for WorldScene (1 = full project px). */
export function bakeQualityScale(quality: RenderQuality): number {
  return quality === 'eco' ? 0.55 : 1;
}
