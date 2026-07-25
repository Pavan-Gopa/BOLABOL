import React from 'react';

interface MandalaExportLoaderProps {
  /** Short status under the title */
  status?: string;
  /** e.g. "4096×4096" */
  detail?: string;
}

/**
 * Full-screen mandala-themed wait overlay for long exports (4K / 8K / transparent + guides).
 */
export default function MandalaExportLoader({
  status = 'Please wait',
  detail
}: MandalaExportLoaderProps) {
  return (
    <div
      className="fixed inset-0 z-[200] flex flex-col items-center justify-center bg-black/75 backdrop-blur-md"
      role="status"
      aria-live="polite"
      aria-busy="true"
    >
      <div className="relative w-44 h-44 mb-8">
        {/* Outer ring */}
        <div
          className="absolute inset-0 rounded-full border border-secondary/25"
          style={{ animation: 'mandala-spin 12s linear infinite' }}
        />
        {/* Mid ring — opposite spin */}
        <div
          className="absolute inset-3 rounded-full border border-dashed border-secondary/40"
          style={{ animation: 'mandala-spin-rev 8s linear infinite' }}
        />
        {/* Inner ring */}
        <div
          className="absolute inset-7 rounded-full border-2 border-secondary/50"
          style={{ animation: 'mandala-spin 5s linear infinite' }}
        />

        {/* Orbit A — 12 petals */}
        <div
          className="absolute inset-0"
          style={{ animation: 'mandala-spin 6s linear infinite' }}
        >
          {Array.from({ length: 12 }).map((_, i) => {
            const angle = (i / 12) * 360;
            return (
              <div
                key={i}
                className="absolute left-1/2 top-1/2 w-0 h-0"
                style={{ transform: `rotate(${angle}deg)` }}
              >
                <span
                  className="absolute block rounded-full bg-secondary"
                  style={{
                    width: i % 3 === 0 ? 9 : 6,
                    height: i % 3 === 0 ? 9 : 6,
                    left: -3.5,
                    top: -62,
                    opacity: 0.55 + (i % 3) * 0.15,
                    boxShadow: '0 0 10px rgba(var(--secondary-rgb), 0.7)'
                  }}
                />
              </div>
            );
          })}
        </div>

        {/* Orbit B — reverse */}
        <div
          className="absolute inset-0"
          style={{ animation: 'mandala-spin-rev 4.5s linear infinite' }}
        >
          {Array.from({ length: 8 }).map((_, i) => {
            const angle = (i / 8) * 360 + 22;
            return (
              <div
                key={`b-${i}`}
                className="absolute left-1/2 top-1/2 w-0 h-0"
                style={{ transform: `rotate(${angle}deg)` }}
              >
                <span
                  className="absolute block w-2 h-2 rounded-full"
                  style={{
                    left: -4,
                    top: -40,
                    background: 'var(--color-tertiary, #cebdff)',
                    opacity: 0.85
                  }}
                />
              </div>
            );
          })}
        </div>

        {/* Core glow */}
        <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
          <div
            className="w-4 h-4 rounded-full bg-secondary"
            style={{
              boxShadow: '0 0 20px rgba(var(--secondary-rgb), 0.9), 0 0 40px rgba(var(--secondary-rgb), 0.35)',
              animation: 'mandala-pulse 1.6s ease-in-out infinite'
            }}
          />
        </div>
      </div>

      <h3 className="font-manrope text-[15px] font-bold text-white tracking-wide mb-1.5">
        Weaving your mandala…
      </h3>
      <p className="font-manrope text-[12px] text-secondary font-semibold mb-1">{status}</p>
      {detail && (
        <p className="font-mono text-[10px] text-slate-400 tracking-wide">{detail}</p>
      )}
      <p className="font-manrope text-[10px] text-slate-500 mt-4 max-w-xs text-center leading-relaxed px-4">
        High-resolution export re-draws every stroke. Large sizes (4K / 8K) and transparent
        guides can take a moment — please keep this tab open.
      </p>

      <style>{`
        @keyframes mandala-spin {
          from { transform: rotate(0deg); }
          to { transform: rotate(360deg); }
        }
        @keyframes mandala-spin-rev {
          from { transform: rotate(360deg); }
          to { transform: rotate(0deg); }
        }
        @keyframes mandala-pulse {
          0%, 100% { transform: scale(1); opacity: 1; }
          50% { transform: scale(1.35); opacity: 0.75; }
        }
      `}</style>
    </div>
  );
}
