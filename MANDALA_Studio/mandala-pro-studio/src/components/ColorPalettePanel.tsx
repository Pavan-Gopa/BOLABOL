import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  SWATCH_PRESETS,
  SwatchPresetId,
  addUserSwatch,
  loadUserSwatches,
  removeUserSwatch,
  sampleCanvasColor
} from '../utils/colorSwatches';

function hexToHsl(hex: string): { h: number; s: number; l: number } {
  let h = hex.replace(/^#/, '');
  if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
  const r = parseInt(h.slice(0, 2), 16) / 255;
  const g = parseInt(h.slice(2, 4), 16) / 255;
  const b = parseInt(h.slice(4, 6), 16) / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  let hue = 0;
  let sat = 0;
  const l = (max + min) / 2;
  if (max !== min) {
    const d = max - min;
    sat = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    switch (max) {
      case r:
        hue = (g - b) / d + (g < b ? 6 : 0);
        break;
      case g:
        hue = (b - r) / d + 2;
        break;
      default:
        hue = (r - g) / d + 4;
    }
    hue /= 6;
  }
  return { h: Math.round(hue * 360), s: Math.round(sat * 100), l: Math.round(l * 100) };
}

function hslToHex(h: number, s: number, l: number): string {
  s /= 100;
  l /= 100;
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
  const m = l - c / 2;
  let r = 0,
    g = 0,
    b = 0;
  if (h < 60) [r, g, b] = [c, x, 0];
  else if (h < 120) [r, g, b] = [x, c, 0];
  else if (h < 180) [r, g, b] = [0, c, x];
  else if (h < 240) [r, g, b] = [0, x, c];
  else if (h < 300) [r, g, b] = [x, 0, c];
  else [r, g, b] = [c, 0, x];
  const to = (n: number) =>
    Math.round((n + m) * 255)
      .toString(16)
      .padStart(2, '0');
  return `#${to(r)}${to(g)}${to(b)}`;
}

interface ColorPalettePanelProps {
  color: string;
  onChange: (hex: string) => void;
  pos: { x: number; y: number };
  onPosChange: (p: { x: number; y: number }) => void;
}

/**
 * Floating theme-aware color studio: square SV map + hue strip + swatches + eyedropper.
 */
export default function ColorPalettePanel({
  color,
  onChange,
  pos,
  onPosChange
}: ColorPalettePanelProps) {
  const mapRef = useRef<HTMLCanvasElement>(null);
  const hueRef = useRef<HTMLCanvasElement>(null);
  const dragMap = useRef(false);
  const dragHue = useRef(false);
  const panelDrag = useRef<{ ox: number; oy: number } | null>(null);

  const [collapsed, setCollapsed] = useState(false);
  const [presetId, setPresetId] = useState<SwatchPresetId>('spectrum');
  const [userSwatches, setUserSwatches] = useState<string[]>(() => loadUserSwatches());
  const [eyedrop, setEyedrop] = useState(false);
  const [hexDraft, setHexDraft] = useState(color);

  const hsl = hexToHsl(color);
  const { h: hue, s: sat, l: light } = hsl;

  useEffect(() => {
    setHexDraft(color);
  }, [color]);

  useEffect(() => {
    const onSw = (e: Event) => {
      const d = (e as CustomEvent<string[]>).detail;
      if (Array.isArray(d)) setUserSwatches(d);
      else setUserSwatches(loadUserSwatches());
    };
    window.addEventListener('mandala-swatches-changed', onSw as EventListener);
    return () => window.removeEventListener('mandala-swatches-changed', onSw as EventListener);
  }, []);

  // Square: X = saturation, Y = lightness (top = light)
  const drawMap = useCallback(() => {
    const canvas = mapRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    const w = canvas.width;
    const h = canvas.height;
    const img = ctx.createImageData(w, h);
    for (let y = 0; y < h; y++) {
      const l = 100 - (y / (h - 1)) * 100;
      for (let x = 0; x < w; x++) {
        const s = (x / (w - 1)) * 100;
        const hex = hslToHex(hue, s, l);
        const i = (y * w + x) * 4;
        img.data[i] = parseInt(hex.slice(1, 3), 16);
        img.data[i + 1] = parseInt(hex.slice(3, 5), 16);
        img.data[i + 2] = parseInt(hex.slice(5, 7), 16);
        img.data[i + 3] = 255;
      }
    }
    ctx.putImageData(img, 0, 0);

    // Cursor
    const cx = (sat / 100) * (w - 1);
    const cy = ((100 - light) / 100) * (h - 1);
    ctx.strokeStyle = light > 55 ? '#0f172a' : '#ffffff';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.arc(cx, cy, 5, 0, Math.PI * 2);
    ctx.stroke();
    ctx.strokeStyle = light > 55 ? '#ffffff' : '#0f172a';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.arc(cx, cy, 6.5, 0, Math.PI * 2);
    ctx.stroke();
  }, [hue, sat, light]);

  const drawHue = useCallback(() => {
    const canvas = hueRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    const w = canvas.width;
    const h = canvas.height;
    for (let y = 0; y < h; y++) {
      const hh = (y / (h - 1)) * 360;
      ctx.fillStyle = `hsl(${hh}, 100%, 50%)`;
      ctx.fillRect(0, y, w, 1);
    }
    const yy = (hue / 360) * (h - 1);
    ctx.strokeStyle = '#fff';
    ctx.lineWidth = 2;
    ctx.strokeRect(0.5, yy - 2, w - 1, 4);
    ctx.strokeStyle = '#0f172a';
    ctx.lineWidth = 1;
    ctx.strokeRect(0, yy - 3, w, 6);
  }, [hue]);

  // Redraw when color changes OR panel expands (canvas remount / was empty)
  useEffect(() => {
    if (collapsed) return;
    let raf = 0;
    let raf2 = 0;
    raf = requestAnimationFrame(() => {
      drawMap();
      drawHue();
      // Second frame: layout settled after expand
      raf2 = requestAnimationFrame(() => {
        drawMap();
        drawHue();
      });
    });
    return () => {
      cancelAnimationFrame(raf);
      cancelAnimationFrame(raf2);
    };
  }, [collapsed, drawMap, drawHue]);

  const pickMap = (e: React.PointerEvent<HTMLCanvasElement>) => {
    const canvas = mapRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const x = Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width));
    const y = Math.min(1, Math.max(0, (e.clientY - rect.top) / rect.height));
    const s = Math.round(x * 100);
    const l = Math.round(100 - y * 100);
    onChange(hslToHex(hue, s, Math.min(96, Math.max(4, l))));
  };

  const pickHue = (e: React.PointerEvent<HTMLCanvasElement>) => {
    const canvas = hueRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const y = Math.min(1, Math.max(0, (e.clientY - rect.top) / rect.height));
    const h = Math.round(y * 360) % 360;
    onChange(hslToHex(h, sat, light));
  };

  // Panel drag
  useEffect(() => {
    const onMove = (e: PointerEvent) => {
      if (!panelDrag.current) return;
      const nx = Math.min(window.innerWidth - 220, Math.max(8, e.clientX - panelDrag.current.ox));
      const ny = Math.min(window.innerHeight - 80, Math.max(48, e.clientY - panelDrag.current.oy));
      onPosChange({ x: nx, y: ny });
    };
    const onUp = () => {
      panelDrag.current = null;
    };
    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
    return () => {
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerup', onUp);
    };
  }, [onPosChange]);

  // Eyedropper from canvas
  useEffect(() => {
    if (!eyedrop) return;
    const canvas = document.getElementById('mandala-canvas') as HTMLCanvasElement | null;
    const prev = document.body.style.cursor;
    document.body.style.cursor = 'crosshair';

    const onClick = (e: MouseEvent) => {
      e.preventDefault();
      e.stopPropagation();
      if (!canvas) {
        setEyedrop(false);
        return;
      }
      const hex = sampleCanvasColor(canvas, e.clientX, e.clientY);
      if (hex) {
        onChange(hex);
        setUserSwatches(addUserSwatch(hex));
      }
      setEyedrop(false);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setEyedrop(false);
    };
    // Capture phase so we win over canvas drawing
    window.addEventListener('pointerdown', onClick, true);
    window.addEventListener('keydown', onKey);
    return () => {
      document.body.style.cursor = prev;
      window.removeEventListener('pointerdown', onClick, true);
      window.removeEventListener('keydown', onKey);
    };
  }, [eyedrop, onChange]);

  const preset = SWATCH_PRESETS.find(p => p.id === presetId) || SWATCH_PRESETS[0];

  const commitHex = () => {
    let v = hexDraft.trim();
    if (!v.startsWith('#')) v = `#${v}`;
    if (/^#[0-9a-fA-F]{3}$/.test(v)) {
      v = `#${v[1]}${v[1]}${v[2]}${v[2]}${v[3]}${v[3]}`;
    }
    if (/^#[0-9a-fA-F]{6}$/.test(v)) onChange(v.toLowerCase());
    else setHexDraft(color);
  };

  return (
    <div
      className="ui-float fixed z-40 w-[210px] rounded-xl shadow-2xl overflow-hidden"
      style={{ left: pos.x, top: pos.y }}
    >
      {/* Header */}
      <div
        className="ui-float-header px-2.5 py-1.5 flex items-center justify-between cursor-move select-none"
        onPointerDown={e => {
          if ((e.target as HTMLElement).closest('button')) return;
          panelDrag.current = { ox: e.clientX - pos.x, oy: e.clientY - pos.y };
        }}
      >
        <div className="flex items-center gap-1 text-slate-400">
          <span className="material-symbols-outlined text-[13px]">drag_indicator</span>
          <span className="font-manrope text-[9px] font-bold uppercase tracking-wider text-slate-300">
            Color
          </span>
        </div>
        <div className="flex items-center gap-0.5">
          <button
            type="button"
            title={eyedrop ? 'Cancel eyedropper (Esc)' : 'Pick from canvas'}
            onClick={() => setEyedrop(v => !v)}
            className={`p-0.5 rounded cursor-pointer transition-colors ${
              eyedrop ? 'text-secondary bg-secondary/15' : 'text-slate-500 hover:text-white'
            }`}
          >
            <span className="material-symbols-outlined text-[15px]">colorize</span>
          </button>
          <button
            type="button"
            onClick={() => setCollapsed(c => !c)}
            className="p-0.5 text-slate-500 hover:text-white cursor-pointer"
          >
            <span className="material-symbols-outlined text-[15px]">
              {collapsed ? 'expand_more' : 'expand_less'}
            </span>
          </button>
        </div>
      </div>

      {eyedrop && (
        <div className="px-2.5 py-1 text-[9px] font-manrope text-secondary bg-secondary/10 border-b border-secondary/20">
          Click canvas to sample · Esc cancel
        </div>
      )}

      <div className="p-2.5 space-y-2.5">
        {/* Keep pickers mounted (display:none) so expand never blanks the square */}
        <div className={collapsed ? 'hidden' : 'space-y-2.5'}>
          {/* Square map + hue strip */}
          <div className="flex gap-1.5 items-stretch">
            <canvas
              ref={mapRef}
              width={160}
              height={140}
              className="rounded border border-white/15 cursor-crosshair shrink-0 bg-[var(--ui-inset)]"
              style={{ width: 160, height: 140 }}
              onPointerDown={e => {
                dragMap.current = true;
                e.currentTarget.setPointerCapture(e.pointerId);
                pickMap(e);
              }}
              onPointerMove={e => {
                if (dragMap.current) pickMap(e);
              }}
              onPointerUp={e => {
                dragMap.current = false;
                e.currentTarget.releasePointerCapture(e.pointerId);
              }}
            />
            <canvas
              ref={hueRef}
              width={16}
              height={140}
              className="rounded border border-white/15 cursor-ns-resize shrink-0 bg-[var(--ui-inset)]"
              style={{ width: 16, height: 140 }}
              onPointerDown={e => {
                dragHue.current = true;
                e.currentTarget.setPointerCapture(e.pointerId);
                pickHue(e);
              }}
              onPointerMove={e => {
                if (dragHue.current) pickHue(e);
              }}
              onPointerUp={e => {
                dragHue.current = false;
                e.currentTarget.releasePointerCapture(e.pointerId);
              }}
            />
          </div>

          <div className="grid grid-cols-3 gap-1 text-[8px] font-mono text-slate-500">
            <span>H {hue}°</span>
            <span>S {sat}%</span>
            <span>L {light}%</span>
          </div>

          {/* Preset tabs — two full rows */}
          <div className="grid grid-cols-4 gap-0.5">
            {SWATCH_PRESETS.map(p => (
              <button
                key={p.id}
                type="button"
                onClick={() => setPresetId(p.id)}
                className={`px-1 py-0.5 rounded text-[7.5px] font-manrope font-bold uppercase tracking-wide cursor-pointer border transition-colors truncate ${
                  presetId === p.id
                    ? 'border-secondary/50 bg-secondary/15 text-secondary'
                    : 'border-white/10 text-slate-500 hover:text-slate-300'
                }`}
              >
                {p.label}
              </button>
            ))}
          </div>

          <div className="grid grid-cols-6 gap-1">
            {preset.colors.map(c => (
              <button
                key={`${presetId}-${c}`}
                type="button"
                title={c}
                onClick={() => onChange(c)}
                className={`aspect-square rounded border cursor-pointer transition-transform hover:scale-110 ${
                  color.toLowerCase() === c.toLowerCase()
                    ? 'border-secondary ring-1 ring-secondary/50'
                    : 'border-white/20'
                }`}
                style={{ background: c }}
              />
            ))}
          </div>

          <div>
            <div className="flex items-center justify-between mb-1">
              <span className="font-manrope text-[8px] font-bold uppercase tracking-wider text-slate-500">
                My colors
              </span>
              <button
                type="button"
                title="Add current color"
                onClick={() => setUserSwatches(addUserSwatch(color))}
                className="text-[8px] font-manrope font-bold text-secondary hover:text-white cursor-pointer flex items-center gap-0.5"
              >
                <span className="material-symbols-outlined text-[12px]">add</span>
                Add
              </button>
            </div>
            {userSwatches.length === 0 ? (
              <p className="text-[8px] text-slate-600 font-manrope leading-snug">
                Empty — eyedropper or Add saves here
              </p>
            ) : (
              <div className="grid grid-cols-6 gap-1">
                {userSwatches.map(c => (
                  <button
                    key={c}
                    type="button"
                    title={`${c} · right-click remove`}
                    onClick={() => onChange(c)}
                    onContextMenu={e => {
                      e.preventDefault();
                      setUserSwatches(removeUserSwatch(c));
                    }}
                    className={`aspect-square rounded border cursor-pointer hover:scale-110 transition-transform ${
                      color.toLowerCase() === c.toLowerCase()
                        ? 'border-secondary ring-1 ring-secondary/50'
                        : 'border-white/20'
                    }`}
                    style={{ background: c }}
                  />
                ))}
              </div>
            )}
          </div>
        </div>

        {/* Hex row always visible */}
        <div className="flex items-center gap-1.5 p-1.5 rounded border border-white/10 bg-black/20">
          <div
            className="w-7 h-7 rounded border border-white/25 shrink-0 shadow-inner"
            style={{ background: color }}
          />
          <input
            value={hexDraft}
            onChange={e => setHexDraft(e.target.value)}
            onBlur={commitHex}
            onKeyDown={e => e.key === 'Enter' && commitHex()}
            className="flex-1 min-w-0 bg-transparent font-mono text-[11px] text-white uppercase tracking-wide focus:outline-none"
            spellCheck={false}
          />
        </div>
      </div>
    </div>
  );
}
