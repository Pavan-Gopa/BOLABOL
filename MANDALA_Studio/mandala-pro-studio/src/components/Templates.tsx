import React, { useState, useEffect, useRef, useCallback } from 'react';
import { TemplateSettings } from '../types';
import { perfHud } from '../utils/PerfHud';
import {
  CanvasPrefs,
  loadCanvasPrefs,
  workspaceFillColor
} from '../utils/canvasPrefs';
import { renderGuides } from '../utils/guides';

interface TemplatesProps {
  settings: TemplateSettings;
  onSettingsChange: (s: TemplateSettings) => void;
  onApplyTemplate: () => void;
}

const DEFAULT_LAYER_ORDER = [
  'grid', 'rings', 'petals', 'spiral', 'lissajous', 'cardioid', 'spirograph', 'superellipse', 'maurer'
];

const PRESET_TEMPLATES: { name: string; settings: TemplateSettings }[] = [
  {
    name: "Tibetan Lotus",
    settings: {
      segments: 12,
      layers: 6,
      rotation: 0,
      radius: 400,
      mirror: true,
      showGridLines: true,
      showRings: true,
      showGridInExport: true,
      snapToGuides: true,
      petalLength: 75,
      petalFrequency: 4,
      showPetals: true,
      spiralGrowth: 0,
      spiralScale: 15,
      spiralArms: 3,
      showSpiral: false,
      showLissajous: false,
      lissFreqX: 3,
      lissFreqY: 4,
      lissPhase: 0,
      showCardioid: false,
      cardioidA: 50,
      cardioidB: 50,
      ringModulationAmp: 0,
      ringModulationFreq: 4,
      showSpirograph: false,
      spiroR: 60,
      spiro_r: 30,
      spiroD: 40,
      spiroType: 'epi',
      spiroRotations: 10,
      showSuperellipse: false,
      superellipseN: 1.0,
      superellipseA: 50,
      superellipseB: 50,
      showMaurer: false,
      maurerN: 6,
      maurerD: 71,
      guideLayerOrder: [...DEFAULT_LAYER_ORDER]
    }
  },
  {
    name: "Golden Ratio Spiral",
    settings: {
      segments: 24,
      layers: 12,
      rotation: 0,
      radius: 400,
      mirror: false,
      showGridLines: false,
      showRings: true,
      showGridInExport: true,
      snapToGuides: true,
      petalLength: 0,
      petalFrequency: 0,
      showPetals: false,
      spiralGrowth: 0.15,
      spiralScale: 30,
      spiralArms: 3,
      showSpiral: true,
      showLissajous: false,
      lissFreqX: 3,
      lissFreqY: 4,
      lissPhase: 0,
      showCardioid: false,
      cardioidA: 50,
      cardioidB: 50,
      ringModulationAmp: 0,
      ringModulationFreq: 4,
      showSpirograph: false,
      spiroR: 60,
      spiro_r: 30,
      spiroD: 40,
      spiroType: 'epi',
      spiroRotations: 10,
      showSuperellipse: false,
      superellipseN: 1.0,
      superellipseA: 50,
      superellipseB: 50,
      showMaurer: false,
      maurerN: 6,
      maurerD: 71,
      guideLayerOrder: [...DEFAULT_LAYER_ORDER]
    }
  },
  {
    name: "Spirograph Nebula",
    settings: {
      segments: 16,
      layers: 6,
      rotation: 45,
      radius: 400,
      mirror: true,
      showGridLines: true,
      showRings: true,
      showGridInExport: true,
      snapToGuides: true,
      petalLength: 0,
      petalFrequency: 0,
      showPetals: false,
      spiralGrowth: 0,
      spiralScale: 15,
      spiralArms: 3,
      showSpiral: false,
      showLissajous: false,
      lissFreqX: 3,
      lissFreqY: 4,
      lissPhase: 0,
      showCardioid: false,
      cardioidA: 50,
      cardioidB: 50,
      ringModulationAmp: 0,
      ringModulationFreq: 4,
      showSpirograph: true,
      spiroR: 72,
      spiro_r: 44,
      spiroD: 55,
      spiroType: 'hypo',
      spiroRotations: 11,
      showSuperellipse: false,
      superellipseN: 1.0,
      superellipseA: 50,
      superellipseB: 50,
      showMaurer: false,
      maurerN: 6,
      maurerD: 71,
      guideLayerOrder: [...DEFAULT_LAYER_ORDER]
    }
  },
  {
    name: "Ocean Wave Ripples",
    settings: {
      segments: 8,
      layers: 8,
      rotation: 0,
      radius: 400,
      mirror: true,
      showGridLines: true,
      showRings: true,
      showGridInExport: true,
      snapToGuides: true,
      petalLength: 0,
      petalFrequency: 0,
      showPetals: false,
      spiralGrowth: 0,
      spiralScale: 15,
      spiralArms: 3,
      showSpiral: false,
      showLissajous: false,
      lissFreqX: 3,
      lissFreqY: 4,
      lissPhase: 0,
      showCardioid: false,
      cardioidA: 50,
      cardioidB: 50,
      ringModulationAmp: 18,
      ringModulationFreq: 8,
      showSpirograph: false,
      spiroR: 60,
      spiro_r: 30,
      spiroD: 40,
      spiroType: 'epi',
      spiroRotations: 10,
      showSuperellipse: false,
      superellipseN: 1.0,
      superellipseA: 50,
      superellipseB: 50,
      showMaurer: false,
      maurerN: 6,
      maurerD: 71,
      guideLayerOrder: [...DEFAULT_LAYER_ORDER]
    }
  },
  {
    name: "Astroid Diamond",
    settings: {
      segments: 8,
      layers: 4,
      rotation: 0,
      radius: 400,
      mirror: true,
      showGridLines: true,
      showRings: false,
      showGridInExport: true,
      snapToGuides: true,
      petalLength: 0,
      petalFrequency: 0,
      showPetals: false,
      spiralGrowth: 0,
      spiralScale: 15,
      spiralArms: 3,
      showSpiral: false,
      showLissajous: false,
      lissFreqX: 3,
      lissFreqY: 4,
      lissPhase: 0,
      showCardioid: false,
      cardioidA: 50,
      cardioidB: 50,
      ringModulationAmp: 0,
      ringModulationFreq: 4,
      showSpirograph: false,
      spiroR: 60,
      spiro_r: 30,
      spiroD: 40,
      spiroType: 'epi',
      spiroRotations: 10,
      showSuperellipse: true,
      superellipseN: 0.6,
      superellipseA: 75,
      superellipseB: 75,
      showMaurer: false,
      maurerN: 6,
      maurerD: 71,
      guideLayerOrder: [...DEFAULT_LAYER_ORDER]
    }
  },
  {
    name: "Maurer Stardust Mesh",
    settings: {
      segments: 6,
      layers: 3,
      rotation: 0,
      radius: 400,
      mirror: true,
      showGridLines: true,
      showRings: true,
      showGridInExport: true,
      snapToGuides: true,
      petalLength: 0,
      petalFrequency: 0,
      showPetals: false,
      spiralGrowth: 0,
      spiralScale: 15,
      spiralArms: 3,
      showSpiral: false,
      showLissajous: false,
      lissFreqX: 3,
      lissFreqY: 4,
      lissPhase: 0,
      showCardioid: false,
      cardioidA: 50,
      cardioidB: 50,
      ringModulationAmp: 0,
      ringModulationFreq: 4,
      showSpirograph: false,
      spiroR: 60,
      spiro_r: 30,
      spiroD: 40,
      spiroType: 'epi',
      spiroRotations: 10,
      showSuperellipse: false,
      superellipseN: 1.0,
      superellipseA: 50,
      superellipseB: 50,
      showMaurer: true,
      maurerN: 5,
      maurerD: 61,
      guideLayerOrder: [...DEFAULT_LAYER_ORDER]
    }
  }
];

// Theme-aware switch (high contrast on Daylight / Latte)
const ToggleSwitch = ({
  checked,
  onChange,
  label
}: {
  checked: boolean;
  onChange: (val: boolean) => void;
  label: string;
}) => (
  <label className="flex items-center justify-between text-[11px] text-slate-300 hover:text-white cursor-pointer select-none py-1.5 transition-colors gap-3">
    <span className="leading-snug">{label}</span>
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      className={`ui-switch ${checked ? 'ui-switch-on' : 'ui-switch-off'}`}
    >
      <span className={`ui-switch-knob ${checked ? 'ui-switch-knob-on' : 'ui-switch-knob-off'}`} />
    </button>
  </label>
);

export default function Templates({ settings, onSettingsChange, onApplyTemplate }: TemplatesProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const [customTemplates, setCustomTemplates] = useState<{ name: string; settings: TemplateSettings }[]>([]);
  const [newTemplateName, setNewTemplateName] = useState('');
  const [shareCodeInput, setShareCodeInput] = useState('');
  const [showShareModal, setShowShareModal] = useState(false);

  // Zoom & Pan states for Visualizer Canvas
  const [zoom, setZoom] = useState(1.0);
  const [pan, setPan] = useState({ x: 0, y: 0 });
  const [isPanning, setIsPanning] = useState(false);
  const [isSpacePressed, setIsSpacePressed] = useState(false);
  const panStartRef = useRef({ x: 0, y: 0 });

  // Load custom templates
  useEffect(() => {
    const saved = localStorage.getItem('custom_templates');
    if (saved) {
      try {
        setCustomTemplates(JSON.parse(saved));
      } catch (e) {
        console.error("Failed to parse custom templates", e);
      }
    }
  }, []);

  // Save custom templates
  const saveCustomTemplates = (list: { name: string; settings: TemplateSettings }[]) => {
    setCustomTemplates(list);
    localStorage.setItem('custom_templates', JSON.stringify(list));
  };

  const handleSaveCurrentAsTemplate = () => {
    if (!newTemplateName.trim()) return;
    const name = newTemplateName.trim();
    
    if (customTemplates.some(t => t.name.toLowerCase() === name.toLowerCase())) {
      alert("A template with this name already exists.");
      return;
    }

    const updatedList = [...customTemplates, { name, settings: { ...settings } }];
    saveCustomTemplates(updatedList);
    setNewTemplateName('');
    alert(`Template "${name}" saved!`);
  };

  const handleDeleteTemplate = (index: number, e: React.MouseEvent) => {
    e.stopPropagation();
    if (confirm("Delete this custom template?")) {
      const updatedList = customTemplates.filter((_, idx) => idx !== index);
      saveCustomTemplates(updatedList);
    }
  };

  // Export Template Settings
  const handleExportTemplate = () => {
    const jsonStr = JSON.stringify(settings);
    const b64 = btoa(unescape(encodeURIComponent(jsonStr)));
    
    navigator.clipboard.writeText(b64).then(() => {
      alert("Template share code copied to clipboard!");
    }).catch(err => {
      console.error(err);
      alert(`Here is your share code: ${b64}`);
    });
  };

  // Import Template Settings
  const handleImportTemplate = () => {
    if (!shareCodeInput.trim()) return;
    try {
      const decodedJson = decodeURIComponent(escape(atob(shareCodeInput.trim())));
      const parsed = JSON.parse(decodedJson);
      
      onSettingsChange({
        segments: parsed.segments || 12,
        layers: parsed.layers || 6,
        rotation: parsed.rotation || 0,
        radius: parsed.radius || 400,
        mirror: parsed.mirror !== undefined ? parsed.mirror : true,
        showGridLines: parsed.showGridLines !== undefined ? parsed.showGridLines : true,
        showRings: parsed.showRings !== undefined ? parsed.showRings : true,
        showGridInExport: parsed.showGridInExport !== undefined ? parsed.showGridInExport : true,
        snapToGuides: parsed.snapToGuides !== undefined ? parsed.snapToGuides : true,
        
        petalLength: parsed.petalLength || 0,
        petalFrequency: parsed.petalFrequency || 1,
        showPetals: parsed.showPetals !== undefined ? parsed.showPetals : false,
        
        spiralGrowth: parsed.spiralGrowth || 0,
        spiralScale: parsed.spiralScale || 15,
        spiralArms: parsed.spiralArms || 3,
        showSpiral: parsed.showSpiral !== undefined ? parsed.showSpiral : false,

        showLissajous: parsed.showLissajous !== undefined ? parsed.showLissajous : false,
        lissFreqX: parsed.lissFreqX || 3,
        lissFreqY: parsed.lissFreqY || 4,
        lissPhase: parsed.lissPhase || 0,

        showCardioid: parsed.showCardioid !== undefined ? parsed.showCardioid : false,
        cardioidA: parsed.cardioidA || 50,
        cardioidB: parsed.cardioidB || 50,

        ringModulationAmp: parsed.ringModulationAmp || 0,
        ringModulationFreq: parsed.ringModulationFreq || 4,

        showSpirograph: parsed.showSpirograph !== undefined ? parsed.showSpirograph : false,
        spiroR: parsed.spiroR || 60,
        spiro_r: parsed.spiro_r || 30,
        spiroD: parsed.spiroD || 40,
        spiroType: parsed.spiroType || 'epi',
        spiroRotations: parsed.spiroRotations || 10,

        showSuperellipse: parsed.showSuperellipse !== undefined ? parsed.showSuperellipse : false,
        superellipseN: parsed.superellipseN || 1.0,
        superellipseA: parsed.superellipseA || 50,
        superellipseB: parsed.superellipseB || 50,

        showMaurer: parsed.showMaurer !== undefined ? parsed.showMaurer : false,
        maurerN: parsed.maurerN || 6,
        maurerD: parsed.maurerD || 71,

        guideLayerOrder: parsed.guideLayerOrder || [...DEFAULT_LAYER_ORDER]
      });

      setShowShareModal(false);
      setShareCodeInput('');
      alert("Template loaded successfully!");
    } catch (e) {
      alert("Failed to import template. Invalid share code format.");
    }
  };

  // Same canvas fill as Workspace (Settings → Canvas color)
  const [canvasFill, setCanvasFill] = useState(() => workspaceFillColor(loadCanvasPrefs()));

  useEffect(() => {
    const sync = (e?: Event) => {
      const detail = (e as CustomEvent<CanvasPrefs> | undefined)?.detail;
      const prefs = detail ?? loadCanvasPrefs();
      setCanvasFill(workspaceFillColor(prefs));
    };
    window.addEventListener('mandala-prefs-changed', sync as EventListener);
    sync();
    return () => window.removeEventListener('mandala-prefs-changed', sync as EventListener);
  }, []);

  // Draw template lattice — same fill + adaptive rails as Workspace
  const drawTemplatePreview = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas || !containerRef.current) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const width = containerRef.current.clientWidth;
    const height = containerRef.current.clientHeight;
    const dpr = window.devicePixelRatio || 1;

    if (canvas.width !== width * dpr || canvas.height !== height * dpr) {
      canvas.width = width * dpr;
      canvas.height = height * dpr;
      canvas.style.width = `${width}px`;
      canvas.style.height = `${height}px`;
    }

    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = canvasFill;
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    ctx.save();
    ctx.scale(dpr, dpr);
    ctx.translate(pan.x, pan.y);
    ctx.scale(zoom, zoom);

    const cx = width / 2;
    const cy = height / 2;
    const maxRadius = (Math.min(width, height) / 2) * 0.85;

    renderGuides(ctx, cx, cy, maxRadius, settings, zoom, canvasFill, {
      drawCenter: true,
      rayLength: maxRadius
    });

    ctx.restore();
  }, [settings, zoom, pan, canvasFill]);

  // Handle mouse wheel zoom centered at cursor
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const handleWheel = (e: WheelEvent) => {
      e.preventDefault();
      const zoomFactor = 1.1;
      const nextZoom = e.deltaY < 0 ? zoom * zoomFactor : zoom / zoomFactor;
      
      // Синхронно с Workspace (CAMERA_ZOOM_*)
      const clampedZoom = Math.max(0.015, Math.min(120.0, nextZoom));
      const rect = canvas.getBoundingClientRect();
      const cursorX = e.clientX - rect.left;
      const cursorY = e.clientY - rect.top;

      setPan(prev => ({
        x: cursorX - (cursorX - prev.x) * (clampedZoom / zoom),
        y: cursorY - (cursorY - prev.y) * (clampedZoom / zoom)
      }));
      setZoom(clampedZoom);
    };

    canvas.addEventListener('wheel', handleWheel, { passive: false });
    return () => canvas.removeEventListener('wheel', handleWheel);
  }, [zoom]);

  // Spacebar shortcuts listener
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.code === 'Space') {
        setIsSpacePressed(true);
      }
    };
    const handleKeyUp = (e: KeyboardEvent) => {
      if (e.code === 'Space') {
        setIsSpacePressed(false);
        setIsPanning(false);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    window.addEventListener('keyup', handleKeyUp);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      window.removeEventListener('keyup', handleKeyUp);
    };
  }, []);

  // Pointer event listeners for Panning
  const handlePointerDown = (e: React.PointerEvent<HTMLCanvasElement>) => {
    if (isSpacePressed || e.button === 1 || e.button === 2) {
      e.preventDefault();
      setIsPanning(true);
      panStartRef.current = { x: e.clientX - pan.x, y: e.clientY - pan.y };
    }
  };

  const handlePointerMove = (e: React.PointerEvent<HTMLCanvasElement>) => {
    if (isPanning) {
      setPan({
        x: e.clientX - panStartRef.current.x,
        y: e.clientY - panStartRef.current.y
      });
    }
  };

  const handlePointerUp = () => {
    setIsPanning(false);
  };

  // Redraw when geometry, camera, or canvas fill changes
  useEffect(() => {
    drawTemplatePreview();
    window.addEventListener('resize', drawTemplatePreview);
    return () => window.removeEventListener('resize', drawTemplatePreview);
  }, [drawTemplatePreview]);

  // HUD только в зоне visualizer (между left/right sidebars)
  const hudHostRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const host = hudHostRef.current;
    if (!host) return;
    perfHud.attach(host);
    perfHud.applyPrefs(loadCanvasPrefs());
    return () => perfHud.detach();
  }, []);

  return (
    <div
      className="absolute inset-0 flex items-center justify-center z-0 overflow-hidden"
      style={{ backgroundColor: canvasFill }}
    >
      
      {/* Background Visualizer Canvas */}
      <div ref={containerRef} className="absolute inset-0 z-0">
         <canvas 
           ref={canvasRef} 
           className={`w-full h-full ${
             isSpacePressed ? (isPanning ? 'cursor-grabbing' : 'cursor-grab') : 'cursor-default'
           }`}
           onPointerDown={handlePointerDown}
           onPointerMove={handlePointerMove}
           onPointerUp={handlePointerUp}
           onPointerLeave={handlePointerUp}
           onContextMenu={e => e.preventDefault()}
         />
         <div className="absolute top-[60px] left-70 text-white/20 text-[10px] tracking-widest uppercase pointer-events-none font-manrope font-bold">
           Generative Lattice Visualizer
         </div>
      </div>

      {/* Зона холста Templates — HUD host */}
      <div
        ref={hudHostRef}
        className="pointer-events-none fixed top-11 bottom-0 left-64 right-64 z-[25]"
        aria-hidden
      />

      {/* Recenter view button */}
      <button
        onClick={() => {
          setZoom(1.0);
          setPan({ x: 0, y: 0 });
        }}
        className="ui-float-pill absolute bottom-6 left-1/2 -translate-x-1/2 px-3 py-1.5 rounded-full transition-all text-[10px] font-manrope font-bold z-40 flex items-center gap-1 shadow-md cursor-pointer"
        title="Recenter Grid"
      >
        <span className="material-symbols-outlined text-[12px]">filter_center_focus</span>
        Recenter visualizer
      </button>

      {/* Templates Sidebar (Left - Saved Templates & Sharing) */}
      <nav className="ui-panel fixed left-0 top-11 bottom-0 w-64 border-r z-30 flex flex-col text-[11px]">
        <div className="flex flex-col h-full p-4 overflow-y-auto scrollbar-thin">
          <div className="mb-4 flex justify-between items-center">
            <div>
              <h2 className="font-manrope text-white font-bold text-[12px] tracking-wide">Template Library</h2>
              <p className="font-manrope text-slate-500 text-[9px] uppercase tracking-wider mt-0.5 font-bold">Lattice Presets</p>
            </div>
            <button
              type="button"
              onClick={onApplyTemplate}
              className="ui-btn-primary px-3 py-1 rounded-full text-[10px] font-bold font-manrope shadow-md transition-all active:scale-95 cursor-pointer flex items-center gap-1"
            >
              <span className="material-symbols-outlined text-[12px]">draw</span>
              Draw
            </button>
          </div>

          {/* Presets List */}
          <div className="space-y-1.5 mb-5">
            <span className="font-manrope text-[9px] text-slate-500 uppercase tracking-widest block mb-0.5 font-bold">Standard Presets</span>
            {PRESET_TEMPLATES.map((preset, idx) => (
              <button
                key={idx}
                onClick={() => onSettingsChange({ ...preset.settings })}
                className="w-full text-left p-2 rounded border border-white/5 bg-white/5 hover:bg-white/10 hover:border-white/10 transition-colors flex items-center justify-between group cursor-pointer"
              >
                <div>
                  <h4 className="font-manrope text-[11px] font-bold text-white group-hover:text-secondary transition-colors truncate w-40">{preset.name}</h4>
                  <p className="font-manrope text-[9px] text-slate-400 mt-0.5">{preset.settings.segments} sectors | {preset.settings.layers} rings</p>
                </div>
                <span className="material-symbols-outlined text-slate-500 group-hover:text-secondary text-[16px] transition-colors">grid_view</span>
              </button>
            ))}
          </div>

          {/* Custom Templates List */}
          <div className="space-y-1.5 mb-5">
            <span className="font-manrope text-[9px] text-slate-500 uppercase tracking-widest block mb-0.5 font-bold">My Geometry Files</span>
            {customTemplates.length === 0 ? (
              <p className="font-manrope text-[10px] text-slate-500 italic px-1">No custom templates saved.</p>
            ) : (
              customTemplates.map((custom, idx) => (
                <div
                  key={idx}
                  onClick={() => onSettingsChange({ ...custom.settings })}
                  className="w-full p-2 rounded border border-white/5 bg-black/40 hover:bg-white/5 transition-colors flex items-center justify-between group cursor-pointer"
                >
                  <div className="flex-1 text-left truncate pr-1">
                    <h4 className="font-manrope text-[11px] font-bold text-white group-hover:text-secondary transition-colors truncate">{custom.name}</h4>
                    <p className="font-manrope text-[9px] text-slate-400 mt-0.5">{custom.settings.segments} sectors | {custom.settings.layers} rings</p>
                  </div>
                  <button 
                    onClick={(e) => handleDeleteTemplate(idx, e)}
                    className="text-slate-500 hover:text-red-400 transition-colors p-0.5 cursor-pointer"
                    title="Delete template"
                  >
                    <span className="material-symbols-outlined text-[16px]">delete</span>
                  </button>
                </div>
              ))
            )}
          </div>

          {/* Save/Import triggers */}
          <div className="mt-auto border-t ui-border-soft pt-3 space-y-2">
            <span className="font-manrope text-[9px] text-slate-500 uppercase tracking-widest block font-bold">
              Save current geometry
            </span>
            <div className="flex gap-1.5">
              <input
                type="text"
                value={newTemplateName}
                onChange={e => setNewTemplateName(e.target.value)}
                placeholder="Name Layout..."
                className="ui-field flex-1 rounded px-2 py-1 text-[10px] font-manrope focus:outline-none focus:border-secondary"
              />
              <button
                type="button"
                onClick={handleSaveCurrentAsTemplate}
                disabled={!newTemplateName.trim()}
                className="ui-btn-primary px-2.5 py-1 rounded text-[10px] font-semibold font-manrope transition-colors cursor-pointer disabled:cursor-not-allowed"
              >
                Save
              </button>
            </div>

            <div className="grid grid-cols-2 gap-1.5 pt-0.5">
              <button
                type="button"
                onClick={handleExportTemplate}
                className="ui-btn-ghost py-1.5 rounded text-[10px] font-medium font-manrope transition-colors flex items-center justify-center gap-1 cursor-pointer"
              >
                <span className="material-symbols-outlined text-[13px]">share</span>
                Export
              </button>
              <button
                type="button"
                onClick={() => setShowShareModal(true)}
                className="ui-btn-accent-soft py-1.5 rounded text-[10px] font-bold font-manrope transition-colors flex items-center justify-center gap-1 cursor-pointer"
              >
                <span className="material-symbols-outlined text-[13px]">login</span>
                Import
              </button>
            </div>
          </div>
        </div>
      </nav>

      {/* Layout Editor Sidebar (Right - Geometric Controls) */}
      <aside className="ui-panel fixed right-0 top-11 bottom-0 w-64 border-l z-30 flex flex-col text-[11px]">
        <div className="flex flex-col h-full p-4 overflow-y-auto scrollbar-thin">
          <div className="mb-3 flex flex-col">
            <h2 className="font-manrope text-white font-bold text-[12px] tracking-wide">Lattice Editor</h2>
            <p className="font-manrope text-slate-500 text-[9px] uppercase tracking-wider mt-0.5 font-bold">Formula Configuration</p>
          </div>

          <div className="space-y-3.5">
            
            <button
              onClick={onApplyTemplate}
              className="w-full bg-secondary text-on-secondary py-2 rounded-lg font-bold font-manrope text-[10px] uppercase tracking-widest hover:scale-102 glow-accent-soft transition-all cursor-pointer text-center"
            >
              Use Template & Draw
            </button>

            {/* Base Lattice */}
            <div className="border-t border-white/5 pt-2.5 space-y-2.5">
              <span className="font-manrope text-[9px] text-secondary font-bold uppercase tracking-widest block">Base Geometry</span>
              
              <div>
                <div className="flex justify-between items-center mb-0.5">
                  <span className="font-manrope text-[10px] text-slate-300">Sectors Count</span>
                  <span className="font-mono text-[10px] text-white">{settings.segments}</span>
                </div>
                <input 
                  type="range" min="4" max="64" step="2" value={settings.segments}
                  onChange={e => onSettingsChange({...settings, segments: parseInt(e.target.value)})}
                  className="w-full accent-secondary h-1 bg-white/15 rounded-lg appearance-none cursor-pointer"
                />
              </div>

              <div>
                <div className="flex justify-between items-center mb-0.5">
                  <span className="font-manrope text-[10px] text-slate-300">Concentric Rings</span>
                  <span className="font-mono text-[10px] text-white">{settings.layers}</span>
                </div>
                <input 
                  type="range" min="1" max="24" step="1" value={settings.layers}
                  onChange={e => onSettingsChange({...settings, layers: parseInt(e.target.value)})}
                  className="w-full accent-secondary h-1 bg-white/15 rounded-lg appearance-none cursor-pointer"
                />
              </div>

              <div>
                <div className="flex justify-between items-center mb-0.5">
                  <span className="font-manrope text-[10px] text-slate-300">Lattice Rotation</span>
                  <span className="font-mono text-[10px] text-white">{settings.rotation}°</span>
                </div>
                <input 
                  type="range" min="0" max="360" step="1" value={settings.rotation}
                  onChange={e => onSettingsChange({...settings, rotation: parseInt(e.target.value)})}
                  className="w-full accent-secondary h-1 bg-white/15 rounded-lg appearance-none cursor-pointer"
                />
              </div>
            </div>

            {/* Ring modulation ripples */}
            <div className="border-t border-white/5 pt-2.5 space-y-2 bg-white/5 rounded p-2">
              <span className="font-manrope text-[9px] text-secondary font-bold uppercase tracking-widest block">Ring modulation</span>
              
              <div>
                <div className="flex justify-between items-center mb-0.5 text-[9px] text-slate-400">
                  <span>Wave Amplitude</span>
                  <span>{settings.ringModulationAmp}%</span>
                </div>
                <input 
                  type="range" min="0" max="40" step="1" value={settings.ringModulationAmp}
                  onChange={e => onSettingsChange({...settings, ringModulationAmp: parseInt(e.target.value)})}
                  className="w-full accent-secondary h-1 bg-white/15 rounded-lg appearance-none cursor-pointer"
                />
              </div>

              <div>
                <div className="flex justify-between items-center mb-0.5 text-[9px] text-slate-400">
                  <span>Wave Lobes Freq</span>
                  <span>{settings.ringModulationFreq}</span>
                </div>
                <input 
                  type="range" min="2" max="24" step="1" value={settings.ringModulationFreq}
                  onChange={e => onSettingsChange({...settings, ringModulationFreq: parseInt(e.target.value)})}
                  className="w-full accent-secondary h-1 bg-white/15 rounded-lg appearance-none cursor-pointer"
                />
              </div>
            </div>

            {/* Display switches */}
            <div className="border-t border-white/5 pt-2.5 space-y-0.5">
              <span className="font-manrope text-[9px] text-slate-500 uppercase tracking-widest block mb-0.5 font-bold">Display Controls</span>
              <ToggleSwitch 
                checked={settings.showGridLines}
                onChange={val => onSettingsChange({...settings, showGridLines: val})}
                label="Show Radial Rays"
              />
              <ToggleSwitch 
                checked={settings.showRings}
                onChange={val => onSettingsChange({...settings, showRings: val})}
                label="Show Concentric Rings"
              />
              <ToggleSwitch 
                checked={settings.mirror}
                onChange={val => onSettingsChange({...settings, mirror: val})}
                label="Mirror Reflections"
              />
              <ToggleSwitch 
                checked={settings.snapToGuides}
                onChange={val => onSettingsChange({...settings, snapToGuides: val})}
                label="Snap Drawing to Lattice"
              />
            </div>

            {/* Advanced overlays */}
            <div className="border-t border-white/5 pt-2.5 space-y-2.5">
              <span className="font-manrope text-[9px] text-secondary font-bold uppercase tracking-widest block">Formula Overlays</span>

              {/* Spirograph */}
              <div className="space-y-1.5 border-b border-white/5 pb-1.5">
                <ToggleSwitch 
                  checked={settings.showSpirograph}
                  onChange={val => onSettingsChange({...settings, showSpirograph: val})}
                  label="Gear Spirograph"
                />
                {settings.showSpirograph && (
                  <div className="pl-2 border-l border-white/10 space-y-1.5 pt-0.5 text-[9px]">
                    <div className="flex gap-1.5 mb-1">
                      <button
                        onClick={() => onSettingsChange({...settings, spiroType: 'epi'})}
                        className={`flex-1 py-0.5 rounded text-center font-manrope font-semibold text-[8px] uppercase tracking-wider border ${settings.spiroType === 'epi' ? 'bg-secondary text-on-secondary border-secondary/40 font-bold' : 'ui-seg-off'}`}
                      >
                        Epi
                      </button>
                      <button
                        onClick={() => onSettingsChange({...settings, spiroType: 'hypo'})}
                        className={`flex-1 py-0.5 rounded text-center font-manrope font-semibold text-[8px] uppercase tracking-wider border ${settings.spiroType === 'hypo' ? 'bg-secondary text-on-secondary border-secondary/40 font-bold' : 'ui-seg-off'}`}
                      >
                        Hypo
                      </button>
                    </div>

                    <div>
                      <div className="flex justify-between text-slate-400">
                        <span>Fixed Circle R</span>
                        <span>{settings.spiroR}%</span>
                      </div>
                      <input 
                        type="range" min="10" max="100" value={settings.spiroR}
                        onChange={e => onSettingsChange({...settings, spiroR: parseInt(e.target.value)})}
                        className="w-full accent-secondary h-1 bg-white/15 appearance-none rounded-lg"
                      />
                    </div>
                    <div>
                      <div className="flex justify-between text-slate-400">
                        <span>Rolling Circle r</span>
                        <span>{settings.spiro_r}%</span>
                      </div>
                      <input 
                        type="range" min="5" max="80" value={settings.spiro_r}
                        onChange={e => onSettingsChange({...settings, spiro_r: parseInt(e.target.value)})}
                        className="w-full accent-secondary h-1 bg-white/15 appearance-none rounded-lg"
                      />
                    </div>
                    <div>
                      <div className="flex justify-between text-slate-400">
                        <span>Pen Offset d</span>
                        <span>{settings.spiroD}%</span>
                      </div>
                      <input 
                        type="range" min="5" max="100" value={settings.spiroD}
                        onChange={e => onSettingsChange({...settings, spiroD: parseInt(e.target.value)})}
                        className="w-full accent-secondary h-1 bg-white/15 appearance-none rounded-lg"
                      />
                    </div>
                    <div>
                      <div className="flex justify-between text-slate-400">
                        <span>Rotations</span>
                        <span>{settings.spiroRotations}</span>
                      </div>
                      <input 
                        type="range" min="1" max="24" value={settings.spiroRotations}
                        onChange={e => onSettingsChange({...settings, spiroRotations: parseInt(e.target.value)})}
                        className="w-full accent-secondary h-1 bg-white/15 appearance-none rounded-lg"
                      />
                    </div>
                  </div>
                )}
              </div>

              {/* Superellipse */}
              <div className="space-y-1.5 border-b border-white/5 pb-1.5">
                <ToggleSwitch 
                  checked={settings.showSuperellipse}
                  onChange={val => onSettingsChange({...settings, showSuperellipse: val})}
                  label="Superellipse"
                />
                {settings.showSuperellipse && (
                  <div className="pl-2 border-l border-white/10 space-y-1.5 pt-0.5 text-[9px]">
                    <div>
                      <div className="flex justify-between text-slate-400">
                        <span>Power n</span>
                        <span>{settings.superellipseN}</span>
                      </div>
                      <input 
                        type="range" min="0.1" max="8.0" step="0.1" value={settings.superellipseN}
                        onChange={e => onSettingsChange({...settings, superellipseN: parseFloat(e.target.value)})}
                        className="w-full accent-secondary h-1 bg-white/15 appearance-none rounded-lg"
                      />
                    </div>
                    <div>
                      <div className="flex justify-between text-slate-400">
                        <span>Width a</span>
                        <span>{settings.superellipseA}%</span>
                      </div>
                      <input 
                        type="range" min="10" max="100" value={settings.superellipseA}
                        onChange={e => onSettingsChange({...settings, superellipseA: parseInt(e.target.value)})}
                        className="w-full accent-secondary h-1 bg-white/15 appearance-none rounded-lg"
                      />
                    </div>
                    <div>
                      <div className="flex justify-between text-slate-400">
                        <span>Height b</span>
                        <span>{settings.superellipseB}%</span>
                      </div>
                      <input 
                        type="range" min="10" max="100" value={settings.superellipseB}
                        onChange={e => onSettingsChange({...settings, superellipseB: parseInt(e.target.value)})}
                        className="w-full accent-secondary h-1 bg-white/15 appearance-none rounded-lg"
                      />
                    </div>
                  </div>
                )}
              </div>

              {/* Maurer Rose */}
              <div className="space-y-1.5 border-b border-white/5 pb-1.5">
                <ToggleSwitch 
                  checked={settings.showMaurer}
                  onChange={val => onSettingsChange({...settings, showMaurer: val})}
                  label="Maurer Rose Mesh"
                />
                {settings.showMaurer && (
                  <div className="pl-2 border-l border-white/10 space-y-1.5 pt-0.5 text-[9px]">
                    <div>
                      <div className="flex justify-between text-slate-400">
                        <span>Factor n</span>
                        <span>{settings.maurerN}</span>
                      </div>
                      <input 
                        type="range" min="2" max="18" value={settings.maurerN}
                        onChange={e => onSettingsChange({...settings, maurerN: parseInt(e.target.value)})}
                        className="w-full accent-secondary h-1 bg-white/15 appearance-none rounded-lg"
                      />
                    </div>
                    <div>
                      <div className="flex justify-between text-slate-400">
                        <span>Step d</span>
                        <span>{settings.maurerD}°</span>
                      </div>
                      <input 
                        type="range" min="1" max="180" value={settings.maurerD}
                        onChange={e => onSettingsChange({...settings, maurerD: parseInt(e.target.value)})}
                        className="w-full accent-secondary h-1 bg-white/15 appearance-none rounded-lg"
                      />
                    </div>
                  </div>
                )}
              </div>

              {/* Rose Petals */}
              <div className="space-y-1.5 border-b border-white/5 pb-1.5">
                <ToggleSwitch 
                  checked={settings.showPetals}
                  onChange={val => onSettingsChange({...settings, showPetals: val})}
                  label="Rose Petals"
                />
                {settings.showPetals && (
                  <div className="pl-2 border-l border-white/10 space-y-1.5 pt-0.5 text-[9px]">
                    <div>
                      <div className="flex justify-between text-slate-400">
                        <span>Petal Length</span>
                        <span>{settings.petalLength}%</span>
                      </div>
                      <input 
                        type="range" min="10" max="100" value={settings.petalLength}
                        onChange={e => onSettingsChange({...settings, petalLength: parseInt(e.target.value)})}
                        className="w-full accent-secondary h-1 bg-white/15 appearance-none rounded-lg"
                      />
                    </div>
                    <div>
                      <div className="flex justify-between text-slate-400">
                        <span>Frequency k</span>
                        <span>{settings.petalFrequency}</span>
                      </div>
                      <input 
                        type="range" min="1" max="16" value={settings.petalFrequency}
                        onChange={e => onSettingsChange({...settings, petalFrequency: parseInt(e.target.value)})}
                        className="w-full accent-secondary h-1 bg-white/15 appearance-none rounded-lg"
                      />
                    </div>
                  </div>
                )}
              </div>

              {/* Logarithmic Spiral */}
              <div className="space-y-1.5 border-b border-white/5 pb-1.5">
                <ToggleSwitch 
                  checked={settings.showSpiral}
                  onChange={val => onSettingsChange({...settings, showSpiral: val})}
                  label="Logarithmic Spiral"
                />
                {settings.showSpiral && (
                  <div className="pl-2 border-l border-white/10 space-y-1.5 pt-0.5 text-[9px]">
                    <div>
                      <div className="flex justify-between text-slate-400">
                        <span>Arms Count</span>
                        <span>{settings.spiralArms || 3}</span>
                      </div>
                      <input 
                        type="range" min="1" max="32" step="1" value={settings.spiralArms || 3}
                        onChange={e => onSettingsChange({...settings, spiralArms: parseInt(e.target.value)})}
                        className="w-full accent-secondary h-1 bg-white/15 appearance-none rounded-lg"
                      />
                    </div>
                    <div>
                      <div className="flex justify-between text-slate-400">
                        <span>Growth b</span>
                        <span>{settings.spiralGrowth}</span>
                      </div>
                      <input 
                        type="range" min="0.02" max="3.0" step="0.02" value={settings.spiralGrowth}
                        onChange={e => onSettingsChange({...settings, spiralGrowth: parseFloat(e.target.value)})}
                        className="w-full accent-secondary h-1 bg-white/15 appearance-none rounded-lg"
                      />
                    </div>
                    <div>
                      <div className="flex justify-between text-slate-400">
                        <span>Base Scale a</span>
                        <span>{settings.spiralScale || 15}px</span>
                      </div>
                      <input 
                        type="range" min="5" max="150" value={settings.spiralScale || 15}
                        onChange={e => onSettingsChange({...settings, spiralScale: parseInt(e.target.value)})}
                        className="w-full accent-secondary h-1 bg-white/15 appearance-none rounded-lg"
                      />
                    </div>
                  </div>
                )}
              </div>

              {/* Lissajous Curves */}
              <div className="space-y-1.5 border-b border-white/5 pb-1.5">
                <ToggleSwitch 
                  checked={settings.showLissajous}
                  onChange={val => onSettingsChange({...settings, showLissajous: val})}
                  label="Lissajous Wave"
                />
                {settings.showLissajous && (
                  <div className="pl-2 border-l border-white/10 space-y-1.5 pt-0.5 text-[9px]">
                    <div>
                      <div className="flex justify-between text-slate-400">
                        <span>X Frequency</span>
                        <span>{settings.lissFreqX}</span>
                      </div>
                      <input 
                        type="range" min="1" max="12" value={settings.lissFreqX}
                        onChange={e => onSettingsChange({...settings, lissFreqX: parseInt(e.target.value)})}
                        className="w-full accent-secondary h-1 bg-white/15 appearance-none rounded-lg"
                      />
                    </div>
                    <div>
                      <div className="flex justify-between text-slate-400">
                        <span>Y Frequency</span>
                        <span>{settings.lissFreqY}</span>
                      </div>
                      <input 
                        type="range" min="1" max="12" value={settings.lissFreqY}
                        onChange={e => onSettingsChange({...settings, lissFreqY: parseInt(e.target.value)})}
                        className="w-full accent-secondary h-1 bg-white/15 appearance-none rounded-lg"
                      />
                    </div>
                    <div>
                      <div className="flex justify-between text-slate-400">
                        <span>Phase angle</span>
                        <span>{settings.lissPhase}°</span>
                      </div>
                      <input 
                        type="range" min="0" max="360" step="5" value={settings.lissPhase}
                        onChange={e => onSettingsChange({...settings, lissPhase: parseInt(e.target.value)})}
                        className="w-full accent-secondary h-1 bg-white/15 appearance-none rounded-lg"
                      />
                    </div>
                  </div>
                )}
              </div>

              {/* Limacon/Cardioid */}
              <div className="space-y-1.5">
                <ToggleSwitch 
                  checked={settings.showCardioid}
                  onChange={val => onSettingsChange({...settings, showCardioid: val})}
                  label="Pascal Limacon"
                />
                {settings.showCardioid && (
                  <div className="pl-2 border-l border-white/10 space-y-1.5 pt-0.5 text-[9px]">
                    <div>
                      <div className="flex justify-between text-slate-400">
                        <span>Size Factor a</span>
                        <span>{settings.cardioidA}%</span>
                      </div>
                      <input 
                        type="range" min="10" max="100" value={settings.cardioidA}
                        onChange={e => onSettingsChange({...settings, cardioidA: parseInt(e.target.value)})}
                        className="w-full accent-secondary h-1 bg-white/15 appearance-none rounded-lg"
                      />
                    </div>
                    <div>
                      <div className="flex justify-between text-slate-400">
                        <span>Indentation b</span>
                        <span>{settings.cardioidB}%</span>
                      </div>
                      <input 
                        type="range" min="10" max="100" value={settings.cardioidB}
                        onChange={e => onSettingsChange({...settings, cardioidB: parseInt(e.target.value)})}
                        className="w-full accent-secondary h-1 bg-white/15 appearance-none rounded-lg"
                      />
                    </div>
                  </div>
                )}
              </div>

            </div>
          </div>
        </div>
      </aside>

      {/* Share Modal */}
      {showShareModal && (
        <div className="fixed inset-0 bg-black/80 backdrop-blur-md flex items-center justify-center z-50 animate-fade-in p-4">
          <div className="ui-modal border rounded-2xl w-full max-w-md p-6 relative shadow-2xl">
            <button 
              onClick={() => { setShowShareModal(false); setShareCodeInput(''); }} 
              className="absolute top-4 right-4 text-slate-400 hover:text-white transition-colors cursor-pointer"
            >
              <span className="material-symbols-outlined text-[20px]">close</span>
            </button>

            <h3 className="font-manrope text-base font-semibold text-white mb-2">Import Shared Template</h3>
            <p className="font-manrope text-slate-400 text-xs mb-4">Paste the shared base64 template code below to immediately configure the editor settings.</p>

            <div className="space-y-4">
              <textarea
                value={shareCodeInput}
                onChange={e => setShareCodeInput(e.target.value)}
                placeholder="Paste code here..."
                className="w-full bg-black/40 border border-white/10 rounded-xl p-3 text-xs text-white placeholder-slate-600 focus:outline-none focus:border-secondary h-24 resize-none font-mono"
              />
              <div className="flex justify-end gap-2">
                <button
                  onClick={() => { setShowShareModal(false); setShareCodeInput(''); }}
                  className="px-4 py-2 bg-transparent text-slate-400 hover:text-white rounded text-xs font-semibold font-manrope transition-colors cursor-pointer"
                >
                  Cancel
                </button>
                <button
                  onClick={handleImportTemplate}
                  disabled={!shareCodeInput.trim()}
                  className="px-5 py-2 bg-secondary text-on-secondary rounded text-xs font-semibold font-manrope disabled:bg-slate-800 disabled:text-slate-500 transition-colors cursor-pointer"
                >
                  Apply Template
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
