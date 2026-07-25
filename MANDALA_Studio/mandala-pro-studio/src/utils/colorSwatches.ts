/**
 * Color swatch presets + user library (localStorage).
 */

export type SwatchPresetId =
  | 'spectrum'
  | 'ocean'
  | 'earth'
  | 'neon'
  | 'mono'
  | 'sunset'
  | 'aurora'
  | 'ink';

export interface SwatchPreset {
  id: SwatchPresetId;
  label: string;
  colors: string[];
}

export const SWATCH_PRESETS: SwatchPreset[] = [
  {
    id: 'spectrum',
    label: 'Spectrum',
    colors: [
      '#ff0000',
      '#ff7a00',
      '#ffd400',
      '#7cff00',
      '#00e676',
      '#00e5ff',
      '#2979ff',
      '#7c4dff',
      '#e040fb',
      '#ff4081',
      '#ffffff',
      '#1a1a1a'
    ]
  },
  {
    id: 'ocean',
    label: 'Ocean',
    colors: [
      '#44e2cd',
      '#0d9488',
      '#0a6f68',
      '#38bdf8',
      '#0369a1',
      '#1e3a5f',
      '#a5f3fc',
      '#67e8f9',
      '#c4b5fd',
      '#818cf8',
      '#e0f2fe',
      '#0f172a'
    ]
  },
  {
    id: 'earth',
    label: 'Earth',
    colors: [
      '#a67c52',
      '#8b5e34',
      '#c4a574',
      '#d4a373',
      '#e9c46a',
      '#f4a261',
      '#e76f51',
      '#6b705c',
      '#a5a58d',
      '#b7b7a4',
      '#f5ebe0',
      '#3a2f24'
    ]
  },
  {
    id: 'neon',
    label: 'Neon',
    colors: [
      '#39ff14',
      '#00f0ff',
      '#ff00e5',
      '#ffe600',
      '#ff073a',
      '#7b2cbf',
      '#00ff9f',
      '#ff6b35',
      '#4cc9f0',
      '#f72585',
      '#b8f2e6',
      '#111111'
    ]
  },
  {
    id: 'mono',
    label: 'Mono',
    colors: [
      '#ffffff',
      '#e5e5e5',
      '#cccccc',
      '#999999',
      '#666666',
      '#444444',
      '#222222',
      '#000000',
      '#f8fafc',
      '#94a3b8',
      '#475569',
      '#0f172a'
    ]
  },
  {
    id: 'sunset',
    label: 'Sunset',
    colors: [
      '#ff6b35',
      '#f7c59f',
      '#ef476f',
      '#ffd166',
      '#f4a261',
      '#e63946',
      '#9b2226',
      '#bb3e03',
      '#ca6702',
      '#ee9b00',
      '#ffe8d6',
      '#370617'
    ]
  },
  {
    id: 'aurora',
    label: 'Aurora',
    colors: [
      '#80ffdb',
      '#72efdd',
      '#64dfdf',
      '#56cfe1',
      '#48bfe3',
      '#4ea8de',
      '#5390d9',
      '#5e60ce',
      '#6930c3',
      '#7400b8',
      '#c77dff',
      '#240046'
    ]
  },
  {
    id: 'ink',
    label: 'Ink Wash',
    colors: [
      '#0d1b2a',
      '#1b263b',
      '#415a77',
      '#778da9',
      '#e0e1dd',
      '#2b2d42',
      '#8d99ae',
      '#edf2f4',
      '#d90429',
      '#ef233c',
      '#8b9556',
      '#c9ada7'
    ]
  }
];

const KEY = 'mandalaUserSwatches';
const MAX_USER = 48;

export function loadUserSwatches(): string[] {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed)) return [];
    return parsed
      .filter((c): c is string => typeof c === 'string' && /^#[0-9a-fA-F]{6}$/.test(c))
      .slice(0, MAX_USER);
  } catch {
    return [];
  }
}

export function saveUserSwatches(colors: string[]): void {
  const clean = colors
    .map(c => c.toLowerCase())
    .filter((c, i, a) => /^#[0-9a-f]{6}$/.test(c) && a.indexOf(c) === i)
    .slice(0, MAX_USER);
  localStorage.setItem(KEY, JSON.stringify(clean));
  window.dispatchEvent(new CustomEvent('mandala-swatches-changed', { detail: clean }));
}

export function addUserSwatch(hex: string): string[] {
  const h = hex.toLowerCase();
  if (!/^#[0-9a-f]{6}$/.test(h)) return loadUserSwatches();
  const next = [h, ...loadUserSwatches().filter(c => c !== h)].slice(0, MAX_USER);
  saveUserSwatches(next);
  return next;
}

export function removeUserSwatch(hex: string): string[] {
  const next = loadUserSwatches().filter(c => c !== hex.toLowerCase());
  saveUserSwatches(next);
  return next;
}

/** Sample pixel from canvas under client coordinates (CSS → device). */
export function sampleCanvasColor(
  canvas: HTMLCanvasElement,
  clientX: number,
  clientY: number
): string | null {
  const rect = canvas.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) return null;
  const x = Math.floor(((clientX - rect.left) / rect.width) * canvas.width);
  const y = Math.floor(((clientY - rect.top) / rect.height) * canvas.height);
  if (x < 0 || y < 0 || x >= canvas.width || y >= canvas.height) return null;
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  if (!ctx) return null;
  try {
    const d = ctx.getImageData(x, y, 1, 1).data;
    const toHex = (n: number) => n.toString(16).padStart(2, '0');
    return `#${toHex(d[0])}${toHex(d[1])}${toHex(d[2])}`;
  } catch {
    return null;
  }
}
