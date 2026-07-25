/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useEffect, useRef } from 'react';
import { ViewState, BrushSettings, TemplateSettings, Stroke, ProjectMeta, DrawingLayer } from './types';
import Workspace from './components/Workspace';
import Templates from './components/Templates';
import Settings from './components/Settings';
import Gallery from './components/Gallery';
import TopNav from './components/TopNav';
import { AmbientSoundscape } from './utils/SoundEngine';
import { perfHud } from './utils/PerfHud';
import CanvasSizeDialog from './components/CanvasSizeDialog';
import {
  DEFAULT_CANVAS_SIZE,
  clampCanvasSize,
  DRAW_WORLD_SIZE,
  migrateStrokesToDrawWorld
} from './utils/projectCanvas';
import {
  applyAppearance,
  bakeQualityScale,
  loadAppSettings,
  type AppSettings
} from './utils/appSettings';
import { setWorldBakeQuality } from './utils/WorldScene';

// --- Delta-based history (узкое место #5) ---
// Вместо хранения полных копий массива штрихов на каждом шаге (O(strokes × undo_depth))
// храним список действий и пересобираем состояние при необходимости (O(undo_depth)).

export type HistoryAction =
  | { type: 'add'; stroke: Stroke }
  | { type: 'remove'; strokeId: string }
  | { type: 'clear' }
  | { type: 'load'; strokes: Stroke[] };

const generateId = (): string => {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `s_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 9)}`;
};

const withId = (stroke: Stroke): Stroke =>
  stroke.id ? stroke : { ...stroke, id: generateId() };

// Пересборка массива штрихов из списка действий (всегда от пустого состояния)
const replayHistory = (actions: HistoryAction[]): Stroke[] => {
  const result: Stroke[] = [];
  for (let i = 0; i < actions.length; i++) {
    const a = actions[i];
    if (a.type === 'add') {
      result.push(a.stroke);
    } else if (a.type === 'remove') {
      const idx = result.findIndex(s => s.id === a.strokeId);
      if (idx >= 0) result.splice(idx, 1);
    } else if (a.type === 'clear') {
      result.length = 0;
    } else if (a.type === 'load') {
      result.length = 0;
      for (let j = 0; j < a.strokes.length; j++) result.push(a.strokes[j]);
    }
  }
  return result;
};

export default function App() {
  // Старт с галереи: новый холст создаётся с выбором разрешения
  const [view, setView] = useState<ViewState>('gallery');
  
  // Meditative sound engine reference
  const soundEngineRef = useRef<AmbientSoundscape>(new AmbientSoundscape());

  // Project attributes state
  const [activeProjectId, setActiveProjectId] = useState<string | null>(null);
  const [projectName, setProjectName] = useState<string>('Sacred Mandala');
  /** Качество / сторона квадратного холста (не размер окна) */
  const [canvasSize, setCanvasSize] = useState<number>(DEFAULT_CANVAS_SIZE);
  const [showNewProjectDialog, setShowNewProjectDialog] = useState(false);
  const [showResizeDialog, setShowResizeDialog] = useState(false);

  const [brushSettings, setBrushSettings] = useState<BrushSettings>({
    type: 'vector',
    size: 5,
    opacity: 100,
    flow: 50,
    color: '#44e2cd',
    dotProfile: 'sine'
  });

  const [templateSettings, setTemplateSettings] = useState<TemplateSettings>({
    segments: 12,
    radius: 400,
    rotation: 0,
    layers: 6,
    mirror: true,
    showGridLines: true,
    showRings: true,
    showGridInExport: true,
    snapToGuides: true,
    
    // Rose Curves
    petalLength: 60,
    petalFrequency: 4,
    showPetals: true,
    
    // Spirals
    spiralGrowth: 0.5,
    spiralScale: 15,
    spiralArms: 3,
    showSpiral: false,

    // Lissajous
    showLissajous: false,
    lissFreqX: 3,
    lissFreqY: 4,
    lissPhase: 0,

    // Cardioid
    showCardioid: false,
    cardioidA: 50,
    cardioidB: 50,

    // Modulated Concentric Rings
    ringModulationAmp: 0,
    ringModulationFreq: 4,

    // Spirograph
    showSpirograph: false,
    spiroR: 60,
    spiro_r: 30,
    spiroD: 40,
    spiroType: 'epi',
    spiroRotations: 10,

    // Superellipse
    showSuperellipse: false,
    superellipseN: 1.0,
    superellipseA: 50,
    superellipseB: 50,

    // Maurer Rose
    showMaurer: false,
    maurerN: 6,
    maurerD: 71,

    // Default layer render order
    guideLayerOrder: [
      'grid', 'rings', 'petals', 'spiral', 'lissajous', 'cardioid', 'spirograph', 'superellipse', 'maurer'
    ]
  });

  const [strokes, setStrokes] = useState<Stroke[]>([]);
  const [drawingLayers, setDrawingLayers] = useState<DrawingLayer[]>([
    { id: 'default', name: 'Background Layer', visible: true }
  ]);
  const [activeLayerId, setActiveLayerId] = useState<string>('default');
  // Delta-based history: храним действия, а не полные копии массива штрихов
  const [history, setHistory] = useState<HistoryAction[]>([]);
  const [historyStep, setHistoryStep] = useState(-1);

  // Clean up sound on unmount
  useEffect(() => {
    return () => {
      soundEngineRef.current.stop();
    };
  }, []);

  // Theme + accent + bake quality from Settings (persisted)
  useEffect(() => {
    const s = loadAppSettings();
    applyAppearance(s);
    setWorldBakeQuality(bakeQualityScale(s.renderQuality));
    const onApp = (e: Event) => {
      const detail = (e as CustomEvent<AppSettings>).detail;
      if (detail) {
        applyAppearance(detail);
        if (detail.renderQuality) {
          setWorldBakeQuality(bakeQualityScale(detail.renderQuality));
        }
      } else {
        applyAppearance(loadAppSettings());
      }
    };
    window.addEventListener('mandala-app-settings', onApp as EventListener);
    return () => window.removeEventListener('mandala-app-settings', onApp as EventListener);
  }, []);

  // HUD только Workspace + Templates (не Gallery / Settings)
  useEffect(() => {
    if (view !== 'workspace' && view !== 'templates') {
      perfHud.detach();
    }
  }, [view]);

  // Listen for keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement;
      if (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA') return;

      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'z') {
        e.preventDefault();
        undo();
      } else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'y') {
        e.preventDefault();
        redo();
      } else if ((e.ctrlKey || e.metaKey) && e.key === 'Backspace') {
        e.preventDefault();
        clearStrokes();
      } else if (e.key === '[') {
        e.preventDefault();
        setBrushSettings(prev => ({ ...prev, size: Math.max(1, prev.size - 2) }));
      } else if (e.key === ']') {
        e.preventDefault();
        setBrushSettings(prev => ({ ...prev, size: Math.min(100, prev.size + 2) }));
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [strokes, history, historyStep]);

  const addStroke = (newStroke: Stroke) => {
    // Fixed DRAW_WORLD — no auto-grow / no mid-stroke resize freezes
    const strokeWithLayer = withId({ ...newStroke, layerId: activeLayerId });
    const newHistory = history.slice(0, historyStep + 1);
    newHistory.push({ type: 'add', stroke: strokeWithLayer });
    setStrokes(prev => [...prev, strokeWithLayer]);
    setHistory(newHistory);
    setHistoryStep(newHistory.length - 1);
  };

  const undo = () => {
    if (historyStep >= 0) {
      const prevStep = historyStep - 1;
      setStrokes(replayHistory(history.slice(0, prevStep + 1)));
      setHistoryStep(prevStep);
    }
  };

  const redo = () => {
    if (historyStep < history.length - 1) {
      const nextStep = historyStep + 1;
      setStrokes(replayHistory(history.slice(0, nextStep + 1)));
      setHistoryStep(nextStep);
    }
  };

  const clearStrokes = () => {
    if (confirm('Clear the entire canvas?')) {
      const newHistory = history.slice(0, historyStep + 1);
      newHistory.push({ type: 'clear' });
      setStrokes([]);
      setHistory(newHistory);
      setHistoryStep(newHistory.length - 1);
    }
  };

  // New project: сначала диалог разрешения
  const handleRequestNewProject = () => {
    setShowNewProjectDialog(true);
  };

  const handleConfirmNewProject = ({ size, name }: { size: number; name?: string }) => {
    setActiveProjectId(null);
    setProjectName(name || 'Sacred Mandala');
    setCanvasSize(clampCanvasSize(size));
    setStrokes([]);
    setHistory([]);
    setHistoryStep(-1);
    setDrawingLayers([{ id: 'default', name: 'Background Layer', visible: true }]);
    setActiveLayerId('default');
    setShowNewProjectDialog(false);
    setView('workspace');
  };

  /** Export quality only — does not move strokes or resize the draw world. */
  const handleResizeCanvas = ({ size }: { size: number }) => {
    const next = clampCanvasSize(size);
    if (next === canvasSize) {
      setShowResizeDialog(false);
      return;
    }
    setCanvasSize(next);
    setShowResizeDialog(false);
  };

  /** Fit camera to all strokes (no resolution jump, no rebake thrash). */
  const handleFitCanvasToContent = () => {
    if (!strokes.length) {
      alert('Nothing to fit — draw something first.');
      return;
    }
    const ok = window.fitMandalaContentToView?.();
    if (!ok) {
      alert('Could not fit view — try Recenter View.');
    }
  };

  // Open/Load project from gallery
  const handleOpenProject = (project?: ProjectMeta) => {
    if (!project) {
      handleRequestNewProject();
      return;
    }
    setActiveProjectId(project.id);
    setProjectName(project.name);
    const quality = clampCanvasSize(project.canvasSize || DEFAULT_CANVAS_SIZE);
    setCanvasSize(quality);

    // Load template settings, merging defaults in case they're older saved projects
    setTemplateSettings({
      segments: project.templateSettings.segments || 12,
      layers: project.templateSettings.layers || 6,
      rotation: project.templateSettings.rotation || 0,
      radius: project.templateSettings.radius || 400,
      mirror: project.templateSettings.mirror !== undefined ? project.templateSettings.mirror : true,
      showGridLines: project.templateSettings.showGridLines !== undefined ? project.templateSettings.showGridLines : true,
      showRings: project.templateSettings.showRings !== undefined ? project.templateSettings.showRings : true,
      showGridInExport: project.templateSettings.showGridInExport !== undefined ? project.templateSettings.showGridInExport : true,
      snapToGuides: project.templateSettings.snapToGuides !== undefined ? project.templateSettings.snapToGuides : true,

      petalLength: project.templateSettings.petalLength || 0,
      petalFrequency: project.templateSettings.petalFrequency || 1,
      showPetals: project.templateSettings.showPetals !== undefined ? project.templateSettings.showPetals : false,

      spiralGrowth: project.templateSettings.spiralGrowth || 0,
      spiralScale: project.templateSettings.spiralScale || 15,
      spiralArms: project.templateSettings.spiralArms || 3,
      showSpiral: project.templateSettings.showSpiral !== undefined ? project.templateSettings.showSpiral : false,

      showLissajous: project.templateSettings.showLissajous !== undefined ? project.templateSettings.showLissajous : false,
      lissFreqX: project.templateSettings.lissFreqX || 3,
      lissFreqY: project.templateSettings.lissFreqY || 4,
      lissPhase: project.templateSettings.lissPhase || 0,

      showCardioid: project.templateSettings.showCardioid !== undefined ? project.templateSettings.showCardioid : false,
      cardioidA: project.templateSettings.cardioidA || 50,
      cardioidB: project.templateSettings.cardioidB || 50,

      ringModulationAmp: project.templateSettings.ringModulationAmp || 0,
      ringModulationFreq: project.templateSettings.ringModulationFreq || 4,

      showSpirograph: project.templateSettings.showSpirograph !== undefined ? project.templateSettings.showSpirograph : false,
      spiroR: project.templateSettings.spiroR || 60,
      spiro_r: project.templateSettings.spiro_r || 30,
      spiroD: project.templateSettings.spiroD || 40,
      spiroType: project.templateSettings.spiroType || 'epi',
      spiroRotations: project.templateSettings.spiroRotations || 10,

      showSuperellipse: project.templateSettings.showSuperellipse !== undefined ? project.templateSettings.showSuperellipse : false,
      superellipseN: project.templateSettings.superellipseN || 1.0,
      superellipseA: project.templateSettings.superellipseA || 50,
      superellipseB: project.templateSettings.superellipseB || 50,

      showMaurer: project.templateSettings.showMaurer !== undefined ? project.templateSettings.showMaurer : false,
      maurerN: project.templateSettings.maurerN || 6,
      maurerD: project.templateSettings.maurerD || 71,

      guideLayerOrder: project.templateSettings.guideLayerOrder || [
        'grid', 'rings', 'petals', 'spiral', 'lissajous', 'cardioid', 'spirograph', 'superellipse', 'maurer'
      ]
    });

    // Strokes: migrate from old world(=quality) into fixed DRAW_WORLD_SIZE if needed
    let loadedStrokes = (project.strokes || []).map(withId);
    if (project.drawWorldSize !== DRAW_WORLD_SIZE) {
      const prevWorld = project.drawWorldSize || quality;
      loadedStrokes = migrateStrokesToDrawWorld(loadedStrokes, prevWorld, DRAW_WORLD_SIZE);
    }
    setStrokes(loadedStrokes);
    setHistory([{ type: 'load', strokes: loadedStrokes }]);
    setHistoryStep(0);

    const defaultLayers = project.drawingLayers || [{ id: 'default', name: 'Background Layer', visible: true }];
    setDrawingLayers(defaultLayers);
    setActiveLayerId(project.activeLayerId || defaultLayers[0].id);
    setView('workspace');
    requestAnimationFrame(() => window.resetMandalaCanvasViewport?.());
  };

  const handleSaveProject = () => {
    let name = projectName;
    let id = activeProjectId;

    if (!id) {
      const input = prompt("Name your mandala project:", projectName);
      if (input === null) return;
      name = input.trim() || "Sacred Mandala";
      id = Date.now().toString();
      setProjectName(name);
      setActiveProjectId(id);
    }

    // Gallery preview: square crop around mandala center (quality-sized region of draw world)
    let previewDataUrl: string | undefined;
    try {
      window.flushMandalaScene?.();
      const snap = window.getMandalaExportSnapshot?.();
      if (snap) {
        const side = Math.min(512, canvasSize);
        const out = document.createElement('canvas');
        out.width = side;
        out.height = side;
        const ctx = out.getContext('2d');
        if (ctx) {
          const worldCenter = DRAW_WORLD_SIZE / 2;
          snap.worldScene.exportSquare(ctx, side, worldCenter, worldCenter, canvasSize);
          previewDataUrl = out.toDataURL('image/png');
        }
      }
    } catch {
      /* fallback below */
    }
    // Fallback: center-crop квадрат из viewport canvas (никогда не сохраняем прямоугольник)
    if (!previewDataUrl) {
      const canvas = document.getElementById('mandala-canvas') as HTMLCanvasElement | null;
      if (canvas && canvas.width > 0 && canvas.height > 0) {
        const srcSide = Math.min(canvas.width, canvas.height);
        const sx = Math.floor((canvas.width - srcSide) / 2);
        const sy = Math.floor((canvas.height - srcSide) / 2);
        const outSide = Math.min(512, srcSide);
        const out = document.createElement('canvas');
        out.width = outSide;
        out.height = outSide;
        const ctx = out.getContext('2d');
        if (ctx) {
          ctx.drawImage(canvas, sx, sy, srcSide, srcSide, 0, 0, outSide, outSide);
          previewDataUrl = out.toDataURL('image/png');
        }
      }
    }

    const currentProject: ProjectMeta = {
      id,
      name,
      updatedAt: Date.now(),
      previewDataUrl,
      templateSettings,
      strokes,
      drawingLayers,
      activeLayerId,
      canvasSize,
      drawWorldSize: DRAW_WORLD_SIZE
    };

    const saved = localStorage.getItem('mandala_projects');
    let projectsList: ProjectMeta[] = [];
    if (saved) {
      try {
        projectsList = JSON.parse(saved);
      } catch (e) {}
    }

    projectsList = [currentProject, ...projectsList.filter(p => p.id !== id)];
    localStorage.setItem('mandala_projects', JSON.stringify(projectsList));
    alert(`Mandala "${name}" saved to gallery!`);
  };

  const handleShareProject = () => {
    try {
      const packageData = {
        templateSettings,
        strokes,
        drawingLayers,
        activeLayerId
      };
      const jsonStr = JSON.stringify(packageData);
      const b64 = btoa(unescape(encodeURIComponent(jsonStr)));
      
      navigator.clipboard.writeText(b64).then(() => {
        alert("Mandala project code copied to clipboard! Share it with others to import.");
      }).catch(() => {
        alert("Failed to copy. Share code:\n" + b64);
      });
    } catch (e) {
      alert("Failed to package mandala project for sharing.");
    }
  };

  const handleImportProject = (shareCode: string) => {
    try {
      const decodedJson = decodeURIComponent(escape(atob(shareCode.trim())));
      const parsed = JSON.parse(decodedJson);
      
      if (!parsed.strokes || !parsed.templateSettings) {
        throw new Error("Invalid project code");
      }

      const input = prompt("Name your imported mandala:", "Imported Mandala");
      if (input === null) return;
      const name = input.trim() || "Imported Mandala";
      const id = Date.now().toString();

      // Ensure backward/forward compatibility of newly added settings fields on import
      const importedProject: ProjectMeta = {
        id,
        name,
        updatedAt: Date.now(),
        templateSettings: {
          segments: parsed.templateSettings.segments || 12,
          radius: parsed.templateSettings.radius || 400,
          rotation: parsed.templateSettings.rotation || 0,
          layers: parsed.templateSettings.layers || 6,
          mirror: parsed.templateSettings.mirror !== undefined ? parsed.templateSettings.mirror : true,
          showGridLines: parsed.templateSettings.showGridLines !== undefined ? parsed.templateSettings.showGridLines : true,
          showRings: parsed.templateSettings.showRings !== undefined ? parsed.templateSettings.showRings : true,
          showGridInExport: parsed.templateSettings.showGridInExport !== undefined ? parsed.templateSettings.showGridInExport : true,
          snapToGuides: parsed.templateSettings.snapToGuides !== undefined ? parsed.templateSettings.snapToGuides : true,
          
          petalLength: parsed.templateSettings.petalLength || 0,
          petalFrequency: parsed.templateSettings.petalFrequency || 1,
          showPetals: parsed.templateSettings.showPetals !== undefined ? parsed.templateSettings.showPetals : false,
          
          spiralGrowth: parsed.templateSettings.spiralGrowth || 0,
          spiralScale: parsed.templateSettings.spiralScale || 15,
          spiralArms: parsed.templateSettings.spiralArms || 3,
          showSpiral: parsed.templateSettings.showSpiral !== undefined ? parsed.templateSettings.showSpiral : false,

          showLissajous: parsed.templateSettings.showLissajous !== undefined ? parsed.templateSettings.showLissajous : false,
          lissFreqX: parsed.templateSettings.lissFreqX || 3,
          lissFreqY: parsed.templateSettings.lissFreqY || 4,
          lissPhase: parsed.templateSettings.lissPhase || 0,

          showCardioid: parsed.templateSettings.showCardioid !== undefined ? parsed.templateSettings.showCardioid : false,
          cardioidA: parsed.templateSettings.cardioidA || 50,
          cardioidB: parsed.templateSettings.cardioidB || 50,

          ringModulationAmp: parsed.templateSettings.ringModulationAmp || 0,
          ringModulationFreq: parsed.templateSettings.ringModulationFreq || 4,

          showSpirograph: parsed.templateSettings.showSpirograph !== undefined ? parsed.templateSettings.showSpirograph : false,
          spiroR: parsed.templateSettings.spiroR || 60,
          spiro_r: parsed.templateSettings.spiro_r || 30,
          spiroD: parsed.templateSettings.spiroD || 40,
          spiroType: parsed.templateSettings.spiroType || 'epi',
          spiroRotations: parsed.templateSettings.spiroRotations || 10,

          showSuperellipse: parsed.templateSettings.showSuperellipse !== undefined ? parsed.templateSettings.showSuperellipse : false,
          superellipseN: parsed.templateSettings.superellipseN || 1.0,
          superellipseA: parsed.templateSettings.superellipseA || 50,
          superellipseB: parsed.templateSettings.superellipseB || 50,

          showMaurer: parsed.templateSettings.showMaurer !== undefined ? parsed.templateSettings.showMaurer : false,
          maurerN: parsed.templateSettings.maurerN || 6,
          maurerD: parsed.templateSettings.maurerD || 71,

          guideLayerOrder: parsed.templateSettings.guideLayerOrder || [
            'grid', 'rings', 'petals', 'spiral', 'lissajous', 'cardioid', 'spirograph', 'superellipse', 'maurer'
          ]
        },
        strokes: parsed.strokes || [],
        drawingLayers: parsed.drawingLayers || [{ id: 'default', name: 'Background Layer', visible: true }],
        activeLayerId: parsed.activeLayerId || 'default',
        canvasSize: clampCanvasSize(parsed.canvasSize || DEFAULT_CANVAS_SIZE),
        // omit drawWorldSize → handleOpenProject migrates strokes into DRAW_WORLD_SIZE
        drawWorldSize: parsed.drawWorldSize
      };

      const saved = localStorage.getItem('mandala_projects');
      let projectsList: ProjectMeta[] = [];
      if (saved) {
        try {
          projectsList = JSON.parse(saved);
        } catch (e) {}
      }

      projectsList = [importedProject, ...projectsList];
      localStorage.setItem('mandala_projects', JSON.stringify(projectsList));
      
      handleOpenProject(importedProject);
      alert(`Mandala "${name}" imported successfully!`);
    } catch (e) {
      alert("Failed to import mandala. Make sure the copied code is valid.");
    }
  };

  return (
    <div className="h-screen w-screen overflow-hidden flex flex-col bg-background text-on-surface selection:bg-secondary/30 relative">
      <TopNav 
        currentView={view} 
        onViewChange={setView} 
        onSave={handleSaveProject}
        onShare={handleShareProject}
      />
      
      <main className="flex-1 relative overflow-hidden h-full">
        {view === 'workspace' && (
          <Workspace 
            brushSettings={brushSettings} 
            setBrushSettings={setBrushSettings}
            templateSettings={templateSettings}
            setTemplateSettings={setTemplateSettings}
            strokes={strokes}
            addStroke={addStroke}
            onClear={clearStrokes}
            onUndo={undo}
            onRedo={redo}
            canUndo={historyStep >= 0}
            canRedo={historyStep < history.length - 1}
            soundEngine={soundEngineRef.current}
            drawingLayers={drawingLayers}
            setDrawingLayers={setDrawingLayers}
            activeLayerId={activeLayerId}
            setActiveLayerId={setActiveLayerId}
            canvasSize={canvasSize}
            onRequestResizeCanvas={() => setShowResizeDialog(true)}
            onFitCanvasToContent={handleFitCanvasToContent}
            onDeleteLayerStrokes={(layerId) => {
              const removed = strokes.filter(s => s.layerId === layerId && s.id);
              const updatedStrokes = strokes.filter(s => s.layerId !== layerId);
              setStrokes(updatedStrokes);
              const newHistory = history.slice(0, historyStep + 1);
              removed.forEach(s => newHistory.push({ type: 'remove', strokeId: s.id! }));
              setHistory(newHistory);
              setHistoryStep(newHistory.length - 1);
            }}
          />
        )}
        {view === 'templates' && (
          <Templates 
            settings={templateSettings} 
            onSettingsChange={setTemplateSettings} 
            onApplyTemplate={() => setView('workspace')}
          />
        )}
        {view === 'settings' && (
          <Settings />
        )}
        {view === 'gallery' && (
          <Gallery 
            onOpenProject={handleOpenProject} 
            onImportProject={handleImportProject}
          />
        )}
      </main>

      <CanvasSizeDialog
        open={showNewProjectDialog}
        mode="create"
        initialSize={DEFAULT_CANVAS_SIZE}
        initialName="Sacred Mandala"
        onCancel={() => setShowNewProjectDialog(false)}
        onConfirm={handleConfirmNewProject}
      />
      <CanvasSizeDialog
        open={showResizeDialog}
        mode="resize"
        initialSize={canvasSize}
        onCancel={() => setShowResizeDialog(false)}
        onConfirm={handleResizeCanvas}
      />
    </div>
  );
}
