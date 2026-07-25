import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { TemplateSettings } from '../types';
import { MandalaExportSnapshot } from '../utils/WorldScene';
import { renderGuidesForExport } from '../utils/guides';
import { loadCanvasPrefs, exportIsTransparent, workspaceFillColor } from '../utils/canvasPrefs';
import { CANVAS_SIZE_PRESETS } from '../utils/projectCanvas';
import MandalaExportLoader from './MandalaExportLoader';

interface ExportModalProps {
  open: boolean;
  onClose: () => void;
  templateSettings: TemplateSettings;
  /** Project quality — used as default export size when modal opens */
  projectCanvasSize?: number;
}

/** Same ladder as project canvas quality (incl. 8K). */
const PRESET_SIZES = CANVAS_SIZE_PRESETS.map(p => ({
  label: p.label,
  px: p.size
}));

function yieldToUi(): Promise<void> {
  return new Promise(resolve => {
    requestAnimationFrame(() => {
      requestAnimationFrame(() => resolve());
    });
  });
}

/**
 * Square export modal — HQ re-render at chosen resolution (up to 8K).
 */
export default function ExportModal({
  open,
  onClose,
  templateSettings,
  projectCanvasSize = 2048
}: ExportModalProps) {
  const previewRef = useRef<HTMLCanvasElement>(null);
  const [snap, setSnap] = useState<MandalaExportSnapshot | null>(null);
  const [exportPx, setExportPx] = useState(2048);
  const [bakeGrid, setBakeGrid] = useState(!!templateSettings.showGridInExport);
  const [exportTransparent, setExportTransparent] = useState(false);
  const [nudgeX, setNudgeX] = useState(0);
  const [nudgeY, setNudgeY] = useState(0);
  const [cropZoom, setCropZoom] = useState(1);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [busyStatus, setBusyStatus] = useState('Please wait');

  useEffect(() => {
    if (!open) {
      setSnap(null);
      setBusy(false);
      return;
    }
    setNudgeX(0);
    setNudgeY(0);
    setCropZoom(1);
    setBakeGrid(!!templateSettings.showGridInExport);
    const prefs = loadCanvasPrefs();
    setExportTransparent(exportIsTransparent(prefs));
    setError(null);
    // Default export size = project quality (clamped to known presets if close)
    const match = PRESET_SIZES.find(p => p.px === projectCanvasSize);
    setExportPx(match ? match.px : projectCanvasSize);
    window.flushMandalaScene?.();
    const s = window.getMandalaExportSnapshot?.() ?? null;
    if (!s) {
      setError('Scene not ready. Close and try again.');
    }
    setSnap(s);
  }, [open, templateSettings.showGridInExport, projectCanvasSize]);

  const baseCrop = useMemo(() => {
    if (!snap) return null;
    const mandalaSide = Math.max(64, (snap.latticeRadius / 0.85) * 2 * 1.08);
    return {
      centerX: snap.cx,
      centerY: snap.cy,
      side: mandalaSide
    };
  }, [snap]);

  const effectiveCrop = useMemo(() => {
    if (!baseCrop) return null;
    const side = Math.max(8, baseCrop.side / Math.max(0.25, cropZoom));
    return {
      centerX: baseCrop.centerX + nudgeX,
      centerY: baseCrop.centerY + nudgeY,
      side
    };
  }, [baseCrop, nudgeX, nudgeY, cropZoom]);

  const paintPreview = useCallback(() => {
    const canvas = previewRef.current;
    if (!canvas || !effectiveCrop || !snap) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const previewSize = 360;
    if (canvas.width !== previewSize || canvas.height !== previewSize) {
      canvas.width = previewSize;
      canvas.height = previewSize;
    }

    const prefs = loadCanvasPrefs();
    const bg = exportTransparent ? null : workspaceFillColor(prefs);
    snap.worldScene.exportSquare(
      ctx,
      previewSize,
      effectiveCrop.centerX,
      effectiveCrop.centerY,
      effectiveCrop.side,
      bg
    );

    if (bakeGrid) {
      const scale = previewSize / effectiveCrop.side;
      const cx = (snap.cx - (effectiveCrop.centerX - effectiveCrop.side / 2)) * scale;
      const cy = (snap.cy - (effectiveCrop.centerY - effectiveCrop.side / 2)) * scale;
      const maxRadius = snap.latticeRadius * scale;
      const guideBg = bg || workspaceFillColor(prefs);
      renderGuidesForExport(ctx, cx, cy, maxRadius, templateSettings, guideBg);
    }

    ctx.save();
    ctx.strokeStyle =
      getComputedStyle(document.documentElement).getPropertyValue('--color-secondary').trim() ||
      '#44e2cd';
    ctx.lineWidth = 2;
    ctx.strokeRect(1, 1, previewSize - 2, previewSize - 2);
    ctx.setLineDash([4, 4]);
    ctx.strokeStyle = 'rgba(255,255,255,0.15)';
    ctx.beginPath();
    ctx.moveTo(previewSize / 2, 0);
    ctx.lineTo(previewSize / 2, previewSize);
    ctx.moveTo(0, previewSize / 2);
    ctx.lineTo(previewSize, previewSize / 2);
    ctx.stroke();
    ctx.restore();
  }, [effectiveCrop, snap, bakeGrid, templateSettings, exportTransparent]);

  useEffect(() => {
    if (open && snap) paintPreview();
  }, [open, snap, paintPreview]);

  const handleExport = async () => {
    if (!snap || !effectiveCrop || busy) {
      if (!snap || !effectiveCrop) setError('Scene not ready.');
      return;
    }
    setBusy(true);
    setError(null);
    setBusyStatus('Preparing export…');

    // Let React paint the mandala loader before heavy work blocks the main thread
    await yieldToUi();
    await new Promise(r => setTimeout(r, 40));

    try {
      setBusyStatus('Flushing scene…');
      await yieldToUi();
      window.flushMandalaScene?.();

      const prefs = loadCanvasPrefs();
      const bg = exportTransparent ? null : workspaceFillColor(prefs);

      setBusyStatus(
        exportTransparent || bakeGrid
          ? 'Rendering strokes & guides…'
          : 'Rendering strokes at full resolution…'
      );
      await yieldToUi();
      await new Promise(r => setTimeout(r, 30));

      // High-quality path (can take several seconds at 4K/8K)
      let out =
        window.renderMandalaExportSquare?.({
          outSize: exportPx,
          centerX: effectiveCrop.centerX,
          centerY: effectiveCrop.centerY,
          side: effectiveCrop.side,
          transparent: exportTransparent,
          bg,
          bakeGrid,
          templateSettings
        }) ?? null;

      if (!out) {
        setBusyStatus('Fallback raster export…');
        await yieldToUi();
        const fresh = window.getMandalaExportSnapshot?.();
        const scene = fresh?.worldScene ?? snap.worldScene;
        out = document.createElement('canvas');
        out.width = exportPx;
        out.height = exportPx;
        const ctx = out.getContext('2d');
        if (!ctx) {
          setError('Could not create canvas.');
          setBusy(false);
          return;
        }
        scene.exportSquare(
          ctx,
          exportPx,
          effectiveCrop.centerX,
          effectiveCrop.centerY,
          effectiveCrop.side,
          bg
        );
        if (bakeGrid) {
          const scale = exportPx / effectiveCrop.side;
          const gcx = (snap.cx - (effectiveCrop.centerX - effectiveCrop.side / 2)) * scale;
          const gcy = (snap.cy - (effectiveCrop.centerY - effectiveCrop.side / 2)) * scale;
          const maxRadius = snap.latticeRadius * scale;
          renderGuidesForExport(
            ctx,
            gcx,
            gcy,
            maxRadius,
            templateSettings,
            bg || workspaceFillColor(prefs)
          );
        }
      }

      setBusyStatus('Encoding PNG…');
      await yieldToUi();

      const dataUrl = out.toDataURL('image/png');
      const a = document.createElement('a');
      a.href = dataUrl;
      a.download = `mandala-square-${exportPx}px-${Date.now()}.png`;
      a.click();
      setBusy(false);
      onClose();
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Export failed';
      setError(msg);
      setBusy(false);
    }
  };

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/80 backdrop-blur-md p-4">
      {busy && (
        <MandalaExportLoader
          status={busyStatus}
          detail={`${exportPx}×${exportPx} px${exportTransparent ? ' · transparent' : ''}${
            bakeGrid ? ' · guides' : ''
          }`}
        />
      )}

      <div
        className={`ui-modal border rounded-2xl w-full max-w-2xl shadow-2xl overflow-hidden ${
          busy ? 'opacity-40 pointer-events-none' : ''
        }`}
      >
        <div className="flex items-center justify-between px-5 py-3 border-b border-white/10">
          <div>
            <h3 className="font-manrope text-[15px] font-semibold text-white flex items-center gap-2">
              <span className="material-symbols-outlined text-secondary text-[20px]">crop_square</span>
              Square Export
            </h3>
            <p className="font-manrope text-[10px] text-slate-400 mt-0.5">
              Centered on mandala · PNG always N×N · up to 8K
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            disabled={busy}
            className="text-slate-400 hover:text-white transition-colors cursor-pointer disabled:opacity-40"
          >
            <span className="material-symbols-outlined text-[22px]">close</span>
          </button>
        </div>

        <div className="p-5 grid grid-cols-1 md:grid-cols-[minmax(0,360px)_1fr] gap-5">
          <div className="flex flex-col items-center gap-2">
            <div className="rounded-xl border border-secondary/30 bg-black/40 p-1 w-full max-w-[360px] aspect-square">
              <canvas
                ref={previewRef}
                width={360}
                height={360}
                className="w-full h-full rounded-lg block"
              />
            </div>
            <p className="font-manrope text-[9px] text-slate-500 text-center">
              Preview = export region (fast). Final file re-draws at full quality.
            </p>
          </div>

          <div className="space-y-4 font-manrope">
            <div>
              <label className="text-[10px] text-slate-400 font-semibold tracking-wide">
                File size (square)
              </label>
              <div className="flex flex-wrap gap-2 mt-1.5">
                {PRESET_SIZES.map(p => (
                  <button
                    key={p.px}
                    type="button"
                    onClick={() => setExportPx(p.px)}
                    disabled={busy}
                    className={`px-2.5 py-1.5 rounded-full text-[10px] font-bold border transition-all cursor-pointer disabled:opacity-40 ${
                      exportPx === p.px
                        ? 'bg-secondary/20 border-secondary text-secondary'
                        : 'bg-black/40 border-white/10 text-slate-300 hover:border-white/30'
                    }`}
                  >
                    {p.label}
                  </button>
                ))}
              </div>
              <p className="text-[9px] text-slate-500 mt-1">
                Output:{' '}
                <span className="text-secondary font-mono">
                  {exportPx}×{exportPx}
                </span>{' '}
                px PNG
                {exportPx >= 4096 && (
                  <span className="text-amber-400/90"> · large export may take longer</span>
                )}
              </p>
            </div>

            <div>
              <label className="text-[10px] text-slate-400 font-semibold flex justify-between">
                <span>Crop zoom</span>
                <span className="text-secondary font-mono">{cropZoom.toFixed(2)}×</span>
              </label>
              <input
                type="range"
                min={0.5}
                max={2.5}
                step={0.01}
                value={cropZoom}
                disabled={busy}
                onChange={e => setCropZoom(parseFloat(e.target.value))}
                className="w-full mt-1 accent-secondary cursor-pointer disabled:opacity-40"
              />
              <p className="text-[9px] text-slate-600">
                1× = full mandala disk (centered). Higher zoom = tighter crop around origin.
              </p>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-[10px] text-slate-400 font-semibold flex justify-between">
                  <span>Nudge X</span>
                  <span className="font-mono text-slate-500">{Math.round(nudgeX)}</span>
                </label>
                <input
                  type="range"
                  min={-500}
                  max={500}
                  step={1}
                  value={nudgeX}
                  disabled={busy}
                  onChange={e => setNudgeX(parseFloat(e.target.value))}
                  className="w-full mt-1 accent-secondary cursor-pointer disabled:opacity-40"
                />
              </div>
              <div>
                <label className="text-[10px] text-slate-400 font-semibold flex justify-between">
                  <span>Nudge Y</span>
                  <span className="font-mono text-slate-500">{Math.round(nudgeY)}</span>
                </label>
                <input
                  type="range"
                  min={-500}
                  max={500}
                  step={1}
                  value={nudgeY}
                  disabled={busy}
                  onChange={e => setNudgeY(parseFloat(e.target.value))}
                  className="w-full mt-1 accent-secondary cursor-pointer disabled:opacity-40"
                />
              </div>
            </div>
            <div className="flex justify-end -mt-1">
              <button
                type="button"
                disabled={busy}
                onClick={() => {
                  setNudgeX(0);
                  setNudgeY(0);
                  setCropZoom(1);
                }}
                className="text-[9px] font-manrope font-bold text-secondary hover:text-white cursor-pointer disabled:opacity-40"
              >
                Reset to mandala center
              </button>
            </div>

            <label className="flex items-center gap-2 cursor-pointer select-none">
              <input
                type="checkbox"
                checked={bakeGrid}
                disabled={busy}
                onChange={e => setBakeGrid(e.target.checked)}
                className="rounded border-white/20 bg-black/40 text-secondary focus:ring-secondary cursor-pointer"
              />
              <span className="text-[11px] text-slate-300">Guides (grid) in export</span>
            </label>

            <label className="flex items-center gap-2 cursor-pointer select-none">
              <input
                type="checkbox"
                checked={exportTransparent}
                disabled={busy}
                onChange={e => setExportTransparent(e.target.checked)}
                className="rounded border-white/20 bg-black/40 text-secondary focus:ring-secondary cursor-pointer"
              />
              <span className="text-[11px] text-slate-300">
                Export without canvas (transparent PNG / alpha)
              </span>
            </label>

            <p className="text-[10px] text-slate-500 leading-relaxed border-t border-white/5 pt-3">
              Frame is locked to the mandala origin. 8K and transparent+guides are heavy — a
              progress overlay will appear while rendering.
            </p>

            {error && (
              <p className="text-[11px] text-red-400 bg-red-500/10 border border-red-500/20 rounded-lg px-3 py-2">
                {error}
              </p>
            )}

            <div className="flex gap-2 pt-1">
              <button
                type="button"
                onClick={onClose}
                disabled={busy}
                className="flex-1 py-2 rounded-full border border-white/10 text-slate-300 text-[11px] font-semibold hover:bg-white/5 cursor-pointer disabled:opacity-40"
              >
                Cancel
              </button>
              <button
                type="button"
                disabled={busy || !effectiveCrop || !snap}
                onClick={() => void handleExport()}
                className="flex-1 py-2 rounded-full bg-secondary/20 border border-secondary/40 text-secondary text-[11px] font-bold hover:bg-secondary/30 disabled:opacity-40 cursor-pointer flex items-center justify-center gap-1"
              >
                <span className="material-symbols-outlined text-[16px]">download</span>
                {busy ? 'Exporting…' : `Export ${exportPx}²`}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
