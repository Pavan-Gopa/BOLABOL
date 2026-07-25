import React, { useState, useEffect } from 'react';
import { ProjectMeta } from '../types';
import { DEFAULT_CANVAS_SIZE } from '../utils/projectCanvas';

interface GalleryProps {
  onOpenProject: (project?: ProjectMeta) => void;
  onImportProject: (code: string) => void;
}

function formatDate(timestamp: number) {
  const date = new Date(timestamp);
  return date.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  });
}

function strokeCount(p: ProjectMeta): number {
  return p.strokes?.length ?? 0;
}

function layerCount(p: ProjectMeta): number {
  return p.drawingLayers?.length ?? 1;
}

export default function Gallery({ onOpenProject, onImportProject }: GalleryProps) {
  const [projects, setProjects] = useState<ProjectMeta[]>([]);
  const [showImportModal, setShowImportModal] = useState(false);
  const [importCode, setImportCode] = useState('');

  useEffect(() => {
    const saved = localStorage.getItem('mandala_projects');
    if (saved) {
      try {
        const parsed = JSON.parse(saved) as ProjectMeta[];
        parsed.sort((a, b) => b.updatedAt - a.updatedAt);
        setProjects(parsed);
      } catch (e) {
        console.error('Failed to load saved projects', e);
      }
    }
  }, []);

  const handleDeleteProject = (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    if (confirm('Are you sure you want to delete this mandala? This action cannot be undone.')) {
      const updated = projects.filter(p => p.id !== id);
      setProjects(updated);
      localStorage.setItem('mandala_projects', JSON.stringify(updated));
    }
  };

  const handleImportSubmit = () => {
    if (!importCode.trim()) return;
    onImportProject(importCode);
    setShowImportModal(false);
    setImportCode('');

    const saved = localStorage.getItem('mandala_projects');
    if (saved) {
      try {
        const parsed = JSON.parse(saved) as ProjectMeta[];
        parsed.sort((a, b) => b.updatedAt - a.updatedAt);
        setProjects(parsed);
      } catch (e) {}
    }
  };

  return (
    <div className="absolute inset-0 overflow-y-auto pt-20 pb-16 px-6 sm:px-12 theme-surface scrollbar-thin">
      <div className="max-w-screen-xl mx-auto mt-6">
        <div className="flex flex-col md:flex-row md:items-end justify-between mb-8 gap-4 border-b border-white/5 pb-6">
          <div>
            <h1 className="font-manrope text-[24px] font-bold tracking-tight text-white flex items-center gap-2">
              <span className="bg-gradient-to-r from-teal-300 via-secondary to-violet-400 bg-clip-text text-transparent">
                Creative Sanctuary
              </span>
            </h1>
            <p className="font-manrope text-[11px] text-slate-400 mt-1 font-medium max-w-lg">
              Create a new square canvas with chosen resolution, or open a saved mandala.
            </p>
          </div>

          <div className="flex items-center gap-3">
            <button
              onClick={() => setShowImportModal(true)}
              className="bg-white/5 border border-white/10 hover:border-secondary/40 text-secondary hover:bg-secondary/10 px-4 py-2 rounded-lg font-manrope text-[11px] font-bold tracking-wide transition-all duration-300 cursor-pointer flex items-center gap-1.5 shadow-lg active:scale-95"
            >
              <span className="material-symbols-outlined text-[15px]">login</span>
              Import Project
            </button>
          </div>
        </div>

        {/* Квадратная сетка превью */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-5">
          {/* New Project — тоже квадрат */}
          <button
            onClick={() => onOpenProject()}
            className="group relative rounded-xl border border-dashed ui-border ui-card hover:border-secondary/50 aspect-square flex flex-col items-center justify-center gap-2 transition-all duration-500 cursor-pointer shadow-2xl overflow-hidden"
          >
            <div className="absolute inset-0 bg-gradient-to-b from-transparent to-[#071626]/20 group-hover:to-secondary/5 transition-all duration-500 pointer-events-none" />
            <div className="w-12 h-12 rounded-full bg-white/5 border border-white/10 flex items-center justify-center group-hover:scale-110 group-hover:border-secondary group-hover:glow-accent transition-all duration-500">
              <span className="material-symbols-outlined text-[22px] text-secondary group-hover:text-white transition-colors">
                add
              </span>
            </div>
            <span className="font-manrope text-[11px] text-slate-300 group-hover:text-white transition-colors uppercase tracking-widest font-bold">
              New Mandala
            </span>
            <span className="font-manrope text-[9px] text-slate-600 group-hover:text-slate-400 transition-colors px-4 text-center">
              Square canvas · choose resolution
            </span>
          </button>

          {projects.map(p => {
            const res = p.canvasSize || DEFAULT_CANVAS_SIZE;
            const strokes = strokeCount(p);
            const layers = layerCount(p);
            const segments = p.templateSettings?.segments ?? '—';
            const mirror = p.templateSettings?.mirror;

            return (
              <div
                key={p.id}
                onClick={() => onOpenProject(p)}
                className="group rounded-xl overflow-hidden ui-card border hover:border-secondary/35 transition-colors duration-500 relative flex flex-col shadow-2xl hover:glow-accent-ring cursor-pointer"
              >
                {/* Только мандала — чистый квадрат, плавный долгий zoom */}
                <div className="relative w-full aspect-square shrink-0 overflow-hidden bg-[#030d17]">
                  {p.previewDataUrl ? (
                    <img
                      src={p.previewDataUrl}
                      alt={p.name}
                      className="absolute inset-0 w-full h-full object-cover object-center will-change-transform transition-transform duration-[1400ms] ease-[cubic-bezier(0.22,1,0.36,1)] group-hover:scale-[1.22] pointer-events-none"
                    />
                  ) : (
                    <div className="absolute inset-0 flex flex-col items-center justify-center gap-2 text-white/10">
                      <span className="material-symbols-outlined text-[48px]">grid_view</span>
                      <span className="font-manrope text-[9px] uppercase tracking-widest">No preview</span>
                    </div>
                  )}
                </div>

                {/* Компактный футер: мета + корзина */}
                <div className="px-2.5 py-2 border-t ui-card-footer">
                  <div className="flex items-start gap-2">
                    <div className="min-w-0 flex-1">
                      <h3 className="font-manrope text-[11px] font-bold text-white truncate leading-tight tracking-wide">
                        {p.name}
                      </h3>
                      <p className="mt-1 font-mono text-[9px] text-secondary/90 tabular-nums tracking-tight">
                        {res}×{res}
                        <span className="text-slate-600 mx-1">·</span>
                        <span className="text-slate-400 font-manrope font-semibold">
                          {strokes}s · {layers}L · {segments}§
                          {mirror ? ' · M' : ''}
                        </span>
                      </p>
                      <p className="mt-0.5 font-manrope text-[8px] font-medium tracking-wide text-slate-600">
                        {formatDate(p.updatedAt)}
                      </p>
                    </div>
                    <button
                      onClick={e => handleDeleteProject(p.id, e)}
                      className="shrink-0 mt-0.5 p-1 rounded-md text-slate-600 hover:text-red-400 hover:bg-red-500/10 border border-transparent hover:border-red-500/20 transition-all cursor-pointer"
                      title="Delete mandala"
                      aria-label="Delete mandala"
                    >
                      <span className="material-symbols-outlined text-[15px] block">delete</span>
                    </button>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {showImportModal && (
        <div className="fixed inset-0 bg-black/80 backdrop-blur-md flex items-center justify-center z-50 animate-fade-in p-4">
          <div className="ui-modal border rounded-2xl w-full max-w-md p-5 relative shadow-2xl">
            <button
              onClick={() => {
                setShowImportModal(false);
                setImportCode('');
              }}
              className="absolute top-4 right-4 text-slate-400 hover:text-white transition-colors cursor-pointer"
            >
              <span className="material-symbols-outlined text-[18px]">close</span>
            </button>

            <h3 className="font-manrope text-sm font-bold text-white mb-1.5">Import Shared Mandala</h3>
            <p className="font-manrope text-slate-400 text-[10px] mb-4">
              Paste the base64 shared project code below to load the complete drawing and templates.
            </p>

            <div className="space-y-4">
              <textarea
                value={importCode}
                onChange={e => setImportCode(e.target.value)}
                placeholder="Paste code here..."
                className="w-full bg-black/40 border border-white/10 rounded-xl p-3 text-[11px] text-white placeholder-slate-600 focus:outline-none focus:border-secondary h-24 resize-none font-mono"
              />
              <div className="flex justify-end gap-2">
                <button
                  onClick={() => {
                    setShowImportModal(false);
                    setImportCode('');
                  }}
                  className="px-3.5 py-2 bg-transparent text-slate-400 hover:text-white rounded text-[10px] font-semibold font-manrope transition-colors cursor-pointer"
                >
                  Cancel
                </button>
                <button
                  onClick={handleImportSubmit}
                  disabled={!importCode.trim()}
                  className="px-4.5 py-2 bg-secondary text-on-secondary rounded text-[10px] font-bold font-manrope disabled:bg-slate-800 disabled:text-slate-500 transition-colors cursor-pointer"
                >
                  Load Mandala
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
