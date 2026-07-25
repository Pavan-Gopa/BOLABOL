import React, { useEffect, useState } from 'react';
import {
  CANVAS_SIZE_PRESETS,
  DEFAULT_CANVAS_SIZE,
  MIN_CANVAS_SIZE,
  MAX_CANVAS_SIZE,
  clampCanvasSize,
  formatCanvasSize
} from '../utils/projectCanvas';

interface CanvasSizeDialogProps {
  open: boolean;
  mode: 'create' | 'resize';
  initialSize?: number;
  initialName?: string;
  onCancel: () => void;
  onConfirm: (opts: { size: number; name?: string }) => void;
}

/** New project / change square canvas resolution dialog. */
export default function CanvasSizeDialog({
  open,
  mode,
  initialSize = DEFAULT_CANVAS_SIZE,
  initialName = 'Sacred Mandala',
  onCancel,
  onConfirm
}: CanvasSizeDialogProps) {
  const [size, setSize] = useState(clampCanvasSize(initialSize));
  const [custom, setCustom] = useState(String(clampCanvasSize(initialSize)));
  const [name, setName] = useState(initialName);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    const s = clampCanvasSize(initialSize);
    setSize(s);
    setCustom(String(s));
    setName(initialName);
    setError(null);
  }, [open, initialSize, initialName]);

  if (!open) return null;

  const applyCustom = () => {
    const n = parseInt(custom, 10);
    if (!Number.isFinite(n)) {
      setError('Enter a number');
      return;
    }
    if (n < MIN_CANVAS_SIZE || n > MAX_CANVAS_SIZE) {
      setError(`Range ${MIN_CANVAS_SIZE}–${MAX_CANVAS_SIZE} px`);
      return;
    }
    setSize(clampCanvasSize(n));
    setCustom(String(clampCanvasSize(n)));
    setError(null);
  };

  const handleOk = () => {
    applyCustom();
    const s = clampCanvasSize(parseInt(custom, 10) || size);
    if (s < MIN_CANVAS_SIZE || s > MAX_CANVAS_SIZE) {
      setError(`Range ${MIN_CANVAS_SIZE}–${MAX_CANVAS_SIZE} px`);
      return;
    }
    onConfirm({
      size: s,
      name: mode === 'create' ? name.trim() || 'Sacred Mandala' : undefined
    });
  };

  return (
    <div className="fixed inset-0 z-[110] flex items-center justify-center bg-black/80 backdrop-blur-md p-4">
      <div className="ui-modal border rounded-2xl w-full max-w-md shadow-2xl overflow-hidden">
        <div className="px-5 py-3 border-b ui-border">
          <h3 className="font-manrope text-[15px] font-semibold text-white flex items-center gap-2">
            <span className="material-symbols-outlined text-secondary text-[20px]">
              {mode === 'create' ? 'add_box' : 'photo_size_select_large'}
            </span>
            {mode === 'create' ? 'New Mandala Project' : 'Change Canvas Resolution'}
          </h3>
          <p className="font-manrope text-[10px] text-slate-400 mt-0.5">
            Export quality (square). Drawing space is a large fixed world — resolution does not clip brushes.
          </p>
        </div>

        <div className="p-5 space-y-4 font-manrope">
          {mode === 'create' && (
            <div>
              <label className="text-[10px] text-slate-400 font-semibold">Name</label>
              <input
                type="text"
                value={name}
                onChange={e => setName(e.target.value)}
                className="mt-1 w-full bg-black/40 border border-white/10 rounded-lg px-3 py-2 text-[12px] text-white focus:outline-none focus:border-secondary"
                placeholder="Sacred Mandala"
              />
            </div>
          )}

          <div>
            <label className="text-[10px] text-slate-400 font-semibold">Presets</label>
            <div className="flex flex-wrap gap-2 mt-1.5">
              {CANVAS_SIZE_PRESETS.map(p => (
                <button
                  key={p.size}
                  type="button"
                  onClick={() => {
                    setSize(p.size);
                    setCustom(String(p.size));
                    setError(null);
                  }}
                  className={`px-2.5 py-1.5 rounded-full text-[10px] font-bold border cursor-pointer transition-all ${
                    size === p.size
                      ? 'bg-secondary/20 border-secondary text-secondary'
                      : 'bg-black/40 border-white/10 text-slate-300 hover:border-white/25'
                  }`}
                >
                  {p.label}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="text-[10px] text-slate-400 font-semibold">
              Custom resolution (square side, px)
            </label>
            <div className="flex gap-2 mt-1.5">
              <input
                type="number"
                min={MIN_CANVAS_SIZE}
                max={MAX_CANVAS_SIZE}
                value={custom}
                onChange={e => setCustom(e.target.value)}
                onBlur={applyCustom}
                className="flex-1 bg-black/40 border border-white/10 rounded-lg px-3 py-2 text-[12px] text-white font-mono focus:outline-none focus:border-secondary"
              />
              <span className="self-center text-[11px] text-slate-500">× {custom || '…'}</span>
            </div>
            <p className="text-[9px] text-slate-600 mt-1">
              {MIN_CANVAS_SIZE}–{MAX_CANVAS_SIZE} px · current{' '}
              <span className="text-secondary font-mono">{formatCanvasSize(size)}</span>
            </p>
          </div>

          {mode === 'resize' && (
            <p className="text-[10px] text-amber-200/80 bg-amber-500/10 border border-amber-500/20 rounded-lg px-3 py-2 leading-relaxed">
              Strokes and brush sizes will be rescaled from the center. Effect brushes
              (smudge/blur) will rebake.
            </p>
          )}

          {error && (
            <p className="text-[11px] text-red-400 bg-red-500/10 border border-red-500/20 rounded-lg px-3 py-2">
              {error}
            </p>
          )}

          <div className="flex gap-2 pt-1">
            <button
              type="button"
              onClick={onCancel}
              className="flex-1 py-2 rounded-full border border-white/10 text-slate-300 text-[11px] font-semibold hover:bg-white/5 cursor-pointer"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleOk}
              className="flex-1 py-2 rounded-full bg-secondary/20 border border-secondary/40 text-secondary text-[11px] font-bold hover:bg-secondary/30 cursor-pointer"
            >
              {mode === 'create' ? 'Create' : 'Apply'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
